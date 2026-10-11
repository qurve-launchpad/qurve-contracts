// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IValidationRegistry
/// @notice ERC-8004 Validation Registry: hook on-chain untuk validator (TEE,
///         zkML, stake-based, atau manual reviewer) mempublikasikan hasil
///         verifikasi kerja sebuah agent atas task tertentu.
///
///         Alur:
///         1. Siapa pun (biasanya requester/klien agent) panggil
///            `requestValidation()` menunjuk agentId + validator + taskHash.
///         2. Validator yang ditunjuk (harus approved via `addValidator`)
///            panggil `submitValidation()` dengan skor 0-100 + bukti (URI).
///         3. Hasil ini bisa dibaca on-chain oleh siapa pun (agent lain,
///            marketplace, dsb) sebagai sinyal trust tambahan di luar
///            Reputation Registry (feedback subjektif) dan Identity Registry
///            (identitas dasar).
interface IValidationRegistry {
    enum ValidationStatus {
        Pending,
        Passed,
        Failed
    }

    struct ValidationRequest {
        uint256 agentId;
        address requester;
        address validator;
        bytes32 taskHash;
        string requestURI;
        uint64 requestedAt;
        uint64 respondedAt;
        ValidationStatus status;
        uint8 score; // 0-100, valid hanya kalau status != Pending
        string responseURI;
    }

    event ValidationRequested(
        uint256 indexed requestId,
        uint256 indexed agentId,
        address indexed validator,
        address requester,
        bytes32 taskHash,
        string requestURI
    );

    event ValidationSubmitted(
        uint256 indexed requestId,
        uint256 indexed agentId,
        address indexed validator,
        uint8 score,
        bool passed,
        string responseURI
    );

    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event PassThresholdUpdated(uint8 oldValue, uint8 newValue);

    /// @notice Ajukan permintaan validasi untuk agentId atas suatu task.
    /// @param agentId Agent yang divalidasi (harus terdaftar di Identity Registry).
    /// @param validator Alamat validator yang ditunjuk (harus approved).
    /// @param taskHash Hash unik dari task/pekerjaan yang divalidasi.
    /// @param requestURI URI (IPFS/HTTP) berisi detail task & bukti yang perlu direview.
    function requestValidation(
        uint256 agentId,
        address validator,
        bytes32 taskHash,
        string calldata requestURI
    ) external returns (uint256 requestId);

    /// @notice Dipanggil oleh validator yang ditunjuk untuk submit hasil.
    /// @param score 0-100. Otomatis dianggap "passed" jika >= threshold.
    /// @param responseURI URI bukti/laporan validasi (opsional tapi disarankan).
    function submitValidation(
        uint256 requestId,
        uint8 score,
        string calldata responseURI
    ) external;

    function getRequest(uint256 requestId)
        external
        view
        returns (ValidationRequest memory);

    function requestCount() external view returns (uint256);

    function isApprovedValidator(address validator) external view returns (bool);
}
