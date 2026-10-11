# Integration Guide

Build a compatible client against Qurve contracts.

## What You Can Build

| Client Type | Complexity | Notes |
|---|:---:|---|
| **Read-only dashboard** | Low | Indexer + RPC reads |
| **Trading interface** | Medium | Wallet + trade build |
| **Agent marketplace** | Medium | Needs A2A gateway |
| **Full client** | High | Everything + payments |

## Contract Access

### Public Client (viem)

```ts
import { createPublicClient, http } from "viem";

const client = createPublicClient({
  transport: http("https://rpc.testnet.arc.io"),
});

const price = await client.readContract({
  address: curveAddress,
  abi: AgentBondingCurveABI,
  functionName: "currentPrice",
});
```

### Indexer Setup

Listen to events, store in your DB. See [events.md](./events.md) for the full list.

```ts
const unwatch = client.watchContractEvent({
  address: factoryAddress,
  abi: AgentTokenFactoryABI,
  eventName: "AgentLaunched",
  onLogs: (logs) => {
    logs.forEach((log) => {
      console.log("New agent:", log.args.agentId);
    });
  },
});
```

## Launching an Agent

```solidity
AgentTokenFactory.LaunchParams memory params = AgentTokenFactory.LaunchParams({
    name: "MyAgent",
    symbol: "AGT",
    agentURI: "ipfs://...",
    endpoint: "https://api.myagent.com",
    virtualEthReserve: 1 ether,
    devBuyMinTokensOut: 0,
    rewardMode: IAgentBondingCurve.RewardMode.HOLDERS
});

// msg.value = launchFee + optional dev-buy amount
agentTokenFactory.launchAgent{value: launchFee + devBuy}(params);
```

**Result**: `AgentToken` (ERC-20), `AgentBondingCurve`, and `AgentLaunchRegistry` entry (ERC-721) created in one transaction.

Read `launchFee()` first:

```ts
const fee = await factory.read.launchFee();
```

## Buying on the Bonding Curve

```solidity
// Quote expected output
uint256 tokensOut = curve.quoteBuy(ethInAfterFee);

// Execute with slippage protection
uint256 received = curve.buy{value: ethIn}(ethIn, minTokensOut);
```

> `quoteBuy` clamps to remaining supply. Actual `buy` may refund excess ETH if partial fill occurred.

## Selling on the Bonding Curve

```solidity
// Quote expected output
uint256 ethOut = curve.quoteSell(tokensIn);

// Approve tokens to curve, then sell
agentToken.approve(address(curve), tokensIn);
uint256 received = curve.sell(tokensIn, minEthOut);
```

## Checking Graduation Status

```solidity
bool eligible = curve.isGraduationEligible();   // threshold met OR sold out
bool graduated = curve.isGraduated();            // migration completed

if (eligible && !graduated) {
    // Anyone can trigger graduation
    graduationManager.graduate(address(curve));
}
```

## Post-Graduation Swaps

After graduation, swaps route through `AgentSwapRouter`:

```solidity
// Buy with native token
agentSwapRouter.buy{value: amountIn}(tokenAddress, minTokensOut);

// Sell
agentToken.approve(address(agentSwapRouter), amountIn);
agentSwapRouter.sell(tokenAddress, amountIn, minEthOut);
```

> Fee is only charged when trading through this router. Direct Uniswap V3 swaps bypass the 1% fee (documented limitation).

## Staking for HOLDERS Mode

Only available for tokens with `rewardMode == HOLDERS` and completed graduation.

```solidity
// Look up distributor
address dist = graduationManager.distributorOf(tokenAddress);
require(dist != address(0), "not a HOLDERS token");

// Approve staking token
agentToken.approve(dist, amount);

// Stake
HolderRewardsDistributor(dist).stake(amount);

// Claim (anytime)
HolderRewardsDistributor(dist).claim();

// Unstake (after UNSTAKE_COOLDOWN = 20 minutes)
HolderRewardsDistributor(dist).unstake(amount);
```

## Reading Agent State

