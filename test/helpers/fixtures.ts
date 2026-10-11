// test/helpers/fixtures.ts
import { ethers } from "hardhat";

// ═══════════════════════════════════════════════════════════════
// SHARED TEST CONSTANTS
// ═══════════════════════════════════════════════════════════════

export const DEFAULT_VIRTUAL_ETH_RESERVE = ethers.parseEther("1.433");
export const DEFAULT_GRADUATION_THRESHOLD = ethers.parseEther("4.2");

export const TOTAL_SUPPLY = ethers.parseUnits("1000000000", 18);
export const TOKENS_FOR_SALE = ethers.parseUnits("800000000", 18);
export const TOKENS_FOR_LIQUIDITY = ethers.parseUnits("200000000", 18);
export const VIRTUAL_TOKEN_RESERVE = ethers.parseUnits("1073000000", 18);

export const REWARD_MODE_CREATOR = 0;
export const REWARD_MODE_HOLDERS = 1;

export const FEE_BPS = 200n;
export const PLATFORM_FEE_BPS = 100n;
export const FLEX_FEE_BPS = 100n;
export const BPS_DENOM = 10_000n;

export const ANTI_SNIPE_MAX_BPS = 400n;
export const ANTI_SNIPE_WINDOW = 60n;

export const LAUNCH_FEE = ethers.parseEther("0.0005");

// ═══════════════════════════════════════════════════════════════
// LAUNCH PARAMS
// ═══════════════════════════════════════════════════════════════

export interface LaunchParams {
  name: string;
  symbol: string;
  agentURI: string;
  endpoint: string;
  virtualEthReserve: bigint;
  devBuyMinTokensOut: bigint;
  rewardMode: number;
}

export function defaultLaunchParams(
  overrides: Partial<LaunchParams> = {}
): LaunchParams {
  return {
    name: "Test Agent",
    symbol: "TEST",
    agentURI: "ipfs://QmTestHash",
    endpoint: "https://agent.example.com",
    virtualEthReserve: DEFAULT_VIRTUAL_ETH_RESERVE,
    devBuyMinTokensOut: 0n,
    rewardMode: REWARD_MODE_CREATOR,
    ...overrides,
  };
}

// ═══════════════════════════════════════════════════════════════
// SHARED DEPLOY HELPER
// ═══════════════════════════════════════════════════════════════

/**
 * Deploy full Qurve suite for tests.
 * Returns all contracts + signers + addresses.
 */
export async function deployFullSuite() {
  const [owner, creator, buyer, seller, validator, other] =
    await ethers.getSigners();

  // Mocks
  const MockWETH = await ethers.getContractFactory("MockWETH");
  const weth = await MockWETH.deploy();

  // Registry
  const Registry = await ethers.getContractFactory("AgentLaunchRegistry");
  const registry = await Registry.deploy(owner.address);

  // GraduationManager
  const GraduationManager = await ethers.getContractFactory(
    "GraduationManager"
  );
  const graduation = await GraduationManager.deploy(
    await registry.getAddress(),
    await weth.getAddress(),
    owner.address, // uniswap factory (mock)
    owner.address, // position manager (mock)
    false, // requiresWrap
    1n // decimalOffset
  );

  // AgentSwapRouter
  const SwapRouter = await ethers.getContractFactory("AgentSwapRouter");
  const swapRouter = await SwapRouter.deploy(
    owner.address, // uniswap swap router (mock)
    await weth.getAddress(),
    owner.address, // protocolFeeRecipient
    owner.address, // agentFactory
    await graduation.getAddress(),
    false,
    1n,
    3000
  );

  // AgentTokenFactory
  const Factory = await ethers.getContractFactory("AgentTokenFactory");
  const factory = await Factory.deploy(
    await registry.getAddress(),
    await weth.getAddress(),
    owner.address, // protocolFeeRecipient
    await graduation.getAddress(),
    true, // antiSnipeEnabled
    false // requiresWrap
  );

  // Grant FACTORY_ROLE
  const FACTORY_ROLE = await registry.FACTORY_ROLE();
  await registry.grantRole(FACTORY_ROLE, await factory.getAddress());

  // Set swap router on graduation
  await graduation.connect(owner).setSwapRouter(await swapRouter.getAddress());

  return {
    // contracts
    weth,
    registry,
    graduation,
    swapRouter,
    factory,
    // signers
    owner,
    creator,
    buyer,
    seller,
    validator,
    other,
    // roles
    FACTORY_ROLE,
  };
}

/**
 * Launch one agent using default params.
 * Returns { agentId, token, curve }.
 */
export async function launchDefaultAgent(
  factory: any,
  creator: any,
  overrides: Partial<LaunchParams> = {}
): Promise<{ agentId: bigint; token: string; curve: string }> {
  const params = defaultLaunchParams(overrides);
  const tx = await factory.connect(creator).launchAgent(params, {
    value: LAUNCH_FEE,
  });
  const receipt = await tx.wait();

  // Parse AgentLaunched event
  const iface = factory.interface;
  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog(log);
      if (parsed?.name === "AgentLaunched") {
        return {
          agentId: parsed.args.agentId,
          token: parsed.args.token,
          curve: parsed.args.curve,
        };
      }
    } catch {
      // skip
    }
  }

  throw new Error("AgentLaunched event not found");
}
