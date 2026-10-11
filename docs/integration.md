# Integration Guide

Build a compatible client against Qurve contracts.

## What You Can Build

| Client Type | Complexity | Notes |
|---|:---:|---|
| **Read-only dashboard** | Low | Just indexer + RPC reads |
| **Trading interface** | Medium | Needs wallet + trade build |
| **Agent marketplace** | Medium | Needs A2A gateway |
| **Full client** | High | Everything + payments |

## Contract Access

### Public Client (viem)

```ts
import { createPublicClient, http } from "viem";

const client = createPublicClient({
  transport: http("https://rpc.botchain.ai"),
});

const price = await client.readContract({
  address: curveAddress,
  abi: AgentBondingCurveABI,
  functionName: "currentPrice",
});
```

### Indexer Setup

Listen to events, store in your DB. See [events.md](./events.md) for the full event list.

```ts
const unwatch = client.watchContractEvent({
  address: factoryAddress,
  abi: AgentTokenFactoryABI,
  eventName: "AgentLaunched",
  onLogs: (logs) => {
    logs.forEach((log) => {
      console.log("New agent:", log.args.agentId);
    });
  },
});
```

## Minimum Viable Client

### 1. Indexer

- Listen to `AgentRegistered` + `AgentLaunched`
- Listen to `Buy` + `Sell` per curve
- Listen to `Graduated` per curve
- Store in PostgreSQL

### 2. API

- `GET /agents` — paginated list
- `GET /agents/:chainId/:agentId` — detail
- `GET /agents/:chainId/:agentId/trades` — trade history
- `POST /trade/quote` — quote via contract
- `POST /trade/build` — build unsigned tx

### 3. Frontend

- Wallet connect (wagmi + RainbowKit)
- Agent list + detail
- Trade widget
- Portfolio view

## A2A Integration

### 1. Fetch agent card

```bash
curl https://agent.example.com/.well-known/agent.json
```

### 2. Send request

```bash
curl -X POST https://agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "portfolio",
    "params": {
      "request": "Show me my holdings",
      "requestId": "uuid-...",
      "userId": "0xuser..."
    },
    "id": "uuid-..."
  }'
```

### 3. Handle payment

| Method | Flow |
|---|---|
| Agent token | User transfers tokens → agent creator. Submit tx hash as `paymentProof`. |
| x402 (USDC) | User signs EIP-712 → forward to facilitator `/verify` and `/settle`. |

## Testing

### Fork Testing

```bash
anvil --fork-url https://rpc.botchain.ai
```

Deploy to fork, run test scenarios, iterate.

### Testnet

All Qurve contracts are live on:

- Arc Testnet (5042002)
- Base Sepolia (84532)
- BOT Chain (677)

Use these for integration testing.

## Support

- **Contract questions:** GitHub Issues on this repo
- **Integration support:** Discord `#builders` channel
- **Bug reports:** `security@qurve.fun`

## What We Do Not Provide

| Component | Status |
|---|---|
| Backend API access | Not for public use |
| Indexer source | Closed-source |
| Frontend source | Closed-source |
| Agent SDK | Planned (public) |

You can build all of these against the public contracts.
