// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IValidationRegistry} from "./interfaces/IValidationRegistry.sol";
import {IAgentLaunchRegistry} from "./interfaces/IAgentLaunchRegistry.sol";

/// @title ValidationRegistry
/// @notice ERC-8004 Validation Registry. Melengkapi AgentLaunchRegistry
///         (Identity) dan ReputationBridge (Reputation) supaya set kontrak
///         ini punya 3 registry ERC-8004 secara lengkap.
///
///         Model validasi di sini "unopinionated": validator bisa berupa EOA
///         manual reviewer, wallet yang dikontrol TEE, atau kontrak zkML —
///         yang penting alamatnya di-approve dulu oleh VALIDATOR_ADMIN_ROLE.
///         Skema stake-slashing atau reward validator sengaja TIDAK
///         dimasukkan di versi ini (bisa ditambah belakangan sebagai layer
///         terpisah) supaya kontrak inti tetap simpel dan gampang diaudit.
///
///         ⚠️ BEDA DARI AgentLaunchRegistry & ReputationBridge: kontrak ini
///         SENGAJA TIDAK disambungkan ke Validation Registry resmi ERC-8004.
///         Per riset (dikonfirmasi banyak sumber independen, termasuk
///         penulis panduan resmi ERC-8004), Validation Registry secara
///         resmi SUDAH DITARIK dari deployment multi-chain standar — lagi
///         di-rework bareng komunitas TEE, dan BUKAN bagian dari set
///         mainnet resmi ERC-8004 saat ini (beda dari Identity & Reputation
///         yang sudah stabil sejak Januari 2026). Nyambungin ke alamat yang
///         "kelihatannya resmi" di Arc testnet sekarang berisiko nyambung
///         ke versi yang bakal deprecated begitu rework-nya kelar. Kalau
///         nanti standarnya udah stabil lagi, dual-sync bisa ditambah pakai
///         pola non-fatal yang sama kayak 2 registry lainnya.
contract ValidationRegistry is IValidationRegistry, AccessControl {
    bytes32 public constant VALIDATOR_ADMIN_ROLE = keccak256("VALIDATOR_ADMIN_ROLE");

    IAgentLaunchRegistry public immutable registry;

    /// @notice Skor >= threshold ini otomatis dianggap "Passed".
    uint8 public passThreshold = 60;

    uint256 private _nextRequestId = 1;
    mapping(uint256 => ValidationRequest) private _requests;
    mapping(address => bool) public isApprovedValidator;

    error ZeroAddress();
    error ValidatorNotApproved();
    error NotAssignedValidator();
    error RequestNotFound();
    error AlreadyResponded();
    error InvalidScore();

    constructor(address registry_, address admin) {
        if (registry_ == address(0) || admin == address(0)) revert ZeroAddress();
        registry = IAgentLaunchRegistry(registry_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VALIDATOR_ADMIN_ROLE, admin);
    }

    // ─────────────────────────────────────────── Validator Admin ───

    function addValidator(address validator) external onlyRole(VALIDATOR_ADMIN_ROLE) {
        if (validator == address(0)) revert ZeroAddress();
        isApprovedValidator[validator] = true;
        emit ValidatorAdded(validator);
    }

    function removeValidator(address validator) external onlyRole(VALIDATOR_ADMIN_ROLE) {
        isApprovedValidator[validator] = false;
        emit ValidatorRemoved(validator);
    }

    function setPassThreshold(uint8 newThreshold) external onlyRole(VALIDATOR_ADMIN_ROLE) {
        if (newThreshold > 100) revert InvalidScore();
        uint8 old = passThreshold;
        passThreshold = newThreshold;
        emit PassThresholdUpdated(old, newThreshold);
    }

    // ─────────────────────────────────────────── Validation Flow ───

    /// @inheritdoc IValidationRegistry
    function requestValidation(
        uint256 agentId,
        address validator,
        bytes32 taskHash,
        string calldata requestURI
    ) external override returns (uint256 requestId) {
        // revert otomatis (AgentNotFound) kalau agentId tidak terdaftar
        registry.getAgent(agentId);

        if (!isApprovedValidator[validator]) revert ValidatorNotApproved();

        requestId = _nextRequestId++;
        _requests[requestId] = ValidationRequest({
            agentId: agentId,
            requester: msg.sender,
            validator: validator,
            taskHash: taskHash,
            requestURI: requestURI,
            requestedAt: uint64(block.timestamp),
            respondedAt: 0,
            status: ValidationStatus.Pending,
            score: 0,
            responseURI: ""
        });

        emit ValidationRequested(requestId, agentId, validator, msg.sender, taskHash, requestURI);
    }

    /// @inheritdoc IValidationRegistry
    function submitValidation(
        uint256 requestId,
        uint8 score,
        string calldata responseURI
    ) external override {
        ValidationRequest storage req = _requests[requestId];
        if (req.validator == address(0)) revert RequestNotFound();
        if (msg.sender != req.validator) revert NotAssignedValidator();
        if (req.status != ValidationStatus.Pending) revert AlreadyResponded();
        // Approval juga dicek SAAT SUBMIT, bukan cuma saat requestValidation().
        // Sebelumnya validator yang sudah di-removeValidator() masih bisa
        // menjawab semua request lama yang masih pending.
        if (!isApprovedValidator[msg.sender]) revert ValidatorNotApproved();
        if (score > 100) revert InvalidScore();

        bool passed = score >= passThreshold;
        req.status = passed ? ValidationStatus.Passed : ValidationStatus.Failed;
        req.score = score;
        req.responseURI = responseURI;
        req.respondedAt = uint64(block.timestamp);

        emit ValidationSubmitted(requestId, req.agentId, msg.sender, score, passed, responseURI);
    }

    // ─────────────────────────────────────────── Views ───

    function getRequest(uint256 requestId)
        external
        view
        override
        returns (ValidationRequest memory)
    {
        ValidationRequest memory req = _requests[requestId];
        if (req.validator == address(0)) revert RequestNotFound();
        return req;
    }

    function requestCount() external view override returns (uint256) {
        return _nextRequestId - 1;
    }
}
