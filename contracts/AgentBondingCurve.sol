// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAgentBondingCurve} from "./interfaces/IAgentBondingCurve.sol";
import {IAgentToken} from "./interfaces/IAgentToken.sol";

/// @title AgentBondingCurve
/// @notice Bonding curve for one agent token. Model: constant product
///         (x * y = k) with virtual reserves — pump.fun style, but with
///         native gas token as the quote asset.
///
///         Formula:
///           virtualTokenReserve_effective = virtualTokenReserve - tokensSold
///           virtualEthReserve_effective   = virtualEthReserve + realEthReserve
///           k = virtualTokenReserve_effective * virtualEthReserve_effective
///
///         Total 2% fee per trade, split 2-way:
///           1.0% platform → sent immediately to protocolFeeRecipient
///           1.0% flex     → routed based on immutable `rewardMode`:
///                             CREATOR -> pendingCreatorClaim (manual claim)
///                             HOLDERS -> pendingHolderPool, flushed to a
///                                        HolderRewardsDistributor at graduation
///
///         Anti-snipe surtax (optional): up to +4%, linear decay to 0 over 60s.
///         The anti-snipe portion is added to realEthReserve (not routed as a
///         fee) — intentionally so the early window raises price faster
///         instead of just moving ETH to fee recipients.
///
///         GRADUATION MODEL (fix C-1): the curve is NEVER locked merely
///         because the threshold / sell-out was reached. Buy and sell stay
///         open until GraduationManager.graduate() completes the whole
///         migration (pool + LP + distributor) and calls markGraduated().
///         If migration fails or is stuck, the whole graduate() tx reverts
///         and holders can keep selling here to exit — funds can never be
///         trapped by a failed migration.
contract AgentBondingCurve is IAgentBondingCurve, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────── Immutable Config ───

    address public immutable factory;
    address public immutable creator;
    address public immutable weth;
    address public immutable graduationManager;
    address public immutable protocolFeeRecipient;

    bool public immutable antiSnipeEnabled;
    uint256 public immutable launchedAt;

    /// @notice Flex 1% fee direction. Immutable, set once at construction.
    RewardMode public immutable rewardMode;

    uint256 public immutable virtualTokenReserve;
    uint256 public immutable virtualEthReserve;
    uint256 public immutable tokensForSale;
    uint256 public immutable tokensForLiquidity;
    uint256 public immutable graduationThreshold;

    // ─────────────────────────────────────────── Constants ───

    uint16 public constant PLATFORM_FEE_BPS = 100; // 1.0%
    uint16 public constant FLEX_FEE_BPS = 100;     // 1.0%
    uint16 public constant FEE_BPS = 200;          // 2% total
    uint16 public constant BPS_DENOM = 10_000;

    uint16 public constant ANTI_SNIPE_MAX_BPS = 400; // +4% at t=0
    uint256 public constant ANTI_SNIPE_WINDOW = 60;  // decay window

    /// @notice If no trade happens for this long, an abandoned HOLDERS pool
    ///         can be swept back to the platform (only if curve never graduated).
    uint256 public constant ABANDON_TIMEOUT = 30 days;

    // ─────────────────────────────────────────── Mutable State ───

    IAgentToken public agentToken;
    bool public initialized;

    uint256 public tokensSold;
    uint256 public realEthReserve;
    bool public graduated;

    /// @notice True only INSIDE a graduate() transaction, between
    ///         withdrawReserveForGraduation() and markGraduated(). Because
    ///         graduate() is atomic, any revert rolls this back to false.
    bool public migrationStarted;

    /// @dev Snapshot of liquidity actually withdrawn at graduation time.
    ///      Needed for the Graduated event because realEthReserve is already
    ///      zeroed by withdrawReserveForGraduation().
    uint256 public ethWithdrawnForGraduation;
    uint256 public tokensWithdrawnForGraduation;

    /// @notice Accumulated flex fee when rewardMode == CREATOR.
    uint256 public pendingCreatorClaim;

    /// @notice Accumulated flex fee when rewardMode == HOLDERS, flushed to
    ///         the HolderRewardsDistributor at graduation.
    uint256 public pendingHolderPool;

    /// @notice Timestamp of the last trade (buy or sell). Initialized to
    ///         launchedAt. Used by sweepAbandonedHolderPool() to decide if
    ///         the curve is truly abandoned.
    uint256 public lastTradeAt;

    // ─────────────────────────────────────────── Errors ───

    error NotFactory();
    error NotCreator();
    error NotGraduationManager();
    error AlreadyInitialized();
    error NotInitialized();
    error AlreadyGraduated();
    error NotGraduated();
    error ZeroAmount();
    error SlippageExceeded();
    error InsufficientReserve();
    error TransferFailed();
    error WrongRewardMode();
    error NotAbandonedYet();
    error NotYetEligible();
    error GraduationPending();
    error MigrationNotStarted();
    error MigrationAlreadyStarted();

    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }

    modifier notGraduated() {
        if (graduated) revert AlreadyGraduated();
        _;
    }

    // ─────────────────────────────────────────── Constructor ───

    constructor(
        address _factory,
        address _creator,
        address _weth,
        address _graduationManager,
        address _protocolFeeRecipient,
        bool _antiSnipeEnabled,
        RewardMode _rewardMode,
        uint256 _virtualTokenReserve,
        uint256 _virtualEthReserve,
        uint256 _tokensForSale,
        uint256 _tokensForLiquidity
    ) {
        require(_virtualEthReserve > 0, "virtualEthReserve=0");
        require(
            _virtualTokenReserve > _tokensForSale,
            "tokensForSale>=virtualTokenReserve"
        );

        factory = _factory;
        creator = _creator;
        weth = _weth;
        graduationManager = _graduationManager;
        protocolFeeRecipient = _protocolFeeRecipient;
        antiSnipeEnabled = _antiSnipeEnabled;
        rewardMode = _rewardMode;
        launchedAt = block.timestamp;
        lastTradeAt = block.timestamp;

        virtualTokenReserve = _virtualTokenReserve;
        virtualEthReserve = _virtualEthReserve;
        tokensForSale = _tokensForSale;
        tokensForLiquidity = _tokensForLiquidity;

        // Derive graduationThreshold from constant product:
        //   k = virtualTokenReserve * virtualEthReserve
        //   tReserveAtSellOut = virtualTokenReserve - tokensForSale
        //   ethReserveAtSellOut = k / tReserveAtSellOut
        //   graduationThreshold = ethReserveAtSellOut - virtualEthReserve
        uint256 tReserveAtSellOut = _virtualTokenReserve - _tokensForSale;
        uint256 k = _virtualTokenReserve * _virtualEthReserve;
        uint256 ethReserveAtSellOut = k / tReserveAtSellOut;
        graduationThreshold = ethReserveAtSellOut - _virtualEthReserve;
    }

    /// @notice Called once by the factory after the token is deployed.
    function initialize(IAgentToken _agentToken) external {
        if (msg.sender != factory) revert NotFactory();
        if (initialized) revert AlreadyInitialized();
        if (address(_agentToken) == address(0)) revert ZeroAmount();

        // Token must hold exactly tokensForSale + tokensForLiquidity
        uint256 bal = IERC20(address(_agentToken)).balanceOf(address(this));
        require(
            bal == tokensForSale + tokensForLiquidity,
            "bad initial supply"
        );

        agentToken = _agentToken;
        initialized = true;
    }

    // ─────────────────────────────────────────── Pricing ───

    function _currentTokenReserve() internal view returns (uint256) {
        return virtualTokenReserve - tokensSold;
    }

    function _currentEthReserve() internal view returns (uint256) {
        return virtualEthReserve + realEthReserve;
    }

    /// @notice Graduation status. Explicit getter needed for the interface
    ///         (auto-generated `graduated()` alone does not satisfy it).
    function isGraduated() external view override returns (bool) {
        return graduated;
    }

    /// @notice True when the curve has reached sell-out or the reserve
    ///         threshold and has not migrated yet. Pure view: it does NOT
    ///         lock trading. Used by GraduationManager / keeper / UI.
    function isGraduationEligible() public view returns (bool) {
        return
            !graduated &&
            (tokensSold >= tokensForSale ||
                realEthReserve >= graduationThreshold);
    }

    /// @notice Spot price (native per token, wei per wei).
    ///         price = ethReserve / tokenReserve
    function currentPrice() public view override returns (uint256) {
        uint256 tReserve = _currentTokenReserve();
        uint256 eReserve = _currentEthReserve();
        if (tReserve == 0) return type(uint256).max;
        return (eReserve * 1e18) / tReserve;
    }

    function _rawQuoteBuy(uint256 ethInAfterFee)
        internal
        view
        returns (uint256 tokensOut)
    {
        uint256 tReserve = _currentTokenReserve();
        uint256 eReserve = _currentEthReserve();
        uint256 k = tReserve * eReserve;
        uint256 newEReserve = eReserve + ethInAfterFee;
        uint256 newTReserve = k / newEReserve;
        tokensOut = tReserve - newTReserve;
    }

    /// @notice Quote buy, clamped to remaining supply (tokensForSale - tokensSold).
    function quoteBuy(uint256 ethInAfterFee)
        public
        view
        override
        returns (uint256 tokensOut)
    {
        tokensOut = _rawQuoteBuy(ethInAfterFee);
        uint256 remaining = tokensForSale - tokensSold;
        if (tokensOut > remaining) {
            tokensOut = remaining;
        }
    }

    /// @notice Quote sell. Rounding is pushed toward the curve side
    ///         (ceil on newEReserve), consistent with quoteBuy, so no dust
    ///         leaks to sellers over time.
    function quoteSell(uint256 tokensIn)
        public
        view
        override
        returns (uint256 ethOut)
    {
        uint256 tReserve = _currentTokenReserve();
        uint256 eReserve = _currentEthReserve();
        uint256 k = tReserve * eReserve;
        uint256 newTReserve = tReserve + tokensIn;
        uint256 newEReserve = (k + newTReserve - 1) / newTReserve;
        ethOut = eReserve - newEReserve;
    }

    // ─────────────────────────────────────────── Anti-Snipe ───

    function _antiSnipeFeeBps() internal view returns (uint256) {
        if (!antiSnipeEnabled) return 0;
        uint256 elapsed = block.timestamp - launchedAt;
        if (elapsed >= ANTI_SNIPE_WINDOW) return 0;
        return
            (uint256(ANTI_SNIPE_MAX_BPS) * (ANTI_SNIPE_WINDOW - elapsed)) /
            ANTI_SNIPE_WINDOW;
    }

    // ─────────────────────────────────────────── Buy ───

    function buy(uint256 ethIn, uint256 minTokensOut)
        external
        payable
        override
        nonReentrant
        onlyInitialized
        notGraduated
        returns (uint256 tokensOut)
    {
        tokensOut = _executeBuy(ethIn, minTokensOut, msg.sender);
    }

    /// @notice Called by the factory for a dev-buy within the launch tx.
    ///         Tokens and events are attributed to `buyer` (the creator).
    function buyFor(uint256 ethIn, uint256 minTokensOut, address buyer)
        external
        payable
        nonReentrant
        onlyInitialized
        notGraduated
        returns (uint256 tokensOut)
    {
        if (msg.sender != factory) revert NotFactory();
        require(buyer != address(0), "buyer=0");
        tokensOut = _executeBuy(ethIn, minTokensOut, buyer);
    }

    function _executeBuy(uint256 ethIn, uint256 minTokensOut, address buyer)
        internal
        returns (uint256 tokensOut)
    {
        if (ethIn == 0) revert ZeroAmount();
        require(msg.value == ethIn, "value mismatch");

        // ── Compute fee ──
        uint256 fee = (ethIn * FEE_BPS) / BPS_DENOM;
        uint256 antiSnipeFee = (ethIn * _antiSnipeFeeBps()) / BPS_DENOM;
        uint256 amountAfterFee = ethIn - fee - antiSnipeFee;

        tokensOut = _rawQuoteBuy(amountAfterFee);

        // ── Partial-fill clamp near sell-out ──
        uint256 remaining = tokensForSale - tokensSold;
        uint256 refund = 0;

        if (tokensOut > remaining) {
            tokensOut = remaining;

            uint256 tReserve = _currentTokenReserve();
            uint256 eReserve = _currentEthReserve();
            uint256 k = tReserve * eReserve;
            uint256 newTReserve = tReserve - tokensOut;
            uint256 newEReserve = (k + newTReserve - 1) / newTReserve;
            uint256 amountAfterFeeNeeded = newEReserve - eReserve;

            uint256 totalFeeBps = FEE_BPS + _antiSnipeFeeBps();
            uint256 ethInNeeded = (amountAfterFeeNeeded * BPS_DENOM +
                (BPS_DENOM - totalFeeBps) -
                1) / (BPS_DENOM - totalFeeBps);

            if (ethInNeeded < ethIn) {
                refund = ethIn - ethInNeeded;
                ethIn = ethInNeeded;
                fee = (ethIn * FEE_BPS) / BPS_DENOM;
                antiSnipeFee = (ethIn * _antiSnipeFeeBps()) / BPS_DENOM;
                amountAfterFee = ethIn - fee - antiSnipeFee;
            }
        }

        require(tokensOut >= minTokensOut, "slippage");
        if (tokensOut == 0) revert ZeroAmount();

        // ── Update state ──
        tokensSold += tokensOut;
        realEthReserve += amountAfterFee + antiSnipeFee;
        lastTradeAt = block.timestamp;

        // ── Route fee ──
        if (fee > 0) _routeFee(fee);

        // ── Transfer token ──
        // The token was fully minted to the curve at launch, so a buy simply
        // transfers from the curve's balance — no mint call needed.
        IERC20(address(agentToken)).safeTransfer(buyer, tokensOut);

        emit Buy(buyer, ethIn, tokensOut, fee, antiSnipeFee);

        // ── Refund (partial fill) ──
        if (refund > 0) {
            (bool sent, ) = buyer.call{value: refund}("");
            if (!sent) revert TransferFailed();
        }

        // NOTE (fix C-1): no auto-lock here anymore. Reaching the threshold
        // only makes the curve *eligible* (see isGraduationEligible()); it
        // stays tradable until graduate() fully succeeds.
    }

    // ─────────────────────────────────────────── Sell ───

    function sell(uint256 tokensIn, uint256 minEthOut)
        external
        override
        nonReentrant
        onlyInitialized
        notGraduated
        returns (uint256 ethOut)
    {
        if (tokensIn == 0) revert ZeroAmount();

        // Pull tokens from the seller into the curve (to be burned)
        IERC20(address(agentToken)).safeTransferFrom(
            msg.sender,
            address(this),
            tokensIn
        );

        uint256 ethOutGross = quoteSell(tokensIn);
        uint256 fee = (ethOutGross * FEE_BPS) / BPS_DENOM;
        ethOut = ethOutGross - fee;

        require(ethOut >= minEthOut, "slippage");
        if (ethOutGross > realEthReserve) revert InsufficientReserve();

        tokensSold -= tokensIn;
        realEthReserve -= ethOutGross;
        lastTradeAt = block.timestamp;

        // Burn tokens
        agentToken.burn(address(this), tokensIn);

        // Route fee
        if (fee > 0) _routeFee(fee);

        // Send native back to seller
        (bool sent, ) = msg.sender.call{value: ethOut}("");
        if (!sent) revert TransferFailed();

        emit Sell(msg.sender, tokensIn, ethOut, fee);
    }

    // ─────────────────────────────────────────── Fee Routing ───

    /// @dev Split 1% platform + 1% flex. Platform is pushed immediately.
    ///      Flex is accumulated according to rewardMode.
    function _routeFee(uint256 totalFee) internal {
        uint256 platformCut = (totalFee * PLATFORM_FEE_BPS) / FEE_BPS;
        uint256 flexCut = totalFee - platformCut;

        if (platformCut > 0) {
            (bool sent, ) = protocolFeeRecipient.call{value: platformCut}("");
            if (!sent) revert TransferFailed();
        }

        if (flexCut > 0) {
            if (rewardMode == RewardMode.CREATOR) {
                pendingCreatorClaim += flexCut;
            } else {
                pendingHolderPool += flexCut;
            }
        }
    }

    // ─────────────────────────────────────────── Claim & Top-Up ───

    function claimCreatorFees() external override nonReentrant {
        if (msg.sender != creator) revert NotCreator();
        uint256 amount = pendingCreatorClaim;
        if (amount == 0) revert ZeroAmount();
        pendingCreatorClaim = 0;
        (bool sent, ) = creator.call{value: amount}("");
        if (!sent) revert TransferFailed();
        emit CreatorFeesClaimed(creator, amount);
    }

    /// @notice Permissionless top-up to pendingCreatorClaim. Used by the
    ///         AgentSwapRouter to route the post-graduation flex fee when
    ///         rewardMode == CREATOR, so the creator still claims from one
    ///         place (pendingCreatorClaim).
    ///
    ///         Guard `rewardMode == CREATOR` prevents funds from getting
    ///         stuck if someone calls this on a HOLDERS-mode curve — that
    ///         ETH would be locked forever (no claim path exists for it).
    function topUpCreatorPool() external payable override {
        if (rewardMode != RewardMode.CREATOR) revert WrongRewardMode();
        if (msg.value == 0) revert ZeroAmount();
        pendingCreatorClaim += msg.value;
    }

    // ─────────────────────────────────────────── Abandoned Pool ───

    /// @notice Permissionless. If the curve never graduated and there has
    ///         been no trade for ABANDON_TIMEOUT, sweep pendingHolderPool
    ///         back to the platform. Prevents flex funds from being stuck
    ///         forever on an abandoned curve.
    function sweepAbandonedHolderPool() external override nonReentrant {
        if (graduated) revert AlreadyGraduated();
        if (rewardMode != RewardMode.HOLDERS) revert WrongRewardMode();
        // A curve that is ready to graduate (but whose migration is stuck)
        // is not "abandoned" — its holder pool belongs to future stakers.
        if (isGraduationEligible()) revert GraduationPending();

        uint256 amount = pendingHolderPool;
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp < lastTradeAt + ABANDON_TIMEOUT) {
            revert NotAbandonedYet();
        }

        pendingHolderPool = 0;
        (bool sent, ) = protocolFeeRecipient.call{value: amount}("");
        if (!sent) revert TransferFailed();

        emit HolderPoolSwept(protocolFeeRecipient, amount);
    }

    // ─────────────────────────────────────────── Stray ETH ───

    /// @notice Permissionless. Sweep ETH that was sent directly to this
    ///         contract address (not via buy/topUpCreatorPool) to
    ///         protocolFeeRecipient.
    ///
    ///         Such ETH is not counted in any accounting bucket
    ///         (realEthReserve, pendingCreatorClaim, pendingHolderPool),
    ///         so without this function it would be stuck forever.
    ///
    ///         Reverts if there is nothing to sweep.
    function sweepStrayETH() external override nonReentrant {
        uint256 balance = address(this).balance;
        uint256 accounted =
            realEthReserve + pendingCreatorClaim + pendingHolderPool;

        if (balance <= accounted) revert ZeroAmount();

        uint256 stray = balance - accounted;
        (bool sent, ) = protocolFeeRecipient.call{value: stray}("");
        if (!sent) revert TransferFailed();

        emit StrayETHSwept(stray);
    }

    // ─────────────────────────────────────────── Graduation ───

    /// @notice Called by the GraduationManager as the LAST step of a fully
    ///         successful migration. This is the only place `graduated`
    ///         becomes true.
    function markGraduated(address pool, uint256 lpTokenId)
        external
        override
    {
        if (msg.sender != graduationManager) revert NotGraduationManager();
        if (!migrationStarted) revert MigrationNotStarted();
        graduated = true;
        migrationStarted = false;
        emit Graduated(
            pool,
            ethWithdrawnForGraduation,
            tokensWithdrawnForGraduation,
            lpTokenId
        );
    }

    /// @notice Called by the GraduationManager to pull the ETH reserve.
    function withdrawReserveForGraduation()
        external
        override
        returns (uint256 amount)
    {
        if (msg.sender != graduationManager) revert NotGraduationManager();
        // Fix C-1 / H-2: reserves can only leave the curve once it is
        // actually eligible, and only once per migration.
        if (migrationStarted) revert MigrationAlreadyStarted();
        if (!isGraduationEligible()) revert NotYetEligible();
        migrationStarted = true;

        amount = realEthReserve;
        realEthReserve = 0;
        ethWithdrawnForGraduation = amount;
        (bool sent, ) = msg.sender.call{value: amount}("");
        if (!sent) revert TransferFailed();
    }

    /// @notice Called by the GraduationManager to pull LP tokens.
    function withdrawTokensForGraduation()
        external
        override
        returns (uint256 amount)
    {
        if (msg.sender != graduationManager) revert NotGraduationManager();
        if (!migrationStarted) revert MigrationNotStarted();
        amount = IERC20(address(agentToken)).balanceOf(address(this));
        tokensWithdrawnForGraduation = amount;
        IERC20(address(agentToken)).safeTransfer(msg.sender, amount);
    }

    /// @notice Called by the GraduationManager to pull pendingHolderPool
    ///         (only when rewardMode == HOLDERS), so it can be flushed into
    ///         the HolderRewardsDistributor. Returns 0 for CREATOR mode.
    function withdrawHolderPoolForGraduation()
        external
        override
        returns (uint256 amount)
    {
        if (msg.sender != graduationManager) revert NotGraduationManager();
        if (!migrationStarted) revert MigrationNotStarted();
        if (rewardMode != RewardMode.HOLDERS) return 0;

        amount = pendingHolderPool;
        pendingHolderPool = 0;

        if (amount > 0) {
            (bool sent, ) = msg.sender.call{value: amount}("");
            if (!sent) revert TransferFailed();
        }
    }

    receive() external payable {}
}
