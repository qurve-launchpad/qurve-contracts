// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IReputationBridge
/// @notice ERC-8004 Reputation Registry: agregasi feedback on-chain.
interface IReputationBridge {
    struct Feedback {
        uint256 agentId;
        address rater;
        uint8 score;        // 0-100
        bytes32 taskHash;
        string commentURI;
        uint64 timestamp;
        bool disputed;
    }

    event FeedbackSubmitted(
        uint256 indexed agentId,
        address indexed rater,
        uint8 score,
        bytes32 taskHash
    );
    event ReputationUpdated(
        uint256 indexed agentId,
        uint256 newAverageScore,
        uint256 totalFeedback
    );
    event FeedbackDisputed(
        uint256 indexed agentId,
        uint256 index,
        address disputer,
        string reasonURI
    );

    function submitFeedback(
        uint256 agentId,
        uint8 score,
        bytes32 taskHash,
        string calldata commentURI
    ) external;

    function disputeFeedback(
        uint256 agentId,
        uint256 index,
        string calldata reasonURI
    ) external;

    function getAverageScore(uint256 agentId)
        external
        view
        returns (uint256 avgScoreX100, uint256 totalFeedback);

    function getFeedback(uint256 agentId, uint256 index)
        external
        view
        returns (Feedback memory);

    function feedbackCount(uint256 agentId) external view returns (uint256);
    function hasRated(uint256 agentId, bytes32 taskHash) external view returns (bool);
}
