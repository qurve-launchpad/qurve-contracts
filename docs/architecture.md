# Architecture

Qurve is a suite of composable contracts. Each layer is independently useful, but the layers work together as a single lifecycle.

## Contract Map

```
┌────────────────────────────────────────────────────────────┐
│ IDENTITY LAYER                                             │
│                                                            │
│ AgentLaunchRegistry (soulbound ERC-721)                    │
│   ├── name, agentURI, endpoint                             │
│   ├── token, curve, owner, createdAt, endpointVerified     │
│   ├── officialAgentId (optional ERC-8004 mirror)           │
│   └── endpointUpdateCooldown (default 1h)                  │
└────────────────────────────────────────────────────────────┘
                            ▲
                            │ registerAgent()
┌────────────────────────────────────────────────────────────┐
│ LAUNCH LAYER                                               │
│                                                            │
│ AgentTokenFactory                                          │
│   ├── deploy AgentToken (ERC-20)                           │
│   ├── deploy AgentBondingCurve                             │
│   ├── mintInitialSupply → curve                            │
│   ├── initialize token + curve                             │
│   └── registerAgent → identity                             │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│ PRICING LAYER                                              │
│                                                            │
│ AgentBondingCurve (x·y = k)                                │
│   ├── quoteBuy / quoteSell / currentPrice                  │
│   ├── buy / sell / buyFor                                  │
│   ├── anti-snipe surtax (0–4% linear / 60s)                │
│   ├── 2% fee (1% platform + 1% flex)                       │
│   ├── rewardMode: immutable (CREATOR | HOLDERS)            │
│   └── sweepAbandonedHolderPool / sweepStrayETH             │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│ GRADUATION LAYER                                           │
│                                                            │
│ GraduationManager (Ownable + ReentrancyGuard)              │
│   ├── graduate(curveAddr) — permissionless                 │
│   ├── createAndInitializePoolIfNecessary (Uniswap V3)      │
│   ├── mint full-range LP → 0xdead                          │
│   ├── alignExistingPool (empty pool price correction)      │
│   └── HOLDERS mode → deploy HolderRewardsDistributor       │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│ POST-GRAD LAYER                                            │
│                                                            │
│ AgentSwapRouter (Ownable + ReentrancyGuard)                │
│   ├── buy(agentToken, minTokensOut) via Uniswap V3         │
│   ├── sell(agentToken, tokensIn, minEthOut)                │
│   └── 1% fee (0.5% platform + 0.5% flex)                   │
│                                                            │
│ HolderRewardsDistributor (per HOLDERS-mode token)          │
│   ├── stake / unstake / claim / earned                     │
│   ├── GRACE_PERIOD = 2 days                                │
│   ├── UNSTAKE_COOLDOWN = 20 minutes                        │
│   └── notifyRewardAmount (notifier-gated)                  │
└────────────────────────────────────────────────────────────┘
                            ▲
┌────────────────────────────────────────────────────────────┐
│ TRUST LAYER                                                │
│                                                            │
│ ReputationBridge (AccessControl)                           │
│   ├── submitFeedback(agentId, score, taskHash, commentURI) │
│   ├── disputeFeedback (DISPUTER_ROLE)                      │
│   ├── minRaterInterval = 5 minutes (default)               │
│   └── optional ERC-8004 Reputation sync (gas-capped)       │
│                                                            │
│ ValidationRegistry (AccessControl)                         │
│   ├── requestValidation(agentId, validator, taskHash, uri) │
│   ├── submitValidation(requestId, score, responseURI)      │
│   ├── addValidator / removeValidator (VALIDATOR_ADMIN)     │
│   └── passThreshold = 60 (default)                         │
└────────────────────────────────────────────────────────────┘
```

## Contract Relationships

