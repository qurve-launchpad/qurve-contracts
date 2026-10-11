# Admin Controls

Qurve minimizes admin surface, but does not eliminate it. This document lists every administrative function across deployed contracts — verified against actual source code.

> **Nothing outside this list can be changed by anyone after deployment.**

## What No Admin Can Do

| Action | Enforced |
|---|:---:|
| Mint agent tokens after launch | ✅ Not possible (`mintInitialSupply` one-shot, `mint`/`burn` curve-only) |
| Withdraw curve reserves outside graduation | ✅ Not possible |
| Move or withdraw LP | ✅ Not possible (LP NFT burned to `0xdead`) |
| Withdraw holder rewards | ✅ Not possible (`HolderRewardsDistributor` has no admin withdrawal) |
| Change reward mode | ✅ Not possible (immutable at curve construction) |
| Change launch fee retroactively | ✅ Not possible (applies to next launch only) |
| Change contract address for existing agent | ✅ Not possible (all core addresses immutable) |
| Pause, freeze, or blacklist | ✅ No `pause()` function exists |
| Upgrade any contract | ✅ None are upgradeable (no UUPS, no proxy) |

## AgentLaunchRegistry

Access: `AccessControl` (`DEFAULT_ADMIN_ROLE`, `FACTORY_ROLE`, `VERIFIER_ROLE`)

| Function | Role | Effect |
|---|---|---|
| `setOfficialSyncEnabled(bool)` | `DEFAULT_ADMIN_ROLE` | Toggles ERC-8004 Identity mirroring for new registrations |
| `setEndpointUpdateCooldown(uint256)` | `DEFAULT_ADMIN_ROLE` | Adjusts cooldown between endpoint updates (default 1 hour) |
| `setEndpointVerified(agentId, bool)` | `VERIFIER_ROLE` | Marks agent endpoint as verified |
| `sweepStrayNFT(nftContract, tokenId, to)` | `DEFAULT_ADMIN_ROLE` | Recovers NFTs accidentally sent to registry |
| `grantRole` / `revokeRole` | `DEFAULT_ADMIN_ROLE` | Manages `FACTORY_ROLE`, `VERIFIER_ROLE` |
| `registerAgent(...)` | `FACTORY_ROLE` | Mints new agent identity (called by factory only) |

**Does NOT affect:** agent ownership, tokens, curves, or existing verification status.

**Permissionless:** `retryOfficialRegistration(agentId)`, `claimOfficialIdentityNFT(agentId)` — anyone can call, no downside.

## AgentTokenFactory

Access: `Ownable`

| Function | Role | Effect |
|---|---|---|
| `setGraduationManager(address)` | `onlyOwner` | Points factory to new GM (future launches only) |
| `setAntiSnipeEnabled(bool)` | `onlyOwner` | Toggles anti-snipe for **future** launches |
| `setLaunchFee(uint256)` | `onlyOwner` | Adjusts launch fee (bounded by `MAX_LAUNCH_FEE = 1 ether`) |
| `transferOwnership` / `renounceOwnership` | `onlyOwner` | Standard OpenZeppelin Ownable |

**Does NOT affect:** already-launched tokens or curves.

**Hard cap:** `MAX_LAUNCH_FEE = 1 ether`. Prevents owner (or compromised key) from setting absurd fee.

## GraduationManager

Access: `Ownable` — **NOT upgradeable**

| Function | Role | Effect |
|---|---|---|
| `setGraduationSlippageBps(uint16)` | `onlyOwner` | Adjusts LP mint slippage (bounded by `MAX_SLIPPAGE_BPS = 1000`) |
| `setSwapRouter(address)` | `onlyOwner` | Updates swap router for future distributor wiring |
| `transferOwnership` / `renounceOwnership` | `onlyOwner` | Standard OpenZeppelin Ownable |

**Does NOT affect:** already-created Uniswap pools or burned LP NFTs.

**Permissionless:** `graduate(curveAddr)` — anyone can trigger graduation for an eligible curve.

## AgentSwapRouter

Access: `Ownable` — **all config immutable**

| Function | Role | Effect |
|---|---|---|
| `transferOwnership` / `renounceOwnership` | `onlyOwner` | Standard OpenZeppelin Ownable |

**No fee recipient setter.** No swap router setter. No parameter changes possible.

## HolderRewardsDistributor

