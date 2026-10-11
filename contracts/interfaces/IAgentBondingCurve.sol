// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentBondingCurve
/// @notice Interface bonding curve untuk satu agent token.
///         Model: constant product (x * y = k) dengan virtual reserve,
///         mirip pump.fun tapi quote asset = native ETH.
///
///         CHANGELOG (holder-rewards redesign):
///         - claimCashback() / CashbackClaimed DIHAPUS. Bucket 0.5% "trader
///           cashback" digabung ke bucket flex 1% yang sekarang arahnya
///           ditentukan RewardMode (dipilih creator saat launch, immutable):
///             CREATOR -> pendingCreatorClaim (sama seperti sebelumnya)
///             HOLDERS -> pendingHolderPool (akumulasi agregat, BUKAN per-trader,
///                        di-flush sekali ke HolderRewardsDistributor saat graduasi)
///         - Kalau curve gak pernah graduate, pendingHolderPool bisa di-sweep
///           balik ke platform lewat sweepAbandonedHolderPool() setelah
///           ABANDON_TIMEOUT tanpa trade (lihat AgentBondingCurve.sol).
///
///         CHANGELOG (M1 — stray ETH sweep):
///         - Tambah sweepStrayETH() + StrayETHSwept event. ETH yang dikirim
///           langsung ke contract address (bukan via buy/topUpCreatorPool)
///           tidak masuk accounting manapun, sebelumnya stuck permanen.
///           Sekarang permissionless sweep ke protocolFeeRecipient.
interface IAgentBondingCurve {
    // ─────────────────────────────────────────── Types ───

    /// @notice Pilihan creator saat launch untuk arah bucket flex 1%.
    ///         Immutable per-token, di-set sekali di constructor curve.
    enum RewardMode {
        CREATOR, // flex 1% -> pendingCreatorClaim (pull-payment, existing behavior)
        HOLDERS  // flex 1% -> pendingHolderPool -> HolderRewardsDistributor saat graduasi
    }

    // ─────────────────────────────────────────── Events ───

    event Buy(
        address indexed buyer,
        uint256 ethIn,
        uint256 tokensOut,
        uint256 feePaid,
        uint256 antiSnipeFee
    );
    event Sell(
        address indexed seller,
        uint256 tokensIn,
        uint256 ethOut,
        uint256 feePaid
    );
    event Graduated(
        address indexed pool,
        uint256 ethLiquidity,
        uint256 tokenLiquidity,
        uint256 lpTokenId
    );
    event CreatorFeesClaimed(address indexed creator, uint256 amount);
    event HolderPoolSwept(address indexed to, uint256 amount);
    /// @notice Dipancarkan saat sweepStrayETH() berhasil menarik ETH yang
    ///         tidak terhitung di accounting manapun (realEthReserve,
    ///         pendingCreatorClaim, pendingHolderPool).
    event StrayETHSwept(uint256 amount);

    // ─────────────────────────────────────────── Functions ───

    function buy(uint256 ethIn, uint256 minTokensOut)
        external
        payable
        returns (uint256 tokensOut);

    function sell(uint256 tokensIn, uint256 minEthOut)
        external
        returns (uint256 ethOut);

    function currentPrice() external view returns (uint256);
    function quoteBuy(uint256 ethInAfterFee) external view returns (uint256 tokensOut);
    function quoteSell(uint256 tokensIn) external view returns (uint256 ethOut);

    function tokensSold() external view returns (uint256);
    function realEthReserve() external view returns (uint256);
    function graduationThreshold() external view returns (uint256);
    function isGraduated() external view returns (bool);
    function tokensForSale() external view returns (uint256);
    function rewardMode() external view returns (RewardMode);
    function pendingHolderPool() external view returns (uint256);
    function lastTradeAt() external view returns (uint256);

    function claimCreatorFees() external;
    function topUpCreatorPool() external payable;
    function sweepAbandonedHolderPool() external;
    /// @notice Permissionless. Sweep ETH yang nyangkut di contract (kiriman
    ///         langsung ke address, bukan via buy/topUp) ke protocolFeeRecipient.
    ///         Revert kalau tidak ada stray.
    function sweepStrayETH() external;

    function markGraduated(address pool, uint256 lpTokenId) external;
    function withdrawReserveForGraduation() external returns (uint256 amount);
    function withdrawTokensForGraduation() external returns (uint256 amount);
    function withdrawHolderPoolForGraduation() external returns (uint256 amount);
}
