<div align="center">

![Qurve Cover](./assets/cover.svg)

# Qurve Contracts

**The trustless agent launchpad — smart contracts.**

`ERC-8004` · `Bonding Curve` · `Uniswap V3` · `A2A`

[Website](https://qurve.fun) · [Whitepaper](https://qurve.fun/whitepaper) · [Twitter](https://twitter.com/qurve) · [Discord](#)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Status: Pre-Audit](https://img.shields.io/badge/Status-Pre--Audit-orange.svg)](#security)

</div>

---

## About

> **This repository contains the smart contracts of Qurve.** The backend and frontend are closed-source and live in separate private repositories.

Qurve is a permissionless protocol for launching, pricing, and monetizing AI agents on-chain. This repo provides:

| Component | Purpose |
|---|---|
| **AgentLaunchRegistry** | Soulbound agent identity (ERC-721) |
| **AgentTokenFactory** | One-transaction agent launch |
| **AgentBondingCurve** | Constant-product price discovery |
| **GraduationManager** | Uniswap V3 liquidity migration |
| **AgentSwapRouter** | Post-graduation swap + fee |
| **HolderRewardsDistributor** | Staking for HOLDERS mode |
| **ReputationBridge** | Signed on-chain feedback |
| **ValidationRegistry** | Third-party task attestation |

> **What is closed-source:** indexer, backend API, frontend, agent SDK. Anyone can build their own against the same contracts.

---

## Table of Contents

- [Why Qurve](#why-qurve)
- [Core Design](#core-design)
- [Fee Schedule](#fee-schedule)
- [Admin Surface](#admin-surface)
- [Deployed Contracts](#deployed-contracts)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

---

## Why Qurve

### Compared to typical launchpads

| Capability | Qurve | Typical Launchpad |
|---|:---:|:---:|
| **Agent identity** | ✅ Soulbound ERC-721 | ❌ None |
| **Post-graduation economics** | ✅ Router + staking | ⚠️ Abandoned |
| **Fee destination** | ✅ Immutable at launch | ❌ Platform decides |
| **LP lock** | ✅ Burned to `0xdead` | ⚠️ Often a promise |
| **Anti-snipe protection** | ✅ 0–4% linear decay | ⚠️ Sometimes |
| **Admin surface** | ✅ Fully enumerated | ❌ Often opaque |
| **Multi-chain** | ✅ Native, no bridges | ⚠️ Single or bridged |
| **Machine-to-machine payment** | ✅ A2A-compatible | ❌ Web2 rails |

### What Qurve does NOT claim

> **Post-graduation swap fees are voluntary.** The 1% fee applies only to swaps routed through the Qurve `AgentSwapRouter`. Direct Uniswap swaps bypass it. This is documented, not hidden.

---

## Core Design

### Immutable reward mode

| Mode | Flex fee destination | Claim mechanism |
|---|---|---|
| **CREATOR** | Creator's claim pool | Manual, dashboard |
| **HOLDERS** | Staking distributor | Staking, post-grad |

> **Set in the curve's constructor.** Cannot be changed by creator, platform, or admin.

### Liquidity locked forever

The LP NFT is minted to `0xdead` at graduation. No function exists to move it.

> **This is not a promise — it is a contract-level constraint.**

### Anti-snipe surtax

t = 0s → +4.0% surtax (added to curve reserve, not as fee)
t = 30s → +2.0%
t = 60s → 0.0%


> **The earliest buys are the most expensive.** Cost falls on whoever buys first.

### Soulbound identity

| Layer | Type | Transferable |
|---|---|:---:|
| **Economic (token)** | ERC-20 | ✅ Liquid |
| **Identity (agent)** | ERC-721 | ❌ Soulbound |

> **This separation prevents an agent's reputation from being purchased outright.**

---

## Fee Schedule

| Phase | Platform | Flex | Anti-snipe | Total |
|---|:---:|:---:|:---:|:---:|
| **Curve trade, t < 60s** | 1.0% | 1.0% | 0–4% | 2.0–6.0% |
| **Curve trade, t ≥ 60s** | 1.0% | 1.0% | 0% | 2.0% |
| **Post-grad swap (via router)** | 0.5% | 0.5% | — | 1.0% |
| **Launch (flat anti-spam)** | ~$1 | — | — | — |
| **Graduation** | 0 | 0 | — | — |

> **No hidden fee. No admin override.**

---

## Admin Surface

Qurve minimizes admin surface, but does not eliminate it.

### What no admin can do

| Action | Enforced |
|---|:---:|
| Mint tokens after launch | ✅ Not possible |
| Withdraw curve reserves outside graduation | ✅ Not possible |
| Move or withdraw LP | ✅ Not possible |
| Withdraw holder rewards | ✅ Not possible |
| Change reward mode | ✅ Not possible |
| Pause, freeze, or blacklist | ✅ No `pause()` function exists |

### What admin can do

| Contract | Function | Effect |
|---|---|---|
| `AgentLaunchRegistry` | `setEndpointVerified` | Mark endpoint verified |
| `AgentTokenFactory` | `setAntiSnipeEnabled` | Toggle for future launches |
| `AgentTokenFactory` | `setGraduationManager` | Point to new GM |
| `GraduationManager` | `setGraduationSlippageBps` | Adjust LP mint slippage |
| `ReputationBridge` | `setMinRaterInterval` | Adjust feedback cooldown |

> **Full list:** [docs/admin-controls.md](./docs/admin-controls.md)

---

## Deployed Contracts

### BOT Chain — Mainnet (677)

| Contract | Address |
|---|---|
| **Registry** | `0xAB180c46651c5e7a2D74672A87fAEDF9253499eC` |
| **Factory** | `0xBB0a2712Da7129abBBF3FB09923b2d7B59b74ee6` |
| **Reputation** | `0x081853e6395Ee8903D0bEE64F24B21BE3D64b52` |
| **Validation** | `0x4Dc7B1C33b1f1697040E38De8708A57755c5fb10` |
| **Graduation** | `0x74845faD460Bf2951b712F43EF946c5B2c867570` |
| **Swap Router** | `0xE593b3eD7aC4e118686e68850b216cc287a5545C` |

### Arc Testnet (5042002)

| Contract | Address |
|---|---|
| **Registry** | `0x65CaB3E5180724063A7e189691649C895335600c` |
| **Factory** | `0x244367954cBe4EbaDC2B474047b4A62D4C82306c` |
| **Reputation** | `0x0EDaDcC2B0b1F305a049866C48e7f21874e8C99a` |
| **Validation** | `0xE73C230E5A203b3FC08cD35aa01D2E8166Be13e9` |
| **Swap Router** | `0xe4c8Cf5866a2e51E28e3F6f2bb22f55202a56211` |

### Base Sepolia (84532)

| Contract | Address |
|---|---|
| **Registry** | `0x6af48f03572D7f6D3d80fEa2d0FE82E28e3E32C1` |
| **Factory** | `0x8Ee73a8c5f8EE868D6FB7112DBBF63402Acbf473` |
| **Reputation** | `0x75caF6E6788F0DdfbA79020BEB9Fc716ad05e5ae` |
| **Validation** | `0xE7e473bfA6258e10Dd82B83F0EcD773e3bacd16c` |
| **Graduation** | `0xA85AbB23bAFC13340AF9bb8f44E31366E029f805` |
| **Swap Router** | `0x0Fd84b95616D7e1Ec43Ad567Fd9FB515588E0d33` |

> **Verify addresses** against the source repository before interacting. Contracts are deployed as-is and cannot be changed.

---

## Quick Start

### Install

```bash
git clone https://github.com/qurve/qurve-contracts
cd qurve-contracts
npm install ```

### Compile
```bash
npx hardhat compile```

 ### Test
```bash
npx hardhat test
```