Access: `Ownable` (owner = GraduationManager at deploy time)

| Function | Role | Effect |
|---|---|---|
| `setNotifier(address, bool)` | `onlyOwner` | Authorizes address to call `notifyRewardAmount()` |
| `transferOwnership` / `renounceOwnership` | `onlyOwner` | Standard OpenZeppelin Ownable |

**Permissionless:** `finalizeInitialPool()` — anyone can trigger after grace period expires (or once `totalStaked > 0`).

**Does NOT affect:** user staked balances or claim rights.

## ReputationBridge

Access: `AccessControl` (`DEFAULT_ADMIN_ROLE`, `DISPUTER_ROLE`)

| Function | Role | Effect |
|---|---|---|
| `setOfficialSyncEnabled(bool)` | `DEFAULT_ADMIN_ROLE` | Toggles ERC-8004 Reputation mirroring |
| `setMinRaterInterval(uint256)` | `DEFAULT_ADMIN_ROLE` | Adjusts minimum time between feedback (default 5 min) |
| `grantRole` / `revokeRole` | `DEFAULT_ADMIN_ROLE` | Manages `DISPUTER_ROLE` |
| `disputeFeedback(agentId, index, reasonURI)` | `DISPUTER_ROLE` | Marks feedback as disputed (removes score) |

**Does NOT affect:** already-recorded feedback content.

## ValidationRegistry

Access: `AccessControl` (`DEFAULT_ADMIN_ROLE`, `VALIDATOR_ADMIN_ROLE`)

| Function | Role | Effect |
|---|---|---|
| `addValidator(address)` | `VALIDATOR_ADMIN_ROLE` | Adds address to approved validators |
| `removeValidator(address)` | `VALIDATOR_ADMIN_ROLE` | Removes address from allowlist |
| `setPassThreshold(uint8)` | `VALIDATOR_ADMIN_ROLE` | Adjusts score threshold (default 60, bounded ≤ 100) |
| `grantRole` / `revokeRole` | `DEFAULT_ADMIN_ROLE` | Manages `VALIDATOR_ADMIN_ROLE` |

**Does NOT affect:** existing validation records.

## AgentToken

**No admin functions.** Only `curve` can call `mint` / `burn`. Only `factory` can call `mintInitialSupply` / `initialize`.

## AgentBondingCurve

**No admin functions.** No owner, no roles, no setters.

**Permissionless:** `sweepAbandonedHolderPool()`, `sweepStrayETH()`.

## Admin Role Summary

| Role | Contract(s) | Typical Holder |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | `AgentLaunchRegistry`, `ReputationBridge`, `ValidationRegistry` | Deployer EOA / multisig |
| `FACTORY_ROLE` | `AgentLaunchRegistry` | `AgentTokenFactory` |
| `VERIFIER_ROLE` | `AgentLaunchRegistry` | Platform verifier |
| `DISPUTER_ROLE` | `ReputationBridge` | Platform moderator |
| `VALIDATOR_ADMIN_ROLE` | `ValidationRegistry` | Platform admin |
| `Ownable.owner` | `AgentTokenFactory`, `GraduationManager`, `AgentSwapRouter`, `HolderRewardsDistributor` | Deployer EOA / multisig |

## No Pause Function

Qurve deliberately does not implement `pause()` on any contract.

> **If a bug is discovered after deployment, there is no way to halt affected contracts.** The only mitigation is deploying a corrected version and migrating new launches. Users retain full access to funds and tokens regardless.

## Emergency Procedures

There are no emergency admin procedures. Qurve is designed to be immutable and trustless.

| Scenario | Response |
|---|---|
| Bug in one contract | Deploy fixed version, migrate new launches |
| Exploit in progress | Cannot pause. Document, warn users, deploy fix |
| RPC down | Users switch RPC. Contracts unaffected |
| Frontend compromised | Users interact via explorer |
| Backend down | Contracts unaffected. A2A calls fail until restored |

## Current Custody

All roles held by a **single deployer EOA per chain** as of current deployments.

| Chain | Admin EOA |
|---|---|
| Arc Testnet | (deployer of `0xFa2952Bb…`) |
| BOT Chain | (deployer of `0xAB180c46…`) |
| Base Sepolia | (deployer of TBD) |

> **Multisig migration** to a disclosed-signer Safe is planned before broader mainnet expansion.
