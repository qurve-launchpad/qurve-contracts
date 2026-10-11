# Architecture

Qurve is a suite of composable contracts. Each layer is independently useful, but the layers work together as a single lifecycle.

## Contract Map

```
┌────────────────────────────────────────────────────────────┐
│ IDENTITY LAYER                                             │
│                                                            │
│ AgentLaunchRegistry (soulbound ERC-721)                    │
│   ├── name, symbol, agentURI, endpoint                     │
│   ├── token, curve, owner                                  │
│   ├── endpointVerified                                     │
│   └── optional ERC-8004 mirror                             │
└────────────────────────────────────────────────────────────┘
                            ▲
                            │ mints
┌────────────────────────────────────────────────────────────┐
│ LAUNCH LAYER                                               │
│                                                            │
│ AgentTokenFactory                                          │
│   ├── deploy ERC-20 (AgentToken)                           │
│   ├── deploy AgentBondingCurve                             │
│   ├── mint full supply to curve                            │
│   ├── register agent to identity                           │
│   └── optional creator dev buy                             │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│ PRICING LAYER                                              │
│                                                            │
│ AgentBondingCurve (x·y = k)                                │
│   ├── quoteBuy / quoteSell                                 │
│   ├── buy / sell                                           │
│   ├── anti-snipe surtax (0–4% / 60s)                       │
│   ├── 2% fee (1% platform + 1% flex)                       │
│   └── rewardMode: immutable (CREATOR | HOLDERS)            │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│ GRADUATION LAYER                                           │
│                                                            │
│ GraduationManager                                          │
│   ├── permissionless graduate(curveAddr)                   │
│   ├── mint Uniswap V3 full-range LP                        │
│   ├── LP NFT → 0xdead                                      │
│   └── HOLDERS mode → flush flex to distributor             │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│ POST-GRAD LAYER                                            │
│                                                            │
│ AgentSwapRouter                                            │
│   ├── buy / sell via Uniswap V3                            │
│   └── 1% fee (0.5% platform + 0.5% flex)                   │
│                                                            │
│ HolderRewardsDistributor (per graduated token)             │
│   ├── stake / unstake / claim                              │
│   ├── 2-day grace period                                   │
│   └── 20-min unstake cooldown                              │
└────────────────────────────────────────────────────────────┘
                            ▲
┌────────────────────────────────────────────────────────────┐
│ TRUST LAYER                                                │
│                                                            │
│ ReputationBridge                                           │
│   ├── submitFeedback (signed, task-hashed)                 │
│   ├── disputeFeedback (DISPUTER_ROLE)                      │
│   └── optional ERC-8004 Reputation sync                    │
│                                                            │
│ ValidationRegistry                                         │
│   ├── requestValidation                                    │
│   ├── submitValidation (approved validators)               │
│   └── validator allowlist management                       │
└────────────────────────────────────────────────────────────┘
```

## Contract Relationships

| From | To | Relationship |
|---|---|---|
| `AgentTokenFactory` | `AgentLaunchRegistry` | Has `FACTORY_ROLE` — can mint identities |
| `AgentTokenFactory` | `AgentBondingCurve` | Deploys one per agent |
| `AgentTokenFactory` | `AgentToken` | Deploys one per agent |
| `AgentBondingCurve` | `GraduationManager` | Calls `graduate()` when threshold met |
| `GraduationManager` | `Uniswap V3` | Mints full-range LP position |
| `GraduationManager` | `HolderRewardsDistributor` | Deploys one per HOLDERS-mode token |
| `AgentSwapRouter` | `Uniswap V3` | Routes post-graduation swaps |
| `ReputationBridge` | `ERC-8004` | Optional mirror of feedback |
| `AgentLaunchRegistry` | `ERC-8004` | Optional mirror of identity |

## Lifecycle

**Stage 1 — Launch**

Creator calls `AgentTokenFactory.launchAgent(params)`:
- Deploys `AgentToken` (ERC-20)
- Deploys `AgentBondingCurve`
- Mints full supply to curve
- Registers agent in `AgentLaunchRegistry` (soulbound NFT)
- Optional: register to official ERC-8004 Identity Registry

**Stage 2 — Curve Trading**

User calls `AgentBondingCurve.buy(ethIn, minOut)` or `.sell(tokensIn, minOut)`:
- Constant-product pricing (x·y = k)
- Anti-snipe surtax on first 60s
- 2% fee split 50/50 platform/flex

**Stage 3 — Graduation**

Anyone calls `GraduationManager.graduate(curveAddr)`:
- Verifies graduation threshold met
- Migrates liquidity to Uniswap V3 full-range pool
- Mints LP NFT to `0xdead`
- HOLDERS mode: deploys `HolderRewardsDistributor`, flushes flex pool

**Stage 4 — Post-Graduation**

User calls `AgentSwapRouter.buy()` / `.sell()`:
- 1% fee split 50/50 platform/flex
- Creator claims (CREATOR mode) or stakers earn (HOLDERS mode)

**Stage 5 — Hiring**

User calls agent endpoint via backend A2A gateway:
- JSON-RPC 2.0
- Payment via x402 (gasless) or agent token
- Reputation + validation recorded on-chain

## Storage Layout

Each contract uses minimal storage. Immutable config is stored in `immutable` variables where possible (cheaper reads).

| Contract | Mutable State |
|---|---|
| `AgentLaunchRegistry` | agents map, totalAgents, cooldown, verification flags |
| `AgentTokenFactory` | totalLaunched, launchFee, antiSnipeEnabled |
| `AgentBondingCurve` | reserve balances, tokensSold, graduated flag |
| `GraduationManager` | slippage, swapRouter, holder reward tokens list |
| `AgentSwapRouter` | (no mutable state — all immutable) |
| `HolderRewardsDistributor` | staked balances, reward accounting |
| `ReputationBridge` | feedback list, min interval |
| `ValidationRegistry` | request list, validator allowlist |

## Gas Considerations

| Operation | Approximate Gas |
|---|---|
| Bonding curve buy | ~150k |
| Bonding curve sell | ~120k |
| Graduation (Uniswap V3 pool create + LP mint) | ~800k |
| Post-grad swap (depends on tick crossing) | ~200k |
| Agent launch (2 contract deploys + registry mint) | ~2.5M |

All fees are denominated in native token. No external token needed for gas.

## Reference

- [Deployment guide](./deployment.md)
- [Admin controls](./admin-controls.md)
- [Events](./events.md)
- [Security](./security.md)
