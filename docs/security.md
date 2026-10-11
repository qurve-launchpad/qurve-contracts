# Security

## Status

> **Qurve contracts have not undergone a third-party security audit.** They have been developed with internal review and live-tested on Arc Testnet. Treat them as pre-audit infrastructure.

## What We Claim

| Claim | Verified |
|---|:---:|
| Code is immutable after deployment | ✅ |
| No contract is upgradeable | ✅ (all plain Ownable/AccessControl, no UUPS/proxy) |
| LP has no exit function | ✅ (NFT minted to `0xdead`) |
| No admin key can move user funds | ✅ |
| No pause, freeze, or blacklist | ✅ |

## What We Do NOT Claim

| Claim | Reason |
|---|---|
| "Battle-tested" | Not until audit + mainnet operation |
| "Bug-free" | Fixes already applied, others may exist |
| "Audited" | Audit not scheduled yet |
| "Multi-chain battle-tested" | Currently verified on Arc Testnet |

## Known Fixes Applied

### FIX #1 — Uniswap V3 tick alignment

**Location:** `GraduationManager.TICK_LOWER` / `TICK_UPPER`

**Issue:** Original values `-887200 / 887200` are not multiples of 60 (tick spacing for fee tier 3000). Every `mint()` would revert.

**Resolution:** Corrected to `-887220 / 887220` (both divisible by 60, still ≤ 887272).

### FIX #2 — `Math.mulDiv` overflow in LP price computation

**Location:** `GraduationManager._computeSqrtPriceX96`

**Issue:** `amount1 * (1 << 192)` overflowed `uint256` when `amount1` was the agent-token side (~2e26). Reverted ~50% of graduations (case: `tokenAddr > weth`).

**Resolution:** Uses `Math.mulDiv(amount1, 1 << 128, amount0)` (512-bit intermediate) then `sqrt() << 32`.

### FIX #4 — Two-way curve validation

**Location:** `GraduationManager.graduate`

**Issue:** Original check verified `curve.agentToken()` returned a registered token — a fake curve could return the real token address and pass the guard, then init the real pool at a manipulated price.

**Resolution:** Now requires `agentFactory.isAgentToken(token)` AND `agentFactory.curveOfToken(token) == curveAddr`.

### FIX #5 — LP mint slippage guard

**Location:** `GraduationManager.graduate`

**Issue:** If the pool was pre-initialized by a third party at a skewed price, `mint()` would silently accept a bad ratio.

**Resolution:** Added `amount0Min` / `amount1Min` from `graduationSlippageBps` (default 1%, max 10%).

### FIX C-1 — No auto-lock on threshold

**Location:** `AgentBondingCurve._executeBuy`

**Issue:** Original design locked the curve the moment the threshold was reached, trapping funds if graduation migration failed.

**Resolution:** Curve remains fully tradable until `GraduationManager.graduate()` completes and calls `markGraduated()`. If migration fails, the whole tx reverts and holders can keep selling.

### FIX M1 — Stray ETH sweep

**Location:** `AgentBondingCurve.sweepStrayETH`

**Issue:** ETH sent directly to the curve address (not via `buy`/`topUpCreatorPool`) was unaccounted and stuck forever.

**Resolution:** Permissionless `sweepStrayETH()` routes unaccounted balance to `protocolFeeRecipient`.

### FIX M3 — `tokenURI` reverts on missing agent

**Location:** `AgentLaunchRegistry.tokenURI`

**Issue:** Returned empty string for non-existent `agentId`, confusing wallets/explorers.

**Resolution:** Reverts with `AgentNotFound()` (EIP-721 compliant).

### FIX H1 — Fee reroute instead of revert

**Location:** `AgentSwapRouter._routeFee`

**Issue:** If a distributor existed but the router wasn't yet registered as notifier, the swap reverted.

**Resolution:** Redirects flex fee to treasury and emits `FlexFeeReroutedToTreasury`. Backend alerts admin to call `setNotifier()`.

### FIX C1 — `address(0)` distributor guard

**Location:** `AgentSwapRouter._routeFee`

**Issue:** Sending ETH to `address(0)` succeeds on the EVM and burns the funds silently.

**Resolution:** Reverts with `DistributorNotReady()` if distributor is zero.

## Threat Model

### In-scope (assumed correct)

| Component | Assumption |
|---|---|
| OpenZeppelin base contracts | Audited, standard usage |
| Solidity 0.8.x overflow checks | Enabled |
| Uniswap V3 core | Audited, used as-is |
| Immutability of `immutable` vars | Guaranteed by EVM |
| Native `msg.value` semantics | Guaranteed by EVM |

### Out-of-scope

| Component | Reason |
|---|---|
| Frontend UI | Closed-source |
| Backend API | Closed-source |
| Indexer | Closed-source |
| Agent endpoints (A2A) | Third-party |
| ERC-8004 external registries | External, best-effort sync only |
| Uniswap V3 pool after graduation | Public & permissionless |

### Attack Vectors Considered

