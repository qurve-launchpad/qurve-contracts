// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/// @title INonfungiblePositionManager (vendored)
/// @notice Versi vendor lokal dari interface NonfungiblePositionManager
///         Uniswap V3 (npm: uniswap/v3-periphery), ditulis ulang untuk pragma
///         0.8.x + OpenZeppelin v5.
///
///         KENAPA DI-VENDOR, BUKAN IMPORT LANGSUNG DARI node_modules:
///         file resmi di package v3-periphery, path contracts/interfaces/
///         INonfungiblePositionManager.sol, masih meng-import OZ dengan path
///         lama (`token/ERC721/IERC721Metadata.sol`) yang sejak OZ v4 sudah
///         pindah ke `token/ERC721/extensions/`. Di pnpm/yarn strict mode itu
///         bikin compile gagal (HH404). Lihat Uniswap/v3-periphery#335.
///
///         ⚠️ SIGNATURE WAJIB 1:1 dengan kontrak yang sudah ter-deploy
///         on-chain (canonical: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88 di
///         Ethereum/Polygon/Optimism/Arbitrum — CEK alamat per-chain sebelum
///         deploy). Selector dihitung dari signature, jadi satu tipe yang
///         meleset = call revert / salah fungsi. Jangan "rapikan" tipe apa pun
///         di file ini. Struct field ORDER juga signifikan untuk ABI encoding.
///
///         Cakupan: hanya bagian yang dipakai proyek ini + fungsi manajemen
///         posisi yang paling umum. Bagian selfPermit/multicall/IERC721Permit
///         sengaja tidak disertakan karena tidak dipakai; kalau nanti butuh,
///         tambahkan dengan signature persis dari package resmi.
interface INonfungiblePositionManager is
    IERC721,
    IERC721Metadata,
    IERC721Enumerable
{
    // ───────────────────────────────────────────── Events ───

    event IncreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event DecreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event Collect(
        uint256 indexed tokenId,
        address recipient,
        uint256 amount0,
        uint256 amount1
    );

    // ──────────────────────────────── IPeripheryImmutableState ───

    /// @notice Alamat UniswapV3Factory yang dipakai position manager ini.
    function factory() external view returns (address);

    /// @notice Alamat WETH9 yang dipakai position manager ini.
    function WETH9() external view returns (address);

    // ──────────────────────────────────────── IPoolInitializer ───

    /// @notice Buat pool kalau belum ada, lalu inisialisasi harganya.
    ///         Kalau pool sudah ada DAN sudah ter-inisialisasi, fungsi ini
    ///         tidak mengubah apa pun dan hanya mengembalikan alamat pool —
    ///         `sqrtPriceX96` yang dikirim akan DIABAIKAN. Itu sebabnya
    ///         GraduationManager tetap butuh slippage guard di `mint()`.
    /// @param token0 Token dengan alamat lebih kecil (wajib terurut).
    /// @param token1 Token dengan alamat lebih besar.
    /// @param fee Fee tier pool (500 / 3000 / 10000).
    /// @param sqrtPriceX96 Harga awal sebagai sqrt(token1/token0) Q64.96.
    /// @return pool Alamat pool (baru atau yang sudah ada).
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    // ─────────────────────────────────────────── Positions ───

    /// @notice Detail posisi untuk `tokenId`.
    /// @dev Urutan return value WAJIB persis seperti ini — decoding-nya
    ///      positional, bukan by-name.
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Mint posisi baru dan bungkus jadi NFT ke `params.recipient`.
    /// @dev Memakai `_mint` (bukan `_safeMint`), jadi aman mengirim ke
    ///      address non-ERC721Receiver seperti 0xdead.
    ///      Pool WAJIB sudah ter-inisialisasi, dan tick WAJIB kelipatan
    ///      tickSpacing fee tier-nya (fee 3000 → spacing 60).
    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    /// @notice Burn NFT posisi. Hanya bisa kalau liquidity == 0 dan
    ///         tokensOwed0/1 == 0.
    function burn(uint256 tokenId) external payable;

    // ──────────────────────────────────── IPeripheryPayments ───

    /// @notice Kembalikan sisa ETH yang nyangkut di position manager ke caller.
    function refundETH() external payable;

    /// @notice Unwrap WETH9 yang dipegang position manager lalu kirim ke
    ///         `recipient` sebagai ETH.
    function unwrapWETH9(uint256 amountMinimum, address recipient)
        external
        payable;

    /// @notice Sapu sisa token yang dipegang position manager ke `recipient`.
    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable;
}
