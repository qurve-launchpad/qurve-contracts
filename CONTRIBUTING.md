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
| Adding `pause()` or upgradeability | Contradicts Qurve's design philosophy |
| Tokenomics changes | Protocol economics are fixed |
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

## Project Structure

```
qurve-contracts/
├── contracts/
│   ├── AgentBondingCurve.sol
│   ├── AgentLaunchRegistry.sol
│   ├── AgentSwapRouter.sol
│   ├── AgentToken.sol
│   ├── AgentTokenFactory.sol
│   ├── GraduationManager.sol
│   ├── HolderRewardsDistributor.sol
│   ├── ReputationBridge.sol
│   ├── ValidationRegistry.sol
│   ├── DEPLOYMENT.md
│   └── interfaces/
├── script/
│   ├── _helpers.ts
│   ├── deploy-arc.ts
│   └── deploy-arc-continue.ts
├── test/
├── docs/
├── CHANGELOG.md
├── CONTRIBUTING.md
├── README.md
└── package.json
```

## Coding Standards

- **Solidity:** `^0.8.24`
- **Line length:** 100 characters max
- **NatSpec:** Required on all public/external functions
- **Errors:** Custom errors, not `require` strings
- **Access control:** OpenZeppelin `Ownable` or `AccessControl`
- **Reentrancy:** `ReentrancyGuard` on any state-changing external-call function

## Testing Requirements

All PRs must include tests covering:

1. **Happy path** — Normal operation
2. **Edge cases** — Zero, max, boundary values
3. **Access control** — Unauthorized callers revert
4. **Reentrancy** — If the function makes external calls

Run:

```bash
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat coverage
```

## Commit Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): short description

Fixes #123
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `security`

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b fix/short-description`)
3. Write clear commits
4. Add tests
5. Ensure `npx hardhat compile && npx hardhat test` passes
6. Update documentation if behavior changed
7. Submit PR with clear description

**Two maintainer approvals required** for changes to `contracts/` (except comments/docs).

## Security Disclosures

**Do not open a public issue for security vulnerabilities.**

Use GitHub's **Security** tab → **Report a vulnerability**.

Include:
- Description
- Steps to reproduce
- Suggested fix (if known)
- Contact for follow-up

We acknowledge within 48 hours. Coordinated disclosure timeline: assessment ≤ 7 days, fix/mitigation ≤ 30 days.

**No bug bounty is currently active.** This may change after audit.

## Code of Conduct

- Be respectful. Disagree on technical merit, not personality.
- Assume good faith.
- No spam, no low-effort PRs.
- Report conduct issues to `conduct@qurve.fun`.

## License

By contributing, you agree your contributions are licensed under the MIT License.
