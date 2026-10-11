# Security

## Status

> **Qurve contracts have not undergone a third-party security audit.** They have been developed with internal review and live-tested on testnets plus mainnet deployments. Treat them as pre-audit infrastructure.

## What We Claim

| Claim | Verified |
|---|:---:|
| Code is immutable after deployment | ✅ |
| LP has no exit function | ✅ |
| No admin key can move user funds | ✅ |
| No pause, freeze, or blacklist | ✅ |
| No upgradeability | ✅ |

## What We Do NOT Claim

| Claim | Reason |
|---|---|
| **"Battle-tested"** | Not until audit + mainnet operation |
| **"Bug-free"** | One fix already applied, others may exist |
| **"Audited"** | Audit not scheduled yet |
| **"Upgradeable"** | Contracts are immutable by design |

## Known Fixes

### FIX #2 — `Math.mulDiv` overflow

**Location:** `GraduationManager` LP price computation

**Issue:** `Math.mulDiv` was used without checking for overflow. On chains where the agent token address sorts higher than the wrapped native token, the multiplication overflowed and reverted approximately 50% of all graduations.

**Resolution:** Applied and present in current deployment.

**Lesson:** Full-range LP computation requires careful decimal handling when token order is not guaranteed.

## Threat Model

### In-scope (assumed correct)

| Component | Assumption |
|---|---|
| OpenZeppelin base contracts | Audited, standard usage |
| Solidity 0.8.x overflow checks | Enabled |
| Uniswap V3 core | Audited, used as-is |
| Immutability of `immutable` vars | Guaranteed by EVM |

### Out-of-scope

| Component | Reason |
|---|---|
| Frontend UI | Closed-source |
| Backend API | Closed-source |
| Indexer | Closed-source |
| Agent endpoints | Third-party |
| Circle Gateway (x402) | External |

### Attack Vectors Considered

| Vector | Mitigation |
|---|---|
| **Reentrancy** | `ReentrancyGuard` on state-changing functions with external calls |
| **Front-running** | Anti-snipe surtax (0–4% over 60s) |
| **Flash loan** | Bonding curve math linear in reserve; flash loans don't gain advantage |
| **Oracle manipulation** | Curve uses internal reserve ratio, not external oracle |
| **Rug pull** | LP NFT burned to `0xdead` — no exit function exists |
| **Admin abuse** | Admin surface fully enumerated and bounded |
| **Upgrade attack** | No upgradeability. Immutable by design. |

### Attack Vectors Accepted

| Vector | Reason accepted |
|---|---|
| **Sniper bot** on first block | Mitigated by surtax, not eliminated |
| **Fee bypass via external router** | Uniswap pool is public. Fee is voluntary. |
| **Wash trading** | Not economically viable due to 2% trade fee |
| **Sybil feedback** | Rate-limited but not impossible. Dispute path available. |

## Responsible Disclosure

To report a vulnerability:

**Email:** `security@qurve.fun`

Include:
- Description
- Steps to reproduce
- Suggested fix (if known)
- Your contact for follow-up

**We do not currently offer a bug bounty.** This will change after audit.

## No Pause Function

Qurve deliberately does not implement `pause()` on any contract.

**Consequences:**
- If a bug is discovered after deployment, there is no way to halt affected contracts
- The only mitigation is deploying a corrected version and migrating
- Users of existing contracts retain full access to their funds and tokens

**Rationale:**
- "No admin override" philosophy
- Prevents governance capture
- Users can exit at any time without permission

This trade-off is acknowledged and accepted.

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

1. **Check address** on the [deployed contracts list](../README.md#deployed-contracts)
2. **Verify source code** on the block explorer
3. **Compare** with this repository's `contracts/` folder
4. **Confirm** the bytecode hash matches

Do not trust any address not listed in this repository.

## Emergency Response

There is no emergency admin key. In case of a discovered vulnerability:

| Action | Possible |
|---|---|:---:|
| Pause contracts | ❌ |
| Freeze user funds | ❌ |
| Blacklist address | ❌ |
| Deploy fix | ✅ (as new version) |
| Warn users | ✅ (off-chain) |

Users always retain access to their funds and tokens, regardless of contract state.