| From | To | Relationship |
|---|---|---|
| `AgentTokenFactory` | `AgentLaunchRegistry` | Has `FACTORY_ROLE` — calls `registerAgent()` |
| `AgentTokenFactory` | `AgentToken` | Deploys one per agent, calls `mintInitialSupply()` + `initialize()` |
| `AgentTokenFactory` | `AgentBondingCurve` | Deploys one per agent, calls `initialize(token)` |
| `AgentTokenFactory` | `AgentBondingCurve` | Calls `buyFor()` for optional dev-buy |
| `AgentBondingCurve` | `AgentToken` | Only minter/burner post-initialize |
| `AgentBondingCurve` | `GraduationManager` | Calls back via `markGraduated()` |
| `GraduationManager` | `AgentBondingCurve` | Pulls reserves via `withdrawReserveForGraduation()`, `withdrawTokensForGraduation()`, `withdrawHolderPoolForGraduation()` |
| `GraduationManager` | `Uniswap V3` | `createAndInitializePoolIfNecessary`, `mint`, `swap` (for empty-pool correction) |
| `GraduationManager` | `HolderRewardsDistributor` | Deploys per HOLDERS-mode token, calls `notifyRewardAmount()` |
| `AgentSwapRouter` | `GraduationManager` | Reads `requiresWrap`, `nativeToQuoteDecimalOffset`, `distributorOf()` |
| `AgentSwapRouter` | `HolderRewardsDistributor` | Calls `notifyRewardAmount()` if registered as notifier |
| `AgentSwapRouter` | `AgentBondingCurve` | Calls `topUpCreatorPool()` (CREATOR mode) |
| `ReputationBridge` | `AgentLaunchRegistry` | Reads `getAgent()` for `officialAgentId` + `endpoint` |
| `ReputationBridge` | `ERC-8004 Reputation` | Optional `giveFeedback()` sync (gas-capped 200k) |
| `AgentLaunchRegistry` | `ERC-8004 Identity` | Optional `register()` sync (try/catch) |

## Lifecycle

### Stage 1 — Launch

Creator calls `AgentTokenFactory.launchAgent(params)` with `msg.value >= launchFee`:

1. Launch fee forwarded to `protocolFeeRecipient`
2. `AgentToken` deployed (factory as `msg.sender`)
3. `AgentBondingCurve` deployed with `rewardMode` from params
4. `mintInitialSupply(curve, TOTAL_SUPPLY)` → mints 1B to curve
5. `token.initialize(curve, creator)` → curve becomes only minter/burner
6. `curve.initialize(token)` → sanity check `balanceOf(curve) == 800M + 200M`
7. `registry.registerAgent(...)` → mints soulbound NFT
8. Optional `curve.buyFor{value: devBuy}(...)` — if `msg.value > launchFee`
9. Tracked in `allTokens`, `allCurves`, `isAgentToken`, `curveOfToken`

### Stage 2 — Curve Trading

User calls `AgentBondingCurve.buy(ethIn, minTokensOut)` or `.sell(tokensIn, minEthOut)`:

- Constant-product pricing (`x·y = k`)
- Anti-snipe surtax: `ANTI_SNIPE_MAX_BPS × (ANTI_SNIPE_WINDOW − elapsed) / ANTI_SNIPE_WINDOW`
- 2% fee (`FEE_BPS = 200`) split 1% platform + 1% flex
- Flex routes to `pendingCreatorClaim` (CREATOR) or `pendingHolderPool` (HOLDERS)
- Anti-snipe portion added to `realEthReserve` (not routed as fee)
- Near sell-out: partial-fill clamp with refund

### Stage 3 — Graduation

Anyone calls `GraduationManager.graduate(curveAddr)`:

- Curve must satisfy `isGraduationEligible()` (sold-out OR threshold met)
- Two-way validation: `agentFactory.isAgentToken(token)` AND `agentFactory.curveOfToken(token) == curveAddr`
- Pulls ETH reserve + token supply + holder pool (if HOLDERS)
- Wraps native → quote asset if `requiresWrap == true`
- Creates Uniswap V3 pool at computed `sqrtPriceX96`
- Aligns existing empty pool price via 1-wei swap if needed
- Mints full-range LP NFT to `0xdead`
- HOLDERS mode: deploys `HolderRewardsDistributor` + flushes `pendingHolderPool`
- `curve.markGraduated(pool, lpTokenId)` sets `graduated = true` as **last step**

**Critical**: The curve is **never locked** merely because the threshold was reached. Buy/sell stay open until `graduate()` succeeds end-to-end. If migration fails, the whole tx reverts and holders can keep selling.

### Stage 4 — Post-Graduation

