// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IReputationBridge} from "./interfaces/IReputationBridge.sol";
import {IAgentLaunchRegistry} from "./interfaces/IAgentLaunchRegistry.sol";

/// @dev Interface minimal ke ERC-8004 Reputation Registry RESMI.
///
///      ⚠️ PERINGATAN STABILITAS SPEC: ERC-8004 masih Draft dan signature
///      `giveFeedback` udah pernah berubah minimal 1x antar versi (versi
///      lama pakai `bytes32 tag1/tag2` + `feedbackAuth`, versi lebih baru
///      pakai `int128 value` + `string tag1/tag2` tanpa auth). Signature di
///      bawah ini yang versi TERBARU per riset (konsisten di 3+ sumber
///      independen per 2026-09), TAPI karena standar ini masih bisa
///      berubah, JANGAN asumsikan ini pasti cocok 1:1 sama kontrak yang
///      benar-benar ter-deploy di Arc tanpa verifikasi ABI langsung dulu.
///      Untungnya desain non-fatal di bawah bikin ini aman walau salah:
///      kalau selector-nya gak cocok sama sekali, call-nya cuma bakal
///      gagal & masuk catch block — gak pernah bikin submitFeedback() ikut
///      revert.
interface IERC8004ReputationRegistry {
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;
}

