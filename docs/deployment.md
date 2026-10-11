# Deployment Guide

Deploy Qurve on a new EVM-compatible chain.

## Prerequisites

| Requirement | Version |
|---|:---:|
| Node.js | 18+ |
| Hardhat | 2.20+ |
| Native gas token | Sufficient for ~10 deployments |
| RPC endpoint | Dedicated (not public rate-limited) |
| Uniswap V3 Factory | Deployed on target chain |
| Uniswap V3 Position Manager | Deployed on target chain |
| Uniswap V3 Swap Router (SwapRouter02-style) | Deployed on target chain |

## Step 1 — Gather Chain Info

| Info | Where to find |
|---|---|
| **Chain ID** | Chain docs / explorer |
| **RPC URL** | Chain docs |
| **Native token** | Chain docs (symbol + decimals) |
| **Quote asset** (WETH / WBOT / USDC) | Chain docs (wrapper or native-stablecoin address) |
| **Uniswap V3 factory** | Chain docs / DEX docs |
| **Uniswap V3 position manager** | Chain docs / DEX docs |
| **Uniswap V3 SwapRouter02** | Chain docs / DEX docs — **NOT** Universal Router |
| **Block explorer + API key** | Chain explorer |

## Step 2 — Configure Hardhat

Edit `hardhat.config.ts`:

```ts
networks: {
  myNewChain: {
    url: process.env.MY_NEW_CHAIN_RPC_URL ?? "",
    chainId: <chainId>,
    accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
  },
},
```

## Step 3 — Add Environment Variables

`.env` (global):

```bash
PRIVATE_KEY=0x...
```

`.env.myNewChain` (chain-specific):

```bash
RPC_URL=https://rpc.example.com
CHAIN_ID=<chainId>

# Launch fee (wei of native token)
INITIAL_LAUNCH_FEE=<wei>

# Quote asset — one of:
USDC_ERC20_INTERFACE=0x...   # if requiresWrap=false
WETH_ADDRESS=0x...           # if requiresWrap=true

# Uniswap V3
UNISWAP_V3_FACTORY=0x...
UNISWAP_V3_POSITION_MANAGER=0x...
UNISWAP_V3_SWAP_ROUTER=0x...

# ERC-8004 (optional — leave blank to disable)
ERC8004_IDENTITY_REGISTRY=0x...
ERC8004_REPUTATION_REGISTRY=0x...

# Roles (optional — default to deployer)
ADMIN_ADDRESS=0x...
PROTOCOL_FEE_RECIPIENT=0x...
VERIFIER_ADDRESS=0x...
DISPUTER_ADDRESS=0x...

# Anti-snipe (optional, default false)
ENABLE_ANTI_SNIPE=false

# Graduation config (must match script)
GRADUATION_REQUIRES_WRAP=true|false
GRADUATION_NATIVE_TO_QUOTE_DECIMAL_OFFSET=1|1000000000000
```

## Step 4 — Create Deploy Script

Copy `script/deploy-arc.ts` and adapt:

```ts
// script/deploy-mynewchain.ts
import { runFullDeploy } from "./_helpers";

runFullDeploy({
  chainId: <chainId>,
  label: "My New Chain",
  requiresWrap: true,
  nativeToQuoteDecimalOffset: 1n,
  envKey: "WETH_ADDRESS",
})
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:\n", error);
    process.exit(1);
  });
```

### Choosing `requiresWrap` / `nativeToQuoteDecimalOffset`

| Native | Quote | requiresWrap | offset |
|---|:---:|:---:|:---:|
| ETH, BOT, LITHO, MATIC | WETH/WBOT/WLITHO (18 dec) | `true` | `1n` |
| Native USDC (Arc-style, 18 dec) | USDC ERC-20 (6 dec) | `false` | `1_000_000_000_000n` (1e12) |

> On Arc, native & ERC-20 USDC share the same balance. There is no `deposit()`/`withdraw()`. Set `requiresWrap=false`.

## Step 5 — Compile

```bash
npm install
npx hardhat compile
```

Must be clean. Address any warnings before proceeding.

## Step 6 — Test Deploy (Local Fork)

```bash
anvil --fork-url <rpc-url> --port 8545
# In another terminal
npx hardhat run script/deploy-mynewchain.ts --network localhost
```

## Step 7 — Deploy to Testnet

```bash
npx hardhat run script/deploy-mynewchain.ts --network myNewChainTestnet
```

Deploy script writes `deployments/<network>-<chainId>.json` and prints an `.env` block.

If the deploy partially fails, copy the printed `EXISTING_*` block to `.env.<network>` and resume:

```bash
npx hardhat run script/deploy-mynewchain-continue.ts --network myNewChainTestnet
```

## Deployment Order (as implemented in `_helpers.ts`)

