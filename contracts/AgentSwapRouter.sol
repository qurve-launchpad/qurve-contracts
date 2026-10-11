// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapRouter} from "./interfaces/uniswap/ISwapRouter.sol";
import {IWETH9} from "./interfaces/uniswap/IWETH9.sol";
import {IAgentBondingCurve} from "./interfaces/IAgentBondingCurve.sol";
import {AgentBondingCurve} from "./AgentBondingCurve.sol";
import {AgentTokenFactory} from "./AgentTokenFactory.sol";
import {GraduationManager} from "./GraduationManager.sol";
import {HolderRewardsDistributor} from "./HolderRewardsDistributor.sol";

/// @title AgentSwapRouter
/// @notice Canonical entry point for swapping agent tokens that have
///         graduated, if you want the platform fee to still apply. One
///         instance is deployed PER CHAIN (not per token).
///
///         MULTI-CHAIN: this contract is identical on every chain, but
///         `requiresWrap` & `nativeToQuoteDecimalOffset` are copied from
///         GraduationManager at construction time (single source of truth,
///         impossible to mismatch between the two contracts on the same
///         chain):
///           - Base / Robinhood Chain -> requiresWrap=true, quoteAsset=WETH, offset=1
///           - BOT Chain              -> requiresWrap=true, quoteAsset=WBOT, offset=1
///             (WBOT = wrapped native BOT; must implement the same
///             deposit()/withdraw() interface as WETH9 — verify the actual
///             WBOT contract before deploying, do not assume)
///           - Arc Testnet/Mainnet    -> requiresWrap=false, quoteAsset=USDC
///             precompile-style (native & ERC-20 share the same balance),
///             offset=1e12 (native 18 decimals -> USDC 6 decimals)
///
///         Post-graduation fee split is 1% (0.5% platform + 0.5% flex),
///         same on every chain — see _routeFee().
///
///         LIMITATION: this fee is only charged when the trader swaps
///         through this contract. The Uniswap V3 pool is public &
///         permissionless — there is no protocol-level way to enforce it.
contract AgentSwapRouter is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────── Immutable Config ───

    ISwapRouter public immutable swapRouter;

    /// @notice Quote asset address for this chain: WETH (Base/Robinhood),
    ///         WBOT (BOT Chain), or the native-USDC ERC-20 precompile (Arc).
    ///         Cast to IWETH9 ONLY when requiresWrap == true — on Arc, this
    ///         address does not implement deposit()/withdraw() at all.
    address public immutable quoteAsset;

    address public immutable protocolFeeRecipient;
    AgentTokenFactory public immutable agentFactory;
    GraduationManager public immutable graduationManager;

    /// @dev Copied from GraduationManager at construction, NOT passed as a
    ///      separate parameter — impossible for the two contracts to be
    ///      configured differently for the same chain.
    bool public immutable requiresWrap;
    uint256 public immutable nativeToQuoteDecimalOffset;

    /// @dev Fee tier of the pool — MUST match POOL_FEE in
    ///      GraduationManager when the pool was created.
    uint24 public constant POOL_FEE = 3000; // 0.3%

    // ─────────────────────────────────────────── Fee Constants ───

    uint16 public constant PLATFORM_FEE_BPS = 50; // 0.5%
    uint16 public constant FLEX_FEE_BPS = 50;     // 0.5%
    uint16 public constant FEE_BPS = 100;         // 1% total, post-graduation
    uint16 public constant BPS_DENOM = 10_000;

    // ─────────────────────────────────────────── Events ───

    event SwapExecuted(
        address indexed trader,
        address indexed agentToken,
        bool isBuy,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feePaid
    );

    /// @notice FIX H1: emitted when the flex 0.5% couldn't be routed to
    ///         the HolderRewardsDistributor (because the router hasn't
    ///         been registered as a notifier yet, or the distributor
    ///         doesn't exist), so it was redirected to the treasury to
    ///         avoid reverting the swap. Backend should alert on this —
    ///         admin needs to call GraduationManager.setSwapRouter() or
    ///         HolderRewardsDistributor.setNotifier() for the affected token.
    event FlexFeeReroutedToTreasury(address indexed agentToken, uint256 amount);

    // ─────────────────────────────────────────── Errors ───

    error ZeroAmount();
    error NotGraduated();
    error UnknownAgentToken();
    error SlippageExceeded();
    error TransferFailed();
    /// @notice FIX C1 + H2: thrown when rewardMode == HOLDERS but the
    ///         HolderRewardsDistributor hasn't been deployed yet. This
    ///         means the curve auto-locked (via threshold or sell-out) but
    ///         GraduationManager.graduate() hasn't been called yet. Reverting
    ///         here (instead of letting the call proceed) prevents the
    ///         router from sending flexCut to address(0) — which would
    ///         silently burn the ETH.
    error DistributorNotReady();

    // ─────────────────────────────────────────── Constructor ───

    constructor(
        address _swapRouter,
        address _quoteAsset,
        address _protocolFeeRecipient,
        address _agentFactory,
        address _graduationManager
    ) Ownable(msg.sender) {
        swapRouter = ISwapRouter(_swapRouter);
        quoteAsset = _quoteAsset;
        protocolFeeRecipient = _protocolFeeRecipient;
        agentFactory = AgentTokenFactory(_agentFactory);
        // GraduationManager has a payable receive() fallback, so the address
        // must be wrapped in payable() before casting to the contract type.
        graduationManager = GraduationManager(payable(_graduationManager));

        // Single source of truth — copied from GraduationManager, not passed
        // in manually, so the two contracts can never disagree for the same
        // chain.
        requiresWrap = graduationManager.requiresWrap();
        nativeToQuoteDecimalOffset = graduationManager.nativeToQuoteDecimalOffset();
        require(nativeToQuoteDecimalOffset > 0, "offset=0");
    }

    // ─────────────────────────────────────────── Buy ───

    /// @notice Buy agentToken with this chain's native currency (ETH/BOT/
    ///         native-USDC on Arc), through the already-graduated Uniswap V3
    ///         pool. The 1% fee is taken BEFORE the swap (from native in).
    function buy(address agentToken, uint256 minTokensOut)
        external
        payable
        nonReentrant
        returns (uint256 tokensOut)
    {
        if (msg.value == 0) revert ZeroAmount();
        AgentBondingCurve curve = _resolveGraduatedCurve(agentToken);

        uint256 fee = (msg.value * FEE_BPS) / BPS_DENOM;
        uint256 swapAmountNative = msg.value - fee;

        if (requiresWrap) {
            IWETH9(quoteAsset).deposit{value: swapAmountNative}();
        }
        // If !requiresWrap (Arc): the native balance received above is
        // AUTOMATICALLY also the ERC-20 quoteAsset balance for address(this)
        // — there is no deposit() call to make (native & ERC-20 share the
        // same balance at the chain level).

        // Convert scale: native (18 decimals) -> the ERC-20 quote scale
        // actually used by the Uniswap pool (WETH/WBOT: /1, USDC-native Arc: /1e12).
        uint256 amountInForSwap = swapAmountNative / nativeToQuoteDecimalOffset;

        IERC20(quoteAsset).forceApprove(address(swapRouter), amountInForSwap);
        tokensOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: quoteAsset,
                tokenOut: agentToken,
                fee: POOL_FEE,
                recipient: msg.sender,
                amountIn: amountInForSwap,
                amountOutMinimum: minTokensOut,
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(quoteAsset).forceApprove(address(swapRouter), 0);

        if (fee > 0) _routeFee(agentToken, curve, fee);

        emit SwapExecuted(msg.sender, agentToken, true, msg.value, tokensOut, fee);
    }

    // ─────────────────────────────────────────── Sell ───

    /// @notice Sell agentToken, receive this chain's native currency back.
    ///         The 1% fee is taken AFTER the swap (from native out).
    function sell(
        address agentToken,
        uint256 tokensIn,
        uint256 minEthOut
    ) external nonReentrant returns (uint256 ethOut) {
        if (tokensIn == 0) revert ZeroAmount();
        AgentBondingCurve curve = _resolveGraduatedCurve(agentToken);

        IERC20(agentToken).safeTransferFrom(msg.sender, address(this), tokensIn);
        IERC20(agentToken).forceApprove(address(swapRouter), tokensIn);

        uint256 quoteOutGross = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: agentToken,
                tokenOut: quoteAsset,
                fee: POOL_FEE,
                recipient: address(this),
                amountIn: tokensIn,
                amountOutMinimum: 0, // slippage checked below, after fee
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(agentToken).forceApprove(address(swapRouter), 0);

        if (requiresWrap) {
            IWETH9(quoteAsset).withdraw(quoteOutGross);
        }
        // If !requiresWrap (Arc): the ERC-20 quoteAsset balance received from
        // the swap is AUTOMATICALLY the native balance of address(this) too
        // — there is no withdraw() call to make.

        // Convert back: quote ERC-20 scale -> native (inverse of buy()).
        uint256 ethOutGrossNative = quoteOutGross * nativeToQuoteDecimalOffset;

        uint256 fee = (ethOutGrossNative * FEE_BPS) / BPS_DENOM;
        ethOut = ethOutGrossNative - fee;
        if (ethOut < minEthOut) revert SlippageExceeded();

        if (fee > 0) _routeFee(agentToken, curve, fee);

        (bool sent, ) = msg.sender.call{value: ethOut}("");
        if (!sent) revert TransferFailed();

        emit SwapExecuted(msg.sender, agentToken, false, tokensIn, ethOut, fee);
    }

    // ─────────────────────────────────────────── Internal ───

    /// @dev FIX H2: for HOLDERS mode, distributor existence is used as the
    ///      on-chain signal that graduation migration completed. The
    ///      `graduated` flag on the curve alone is NOT sufficient — it's
    ///      set as soon as the curve locks itself (in _executeBuy when
    ///      threshold is met), which is BEFORE GraduationManager.graduate()
    ///      is called. Without this check, a swap in the window between
    ///      auto-lock and actual migration would revert with a cryptic
    ///      Uniswap error (pool doesn't exist yet).
    ///
    ///      For CREATOR mode there's no distributor to check. In that case
    ///      the router will call the Uniswap pool directly — if the pool
    ///      hasn't been created yet, Uniswap itself will revert. This
    ///      window is short in practice (keeper runs every 10 min).
    function _resolveGraduatedCurve(address agentToken)
        internal
        view
        returns (AgentBondingCurve curve)
    {
        address curveAddr = agentFactory.curveOfToken(agentToken);
        if (curveAddr == address(0)) revert UnknownAgentToken();
        curve = AgentBondingCurve(payable(curveAddr));
        if (!curve.isGraduated()) revert NotGraduated();

        if (curve.rewardMode() == IAgentBondingCurve.RewardMode.HOLDERS) {
            if (graduationManager.distributorOf(agentToken) == address(0)) {
                revert DistributorNotReady();
            }
        }
    }

    /// @dev Platform 0.5% always goes directly to treasury. Flex 0.5% follows
    ///      the SAME rewardMode as the bonding-curve phase (immutable, cannot
    ///      differ between curve phase and post-graduation for the same
    ///      token). Always paid in this chain's native currency.
    ///
    ///      FIX C1: guard against `dist == address(0)` before calling
    ///      notifyRewardAmount — calling a non-existent contract with value
    ///      succeeds on the EVM and silently BURNS the ETH, because
    ///      address(0) has no code to reject or accept the funds.
    ///
    ///      FIX H1: if the distributor exists but hasn't registered this
    ///      router as a notifier yet (because setSwapRouter was called
    ///      after this token graduated — it's not retroactive), redirect
    ///      the flexCut to the treasury instead of reverting the swap.
    ///      This keeps swaps working; backend alerts on the
    ///      FlexFeeReroutedToTreasury event so admin can fix the config.
    function _routeFee(
        address agentToken,
        AgentBondingCurve curve,
        uint256 totalFee
    ) internal {
        uint256 platformCut = (totalFee * PLATFORM_FEE_BPS) / FEE_BPS;
        uint256 flexCut = totalFee - platformCut;

        if (platformCut > 0) {
            (bool sent, ) = protocolFeeRecipient.call{value: platformCut}("");
            if (!sent) revert TransferFailed();
        }

        if (flexCut > 0) {
            if (curve.rewardMode() == IAgentBondingCurve.RewardMode.HOLDERS) {
                address dist = graduationManager.distributorOf(agentToken);

                // FIX C1: distributor must exist. If it doesn't, this swap
                // happened before graduation migration completed — which
                // shouldn't happen because _resolveGraduatedCurve() already
                // checks. This is a defensive second guard.
                if (dist == address(0)) revert DistributorNotReady();

                HolderRewardsDistributor distributor = HolderRewardsDistributor(dist);

                if (distributor.isNotifier(address(this))) {
                    distributor.notifyRewardAmount{value: flexCut}();
                } else {
                    // FIX H1: distributor exists but router isn't authorized
                    // yet. Redirect to treasury to keep the swap working
                    // instead of reverting. Emit event so backend can
                    // alert admin to call setNotifier() on the distributor.
                    (bool sent, ) = protocolFeeRecipient.call{value: flexCut}("");
                    if (!sent) revert TransferFailed();
                    emit FlexFeeReroutedToTreasury(agentToken, flexCut);
                }
            } else {
                curve.topUpCreatorPool{value: flexCut}();
            }
        }
    }

    /// @dev Receives native currency from quoteAsset.withdraw() in the sell()
    ///      flow (only when requiresWrap == true).
    receive() external payable {}
}