/// @title ReputationBridge
/// @notice ERC-8004 Reputation Registry. Anti-sybil via min rater interval.
///         Plus sync opsional (best-effort, non-fatal) ke ERC-8004
///         Reputation Registry RESMI — lihat prinsip desain yang sama
///         dengan AgentLaunchRegistry (gas dibatasi, toggle admin, gak
///         pernah bikin transaksi utama revert).
contract ReputationBridge is IReputationBridge, AccessControl {
    bytes32 public constant DISPUTER_ROLE = keccak256("DISPUTER_ROLE");

    /// @notice Sama seperti di AgentLaunchRegistry — gas di-batasi eksplisit
    ///         biar kontrak eksternal yang bermasalah gak bisa bikin
    ///         transaksi ini kehabisan gas pas lanjut nulis state internal.
    uint256 public constant OFFICIAL_CALL_GAS = 200_000;

    IAgentLaunchRegistry public immutable registry;

    /// @notice Alamat ERC-8004 Reputation Registry RESMI. address(0) = sync
    ///         eksternal off permanen.
    address public immutable officialReputationRegistry;

    /// @notice Saklar admin, terpisah dari alamat immutable di atas —
    ///         bisa dimatiin cepat tanpa redeploy kalau ada masalah
    ///         berulang di sisi eksternal.
    bool public officialSyncEnabled = true;

    uint256 public minRaterInterval = 5 minutes;

    mapping(uint256 => Feedback[]) private _feedbacks;
    mapping(uint256 => mapping(bytes32 => bool)) private _rated;
    mapping(uint256 => uint256) private _scoreSum;
    mapping(uint256 => uint256) private _validFeedbackCount;
    mapping(uint256 => mapping(address => uint256)) private _lastRaterTimestamp;

    error InvalidScore();
    error AlreadyRated();
    error AgentDoesNotExist();
    error RaterCooldown();
    error FeedbackNotFound();
    error AlreadyDisputed();

    event MinRaterIntervalUpdated(uint256 oldValue, uint256 newValue);
    event OfficialSyncEnabledUpdated(bool enabled);
    /// @notice Dipancarkan setelah feedback berhasil ikut ke-sync ke
    ///         Reputation Registry resmi (butuh agent yang bersangkutan
    ///         sudah punya officialAgentId di AgentLaunchRegistry).
    event OfficialFeedbackSynced(uint256 indexed agentId, uint256 indexed officialAgentId);
    /// @notice Dipancarkan kalau sync ke resmi gagal/revert, ATAU kalau
    ///         agent-nya belum punya officialAgentId sama sekali — di kedua
    ///         kasus, feedback internal di atas TETAP tersimpan normal.
    event OfficialFeedbackSyncSkipped(uint256 indexed agentId, bytes reason);

    constructor(address registry_, address admin, address officialReputationRegistry_) {
        if (registry_ == address(0) || admin == address(0)) revert AgentDoesNotExist();
        registry = IAgentLaunchRegistry(registry_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // officialReputationRegistry_ BOLEH address(0) — sync eksternal off.
        officialReputationRegistry = officialReputationRegistry_;
    }

    function setOfficialSyncEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        officialSyncEnabled = enabled;
        emit OfficialSyncEnabledUpdated(enabled);
    }

    function submitFeedback(
        uint256 agentId,
        uint8 score,
        bytes32 taskHash,
        string calldata commentURI
    ) external override {
        if (score > 100) revert InvalidScore();
        if (_rated[agentId][taskHash]) revert AlreadyRated();

        IAgentLaunchRegistry.AgentMetadata memory agent = registry.getAgent(agentId);

        uint256 last = _lastRaterTimestamp[agentId][msg.sender];
        if (last != 0 && block.timestamp < last + minRaterInterval) {
            revert RaterCooldown();
        }
        _lastRaterTimestamp[agentId][msg.sender] = block.timestamp;

        _rated[agentId][taskHash] = true;
        _scoreSum[agentId] += score;
        _validFeedbackCount[agentId] += 1;

        _feedbacks[agentId].push(
            Feedback({
                agentId: agentId,
                rater: msg.sender,
                score: score,
                taskHash: taskHash,
                commentURI: commentURI,
                timestamp: uint64(block.timestamp),
                disputed: false
            })
        );

        emit FeedbackSubmitted(agentId, msg.sender, score, taskHash);

        (uint256 avgX100, uint256 total) = _computeAverage(agentId);
        emit ReputationUpdated(agentId, avgX100, total);

        // Feedback internal di atas SUDAH final & tersimpan sampai titik
        // ini. Sync ke resmi di bawah murni best-effort tambahan — apapun
        // hasilnya (sukses, gagal, atau di-skip), TIDAK PERNAH mengubah
        // atau membatalkan apa yang udah kejadian di atas.
        _trySyncOfficialFeedback(agentId, agent.officialAgentId, score, agent.endpoint, commentURI);
    }

    /// @dev Dipanggil dari submitFeedback(). Dipisah jadi fungsi sendiri
    ///      biar submitFeedback() gampang dibaca & di-audit (logic scoring
    ///      internal terpisah jelas dari logic sync eksternal).
    function _trySyncOfficialFeedback(
        uint256 agentId,
        uint256 officialAgentId,
        uint8 score,
        string memory endpoint,
        string calldata commentURI
    ) private {
        if (!officialSyncEnabled || officialReputationRegistry == address(0)) return;

        // Agent yang bersangkutan belum ke-sync ke Identity Registry resmi
        // (officialAgentId == 0) → gak ada agentId resmi buat dituju, skip
        // tanpa nyoba call sama sekali (biar gak buang gas percuma manggil
        // agentId yang pasti gak valid di sisi resmi).
        if (officialAgentId == 0) {
            emit OfficialFeedbackSyncSkipped(agentId, bytes("agent belum punya officialAgentId"));
            return;
        }

        // Catatan: registry resmi menolak feedback dari owner/operator agent
        // itu sendiri (anti self-dealing, per spec ERC-8004) — kalau
        // msg.sender kebetulan owner agent, call ini WAJAR gagal di sisi
        // resmi. Itu bukan bug, feedback internal Qurve tetap tersimpan.
        try IERC8004ReputationRegistry(officialReputationRegistry).giveFeedback{gas: OFFICIAL_CALL_GAS}(
            officialAgentId,
            int128(uint128(score)),
            0, // valueDecimals — skor kita 0-100 integer, gak butuh desimal
            "qurve", // tag1
            "", // tag2
            endpoint,
            commentURI, // feedbackURI
            bytes32(0) // feedbackHash — sengaja kosong, commentURI dianggap sumber utama
        ) {
            emit OfficialFeedbackSynced(agentId, officialAgentId);
        } catch (bytes memory reason) {
            emit OfficialFeedbackSyncSkipped(agentId, reason);
        }
    }

    function disputeFeedback(uint256 agentId, uint256 index, string calldata reasonURI)
        external
        override
        onlyRole(DISPUTER_ROLE)
    {
        Feedback storage fb = _feedbacks[agentId][index];
        if (fb.rater == address(0)) revert FeedbackNotFound();
        if (fb.disputed) revert AlreadyDisputed();

        fb.disputed = true;
        _scoreSum[agentId] -= fb.score;
        _validFeedbackCount[agentId] -= 1;

        emit FeedbackDisputed(agentId, index, msg.sender, reasonURI);

        (uint256 avgX100, uint256 total) = _computeAverage(agentId);
        emit ReputationUpdated(agentId, avgX100, total);
    }

    function getAverageScore(uint256 agentId)
        external
        view
        override
        returns (uint256 avgScoreX100, uint256 totalFeedback)
    {
        return _computeAverage(agentId);
    }

    function getFeedback(uint256 agentId, uint256 index)
        external
        view
        override
        returns (Feedback memory)
    {
        return _feedbacks[agentId][index];
    }

    function feedbackCount(uint256 agentId) external view override returns (uint256) {
        return _feedbacks[agentId].length;
    }

    function hasRated(uint256 agentId, bytes32 taskHash)
        external
        view
        override
        returns (bool)
    {
        return _rated[agentId][taskHash];
    }

    function lastRaterTimestamp(uint256 agentId, address rater)
        external
        view
        returns (uint256)
    {
        return _lastRaterTimestamp[agentId][rater];
    }

    function _computeAverage(uint256 agentId)
        internal
        view
        returns (uint256 avgX100, uint256 totalFeedback)
    {
        totalFeedback = _validFeedbackCount[agentId];
        if (totalFeedback == 0) return (0, 0);
        avgX100 = (_scoreSum[agentId] * 100) / totalFeedback;
    }

    function setMinRaterInterval(uint256 newInterval)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 old = minRaterInterval;
        minRaterInterval = newInterval;
        emit MinRaterIntervalUpdated(old, newInterval);
    }
}