| Vector | Mitigation |
|---|---|
| **Reentrancy** | `ReentrancyGuard` on `AgentBondingCurve`, `AgentTokenFactory`, `GraduationManager`, `AgentSwapRouter`, `HolderRewardsDistributor` |
| **Front-running / sniping** | Anti-snipe surtax (0–4% over 60s, linear decay) |
| **Flash loan** | Curve math linear in reserve — flash loans don't gain advantage |
| **Oracle manipulation** | Curve uses internal reserve ratio, not external oracle |
| **Rug pull** | LP NFT burned to `0xdead`; no transfer function |
| **Admin abuse** | Admin surface fully enumerated and bounded |
| **Upgrade attack** | None — no upgradeability anywhere |
| **Fake curve at graduation** | Two-way validation in `graduate()` (FIX #4) |
| **Skewed pre-init pool** | `_alignExistingPool` + `amountMin` slippage (FIX #5) |
| **Sandwiching curve trades** | `minTokensOut` / `minEthOut` params |
| **Partial fill at sell-out** | Clamp with ETH refund (no ETH kept) |
| **Fee stuck on abandoned curve** | `sweepAbandonedHolderPool` after 30 days |
| **Stray ETH stuck** | `sweepStrayETH` permissionless |
| **Contract address squatting** | Deterministic deploy from factory |

### Attack Vectors Accepted

| Vector | Reason accepted |
|---|---|
| **Sniper bot** on first block | Mitigated by surtax, not eliminated |
| **Fee bypass via external router** | Uniswap V3 pool is public. Fee is voluntary. |
| **Wash trading** | Not economically viable due to 2% trade fee |
| **Sybil feedback** | Rate-limited via `minRaterInterval`; dispute path available |
| **Creator fee pull** | `claimCreatorFees` is manual — creator may never claim |

## Reentrancy Protection

All state-mutating contracts with external calls use OpenZeppelin's `ReentrancyGuard`:

- `AgentBondingCurve`
- `AgentTokenFactory`
- `GraduationManager`
- `AgentSwapRouter`
- `HolderRewardsDistributor`

## Access Control

| Contract | Access Model |
|---|---|
| `AgentLaunchRegistry` | `AccessControl` (`DEFAULT_ADMIN_ROLE`, `FACTORY_ROLE`, `VERIFIER_ROLE`) |
| `AgentTokenFactory` | `Ownable` + `ReentrancyGuard` |
| `AgentToken` | No owner — factory-only init, curve-only mint/burn |
| `AgentBondingCurve` | No owner — immutables only |
| `GraduationManager` | `Ownable` + `ReentrancyGuard` (no upgradeability) |
| `AgentSwapRouter` | `Ownable` + `ReentrancyGuard` (all params immutable) |
| `HolderRewardsDistributor` | `Ownable` + `ReentrancyGuard` |
| `ReputationBridge` | `AccessControl` (`DEFAULT_ADMIN_ROLE`, `DISPUTER_ROLE`) |
| `ValidationRegistry` | `AccessControl` (`DEFAULT_ADMIN_ROLE`, `VALIDATOR_ADMIN_ROLE`) |

## External Calls — Safety Pattern

All external calls to non-critical dependencies follow a **non-fatal** pattern:

| Call site | Pattern |
|---|---|
| `AgentLaunchRegistry._trySyncOfficialIdentity` | try/catch, no gas cap (last op in tx) |
| `ReputationBridge._trySyncOfficialFeedback` | try/catch + `{gas: OFFICIAL_CALL_GAS}` (200k) |
| `AgentLaunchRegistry.onERC721Received` forward | try/catch on `safeTransferFrom` |
| `AgentSwapRouter._routeFee` → distributor | try/catch on notifier status + emit event |

## ERC-8004 Stability Warning

ERC-8004 is a **Draft standard**. The `giveFeedback` signature has changed at least once during development.

`ReputationBridge` uses:
```solidity
giveFeedback(
    uint256 agentId,
    int128 value,
    uint8 valueDecimals,
    string tag1,
    string tag2,
    string endpoint,
    string feedbackURI,
    bytes32 feedbackHash
)
```

If the deployed registry's ABI differs, the call reverts → caught → `OfficialFeedbackSyncSkipped` emitted. Local feedback is **always** stored.

## Validation Registry Not Connected

`ValidationRegistry` is **deliberately not** connected to the official ERC-8004 Validation Registry. That registry was withdrawn from standard multi-chain deployment pending a community rework. Connecting to a "seemingly official" address now risks connecting to a version that will be deprecated.

## Responsible Disclosure

To report a vulnerability:

**Email:** `security@qurve.fun`

Include:
- Description
- Steps to reproduce
- Suggested fix (if known)
- Your contact for follow-up

**We do not currently offer a bug bounty.** This will change after audit.

## Multisig Migration

Currently, all admin roles are held by a **single deployer EOA per chain**. This is a temporary state.

**Planned migration:**
- Deploy Gnosis Safe on each chain
- Disclose signer addresses publicly
- Set threshold: 3-of-5 or 2-of-3
- Transfer all `onlyOwner` and `DEFAULT_ADMIN_ROLE` to multisig

**Timeline:** Before broader mainnet expansion.

## Verifying Contracts

Before interacting with any Qurve contract:

1. **Check address** on the [deployed contracts list](./deployment.md#deployed-contracts)
2. **Verify source code** on the block explorer
3. **Compare** with this repository's `contracts/` folder
4. **Confirm** the bytecode hash matches

Do not trust any address not listed in this repository.
