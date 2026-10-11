# Events Reference

Every event emitted by Qurve contracts — verified against actual source code — for indexer integration.

## AgentLaunchRegistry

### `AgentRegistered`

```solidity
event AgentRegistered(
    uint256 indexed agentId,
    address indexed owner,
    address indexed token,
    string endpoint
);
```

### `EndpointUpdated`

```solidity
event EndpointUpdated(
    uint256 indexed agentId,
    string newEndpoint
);
```

### `EndpointVerified`

```solidity
event EndpointVerified(
    uint256 indexed agentId,
    bool verified
);
```

### `EndpointCooldownUpdated`

```solidity
event EndpointCooldownUpdated(uint256 oldValue, uint256 newValue);
```

### `OfficialSyncEnabledUpdated`

```solidity
event OfficialSyncEnabledUpdated(bool enabled);
```

### `OfficialAgentRegistered`

```solidity
event OfficialAgentRegistered(
    uint256 indexed agentId,
    uint256 officialAgentId
);
```

### `OfficialRegistrationFailed`

```solidity
event OfficialRegistrationFailed(
    uint256 indexed agentId,
    bytes reason
);
```

### `OfficialNFTClaimed`

```solidity
event OfficialNFTClaimed(
    uint256 indexed agentId,
    address indexed to
);
```

### `Transfer`

Standard ERC-721 `Transfer`. Soulbound: only emits from `address(0)` (mint).

## AgentTokenFactory

### `AgentLaunched`

```solidity
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
```

### `AntiSnipeToggled`

```solidity
event AntiSnipeToggled(bool enabled);
```

### `GraduationManagerUpdated`

```solidity
event GraduationManagerUpdated(
    address indexed oldManager,
    address indexed newManager
);
```

### `LaunchFeeUpdated`

```solidity
event LaunchFeeUpdated(uint256 oldFee, uint256 newFee);
```

## AgentBondingCurve

### `Buy`

```solidity
event Buy(
    address indexed buyer,
    uint256 ethIn,
    uint256 tokensOut,
    uint256 feePaid,
    uint256 antiSnipeFee
);
```

### `Sell`

```solidity
event Sell(
    address indexed seller,
    uint256 tokensIn,
    uint256 ethOut,
    uint256 feePaid
);
```

### `Graduated`

```solidity
event Graduated(
    address indexed pool,
    uint256 ethLiquidity,
    uint256 tokenLiquidity,
    uint256 lpTokenId
);
```

### `CreatorFeesClaimed`

```solidity
event CreatorFeesClaimed(
    address indexed creator,
    uint256 amount
);
```

### `HolderPoolSwept`

```solidity
event HolderPoolSwept(
    address indexed to,
    uint256 amount
);
```

### `StrayETHSwept`

```solidity
event StrayETHSwept(uint256 amount);
```

## GraduationManager

### `AgentGraduated`

```solidity
event AgentGraduated(
    address indexed curve,
    address indexed token,
    address indexed pool,
    uint256 lpTokenId
);
```

### `HolderDistributorDeployed`

```solidity
event HolderDistributorDeployed(
    address indexed token,
    address indexed distributor,
    uint256 initialPool
);
```

### `SwapRouterUpdated`

```solidity
event SwapRouterUpdated(
    address indexed oldRouter,
    address indexed newRouter
);
```

### `GraduationSlippageUpdated`

```solidity
event GraduationSlippageUpdated(uint16 oldBps, uint16 newBps);
```

## AgentSwapRouter

### `SwapExecuted`

```solidity
event SwapExecuted(
    address indexed trader,
    address indexed agentToken,
    bool isBuy,
    uint256 amountIn,
    uint256 amountOut,
    uint256 feePaid
);
```

### `FlexFeeReroutedToTreasury`

```solidity
event FlexFeeReroutedToTreasury(
    address indexed agentToken,
    uint256 amount
);
```

> **Backend alerting:** Subscribe to this event. It means the distributor exists but the router isn't registered as a notifier yet. Admin should call `HolderRewardsDistributor.setNotifier(router, true)` for the affected token.

## HolderRewardsDistributor

### `Staked`

```solidity
event Staked(address indexed user, uint256 amount);
```

### `Unstaked`

```solidity
event Unstaked(address indexed user, uint256 amount);
```

### `RewardClaimed`

```solidity
event RewardClaimed(address indexed user, uint256 amount);
```

### `RewardAdded`

```solidity
event RewardAdded(uint256 amount, bool heldForGrace);
```

### `InitialPoolFinalized`

```solidity
event InitialPoolFinalized(
    uint256 amount,
    uint256 totalStakedAtFinalize
);
```

### `NotifierUpdated`

```solidity
event NotifierUpdated(
    address indexed notifier,
    bool allowed
);
```

## ReputationBridge

### `FeedbackSubmitted`

```solidity
event FeedbackSubmitted(
    uint256 indexed agentId,
    address indexed rater,
    uint8 score,
    bytes32 taskHash
);
```

### `ReputationUpdated`

```solidity
event ReputationUpdated(
    uint256 indexed agentId,
    uint256 newAverageScore,
    uint256 totalFeedback
);
```

### `FeedbackDisputed`

```solidity
event FeedbackDisputed(
    uint256 indexed agentId,
    uint256 index,
    address disputer,
    string reasonURI
);
```

### `MinRaterIntervalUpdated`

```solidity
event MinRaterIntervalUpdated(uint256 oldValue, uint256 newValue);
```

### `OfficialSyncEnabledUpdated`

```solidity
event OfficialSyncEnabledUpdated(bool enabled);
```

### `OfficialFeedbackSynced`

```solidity
event OfficialFeedbackSynced(
    uint256 indexed agentId,
    uint256 indexed officialAgentId
);
```

### `OfficialFeedbackSyncSkipped`

```solidity
event OfficialFeedbackSyncSkipped(
    uint256 indexed agentId,
    bytes reason
);
```

## ValidationRegistry

### `ValidationRequested`

```solidity
event ValidationRequested(
    uint256 indexed requestId,
    uint256 indexed agentId,
    address indexed validator,
    address requester,
    bytes32 taskHash,
    string requestURI
);
```

### `ValidationSubmitted`

```solidity
event ValidationSubmitted(
    uint256 indexed requestId,
    uint256 indexed agentId,
    address indexed validator,
    uint8 score,
    bool passed,
    string responseURI
);
```

### `ValidatorAdded`

```solidity
event ValidatorAdded(address indexed validator);
```

### `ValidatorRemoved`

```solidity
event ValidatorRemoved(address indexed validator);
```

### `PassThresholdUpdated`

```solidity
event PassThresholdUpdated(uint8 oldValue, uint8 newValue);
```

## AgentToken

Standard ERC-20 events inherited from OpenZeppelin:

```solidity
event Transfer(address indexed from, address indexed to, uint256 value);
event Approval(address indexed owner, address indexed spender, uint256 value);
```

## Indexer Reference

Each event should be indexed with a unique constraint on:

```
(chain_id, tx_hash, log_index)
```

This prevents double-indexing in case of reorg or backfill overlap.

### Standard fields

| Field | Source |
|---|---|
| `chainId` | Network config |
| `blockNumber` | Event metadata |
| `txHash` | Event metadata |
| `logIndex` | Event metadata |
| `timestamp` | Block timestamp |