User calls `AgentSwapRouter.buy(agentToken, minOut)` or `.sell(agentToken, tokensIn, minEthOut)`:

- 1% fee (`FEE_BPS = 100`) split 0.5% platform + 0.5% flex
- Buy: fee taken before swap, wraps native if needed, converts scale via `nativeToQuoteDecimalOffset`
- Sell: fee taken after swap, unwraps quote → native if needed
- Flex: `notifyRewardAmount{value: flexCut}()` on distributor (if registered notifier), else `FlexFeeReroutedToTreasury`
- CREATOR mode: `curve.topUpCreatorPool{value: flexCut}()`

### Stage 5 — Hiring

User calls agent endpoint via backend A2A gateway:

- JSON-RPC 2.0
- Payment via x402 (gasless) or agent token
- Reputation (`submitFeedback`) + Validation (`requestValidation` → `submitValidation`) recorded on-chain

## Bonding Curve Math (Verbatim From Code)

```
Current effective reserves:
    tReserve = virtualTokenReserve - tokensSold
    eReserve = virtualEthReserve + realEthReserve

Buy quote (_rawQuoteBuy(ethInAfterFee)):
    k = tReserve * eReserve
    newEReserve = eReserve + ethInAfterFee
    newTReserve = k / newEReserve              // floor division
    tokensOut = tReserve - newTReserve

Sell quote (quoteSell(tokensIn)):
    k = tReserve * eReserve
    newTReserve = tReserve + tokensIn
    newEReserve = (k + newTReserve - 1) / newTReserve   // ceil division
    ethOut = eReserve - newEReserve

Spot price:
    price = (eReserve * 1e18) / tReserve

Graduation threshold (derived in constructor):
    tReserveAtSellOut = virtualTokenReserve - tokensForSale
    k = virtualTokenReserve * virtualEthReserve
    ethReserveAtSellOut = k / tReserveAtSellOut
    graduationThreshold = ethReserveAtSellOut - virtualEthReserve
```

**Fee & Surtax:**

```
fee          = ethIn * FEE_BPS / BPS_DENOM                      // FEE_BPS = 200
antiSnipeFee = ethIn * _antiSnipeFeeBps() / BPS_DENOM
amountAfterFee = ethIn - fee - antiSnipeFee

_antiSnipeFeeBps():
    if !antiSnipeEnabled: return 0
    elapsed = block.timestamp - launchedAt
    if elapsed >= ANTI_SNIPE_WINDOW: return 0
    return ANTI_SNIPE_MAX_BPS * (ANTI_SNIPE_WINDOW - elapsed) / ANTI_SNIPE_WINDOW
```

## Reward Modes

Set once at curve construction, immutable:

| Mode | Flex Fee Destination | Claim Mechanism |
|---|---|---|
| `CREATOR` | `pendingCreatorClaim` | `claimCreatorFees()` (creator-only) |
| `HOLDERS` | `pendingHolderPool` | `withdrawHolderPoolForGraduation()` → distributor |

**Fallback paths:**
- If HOLDERS curve is abandoned (no trade for `ABANDON_TIMEOUT = 30 days`) AND not graduation-eligible → anyone can `sweepAbandonedHolderPool()` to `protocolFeeRecipient`
- Stray ETH (not counted in `realEthReserve`, `pendingCreatorClaim`, or `pendingHolderPool`) can be swept by anyone via `sweepStrayETH()`

## ERC-8004 Registry Integration

| Registry | Status | Sync |
|---|---|---|
| Identity | ✅ Connected | `AgentLaunchRegistry._trySyncOfficialIdentity()` — try/catch, non-fatal |
| Reputation | ✅ Connected | `ReputationBridge._trySyncOfficialFeedback()` — gas-capped 200k, non-fatal |
| Validation | ❌ **Deliberately NOT connected** | Official Validation Registry withdrawn from multi-chain deployment pending community rework |

## Storage Layout

