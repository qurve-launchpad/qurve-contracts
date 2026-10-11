// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AgentToken} from "./AgentToken.sol";
import {AgentBondingCurve} from "./AgentBondingCurve.sol";
import {IAgentBondingCurve} from "./interfaces/IAgentBondingCurve.sol";
import {IAgentLaunchRegistry} from "./interfaces/IAgentLaunchRegistry.sol";

/// @title AgentTokenFactory
/// @notice Entry point for launching a new agent in a single transaction.
///
///         LAUNCH FEE:
///         Flat anti-spam fee per launch, mutable by owner. Set once at
///         construction (per chain — the amount differs because native
///         assets differ: 0.0005 ETH on Base/Robinhood, 0.1 BOT on BOT
///         Chain, 1 USDC on Arc). Owner can update later if native price
///         moves significantly, subject to MAX_LAUNCH_FEE hard cap.
contract AgentTokenFactory is Ownable, ReentrancyGuard {
    struct LaunchParams {
        string name;
        string symbol;
        string agentURI;
        string endpoint;
        uint256 virtualEthReserve;
        uint256 devBuyMinTokensOut;
        /// @notice Direction of the flex 1% fee. Immutable per token.
        ///         CREATOR -> fee goes to pendingCreatorClaim (manual claim)
        ///         HOLDERS -> fee goes to pendingHolderPool, flushed to a
        ///                    HolderRewardsDistributor at graduation
        IAgentBondingCurve.RewardMode rewardMode;
    }

    // ─────────────────────────────────────────── Immutable ───

    IAgentLaunchRegistry public immutable registry;
    address public immutable weth;
    address public immutable protocolFeeRecipient;

    // ─────────────────────────────────────────── Constants ───

    /// @notice Hard cap on launchFee. Prevents owner (or a compromised key)
    ///         from setting an absurdly high fee. Sized generously (1 native
    ///         unit) so Arc's 1 USDC and BOT's 0.1 BOT both fit comfortably.
    ///         If a future chain needs a higher fee, redeploy with a larger
    ///         cap — do NOT raise this in place without considering the
    ///         rug-vector that an unbounded owner can create.
    uint256 public constant MAX_LAUNCH_FEE = 1 ether;

    /// @notice Fixed tokenomics — identical for every launch.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;         // 1B
    uint256 public constant TOKENS_FOR_SALE = 800_000_000 ether;        // 80%
    uint256 public constant TOKENS_FOR_LIQUIDITY = 200_000_000 ether;   // 20%
    uint256 public constant VIRTUAL_TOKEN_RESERVE = 1_073_000_000 ether; // pump.fun convention

    // ─────────────────────────────────────────── Mutable State ───

    /// @notice Flat anti-spam launch fee, in wei of this chain's native
    ///         token. Set at construction, updatable by owner. Applicable
    ///         to the NEXT launch — no retroactive effect.
    uint256 public launchFee;

    address public graduationManager;
    bool public antiSnipeEnabled;

    address[] public allTokens;
    address[] public allCurves;
    mapping(address => bool) public isAgentToken;
    mapping(address => address) public curveOfToken;

    // ─────────────────────────────────────────── Events ───

    event AgentLaunched(
        uint256 indexed agentId,
        address indexed creator,
        address token,
        address curve,
        string name,
        string symbol,
        uint256 virtualEthReserve,
        uint256 graduationThreshold,
        bool antiSnipeEnabled,
        IAgentBondingCurve.RewardMode rewardMode
    );

    event AntiSnipeToggled(bool enabled);
    event GraduationManagerUpdated(address indexed oldManager, address indexed newManager);
    event LaunchFeeUpdated(uint256 oldFee, uint256 newFee);

    // ─────────────────────────────────────────── Errors ───

    error InsufficientLaunchFee();
    error EmptyName();
    error EmptySymbol();
    error ZeroAddress();
    error InvalidVirtualReserve();
    error FeeTransferFailed();
    error GraduationManagerNotSet();
    error InvalidLaunchFee();

    // ─────────────────────────────────────────── Constructor ───

    constructor(
        address registry_,
        address weth_,
        address protocolFeeRecipient_,
        address initialOwner,
        uint256 initialLaunchFee_
    ) Ownable(initialOwner) {
        if (
            registry_ == address(0) ||
            weth_ == address(0) ||
            protocolFeeRecipient_ == address(0)
        ) revert ZeroAddress();

        if (initialLaunchFee_ == 0 || initialLaunchFee_ > MAX_LAUNCH_FEE) {
            revert InvalidLaunchFee();
        }

        registry = IAgentLaunchRegistry(registry_);
        weth = weth_;
        protocolFeeRecipient = protocolFeeRecipient_;
        launchFee = initialLaunchFee_;
    }

    // ─────────────────────────────────────────── Launch ───

    /// @notice Launch a new agent. Creator pays launchFee + optional dev-buy.
    function launchAgent(LaunchParams calldata p)
        external
        payable
        nonReentrant
        returns (address token, address curve, uint256 agentId)
    {
        uint256 fee = launchFee;

        if (msg.value < fee) revert InsufficientLaunchFee();
        if (bytes(p.name).length == 0) revert EmptyName();
        if (bytes(p.symbol).length == 0) revert EmptySymbol();
        if (p.virtualEthReserve == 0) revert InvalidVirtualReserve();
        if (graduationManager == address(0)) revert GraduationManagerNotSet();

        // ── 1. Forward launch fee to protocol ──
        (bool sent, ) = protocolFeeRecipient.call{value: fee}("");
        if (!sent) revert FeeTransferFailed();

        // ── 2. Deploy the token ──
        AgentToken newToken = new AgentToken(p.name, p.symbol, address(this));
        token = address(newToken);

        // ── 3. Deploy the curve (with creator's chosen rewardMode) ──
        AgentBondingCurve newCurve = new AgentBondingCurve(
            address(this),              // factory
            msg.sender,                 // creator
            weth,
            graduationManager,
            protocolFeeRecipient,
            antiSnipeEnabled,
            p.rewardMode,
            VIRTUAL_TOKEN_RESERVE,
            p.virtualEthReserve,
            TOKENS_FOR_SALE,
            TOKENS_FOR_LIQUIDITY
        );
        curve = address(newCurve);

        // ── 4. Mint the full supply to the curve ──
        newToken.mintInitialSupply(curve, TOTAL_SUPPLY);

        // ── 5. Lock the curve as the only minter/burner ──
        newToken.initialize(curve, msg.sender);

        // ── 6. Lock the token as the curve's official token ──
        // newCurve.initialize() reverts if the token balance on the curve
        // does not exactly equal TOKENS_FOR_SALE + TOKENS_FOR_LIQUIDITY.
        newCurve.initialize(newToken);

        // ── 7. Register in the ERC-8004 Identity Registry ──
        agentId = registry.registerAgent(
            msg.sender,
            token,
            curve,
            p.name,
            p.agentURI,
            p.endpoint
        );

        // ── 8. Optional dev-buy ──
        uint256 devBuyAmount = msg.value - fee;
        if (devBuyAmount > 0) {
            newCurve.buyFor{value: devBuyAmount}(
                devBuyAmount,
                p.devBuyMinTokensOut,
                msg.sender
            );
        }

        // ── 9. Track ──
        allTokens.push(token);
        allCurves.push(curve);
        isAgentToken[token] = true;
        curveOfToken[token] = curve;

        emit AgentLaunched(
            agentId,
            msg.sender,
            token,
            curve,
            p.name,
            p.symbol,
            p.virtualEthReserve,
            newCurve.graduationThreshold(),
            antiSnipeEnabled,
            p.rewardMode
        );
    }

    // ─────────────────────────────────────────── Admin ───

    function setGraduationManager(address manager) external onlyOwner {
        if (manager == address(0)) revert ZeroAddress();
        address old = graduationManager;
        graduationManager = manager;
        emit GraduationManagerUpdated(old, manager);
    }

    function setAntiSnipeEnabled(bool enabled) external onlyOwner {
        antiSnipeEnabled = enabled;
        emit AntiSnipeToggled(enabled);
    }

    /// @notice Update the flat anti-spam launch fee. Owner-only. Applies to
    ///         the NEXT launch; already-launched agents are unaffected.
    /// @param newFee New fee in wei of the native token for this chain.
    function setLaunchFee(uint256 newFee) external onlyOwner {
        if (newFee == 0 || newFee > MAX_LAUNCH_FEE) revert InvalidLaunchFee();
        uint256 old = launchFee;
        launchFee = newFee;
        emit LaunchFeeUpdated(old, newFee);
    }

    // ─────────────────────────────────────────── Views ───

    function totalLaunched() external view returns (uint256) {
        return allTokens.length;
    }

    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }

    function getAllCurves() external view returns (address[] memory) {
        return allCurves;
    }
}
