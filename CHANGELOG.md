
---

## 📄 File 6 — `CHANGELOG.md`

```markdown
# Changelog

All notable changes to Qurve contracts are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- Lithosphere chain deployment scripts (testnet + mainnet)
- Test suite for all core contracts

### Changed
- Documented `FIX #2` (Math.mulDiv overflow) in code comments

---

## [1.0.0] — 2026-10-13

Initial public release of Qurve contracts.

### Added

**Core contracts:**
- `AgentLaunchRegistry` — soulbound agent identity (ERC-721)
- `AgentTokenFactory` — one-transaction agent launch
- `AgentToken` — ERC-20 with curve-restricted mint
- `AgentBondingCurve` — constant-product price discovery
- `GraduationManager` — Uniswap V3 liquidity migration
- `AgentSwapRouter` — post-graduation swap routing
- `HolderRewardsDistributor` — staking distributor for HOLDERS mode
- `ReputationBridge` — signed on-chain feedback
- `ValidationRegistry` — third-party task attestation

**Chain deployments:**
- BOT Chain mainnet (677)
- Arc Testnet (5042002)
- Base Sepolia (84532)

**Features:**
- Immutable reward mode (CREATOR / HOLDERS)
- LP NFT burned to `0xdead` at graduation
- Anti-snipe surtax (0–4% linear decay over 60s)
- Grace-period staking (2-day window)
- ERC-8004 optional dual-registration
- Multi-chain native deployment

### Fixed

- `FIX #2` — `Math.mulDiv` based overflow in initial LP price computation
  that would have reverted ~half of all graduations on chains where the
  agent token address sorts higher than the wrapped native token.

### Security

- Not yet audited. Pre-audit infrastructure. See [docs/security.md](./docs/security.md).
- No `pause()` function by design.
- Single deployer EOA per chain — multisig migration planned.

---

## Format Legend

| Symbol | Meaning |
|:---:|---|
| 🟢 | Added |
| 🟡 | Changed |
| 🔴 | Removed / Fixed |
| 🔵 | Security |
| ⚠️ | Breaking |
