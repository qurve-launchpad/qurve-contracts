# Admin Controls

Qurve minimizes admin surface, but does not eliminate it. This document lists every administrative function across deployed contracts.

> **Nothing outside this list can be changed by anyone after deployment.**

## What No Admin Can Do

| Action | Enforced |
|---|:---:|
| Mint agent tokens after launch | ✅ Not possible |
| Withdraw curve reserves outside graduation | ✅ Not possible |
| Move or withdraw LP | ✅ Not possible |
| Withdraw holder rewards | ✅ Not possible |
| Change reward mode | ✅ Not possible |
| Change launch fee retroactively | ✅ Not possible |
| Pause, freeze, or blacklist | ✅ No `pause()` exists |

## AgentLaunchRegistry

| Function | Role | Effect |
|---|---|---|
| `setOfficialSyncEnabled(bool)` | `DEFAULT_ADMIN_ROLE` | Toggles ERC-8004 identity mirroring for new agents |
| `setEndpointUpdateCooldown(uint256)` | `DEFAULT_ADMIN_ROLE` | Adjusts cooldown between endpoint updates |
| `setEndpointVerified(agentId, bool)` | `VERIFIER_ROLE` | Marks agent endpoint as verified |
| `sweepStrayNFT(nftContract, tokenId, to)` | `DEFAULT_ADMIN_ROLE` | Recovers NFTs accidentally sent to registry |
| `grantRole / revokeRole` | `DEFAULT_ADMIN_ROLE` | Manages `FACTORY_ROLE` and `VERIFIER_ROLE` |

**Does not affect:** agent ownership, tokens, curves, or existing verification status.

## AgentTokenFactory

| Function | Role | Effect |
|---|---|---|
| `setGraduationManager(address)` | `onlyOwner` | Points factory to new GM (future launches only) |
| `setAntiSnipeEnabled(bool)` | `onlyOwner` | Toggles anti-snipe for future launches |
| `setLaunchFee(uint256)` | `onlyOwner` | Adjusts launch fee (bounded by `MAX_LAUNCH_FEE`) |

**Does not affect:** already-launched tokens or curves.

## GraduationManager

| Function | Role | Effect |
|---|---|---|
| `setGraduationSlippageBps(uint16)` | `onlyOwner` | Adjusts LP mint slippage (bounded by `MAX_SLIPPAGE_BPS = 1000`) |
| `setSwapRouter(address)` | `onlyOwner` | Updates swap router for future graduations |
| `transferOwnership / renounceOwnership` | `onlyOwner` | Standard OpenZeppelin Ownable |

**Does not affect:** already-created Uniswap pools or burned LP NFTs.

## ReputationBridge

| Function | Role | Effect |
|---|---|---|
| `setOfficialSyncEnabled(bool)` | `DEFAULT_ADMIN_ROLE` | Toggles ERC-8004 reputation mirroring |
| `setMinRaterInterval(uint256)` | `DEFAULT_ADMIN_ROLE` | Adjusts minimum time between feedback |
| `grantRole / revokeRole` | `DEFAULT_ADMIN_ROLE` | Manages `DISPUTER_ROLE` |

**Does not affect:** already-recorded feedback.

## ValidationRegistry

| Function | Role | Effect |
|---|---|---|
| `addValidator(address)` | `VALIDATOR_ADMIN_ROLE` | Adds address to approved validators |
| `removeValidator(address)` | `VALIDATOR_ADMIN_ROLE` | Removes address from allowlist |
| `setPassThreshold(uint8)` | `VALIDATOR_ADMIN_ROLE` | Adjusts score threshold for "passed" |
| `grantRole / revokeRole` | `DEFAULT_ADMIN_ROLE` | Manages `VALIDATOR_ADMIN_ROLE` |

**Does not affect:** existing validation records.

## HolderRewardsDistributor

| Function | Role | Effect |
|---|---|---|
| `setNotifier(address, bool)` | `onlyOwner` (GM) | Authorizes address to call `notifyRewardAmount()` |
| `finalizeInitialPool()` | `onlyOwner` | Finalizes grace period, distributes held rewards |

**Does not affect:** user staked balances or claim rights.

## AgentSwapRouter

**No operational functions exist beyond Ownable built-ins.**

The router is a pure pass-through with immutable fee parameters.

## Current Custody

As of the current deployment, all roles are held by a **single deployer EOA per chain**.

| Chain | Deployer EOA |
|---|---|
| BOT Chain | `0x...` |
| Arc Testnet | `0x...` |
| Base Sepolia | `0x...` |

> **Multisig migration** to a disclosed-signer Safe is planned before broader mainnet expansion.

## No Pause Function

Qurve deliberately does not implement `pause()` on any contract.

> **If a bug is discovered after deployment, there is no way to halt affected contracts.** The only mitigation is deploying a corrected version and migrating. Users retain full access to funds and tokens regardless.

This trade-off is acknowledged and accepted.

## Emergency Procedures

There are no emergency admin procedures. Qurve is designed to be immutable and trustless.

| Scenario | Response |
|---|---|
| Bug in one contract | Deploy fixed version, migrate new launches |
| Exploit in progress | Cannot pause. Document, warn users, deploy fix |
| RPC down | Users switch RPC. Contracts unaffected |
| Frontend compromised | Users interact via explorer |
| Backend down | Contracts unaffected. A2A calls fail until restored |
