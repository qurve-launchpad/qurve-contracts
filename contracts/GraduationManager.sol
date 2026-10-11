// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AgentBondingCurve} from "./AgentBondingCurve.sol";
import {IAgentBondingCurve} from "./interfaces/IAgentBondingCurve.sol";
import {IAgentToken} from "./interfaces/IAgentToken.sol";
import {AgentTokenFactory} from "./AgentTokenFactory.sol";
import {HolderRewardsDistributor} from "./HolderRewardsDistributor.sol";

// ── Interface Uniswap ────────────────────────────────────────────────────
// `IUniswapV3Factory` aman diimpor langsung dari package resmi (gak ada
// masalah kompatibilitas apa pun di file itu).
// `INonfungiblePositionManager` & `IWETH9` diimpor dari versi VENDOR lokal
// di ./interfaces/uniswap/, bukan langsung dari node_modules — karena versi
// resmi @uniswap/v3-periphery (di file & dependency-nya) tidak kompatibel
// langsung dengan OpenZeppelin v5 dan Solidity 0.8.x. Lihat komentar di
// masing-masing file vendor dan DEPLOYMENT.md untuk detail.
// Install dulu: npm install @uniswap/v3-core@1.0.1 @uniswap/v3-periphery@1.4.4
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "./interfaces/uniswap/INonfungiblePositionManager.sol";
import {IWETH9} from "./interfaces/uniswap/IWETH9.sol";

// ── Catatan native-quote-asset (Arc/Circle chain) ──────────────────────────
// Di Arc, native gas token = USDC, direpresentasikan 18 desimal (sama kayak
// wei ETH), TAPI USDC juga punya ERC-20 interface resmi di alamat tetap
// (mainnet: 0x3600000000000000000000000000000000000000) dengan 6 desimal —
// dan itu saldo yang SAMA, cuma beda skala tampilan. Arc TIDAK punya token
// wrapped (gak ada "WUSDC"), karena native-nya udah otomatis satisfy
// IERC20 tanpa perlu deposit()/wrap. Makanya kontrak ini sekarang punya
// mode `requiresWrap = false` buat Arc: saldo native yang diterima lewat
// receive() otomatis juga jadi saldo ERC-20 di alamat quote token, tinggal
// dikonversi skala (dibagi `nativeToQuoteDecimalOffset`) sebelum dipakai di
// approve()/mint() Uniswap. Untuk chain WETH-style lama (mis. Base),
// `requiresWrap = true` dan offset = 1 (WETH sama-sama 18 desimal).

/// @dev Minimal pool interface (hanya yang dibutuhkan untuk menangani pool
///      yang sudah ada sebelum graduasi). slot0() dibaca lewat staticcall
///      low-level (hanya word pertama = sqrtPriceX96) supaya tahan terhadap
///      fork Uniswap V3 yang mengubah tipe field lain di slot0.
interface IUniswapV3PoolLite {
    function liquidity() external view returns (uint128);

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

/// @title GraduationManager
/// @notice Migrasi bonding curve ke Uniswap V3 setelah threshold tercapai.
///         LP NFT di-burn ke 0xdead (locked forever).
///         Pakai interface RESMI Uniswap (bukan versi "Minimal" buatan
///         sendiri) supaya method signature dijamin 1:1 sama dengan
///         deployment on-chain-nya dan gak ada celah salah tafsir ABI.
contract GraduationManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IUniswapV3Factory public immutable uniswapFactory;
    INonfungiblePositionManager public immutable positionManager;
    address public immutable weth;
    AgentTokenFactory public immutable agentFactory;

    /// @notice true kalau quote asset butuh di-wrap dulu (WETH-style, mis.
    ///         Base/Ethereum). false kalau native balance sudah otomatis
    ///         jadi saldo ERC-20 (Arc-style stablecoin-native, quote = USDC).
    bool public immutable requiresWrap;

    /// @notice Faktor pembagi buat konversi jumlah native (18 desimal,
    ///         satuan msg.value/`ethLiquidity` dari curve) ke satuan ERC-20
    ///         quote token yang sebenarnya dipakai Uniswap. WETH: 1 (sama
    ///         18 desimal). USDC-native Arc: 1e12 (native 18 dec -> ERC-20
    ///         6 dec).
    uint256 public immutable nativeToQuoteDecimalOffset;

