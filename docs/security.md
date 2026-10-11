# Security Policy

## Status

> **Qurve contracts are pre-audit.** They have not undergone a third-party security audit. Use at your own risk.

See [docs/security.md](./docs/security.md) for the full threat model, known fixes, and design trade-offs.

## Supported Versions

| Version | Supported |
|---|:---:|
| `main` branch | ✅ |
| Tagged releases | ✅ |
| Older commits | ❌ |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

### How to Report

Use GitHub's private security advisory feature:

1. Go to the [**Security** tab](https://github.com/qurve-launchpad/qurve-contracts/security)
2. Click **Report a vulnerability**
3. Provide:
   - Detailed description of the vulnerability
   - Steps to reproduce (with code if possible)
   - Affected contracts / functions
   - Suggested fix (optional)
   - Your contact for follow-up

**Or email:** `security@qurve.fun`

### Response Timeline

| Stage | Target |
|---|---|
| Acknowledge receipt | ≤ 48 hours |
| Initial assessment | ≤ 7 days |
| Fix or mitigation plan | ≤ 30 days |
| Public disclosure | Coordinated with reporter |

### Scope

| In Scope | Out of Scope |
|---|---|
| Contracts in `contracts/` | Frontend UI |
| Deployed addresses in [docs/deployment.md](./docs/deployment.md) | Backend API |
| Interaction between Qurve contracts | Indexer |
| ERC-8004 sync logic | Third-party agent endpoints |
|  | Circle Gateway (x402) |
|  | Uniswap V3 core |

### Bug Bounty

**No bug bounty program is currently active.** This may change after the third-party audit completes. Security researchers who responsibly disclose will be credited in the changelog (unless anonymity is requested).

## Known Design Decisions

These are **intentional** and not vulnerabilities:

| Item | Rationale |
|---|---|
| No `pause()` function | Users always retain exit; prevents governance capture |
| No upgradeability | Immutability is a feature, not a limitation |
| Post-graduation fee is voluntary | Uniswap V3 pool is public; fee applies only via `AgentSwapRouter` |
| Validation Registry not connected to ERC-8004 official | Official registry withdrawn pending community rework |
| Single-deployer EOA for admin roles | Multisig migration planned before broader mainnet expansion |

## Verifying Contracts

Before interacting with any Qurve contract:

1. **Check address** in [docs/deployment.md](./docs/deployment.md)
2. **Verify source** on the block explorer
3. **Compare** with this repository's `contracts/` folder
4. **Confirm** bytecode hash matches

Do not trust any address not listed in this repository.