| # | Contract | Constructor Args |
|:-:|---|---|
| 1 | `AgentLaunchRegistry` | `(admin, officialIdentityRegistry)` |
| 2 | `AgentTokenFactory` | `(registry, quoteAsset, protocolFeeRecipient, admin, initialLaunchFee)` |
| 3 | — | `registry.grantRole(FACTORY_ROLE, factory)` |
| 4 | `ReputationBridge` | `(registry, admin, officialReputationRegistry)` |
| 5 | — | `reputation.grantRole(DISPUTER_ROLE, disputer)` |
| 6 | `ValidationRegistry` | `(registry, admin)` |
| 7 | `GraduationManager` | `(uniswapV3Factory, positionManager, quoteAsset, factory, admin, requiresWrap, nativeToQuoteDecimalOffset)` |
| 8 | — | `factory.setGraduationManager(graduation)` |
| 9 | `AgentSwapRouter` | `(swapRouter, quoteAsset, protocolFeeRecipient, factory, graduation)` |
| 10 | — | `graduation.setSwapRouter(router)` |
| 11 | — | `registry.grantRole(VERIFIER_ROLE, verifier)` |
| 12 | — | (optional) `factory.setAntiSnipeEnabled(true)` |

## Constructor Reference (Verbatim)

```solidity
// AgentLaunchRegistry
constructor(address admin, address officialIdentityRegistry_)

// AgentTokenFactory
constructor(
    address registry_,
    address weth_,
    address protocolFeeRecipient_,
    address initialOwner,
    uint256 initialLaunchFee_
)

// ReputationBridge
constructor(address registry_, address admin, address officialReputationRegistry_)

// ValidationRegistry
constructor(address registry_, address admin)

// GraduationManager
constructor(
    address uniswapFactory_,
    address positionManager_,
    address weth_,
    address agentFactory_,
    address initialOwner,
    bool requiresWrap_,
    uint256 nativeToQuoteDecimalOffset_
)

// AgentSwapRouter
// Note: requiresWrap & nativeToQuoteDecimalOffset are COPIED from
// GraduationManager — not passed as constructor args.
constructor(
    address _swapRouter,
    address _quoteAsset,
    address _protocolFeeRecipient,
    address _agentFactory,
    address _graduationManager
)
```

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

### Arc Testnet — Uniswap V3 (for reference)

| Contract | Address |
|---|---|
| Factory | `0x428175C4CBCC83E305Fa9827Ce896129D60B9319` |
| Position Manager | `0xBA100E0634eb6932245d63dF05450dc36eD5e787` |
| Swap Router | `0x726e7fEF9BF3Ac376895843a98a78Db1817c1DBc` |

### Arc Testnet — ERC-8004

| Registry | Address |
|---|---|
| Identity | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| Reputation | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |
| Validation | `0x8004Cb1BF31DAf7788923b405b754f57acEB4272` *(not connected)* |

> **Verify addresses** against the source repository before interacting.

## Post-Deploy Checklist

```
[ ] All contracts verified on explorer
[ ] deployments/<network>-<chainId>.json saved
[ ] Backend chainConfigs.json updated
[ ] Backend restarted
[ ] Indexer caught first AgentLaunched event
[ ] FE added chain to wagmi config
[ ] FE added contract addresses to constants
[ ] Smoke test: launch → buy → graduate → swap → stake
[ ] Whitepaper appendix updated
```

## Verify Commands

```bash
# AgentLaunchRegistry
npx hardhat verify --network <net> <registry> "<admin>" "<officialIdentityRegistry>"

# AgentTokenFactory
npx hardhat verify --network <net> <factory> \
  "<registry>" "<quoteAsset>" "<protocolTreasury>" "<admin>" "<initialLaunchFee>"

# ReputationBridge
npx hardhat verify --network <net> <reputation> \
  "<registry>" "<admin>" "<officialReputationRegistry>"

# ValidationRegistry
npx hardhat verify --network <net> <validation> "<registry>" "<admin>"

# GraduationManager
npx hardhat verify --network <net> <graduation> \
  "<uniswapV3Factory>" "<positionManager>" "<quoteAsset>" \
  "<factory>" "<admin>" <requiresWrap> "<offset>"

# AgentSwapRouter
npx hardhat verify --network <net> <router> \
  "<swapRouter>" "<quoteAsset>" "<protocolTreasury>" \
  "<factory>" "<graduation>"
```

## Troubleshooting

| Issue | Fix |
|---|---|
| `insufficient funds for gas` | Top up deployer wallet |
| `nonce too low` | Reset nonce via `cast nonce` |
| `Chain ID mismatch` | Check `.env.<network>` `CHAIN_ID` matches RPC |
| `Missing env: INITIAL_LAUNCH_FEE` | Add to `.env.<network>` |
| `Missing env: UNISWAP_V3_SWAP_ROUTER` | Add SwapRouter02 address |
| `FACTORY_ROLE grant reverted` | Check registry owner |
| Contract bytecode not visible | Wait + retry; script has built-in `waitForCode` |