    uint24 public constant POOL_FEE = 3000; // 0.3%

    /// @dev FIX #1: fee tier 3000 => tickSpacing 60. Tick WAJIB kelipatan 60.
    ///      -887200 / 887200 BUKAN kelipatan 60 (887200 % 60 == 40), jadi
    ///      setiap mint() pasti revert. Full-range yang valid untuk spacing 60
    ///      adalah -887220 / 887220 (887220 % 60 == 0, dan masih <= 887272).
    int24 public constant TICK_LOWER = -887220;
    int24 public constant TICK_UPPER = 887220;

    /// @dev Batas sqrtPriceX96 yang diterima Uniswap V3.
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    /// @notice Toleransi slippage untuk mint LP pertama (FIX #5).
    ///         Kalau pool sudah di-init duluan oleh pihak lain pada harga yang
    ///         timpang, rasio token yang terpakai akan meleset dan mint()
    ///         revert — bukan "mendonasikan" likuiditas pada harga buruk.
    uint16 public graduationSlippageBps = 100; // 1%
    uint16 public constant MAX_SLIPPAGE_BPS = 1000; // 10% hard cap

    uint16 internal constant BPS_DENOM = 10_000;

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @notice token => HolderRewardsDistributor. Cuma keisi kalau curve-nya
    ///         rewardMode == HOLDERS. Cek address(0) buat tau apakah token
    ///         tertentu punya distributor.
    mapping(address => address) public distributorOf;

    /// @notice Daftar SEMUA agent token yang punya distributor (rewardMode ==
    ///         HOLDERS), urut sesuai waktu graduasi. Dipakai staking page
    ///         buat nge-list semua pool yang ada tanpa perlu tau address-nya
    ///         duluan — iterate array ini, terus distributorOf[token] buat
    ///         dapet alamat pool-nya masing-masing.
    address[] public holderRewardTokens;

    function holderRewardTokensCount() external view returns (uint256) {
        return holderRewardTokens.length;
    }

    /// @notice Ambil sepotong (bukan semua) daftar holderRewardTokens —
    ///         penting kalau daftarnya udah panjang, biar gak kena block
    ///         gas limit / RPC response limit pas di-query dari frontend.
    function getHolderRewardTokens(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory tokens)
    {
        uint256 total = holderRewardTokens.length;
        if (offset >= total) return new address[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;
        tokens = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            tokens[i - offset] = holderRewardTokens[i];
        }
    }

    /// @notice Alamat AgentSwapRouter (satu per chain, di-set owner setelah
    ///         router-nya di-deploy). Kalau udah diset, tiap distributor
    ///         baru otomatis authorize router ini sebagai notifier —
    ///         gak perlu setNotifier() manual satu-satu per token.
    address public swapRouter;

    /// @dev Pool yang sedang dikoreksi harganya (hanya terisi di dalam
    ///      _alignExistingPool). Dipakai untuk memvalidasi callback swap.
    address private _poolInCorrection;

    event SwapRouterUpdated(address indexed oldRouter, address indexed newRouter);

    event GraduationSlippageUpdated(uint16 oldBps, uint16 newBps);
    event AgentGraduated(
        address indexed curve,
        address indexed token,
        address indexed pool,
        uint256 lpTokenId
    );
    event HolderDistributorDeployed(
        address indexed token,
        address indexed distributor,
        uint256 initialPool
    );

    error NotYetEligible();
    error AlreadyGraduated();
    error ZeroAddress();
    error TransferFailed();
    error UnauthorizedCurve();
    error PoolMismatch();
    error InvalidSlippage();
    error InvalidSqrtPrice();
    error PoolPriceManipulated();
    error UnexpectedCallback();