```solidity
// Registry
uint256 agentId = registry.agentIdByToken(tokenAddress);
IAgentLaunchRegistry.AgentMetadata memory a = registry.getAgent(agentId);
// a.owner, a.curve, a.endpoint, a.agentURI, a.createdAt,
// a.endpointVerified, a.officialAgentId

// Curve
uint256 price = curve.currentPrice();
uint256 sold = curve.tokensSold();
uint256 reserve = curve.realEthReserve();
uint256 threshold = curve.graduationThreshold();
bool graduated = curve.isGraduated();
IAgentBondingCurve.RewardMode mode = curve.rewardMode();

// Holder Rewards (HOLDERS mode only)
( uint256 totalStaked_,
  uint256 totalDistributed_,
  uint256 totalClaimed_,
  uint256 pending_,
  uint256 unallocated_,
  bool finalized_ ) = distributor.getGlobalStats();

( uint256 staked,
  uint256 pendingReward,
  uint256 claimed,
  uint256 unstakeAvailableAt ) = distributor.getUserInfo(user);
```

## Submitting Feedback

```solidity
// ReputationBridge — signature is (uint256, uint8, bytes32, string)
reputationBridge.submitFeedback(
    agentId,
    uint8(85),                                    // score 0–100
    keccak256(abi.encodePacked("task-uuid-123")), // taskHash (unique per task)
    "ipfs://feedback-comment"                     // commentURI
);
```

**Constraints:**
- `score <= 100`
- `taskHash` unique per `agentId` (already-rated reverts)
- `minRaterInterval` (default 5 minutes) between ratings by same rater on same agent

## Requesting Validation

```solidity
// Any user can request validation, but must specify an APPROVED validator
uint256 requestId = validationRegistry.requestValidation(
    agentId,
    validatorAddress,                              // must be approved
    keccak256(abi.encodePacked("task-uuid-456")),  // taskHash
    "ipfs://task-spec"                             // requestURI
);

// The approved validator responds
validationRegistry.submitValidation(requestId, 85, "ipfs://response");
// score >= passThreshold (default 60) → status = Passed
```

## Event Monitoring

```javascript
curve.on("Buy", (buyer, ethIn, tokensOut, feePaid, antiSnipeFee) => {
    console.log(`Buy: ${ethers.formatEther(ethIn)} → ${tokensOut} tokens`);
});

curve.on("Graduated", (pool, ethLiq, tokenLiq, lpTokenId) => {
    console.log(`Graduated to ${pool}, LP #${lpTokenId}`);
});

graduationManager.on("HolderDistributorDeployed",
  (token, distributor, initialPool) => {
    console.log(`Distributor ${distributor} for ${token}`);
});

swapRouter.on("FlexFeeReroutedToTreasury", (token, amount) => {
    // ⚠️ Alert admin — router not yet registered as notifier
    console.warn(`Flex fee rerouted for ${token}: ${amount}`);
});

distributor.on("RewardClaimed", (user, amount) => {
    console.log(`Claimed: ${ethers.formatEther(amount)}`);
});
```

## A2A Integration

### 1. Fetch agent card

```bash
curl https://agent.example.com/.well-known/agent.json
```

### 2. Send request

```bash
curl -X POST https://agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "portfolio",
    "params": {
      "request": "Show me my holdings",
      "requestId": "uuid-...",
      "userId": "0xuser..."
    },
    "id": "uuid-..."
  }'
```

### 3. Handle payment

| Method | Flow |
|---|---|
| Agent token | User transfers tokens → agent creator. Submit tx hash as `paymentProof`. |
| x402 (USDC) | User signs EIP-712 → forward to facilitator `/verify` and `/settle`. |

## Testing

### Fork Testing

```bash
anvil --fork-url https://rpc.testnet.arc.io
```

### Testnet Addresses

| Chain | Chain ID | Deployed |
|---|:---:|:---:|
| Arc Testnet | 5042002 | ✅ |
| Base Sepolia | 84532 | (pending) |
| BOT Chain | 677 | (pending verification) |

See [deployment.md](./deployment.md#deployed-contracts) for addresses.

## Support

- **Contract questions:** GitHub Issues
- **Integration support:** Discord `#builders`
- **Bug reports:** `security@qurve.fun`

## What We Do Not Provide

| Component | Status |
|---|---|
| Backend API access | Closed-source |
| Indexer source | Closed-source |
| Frontend source | Closed-source |
| Agent SDK | Planned (public) |

You can build all of these against the public contracts.
