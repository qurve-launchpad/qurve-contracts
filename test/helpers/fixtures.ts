// test/helpers/fixtures.ts
import { ethers } from "hardhat";

// ═══════════════════════════════════════════════════════════════
// SHARED TEST CONSTANTS (match contract constants)
// ═══════════════════════════════════════════════════════════════

export const TOTAL_SUPPLY = ethers.parseUnits("1000000000", 18);          // 1B
export const TOKENS_FOR_SALE = ethers.parseUnits("800000000", 18);        // 80%
export const TOKENS_FOR_LIQUIDITY = ethers.parseUnits("200000000", 18);   // 20%
export const VIRTUAL_TOKEN_RESERVE = ethers.parseUnits("1073000000", 18); // accounting only

export const DEFAULT_VIRTUAL_ETH_RESERVE = ethers.parseEther("1.433");

export const REWARD_MODE_CREATOR = 0;
export const REWARD_MODE_HOLDERS = 1;

export const FEE_BPS = 200n;
export const PLATFORM_FEE_BPS = 100n;
export const FLEX_FEE_BPS = 100n;
export const BPS_DENOM = 10_000n;

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
// FULL SUITE DEPLOY — matches actual contract constructors
// ═══════════════════════════════════════════════════════════════

/**
 * Deploy the full Qurve suite for tests.
 *
 * Constructor order matches contracts exactly:
 *   AgentLaunchRegistry(admin, officialIdentityRegistry)
 *   AgentTokenFactory(registry, weth, protocolFeeRecipient, initialOwner, initialLaunchFee)
 *   GraduationManager(uniswapFactory, positionManager, weth, agentFactory, initialOwner, requiresWrap, offset)
 *   AgentSwapRouter(swapRouter, quoteAsset, protocolFeeRecipient, agentFactory, graduationManager)
 */
export async function deployFullSuite() {
  const [owner, creator, buyer, seller, validator, other] =
    await ethers.getSigners();

  // ── Mock WETH ──
  const MockWETH = await ethers.getContractFactory("MockWETH");
  const weth = await MockWETH.deploy();

  // ── AgentLaunchRegistry(admin, officialIdentityRegistry) ──
  // ZeroAddress disables external ERC-8004 sync — safe for tests.
  const Registry = await ethers.getContractFactory("AgentLaunchRegistry");
  const registry = await Registry.deploy(owner.address, ethers.ZeroAddress);

  // ── AgentTokenFactory(registry, weth, protocolFeeRecipient, initialOwner, initialLaunchFee) ──
  const Factory = await ethers.getContractFactory("AgentTokenFactory");
  const factory = await Factory.deploy(
    await registry.getAddress(),
    await weth.getAddress(),
    owner.address, // protocolFeeRecipient
    owner.address, // initialOwner
    LAUNCH_FEE     // initialLaunchFee
  );

  // ── Grant FACTORY_ROLE to factory ──
  const FACTORY_ROLE = await registry.FACTORY_ROLE();
  await registry.grantRole(FACTORY_ROLE, await factory.getAddress());

  // ── GraduationManager(uniswapFactory, positionManager, weth, agentFactory, initialOwner, requiresWrap, offset) ──
  const GraduationManager = await ethers.getContractFactory(
    "GraduationManager"
  );
  const graduation = await GraduationManager.deploy(
    owner.address,               // uniswapFactory (mock)
    owner.address,               // positionManager (mock)
    await weth.getAddress(),     // weth / quote asset
    await factory.getAddress(),  // agentFactory
    owner.address,               // initialOwner
    false,                       // requiresWrap (Arc-style = false)
    1n                           // nativeToQuoteDecimalOffset
  );

  // ── Wire factory → graduation ──
  await factory
    .connect(owner)
    .setGraduationManager(await graduation.getAddress());

  // ── AgentSwapRouter(swapRouter, quoteAsset, protocolFeeRecipient, agentFactory, graduationManager) ──
  const SwapRouter = await ethers.getContractFactory("AgentSwapRouter");
  const swapRouter = await SwapRouter.deploy(
    owner.address,                 // uniswap swap router (mock)
    await weth.getAddress(),       // quote asset
    owner.address,                 // protocolFeeRecipient
    await factory.getAddress(),    // agentFactory
    await graduation.getAddress()  // graduationManager
  );

  // ── Wire graduation → swap router ──
  await graduation.connect(owner).setSwapRouter(await swapRouter.getAddress());

  return {
    // contracts
    weth,
    registry,
    factory,
    graduation,
    swapRouter,
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

// ═══════════════════════════════════════════════════════════════
// LAUNCH HELPER
// ═══════════════════════════════════════════════════════════════

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
      // skip logs from other contracts
    }
  }

  throw new Error("AgentLaunched event not found");
}
