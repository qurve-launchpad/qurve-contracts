// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAgentToken} from "./interfaces/IAgentToken.sol";

/// @title AgentToken
/// @notice Token ERC-20 per-agen.
///
///         Lifecycle:
///         1. Factory deploy AgentToken → factory = msg.sender.
///         2. Factory panggil mintInitialSupply(curve, TOTAL_SUPPLY) → mint
///            seluruh supply ke curve. Wajib dipanggil SEBELUM initialize().
///         3. Factory panggil initialize(curve, creator) → curve dikunci
///            sebagai satu-satunya yang boleh mint/burn.
///         4. Setelah initialize, mint() dan burn() hanya bisa dipanggil
///            oleh curve. mintInitialSupply() tidak bisa dipanggil lagi.
///
///         Fungsi mint() tetap ada untuk keperluan future upgrade (misal
///         minting tambahan saat graduasi jika diperlukan).
contract AgentToken is ERC20, IAgentToken {
    // ─────────────────────────────────────────── Immutable ───

    address public immutable factory;

    // ─────────────────────────────────────────── State ───

    address private _curve;
    address private _agentOwner;
    bool private _initialized;

    // ─────────────────────────────────────────── Errors ───

    error AlreadyInitialized();
    error NotInitialized();
    error NotCurve();
    error NotFactory();
    error ZeroAddress();
    error InvalidAmount();

    // ─────────────────────────────────────────── Modifiers ───

    modifier onlyCurve() {
        if (msg.sender != _curve) revert NotCurve();
        _;
    }

    // ─────────────────────────────────────────── Constructor ───

    constructor(
        string memory name_,
        string memory symbol_,
        address factory_
    ) ERC20(name_, symbol_) {
        if (factory_ == address(0)) revert ZeroAddress();
        factory = factory_;
    }

    // ─────────────────────────────────────────── Init ───

    /// @inheritdoc IAgentToken
    /// @notice Hanya bisa dipanggil oleh factory, dan hanya sekali, SEBELUM
    ///         initialize(). Mint seluruh supply ke `to` (biasanya curve).
    function mintInitialSupply(address to, uint256 amount) external override {
        if (msg.sender != factory) revert NotFactory();
        if (_initialized) revert AlreadyInitialized();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        _mint(to, amount);
    }

    /// @inheritdoc IAgentToken
    /// @notice Kunci curve sebagai satu-satunya minter/burner. Dipanggil
    ///         sekali oleh factory setelah mintInitialSupply() selesai.
    function initialize(address curve_, address agentOwner_) external override {
        if (_initialized) revert AlreadyInitialized();
        if (msg.sender != factory) revert NotFactory();
        if (curve_ == address(0) || agentOwner_ == address(0)) revert ZeroAddress();

        _curve = curve_;
        _agentOwner = agentOwner_;
        _initialized = true;
    }

    // ─────────────────────────────────────────── Mint / Burn ───

    /// @inheritdoc IAgentToken
    /// @notice Mint tambahan. Hanya bisa dipanggil oleh curve.
    function mint(address to, uint256 amount) external override onlyCurve {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        _mint(to, amount);
    }

    /// @inheritdoc IAgentToken
    /// @notice Burn token dari `from`. Hanya bisa dipanggil oleh curve.
    function burn(address from, uint256 amount) external override onlyCurve {
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        _burn(from, amount);
    }

    // ─────────────────────────────────────────── Views ───

    function curve() external view override returns (address) {
        return _curve;
    }

    function agentOwner() external view override returns (address) {
        return _agentOwner;
    }

    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}