    constructor(
        address uniswapFactory_,
        address positionManager_,
        address weth_,
        address agentFactory_,
        address initialOwner,
        bool requiresWrap_,
        uint256 nativeToQuoteDecimalOffset_
    ) Ownable(initialOwner) {
        if (
            uniswapFactory_ == address(0) ||
            positionManager_ == address(0) ||
            weth_ == address(0) ||
            agentFactory_ == address(0)
        ) revert ZeroAddress();
        require(nativeToQuoteDecimalOffset_ > 0, "offset=0");

        uniswapFactory = IUniswapV3Factory(uniswapFactory_);
        positionManager = INonfungiblePositionManager(positionManager_);
        weth = weth_;
        agentFactory = AgentTokenFactory(agentFactory_);
        requiresWrap = requiresWrap_;
        nativeToQuoteDecimalOffset = nativeToQuoteDecimalOffset_;
    }

    /// @notice Trigger graduasi untuk curve yang sudah mencapai threshold.
    ///         Permissionless — siapa pun bisa memanggil.
    function graduate(address curveAddr)
        external
        nonReentrant
        returns (address pool, uint256 lpTokenId)
    {
        AgentBondingCurve curve = AgentBondingCurve(payable(curveAddr));

        if (curve.graduated()) revert AlreadyGraduated();

        // FIX #4: validasi dua arah. Sebelumnya hanya dicek bahwa
        // curveAddr.agentToken() mengembalikan token yang terdaftar — kontrak
        // palsu bisa mengembalikan alamat token asli dan lolos guard, lalu
        // meng-init pool token asli pada harga manipulatif. Sekarang curve
        // harus benar-benar curve resmi milik token tersebut.
        address tokenAddr = address(curve.agentToken());
        if (!agentFactory.isAgentToken(tokenAddr)) revert UnauthorizedCurve();
        if (agentFactory.curveOfToken(tokenAddr) != curveAddr) revert UnauthorizedCurve();

        // Eligible if EITHER the curve is fully sold out OR the ETH reserve
        // has reached the graduation threshold. The curve auto-locks itself on
        // the FIRST of these two conditions (see AgentBondingCurve._executeBuy),
        // so graduate() must accept BOTH — otherwise a sell-out that lands a few
        // wei below the threshold (due to floor/ceil rounding mismatch between
        // the curve's quote math and the constructor's threshold derivation)
        // would leave the curve locked but permanently un-graduable, trapping
        // all ETH + tokens + pendingHolderPool forever.
        bool soldOut = curve.tokensSold() >= curve.tokensForSale();
        bool thresholdMet = curve.realEthReserve() >= curve.graduationThreshold();
        if (!soldOut && !thresholdMet) revert NotYetEligible();

        // Tarik ETH/native dan token dari curve
        uint256 ethLiquidity = curve.withdrawReserveForGraduation();
        uint256 tokenLiquidity = curve.withdrawTokensForGraduation();

        // Wrap native -> quote token ERC-20, HANYA kalau chain butuh
        // (WETH-style). Di Arc (requiresWrap=false), saldo native yang
        // baru diterima lewat receive() SUDAH otomatis jadi saldo ERC-20
        // USDC di alamat `weth` (native & ERC-20 share saldo yang sama) —
        // gak ada deposit() yang perlu dipanggil, dan gak ada fungsi
        // deposit() di alamat itu (bukan wrapper).
        if (requiresWrap) {
            IWETH9(weth).deposit{value: ethLiquidity}();
        }

        // Konversi skala native (18 desimal) -> skala quote token ERC-20
        // yang sebenarnya dipakai Uniswap (WETH: /1, USDC-native Arc: /1e12).
        uint256 quoteLiquidity = ethLiquidity / nativeToQuoteDecimalOffset;

        // Order token
        (address token0, address token1, uint256 amount0, uint256 amount1) =
            _orderTokens(tokenAddr, weth, tokenLiquidity, quoteLiquidity);

        // Approve position manager
        IERC20(token0).forceApprove(address(positionManager), amount0);
        IERC20(token1).forceApprove(address(positionManager), amount1);

        // Compute sqrtPriceX96
        uint160 sqrtPriceX96 = _computeSqrtPriceX96(amount0, amount1);

        // Create & initialize pool if needed
        pool = positionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            POOL_FEE,
            sqrtPriceX96
        );

        // Sanity check tambahan — sekarang bisa dilakukan karena pakai
        // interface factory resmi (bukan minimal): pastikan pool yang
        // dikembalikan positionManager memang match dengan yang tercatat
        // di factory, buat jaga-jaga ada custom deployment yang aneh.
        if (uniswapFactory.getPool(token0, token1, POOL_FEE) != pool) {
            revert PoolMismatch();
        }

