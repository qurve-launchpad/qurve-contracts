// hardhat.config.ts
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
import * as fs from "fs";
import * as path from "path";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY ?? "";
const accounts = PRIVATE_KEY ? [PRIVATE_KEY] : [];

function getRpcForNetwork(networkKey: string, fallback: string): string {
  const envFile = path.join(__dirname, `.env.${networkKey}`);
  if (fs.existsSync(envFile)) {
    try {
      const parsed = dotenv.parse(fs.readFileSync(envFile));
      if (parsed.RPC_URL) return parsed.RPC_URL;
    } catch {}
  }
  return fallback;
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      // ⚠️ WAJIB: OpenZeppelin v5 pakai MCOPY (opcode Cancun)
      evmVersion: "cancun",
      viaIR: true,   // ← opsional, untuk hindari "stack too deep"
    },
  },
  networks: {
    arcTestnet: {
      url: getRpcForNetwork("arcTestnet", "https://rpc.testnet.arc.io"),
      chainId: 5042002,
      accounts,
    },
    arc: {
      url: getRpcForNetwork("arc", "https://rpc.arc.io"),
      chainId: 5042,
      accounts,
    },
    base: {
      url: getRpcForNetwork("base", "https://mainnet.base.org"),
      chainId: 8453,
      accounts,
    },
    baseSepolia: {
      url: getRpcForNetwork("baseSepolia", "https://sepolia.base.org"),
      chainId: 84532,
      accounts,
    },
    robinhood: {
      url: getRpcForNetwork(
        "robinhood",
        "https://rpc.mainnet.chain.robinhood.com"
      ),
      chainId: 4663,
      accounts,
    },
    bot: {
      url: getRpcForNetwork("bot", "https://rpc.botchain.io"),
      chainId: 677,
      accounts,
    },
  },
  etherscan: {
    apiKey: {
      base: process.env.BASESCAN_API_KEY ?? "",
      baseSepolia: process.env.BASESCAN_API_KEY ?? "",
      arcTestnet: process.env.ARCSCAN_API_KEY ?? "",
      arc: process.env.ARCSCAN_API_KEY ?? "",
    },
  },
};

export default config;
