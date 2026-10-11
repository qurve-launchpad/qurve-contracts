# Deployment Guide

Deploy Qurve on a new EVM-compatible chain in ~30 minutes.

## Prerequisites

| Requirement | Version |
|---|:---:|
| Node.js | 18+ |
| Hardhat | 2.20+ |
| Native gas token | Sufficient for ~10 deployments |
| RPC endpoint | Dedicated (not public rate-limited) |

## Step 1 — Gather Chain Info

| Info | Where to find |
|---|---|
| **Chain ID** | Chain docs / explorer |
| **RPC URL** | Chain docs |
| **Native token** | Chain docs (symbol + decimals) |
| **Wrapped native token** | Chain docs (WLITHO, WETH, etc.) |
| **Uniswap V3 factory** | Chain docs / DEX docs |
| **Uniswap V3 position manager** | Chain docs / DEX docs |
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

etherscan: {
  apiKey: {
    myNewChain: process.env.MY_NEW_CHAIN_API_KEY ?? "",
  },
  customChains: [
    {
      network: "myNewChain",
      chainId: <chainId>,
      urls: {
        apiURL: "<explorer-api-url>",
        browserURL: "<explorer-url>",
      },
    },
  ],
},
```

## Step 3 — Add Environment Variables

Edit `.env`:

```bash
MY_NEW_CHAIN_RPC_URL=https://rpc.example.com
WRAPPED_NATIVE_ADDRESS=0x...
UNISWAP_V3_FACTORY=0x...
UNISWAP_V3_POSITION_MANAGER=0x...
```

## Step 4 — Create Deploy Script

Copy an existing script (e.g., `script/deploy-arc.ts`) and adapt:

```ts
// script/deploy-mynewchain.ts
import { runFullDeploy } from "./_helpers";

runFullDeploy({
  chainId: <chainId>,
  label: "My New Chain",
  requiresWrap: true,
  nativeToQuoteDecimalOffset: 1n,
  envKey: "WRAPPED_NATIVE_ADDRESS",
})
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:\n", error);
    process.exit(1);
  });
```

### Choosing `requiresWrap`

| Native Token | `requiresWrap` |
|---|:---:|
| ETH, BOT, LITHO, MATIC | ✅ `true` |
| USDC (native stablecoin) | ❌ `false` |

### Choosing `nativeToQuoteDecimalOffset`

| Native Decimals | Quote Decimals | Offset |
|:---:|:---:|:---:|
| 18 | 18 | `1n` |
| 18 | 6 | `1e12` |

## Step 5 — Compile

```bash
npx hardhat compile
```

Must be clean. Address any warnings before proceeding.

## Step 6 — Test Deploy (Local Fork)

```bash
# Fork mainnet (or testnet)
npx hardhat node --fork <rpc-url> --port 8545

# In another terminal
npx hardhat run script/deploy-mynewchain.ts --network localhost
```

## Step 7 — Deploy to Testnet

```bash
npx hardhat run script/deploy-mynewchain.ts --network myNewChainTestnet
```

Save output addresses.

## Step 8 — Verify Contracts

```bash
npx hardhat verify --network myNewChainTestnet <address> <constructor-args...>
```

Verify each deployed contract on the explorer.

## Step 9 — Update Backend Config

Add entry to `chainConfigs.json`:

```json
{
  "<chainId>": {
    "name": "My New Chain",
    "rpcUrls": ["https://rpc.example.com"],
    "registryAddress": "0x...",
    "factoryAddress": "0x...",
    "reputationAddress": "0x...",
    "validationAddress": "0x...",
    "graduationAddress": "0x...",
    "swapRouterAddress": "0x...",
    "identityRegistryAddress": "0x0000000000000000000000000000000000000000",
    "startBlock": <block-deploy>,
    "x402FacilitatorUrl": null,
    "x402UsdcAddress": null,
    "x402Network": null,
    "isMainnet": false,
    "enabled": true
  }
}
```

Restart backend. Indexer will backfill from `startBlock`.

## Step 10 — Smoke Test

**Test 1 — Launch agent:**

```bash
cast send <factory> "launchAgent((string,string,string,string,uint256,uint256,uint8))" \
  "(...)" --value <launchFee> --private-key <key> --rpc-url <rpc>
```

**Test 2 — Buy on curve:**

```bash
cast send <curve> "buy(uint256,uint256)" 1000000000000000 0 \
  --value 1000000000000000 --private-key <key> --rpc-url <rpc>
```

**Test 3 — Check backend:**

```bash
curl https://api.qurve.fun/api/agents?chainId=<chainId>
```

Should return the new agent.

## Troubleshooting

| Issue | Fix |
|---|---|
| `insufficient funds for gas` | Top up deployer wallet |
| `nonce too low` | Reset: `cast nonce <addr> --rpc-url <rpc>` |
| `contract deployment failed` | Check RPC not rate-limited |
| `verify failed` | Check explorer API key + constructor args |
| `indexer not catching events` | Check `startBlock` matches deploy block |

## Post-Deploy Checklist

```
[ ] All contracts verified on explorer
[ ] chainConfigs.json updated
[ ] Backend restarted
[ ] Indexer caught first events
[ ] FE added chain to wagmi config
[ ] FE added contracts to constants
[ ] Smoke test passed (launch → trade → graduate)
[ ] Whitepaper appendix updated
[ ] Announcement drafted
```

## Reference Deploys

| Chain | Deploy Script | Notes |
|---|---|---|
| Arc Testnet | `script/deploy-arc.ts` | USDC-native, no wrap |
| Base Sepolia | `script/deploy-base.ts` | WETH, wrap required |
| BOT Chain | `script/deploy-bot.ts` | WBOT, wrap required |
| Lithosphere | `script/deploy-litho.ts` | WLITHO, wrap required |
