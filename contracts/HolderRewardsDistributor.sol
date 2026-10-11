// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title HolderRewardsDistributor
/// @notice Satu instance di-deploy PER TOKEN oleh GraduationManager, HANYA
///         kalau creator pilih RewardMode.HOLDERS saat launch. Holder token
///         stake di sini buat dapet bagian dari:
///           1. Lump sum pendingHolderPool yang terkumpul sepanjang fase
///              bonding curve (di-notify sekali saat graduasi).
///           2. Bucket flex 1% dari tiap swap post-graduation via
///              AgentSwapRouter (di-notify berkelanjutan, per-swap).
///
///         Reward dibayar dalam native ETH, BUKAN emisi token baru — jadi
///         model akuntansinya accRewardPerShare (mirip MasterChef), bukan
///         reward-rate-per-detik ala Synthetix.
///
///         GRACE PERIOD (khusus lump sum awal): supaya whale gak bisa
///         nyaplok 100% pendingHolderPool cuma dengan jadi staker PERTAMA
///         yang gercep abis graduasi, lump sum awal ditahan dulu
///         (unallocatedInitialPool) dan baru di-fold ke accRewardPerShare
///         setelah GRACE_PERIOD lewat, dibagi rata ke SEMUA yang udah stake
///         sampai saat itu — bukan cuma staker pertama.
contract HolderRewardsDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────── Immutable ───

    IERC20 public immutable stakingToken;
    uint256 public immutable deployedAt;

    // ─────────────────────────────────────────── Constants ───

    uint256 public constant GRACE_PERIOD = 2 days;
    uint256 public constant UNSTAKE_COOLDOWN = 20 minutes;

    // ─────────────────────────────────────────── State ───

    /// @notice Alamat yang boleh nyuntik reward (notifyRewardAmount). Awalnya
    ///         cuma GraduationManager (buat lump sum awal); owner bisa
    ///         nambah AgentSwapRouter belakangan lewat setNotifier() begitu
    ///         router-nya di-deploy.
    mapping(address => bool) public isNotifier;

    uint256 public accRewardPerShare; // scaled 1e18
    uint256 public totalStaked;
    uint256 public totalRewardsDistributed; // GLOBAL, all-time, folded ke accRewardPerShare (claimed maupun belum)
    uint256 public totalClaimed;            // GLOBAL, all-time, yang udah bener-bener ditarik staker

    /// @notice Dana yang masuk sebelum ada staker (atau selama grace period)
    ///         dan belum di-fold ke accRewardPerShare.
    uint256 public unallocatedInitialPool;
    bool public initialPoolFinalized;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public stakedAt;      // buat cooldown unstake
    mapping(address => uint256) public totalClaimedBy; // PER-USER, all-time

    // ─────────────────────────────────────────── Events ───

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardAdded(uint256 amount, bool heldForGrace);
    event InitialPoolFinalized(uint256 amount, uint256 totalStakedAtFinalize);
    event NotifierUpdated(address indexed notifier, bool allowed);

    // ─────────────────────────────────────────── Errors ───

    error NotNotifier();
    error ZeroAmount();
    error InsufficientStake();
    error CooldownActive();
    error GracePeriodNotOver();
    error AlreadyFinalized();
    error TransferFailed();
    error ZeroAddress();

    modifier onlyNotifier() {
        if (!isNotifier[msg.sender]) revert NotNotifier();
        _;
    }

    // ─────────────────────────────────────────── Constructor ───

    constructor(
        address stakingToken_,
        address initialNotifier_,
        address initialOwner_
    ) Ownable(initialOwner_) {
        if (stakingToken_ == address(0) || initialNotifier_ == address(0)) {
            revert ZeroAddress();
        }
        stakingToken = IERC20(stakingToken_);
        isNotifier[initialNotifier_] = true;
        deployedAt = block.timestamp;
    }

    // ─────────────────────────────────────────── Admin ───

    /// @notice Nambah/cabut alamat yang boleh notifyRewardAmount(). Dipanggil
    ///         owner (protocol admin) buat wire-in AgentSwapRouter setelah
    ///         di-deploy, tanpa perlu redeploy distributor ini.
    function setNotifier(address notifier, bool allowed) external onlyOwner {
        if (notifier == address(0)) revert ZeroAddress();
        isNotifier[notifier] = allowed;
        emit NotifierUpdated(notifier, allowed);
    }

    // ─────────────────────────────────────────── Reward Inflow ───

    /// @notice Dipanggil GraduationManager (lump sum awal) atau AgentSwapRouter
    ///         (fee per-swap post-graduation).
    function notifyRewardAmount() external payable onlyNotifier {
        if (msg.value == 0) revert ZeroAmount();

        bool stillInGrace = !initialPoolFinalized &&
            block.timestamp <= deployedAt + GRACE_PERIOD;

        if (stillInGrace || totalStaked == 0) {
            // Masih grace period, ATAU gak ada staker sama sekali -> tahan
            // dulu, jangan di-fold (mencegah div-by-zero & sniping).
            unallocatedInitialPool += msg.value;
            emit RewardAdded(msg.value, true);
            return;
        }

        accRewardPerShare += (msg.value * 1e18) / totalStaked;
        totalRewardsDistributed += msg.value;
        emit RewardAdded(msg.value, false);
    }

    /// @notice Permissionless. Fold unallocatedInitialPool ke accRewardPerShare
    ///         setelah grace period lewat, dibagi rata ke totalStaked SAAT INI
    ///         (yaitu semua yang stake selama grace window). Kalau masih 0
    ///         staker pas dipanggil, dana tetap nganggur & bisa dicoba lagi
    ///         belakangan begitu ada staker pertama.
    function finalizeInitialPool() external {
        if (initialPoolFinalized) revert AlreadyFinalized();
        if (block.timestamp < deployedAt + GRACE_PERIOD) revert GracePeriodNotOver();

        uint256 amount = unallocatedInitialPool;
        if (amount == 0) {
            initialPoolFinalized = true;
            return;
        }
        if (totalStaked == 0) {
            // Belum ada staker sama sekali -> jangan finalize, biar bisa
            // dicoba lagi nanti begitu ada yang stake.
            return;
        }

        unallocatedInitialPool = 0;
        initialPoolFinalized = true;
        accRewardPerShare += (amount * 1e18) / totalStaked;
        totalRewardsDistributed += amount;
        emit InitialPoolFinalized(amount, totalStaked);
    }

    // ─────────────────────────────────────────── Stake / Unstake / Claim ───

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _harvest(msg.sender);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;
        stakedAt[msg.sender] = block.timestamp;
        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accRewardPerShare) / 1e18;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (stakedBalance[msg.sender] < amount) revert InsufficientStake();
        if (block.timestamp < stakedAt[msg.sender] + UNSTAKE_COOLDOWN) {
            revert CooldownActive();
        }
        _harvest(msg.sender);

        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;
        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accRewardPerShare) / 1e18;
        stakingToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /// @notice Claim reward tanpa unstake.
    function claim() external nonReentrant {
        uint256 pending = earned(msg.sender);
        if (pending == 0) revert ZeroAmount();
        rewardDebt[msg.sender] = (stakedBalance[msg.sender] * accRewardPerShare) / 1e18;
        totalClaimed += pending;
        totalClaimedBy[msg.sender] += pending;
        (bool sent, ) = msg.sender.call{value: pending}("");
        if (!sent) revert TransferFailed();
        emit RewardClaimed(msg.sender, pending);
    }

    function _harvest(address user) internal {
        uint256 pending = earned(user);
        if (pending > 0) {
            rewardDebt[user] = (stakedBalance[user] * accRewardPerShare) / 1e18;
            totalClaimed += pending;
            totalClaimedBy[user] += pending;
            (bool sent, ) = user.call{value: pending}("");
            if (!sent) revert TransferFailed();
            emit RewardClaimed(user, pending);
        }
    }

    // ─────────────────────────────────────────── Views ───

    /// @notice Reward yang bisa diclaim `user` sekarang. Ini yang ditampilkan
    ///         di UI sebagai "reward kamu".
    function earned(address user) public view returns (uint256) {
        return (stakedBalance[user] * accRewardPerShare) / 1e18 - rewardDebt[user];
    }

    /// @notice Reward yang UDAH di-fold tapi BELUM ditarik siapa pun,
    ///         gabungan dari semua staker (bukan cuma satu user).
    ///         TIDAK termasuk unallocatedInitialPool (yang itu belum
    ///         di-fold sama sekali, beda kategori).
    function totalPendingRewards() external view returns (uint256) {
        return totalRewardsDistributed - totalClaimed;
    }

    /// @notice Satu call buat ambil semua stats GLOBAL pool ini — dipakai
    ///         staking page biar gak perlu banyak RPC call terpisah.
    function getGlobalStats()
        external
        view
        returns (
            uint256 totalStaked_,
            uint256 totalRewardsDistributed_,
            uint256 totalClaimed_,
            uint256 totalPendingRewards_,
            uint256 unallocatedInitialPool_,
            bool initialPoolFinalized_
        )
    {
        totalStaked_ = totalStaked;
        totalRewardsDistributed_ = totalRewardsDistributed;
        totalClaimed_ = totalClaimed;
        totalPendingRewards_ = totalRewardsDistributed - totalClaimed;
        unallocatedInitialPool_ = unallocatedInitialPool;
        initialPoolFinalized_ = initialPoolFinalized;
    }

    /// @notice Satu call buat ambil semua stats PER-USER — dipakai staking
    ///         page pas user buka halaman token tertentu yang dia hold.
    function getUserInfo(address user)
        external
        view
        returns (
            uint256 staked,
            uint256 pendingReward,
            uint256 claimed,
            uint256 unstakeAvailableAt
        )
    {
        staked = stakedBalance[user];
        pendingReward = earned(user);
        claimed = totalClaimedBy[user];
        unstakeAvailableAt = stakedAt[user] + UNSTAKE_COOLDOWN;
    }
}
