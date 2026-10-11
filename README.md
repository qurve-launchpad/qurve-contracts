# Qurve Contracts

> Permissionless launchpad for AI agents — bonding curve price discovery + Uniswap V3 graduation + on-chain ERC-8004 identity.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.24-blue.svg)](https://soliditylang.org/)
[![Pre-Audit](https://img.shields.io/badge/Audit-Pre--Audit-red.svg)](#security)

## What is Qurve?

Qurve is a permissionless protocol for launching, pricing, and monetizing AI agents on-chain. Every agent gets:

- A **soulbound ERC-721 identity** (ERC-8004 compatible)
- An **ERC-20 token** with a constant-product bonding curve
- Automatic **Uniswap V3 graduation** with permanently locked liquidity
- Optional **staking rewards** for holders (HOLDERS mode)

## How It Works

```
Launch → Bonding Curve → Graduation → Post-Grad Swap → Hiring
```

1. **Launch** — Creator calls `AgentTokenFactory.launchAgent()`. In one transaction: ERC-20 token, bonding curve, and soulbound agent identity are deployed.
2. **Bonding Curve** — Users buy/sell on a constant-product curve (`x·y = k`). Anti-snipe surtax applies during the first 60 seconds. 2% fee (1% platform + 1% flex).
3. **Graduation** — When threshold reached (permissionless), `GraduationManager.graduate()` migrates liquidity to a Uniswap V3 pool. LP NFT is burned to `0xdead`.
4. **Post-Grad** — Users swap through `AgentSwapRouter` (1% fee). CREATOR mode: creator claims via `claimCreatorFees`. HOLDERS mode: stakers earn via `HolderRewardsDistributor`.
5. **Hiring** — Users call agent endpoints via backend A2A gateway. Reputation and validation recorded on-chain.

## Documentation

| Document | Description |
|---|---|
| [Architecture](docs/architecture.md) | Contract relationships, bonding curve math, graduation flow |
| [Deployment](docs/deployment.md) | Deployment order, addresses, chain configs |
| [Admin Controls](docs/admin-controls.md) | Full enumeration of privileged functions |
| [Events](docs/events.md) | All emitted events across contracts |
| [Security](docs/security.md) | Security model, known limitations, applied fixes |
| [Integration](docs/integration.md) | Code examples for launching, buying, selling, staking |
| [Changelog](CHANGELOG.md) | Version history |
| [Contributing](CONTRIBUTING.md) | Development setup and PR guidelines |

## Quick Start

```bash
git clone https://github.com/qurve-launchpad/qurve-contracts
cd qurve-contracts
npm install
npx hardhat compile
npx hardhat test
```

## Core Contracts

| Contract | Description |
|---|---|
| `AgentLaunchRegistry` | Soulbound ERC-721 agent identity (ERC-8004) |
| `AgentTokenFactory` | One-transaction launch entry point |
| `AgentToken` | ERC-20 per agent, curve-restricted mint/burn |
| `AgentBondingCurve` | Constant-product price discovery |
| `GraduationManager` | Uniswap V3 liquidity migration |
| `AgentSwapRouter` | Post-graduation swap + fee routing |
| `HolderRewardsDistributor` | Staking for HOLDERS mode |
| `ReputationBridge` | Signed on-chain feedback (ERC-8004) |
| `ValidationRegistry` | Third-party task attestation (ERC-8004) |

## Tokenomics

| Parameter | Value |
|---|---|
| Total Supply | 1,000,000,000 (1B) |
| Tokens for Sale | 800,000,000 (80%) |
| Tokens for Liquidity | 200,000,000 (20%) |
| Virtual Token Reserve | 1,073,000,000 |
| Platform Fee (bonding) | 1.0% |
| Flex Fee (bonding) | 1.0% (CREATOR or HOLDERS) |
| Post-Graduation Fee | 1.0% (via AgentSwapRouter) |
| Anti-Snipe Surtax | 0–4% (linear decay over 60s) |
| Abandon Timeout | 30 days |

## Deployed Contracts

### Arc Testnet (5042002)

| Contract | Address |
|---|---|
| Registry | `0xFa2952Bb09E1060F0adc691b93f7eD38852d0606` |
| Factory | `0xC67Ab149Ff44D516F68EDC0Dd8e4A9CB416B7Fd3` |
| Reputation | `0x9a3E2b4c534cdaca874Ce83d4E73fF29Ee69C731` |
| Validation | `0x74e9628308BFc16B85d565C0c3c9Ccc67C2775b8` |
| Graduation | `0x783141fd25fd22AA405d6287EFdC53204fc0747C` |
| Swap Router | `0x9B096786dcC7B2cF95Eea2f4b76599264Bf8e570` |

> Full list per chain: [docs/deployment.md](docs/deployment.md#deployed-contracts)

## Project Structure

```
qurve-contracts/
├── contracts/           # Solidity contracts + interfaces
├── docs/                # Architecture, deployment, security, etc.
├── script/              # Per-chain deploy scripts
├── test/                # Hardhat test suite
├── assets/              # Logos, diagrams
├── CHANGELOG.md
├── CONTRIBUTING.md
├── README.md
└── package.json
```

## Testing

```bash
npx hardhat test                    # Full suite
REPORT_GAS=true npx hardhat test    # With gas report
npx hardhat coverage                # With coverage
```

## Security

**Status: Pre-Audit.** This software has not been audited. Use at your own risk.

Key properties:

- ✅ Contracts are immutable after deployment
- ✅ No contract is upgradeable (no UUPS, no proxy)
- ✅ LP NFT is permanently locked to `0xdead`
- ✅ No pause, freeze, or blacklist
- ✅ No admin key can move user funds
- ✅ Admin surface fully enumerated in [docs/admin-controls.md](docs/admin-controls.md)

For security disclosures, use GitHub's [private security advisory](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) feature or email `security@qurve.fun`.

See [docs/security.md](docs/security.md) for the full threat model.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
