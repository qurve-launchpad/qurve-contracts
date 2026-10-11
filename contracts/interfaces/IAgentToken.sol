// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentToken
/// @notice Interface token ERC-20 per-agen.
///
///         Lifecycle:
///         1. Factory deploy AgentToken (factory jadi `msg.sender`).
///         2. Factory panggil `mintInitialSupply(curve, TOTAL_SUPPLY)` — mint
///            SELURUH supply ke curve, sebelum token di-initialize.
///         3. Factory deploy curve (curve jadi `msg.sender` untuk AgentToken
///            yang baru di-initialize).
///         4. Factory panggil `token.initialize(curve, creator)` — mengunci
///            curve sebagai satu-satunya yang boleh mint/burn selanjutnya.
///         5. Curve distribusikan token ke pembeli via `safeTransfer`.
///
///         Setelah `initialize()`, `mintInitialSupply()` tidak bisa dipanggil
///         lagi. `mint()` dan `burn()` hanya bisa dipanggil oleh curve.
interface IAgentToken {
    /// @notice Mint seluruh total supply ke curve SEBELUM initialize().
    ///         Hanya bisa dipanggil oleh factory. Setelah initialize(),
    ///         fungsi ini tidak bisa dipanggil lagi.
    /// @param to Alamat penerima (biasanya curve address).
    /// @param amount Jumlah token yang di-mint (TOTAL_SUPPLY).
    function mintInitialSupply(address to, uint256 amount) external;

    /// @notice Kunci curve sebagai satu-satunya minter/burner. Dipanggil
    ///         sekali oleh factory setelah mintInitialSupply() selesai.
    /// @param curve_ Alamat bonding curve.
    /// @param agentOwner_ Alamat creator agen.
    function initialize(address curve_, address agentOwner_) external;

    /// @notice Mint token tambahan ke `to`. Hanya bisa dipanggil oleh curve.
    ///         Dipakai saat graduasi untuk menambah supply sisi LP (jika perlu).
    function mint(address to, uint256 amount) external;

    /// @notice Burn token dari `from`. Hanya bisa dipanggil oleh curve.
    function burn(address from, uint256 amount) external;

    function curve() external view returns (address);
    function agentOwner() external view returns (address);
}
