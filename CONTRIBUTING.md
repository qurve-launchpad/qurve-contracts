# Contributing to Qurve Contracts

Thank you for considering a contribution. Qurve is pre-audit infrastructure — every improvement to correctness, gas efficiency, or documentation helps.

## What We Welcome

| Contribution Type | Priority |
|---|:---:|
| Security review | 🔴 Critical |
| Bug fixes | 🔴 Critical |
| Gas optimization | 🟡 High |
| Test coverage | 🟡 High |
| Documentation (NatSpec) | 🟢 Medium |
| Refactoring | 🟢 Medium |

## What We Do Not Accept

| Contribution | Reason |
|---|---|
| New features without prior discussion | Contracts are immutable once deployed |
| Breaking ABI changes | Would invalidate existing deployments |
| Add `pause()` or upgradeability | Contradicts Qurve's design philosophy |
| Token contracts or fee changes | Protocol economics are fixed |
| Cosmetic changes without function | Adds risk without value |

> If you have a novel idea, open a **Discussion** first. Do not submit a PR before alignment.

## Development Setup

```bash
git clone https://github.com/qurve-launchpad/qurve-contracts
cd qurve-contracts
npm install
cp .env.example .env
npx hardhat compile
npx hardhat test
```