| Contract | Mutable State |
|---|---|
| `AgentLaunchRegistry` | `_agents`, `_agentIdByToken`, `_lastEndpointUpdate`, `_pendingOfficialSyncAgentId`, `endpointUpdateCooldown`, `officialSyncEnabled` |
| `AgentTokenFactory` | `launchFee`, `graduationManager`, `antiSnipeEnabled`, `allTokens`, `allCurves`, `isAgentToken`, `curveOfToken` |
| `AgentToken` | `_curve`, `_agentOwner`, `_initialized` |
| `AgentBondingCurve` | `agentToken`, `initialized`, `tokensSold`, `realEthReserve`, `graduated`, `migrationStarted`, `ethWithdrawnForGraduation`, `tokensWithdrawnForGraduation`, `pendingCreatorClaim`, `pendingHolderPool`, `lastTradeAt` |
| `GraduationManager` | `graduationSlippageBps`, `distributorOf`, `holderRewardTokens`, `swapRouter`, `_poolInCorrection` |
| `AgentSwapRouter` | (no mutable state — all immutable) |
| `HolderRewardsDistributor` | `isNotifier`, `accRewardPerShare`, `totalStaked`, `totalRewardsDistributed`, `totalClaimed`, `unallocatedInitialPool`, `initialPoolFinalized`, `stakedBalance`, `rewardDebt`, `stakedAt`, `totalClaimedBy` |
| `ReputationBridge` | `officialSyncEnabled`, `minRaterInterval`, `_feedbacks`, `_rated`, `_scoreSum`, `_validFeedbackCount`, `_lastRaterTimestamp` |
| `ValidationRegistry` | `passThreshold`, `_nextRequestId`, `_requests`, `isApprovedValidator` |

## Immutable Config

| Contract | Immutable Variables |
|---|---|
| `AgentLaunchRegistry` | `officialIdentityRegistry` |
| `AgentToken` | `factory` |
| `AgentBondingCurve` | `factory`, `creator`, `weth`, `graduationManager`, `protocolFeeRecipient`, `antiSnipeEnabled`, `launchedAt`, `rewardMode`, `virtualTokenReserve`, `virtualEthReserve`, `tokensForSale`, `tokensForLiquidity`, `graduationThreshold` |
| `AgentTokenFactory` | `registry`, `weth`, `protocolFeeRecipient` |
| `GraduationManager` | `uniswapFactory`, `positionManager`, `weth`, `agentFactory`, `requiresWrap`, `nativeToQuoteDecimalOffset` |
| `AgentSwapRouter` | `swapRouter`, `quoteAsset`, `protocolFeeRecipient`, `agentFactory`, `graduationManager`, `requiresWrap`, `nativeToQuoteDecimalOffset` |
| `HolderRewardsDistributor` | `stakingToken`, `deployedAt` |
| `ReputationBridge` | `registry`, `officialReputationRegistry` |
| `ValidationRegistry` | `registry` |

## Constants

| Contract | Constants |
|---|---|
| `AgentBondingCurve` | `PLATFORM_FEE_BPS=100`, `FLEX_FEE_BPS=100`, `FEE_BPS=200`, `BPS_DENOM=10_000`, `ANTI_SNIPE_MAX_BPS=400`, `ANTI_SNIPE_WINDOW=60`, `ABANDON_TIMEOUT=30 days` |
| `AgentTokenFactory` | `MAX_LAUNCH_FEE=1 ether`, `TOTAL_SUPPLY=1B ether`, `TOKENS_FOR_SALE=800M ether`, `TOKENS_FOR_LIQUIDITY=200M ether`, `VIRTUAL_TOKEN_RESERVE=1073M ether` |
| `GraduationManager` | `POOL_FEE=3000`, `TICK_LOWER=-887220`, `TICK_UPPER=887220`, `MAX_SLIPPAGE_BPS=1000`, `BPS_DENOM=10_000`, `DEAD=0x…dEaD` |
| `AgentSwapRouter` | `POOL_FEE=3000`, `PLATFORM_FEE_BPS=50`, `FLEX_FEE_BPS=50`, `FEE_BPS=100`, `BPS_DENOM=10_000` |
| `HolderRewardsDistributor` | `GRACE_PERIOD=2 days`, `UNSTAKE_COOLDOWN=20 minutes` |
| `ReputationBridge` | `OFFICIAL_CALL_GAS=200_000` |

## Reference

- [Deployment guide](./deployment.md)
- [Admin controls](./admin-controls.md)
- [Events](./events.md)
- [Security](./security.md)
- [Integration](./integration.md)
