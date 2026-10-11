// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentLaunchRegistry
/// @notice ERC-8004 Identity Registry: setiap agen = 1 ERC-721 soulbound,
///         menyimpan metadata (endpoint A2A, agentURI, capabilities).
interface IAgentLaunchRegistry {
    struct AgentMetadata {
        string name;
        string agentURI;
        string endpoint;
        address token;
        address curve;
        address owner;
        uint64 createdAt;
        bool endpointVerified;
        // FIX (Arc dual-registration): agentId di ERC-8004 Identity Registry
        // RESMI (mis. 0x8004A169... di Arc mainnet), 0 kalau belum/gagal
        // ke-register di sana. Registry internal ini TETAP sumber kebenaran
        // utama — field ini murni buat interoperabilitas/discoverability.
        uint256 officialAgentId;
    }

    event AgentRegistered(
        uint256 indexed agentId,
        address indexed owner,
        address indexed token,
        string endpoint
    );
    event EndpointUpdated(uint256 indexed agentId, string newEndpoint);
    event EndpointVerified(uint256 indexed agentId, bool verified);
    /// @notice Dipancarkan setelah dual-registration ke ERC-8004 Identity
    ///         Registry resmi berhasil.
    event OfficialAgentRegistered(uint256 indexed agentId, uint256 officialAgentId);
    /// @notice Dipancarkan kalau call ke registry resmi gagal/revert —
    ///         non-fatal, registrasi internal tetap lanjut.
    event OfficialRegistrationFailed(uint256 indexed agentId, bytes reason);

    function registerAgent(
        address owner,
        address token,
        address curve,
        string calldata name,
        string calldata agentURI,
        string calldata endpoint
    ) external returns (uint256 agentId);

    function updateEndpoint(uint256 agentId, string calldata newEndpoint) external;
    function setEndpointVerified(uint256 agentId, bool verified) external;
    function getAgent(uint256 agentId) external view returns (AgentMetadata memory);
    function agentIdByToken(address token) external view returns (uint256);
    function totalAgents() external view returns (uint256);
}