        // Fix C-1: pool boleh sudah dibuat/di-initialize pihak lain sebelum
        // graduasi. Kalau harganya meleset dan pool masih kosong, geser
        // harganya ke harga target (gratis, tanpa likuiditas). Kalau pool
        // sudah punya likuiditas aktif dan harganya jauh, mint() di bawah
        // akan revert lewat amountMin -> graduate() revert, curve tetap
        // terbuka, user tetap bisa exit lewat curve.
        _alignExistingPool(pool, sqrtPriceX96);

        // Mint LP NFT (dengan slippage guard — FIX #5)
        uint256 amount0Min = (amount0 * (BPS_DENOM - graduationSlippageBps)) / BPS_DENOM;
        uint256 amount1Min = (amount1 * (BPS_DENOM - graduationSlippageBps)) / BPS_DENOM;

        (lpTokenId, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: POOL_FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: DEAD, // LP NFT langsung ke 0xdead (locked forever)
                deadline: block.timestamp + 15 minutes
            })
        );

        // Bersihkan approval & sisa dust (mint hampir tidak pernah menghabiskan
        // 100% amountDesired karena pembulatan sqrtPrice).
        IERC20(token0).forceApprove(address(positionManager), 0);
        IERC20(token1).forceApprove(address(positionManager), 0);
        _sweepDust(tokenAddr);

        // ── Holder-rewards distributor (kalau rewardMode == HOLDERS) ──
        // Deploy satu instance HolderRewardsDistributor khusus token ini,
        // lalu langsung flush seluruh pendingHolderPool yang terkumpul
        // sepanjang fase bonding curve dalam satu notifyRewardAmount().
        // `owner()` (protocol admin) diset sebagai owner distributor supaya
        // belakangan bisa nambah AgentSwapRouter lewat setNotifier() begitu
        // router post-graduation-nya sudah di-deploy.
        // ── Holder-rewards distributor (if rewardMode == HOLDERS) ──
        if (curve.rewardMode() == IAgentBondingCurve.RewardMode.HOLDERS) {
            HolderRewardsDistributor dist = new HolderRewardsDistributor(
                tokenAddr,
                address(this),   // initialNotifier = GraduationManager
                address(this)    // initialOwner    = GraduationManager (so it can call setNotifier)
            );
            distributorOf[tokenAddr] = address(dist);
            holderRewardTokens.push(tokenAddr);

            uint256 accumulated = curve.withdrawHolderPoolForGraduation();
            if (accumulated > 0) {
                dist.notifyRewardAmount{value: accumulated}();
            }

            if (swapRouter != address(0)) {
                dist.setNotifier(swapRouter, true);
            }

            emit HolderDistributorDeployed(tokenAddr, address(dist), accumulated);
        }

        // Mark graduated
        curve.markGraduated(pool, lpTokenId);

        emit AgentGraduated(curveAddr, tokenAddr, pool, lpTokenId);
    }

    // ─────────────────────────────────────────── Admin ───

    function setGraduationSlippageBps(uint16 newBps) external onlyOwner {
        if (newBps > MAX_SLIPPAGE_BPS) revert InvalidSlippage();
        uint16 old = graduationSlippageBps;
        graduationSlippageBps = newBps;
        emit GraduationSlippageUpdated(old, newBps);
    }

    /// @notice Daftarin AgentSwapRouter (satu per chain) setelah dia
    ///         di-deploy. Gak retroaktif — distributor yang udah lahir
    ///         SEBELUM ini diset TIDAK otomatis dapet notifier baru, harus
    ///         di-setNotifier() manual satu-satu buat token yang udah
    ///         graduated duluan. Yang graduate SETELAH ini diset otomatis kebagi.
    function setSwapRouter(address newRouter) external onlyOwner {
        address old = swapRouter;
        swapRouter = newRouter;
        emit SwapRouterUpdated(old, newRouter);
    }

    // ─────────────────────────────────────────── Internal ───

    /// @dev Kalau pool (token, WETH, POOL_FEE) sudah ada dengan harga
    ///      berbeda dari target dan TIDAK punya likuiditas aktif, geser
    ///      harganya lewat swap 1 wei dengan price limit = target. Di pool
    ///      kosong swap ini tidak mengonsumsi token apa pun. Kalau ternyata
    ///      butuh bayaran (ada likuiditas di jalur harga), callback revert.
    function _alignExistingPool(address pool, uint160 targetSqrtPriceX96) internal {
        uint160 currentSqrt = _poolSqrtPrice(pool);
        if (currentSqrt == targetSqrtPriceX96) return;
        if (IUniswapV3PoolLite(pool).liquidity() != 0) return; // biar mint()+amountMin yang menjaga

        bool zeroForOne = currentSqrt > targetSqrtPriceX96;
        _poolInCorrection = pool;
        IUniswapV3PoolLite(pool).swap(
            address(this),
            zeroForOne,
            int256(1),
            targetSqrtPriceX96,
            ""
        );
        _poolInCorrection = address(0);

        if (_poolSqrtPrice(pool) != targetSqrtPriceX96) revert PoolPriceManipulated();
    }

    /// @dev Baca sqrtPriceX96 dari slot0() (selector 0x3850c7bd), hanya word pertama.
    function _poolSqrtPrice(address pool) internal view returns (uint160 p) {
        (bool ok, bytes memory data) = pool.staticcall(
            abi.encodeWithSelector(bytes4(0x3850c7bd))
        );
        if (!ok || data.length < 32) revert PoolMismatch();
        p = abi.decode(data, (uint160));
    }

    /// @notice Callback Uniswap V3 untuk koreksi harga pool kosong. Kontrak
    ///         ini tidak pernah membayar apa pun: delta positif = revert.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /* data */
    ) external view {
        if (_poolInCorrection == address(0) || msg.sender != _poolInCorrection) {
            revert UnexpectedCallback();
        }
        if (amount0Delta > 0 || amount1Delta > 0) revert PoolPriceManipulated();
    }

    /// @dev Sisa agent token dikirim ke 0xdead (tidak boleh nyangkut &
    ///      tidak boleh dijual lagi); sisa WETH dikembalikan ke owner/treasury.
    function _sweepDust(address tokenAddr) internal {
        uint256 tokenDust = IERC20(tokenAddr).balanceOf(address(this));
        if (tokenDust > 0) IERC20(tokenAddr).safeTransfer(DEAD, tokenDust);

        uint256 wethDust = IERC20(weth).balanceOf(address(this));
        if (wethDust > 0) IERC20(weth).safeTransfer(owner(), wethDust);
    }

    function _orderTokens(address tokenA, address tokenB, uint256 amountA, uint256 amountB)
        internal
        pure
        returns (address token0, address token1, uint256 amount0, uint256 amount1)
    {
        if (tokenA < tokenB) {
            return (tokenA, tokenB, amountA, amountB);
        }
        return (tokenB, tokenA, amountB, amountA);
    }

    /// @dev FIX #2: versi lama menghitung `amount1 * (1 << 192)` yang overflow
    ///      total kalau amount1 adalah sisi agent token (~2e26 * 6.3e57 = 1.3e84
    ///      >> uint256.max). Artinya ~50% graduasi (kasus tokenAddr > weth)
    ///      pasti revert. Sekarang:
    ///        - pakai Math.mulDiv (512-bit intermediate, tidak bisa overflow),
    ///        - basis X128 lalu sqrt -> hasil X64, di-shift 32 bit jadi X96.
    ///      Presisi 64 bit fraksional sudah jauh lebih dari cukup.
    function _computeSqrtPriceX96(uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint160)
    {
        require(amount0 > 0 && amount1 > 0, "zero amount");

        uint256 ratioX128 = Math.mulDiv(amount1, 1 << 128, amount0);
        uint256 sqrtPriceX96 = Math.sqrt(ratioX128) << 32;

        if (
            sqrtPriceX96 < MIN_SQRT_RATIO ||
            sqrtPriceX96 > MAX_SQRT_RATIO
        ) revert InvalidSqrtPrice();

        return uint160(sqrtPriceX96);
    }

    receive() external payable {}
}
