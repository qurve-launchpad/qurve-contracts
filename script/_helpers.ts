// script/_helpers.ts
import { ethers, network } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from "dotenv";

// ═════════════════════════════════════════════════════════════════════════
// ENV LOADER — merge .env (global) + .env.<network> (chain-specific)
// ═════════════════════════════════════════════════════════════════════════

export function loadEnvForNetwork(networkName: string) {
  const rootDir = path.join(__dirname, "..");

  const globalEnv = path.join(rootDir, ".env");
  if (fs.existsSync(globalEnv)) {
    dotenv.config({ path: globalEnv });
    console.log(`   📄 Loaded: .env`);
  } else {
    console.warn(`   ⚠️  .env not found at ${globalEnv}`);
  }

  const chainEnv = path.join(rootDir, `.env.${networkName}`);
  if (fs.existsSync(chainEnv)) {
    dotenv.config({ path: chainEnv, override: true });
    console.log(`   📄 Loaded: .env.${networkName} (override)`);
  } else {
    console.warn(`   ⚠️  .env.${networkName} not found at ${chainEnv}`);
  }
}

// ═════════════════════════════════════════════════════════════════════════
// QUOTE CONFIG TYPE
// ═════════════════════════════════════════════════════════════════════════

export interface QuoteConfig {
  requiresWrap: boolean;
  nativeToQuoteDecimalOffset: bigint;
  envKey: "USDC_ERC20_INTERFACE" | "WETH_ADDRESS";
  label: string;
  chainId: number;
}

// ═════════════════════════════════════════════════════════════════════════
// HELPERS
// ═════════════════════════════════════════════════════════════════════════

export async function waitForCode(
  label: string,
  address: string,
  attempts = 6,
  delayMs = 2000
): Promise<void> {
  for (let i = 1; i <= attempts; i++) {
    const code = await ethers.provider.getCode(address);
    if (code && code !== "0x") return;
    if (i === attempts) {
      throw new Error(
        `${label} (${address}) — bytecode still missing after ${attempts} attempts. ` +
          `Check the explorer; if present, switch RPC (multi-node read lag).`
      );
    }
    console.log(
      `   ⏳ ${label} not indexed yet, retry ${i}/${attempts - 1} in ${delayMs / 1000}s...`
    );
    await new Promise((r) => setTimeout(r, delayMs));
  }
}

export async function verifyWithRetry(
  label: string,
  check: () => Promise<boolean>,
  attempts = 5,
  delayMs = 2000
): Promise<void> {
  for (let i = 1; i <= attempts; i++) {
    if (await check()) return;
    if (i === attempts) {
      throw new Error(`${label} — still failing after ${attempts} attempts.`);
    }
    console.log(`   ⏳ ${label} not visible yet, retry ${i}/${attempts - 1}...`);
    await new Promise((r) => setTimeout(r, delayMs));
  }
}

export function requireEnvAddress(envKey: string): string {
  const raw = process.env[envKey];
  if (!raw) {
    throw new Error(`Missing env: ${envKey}`);
  }
  const trimmed = raw.trim().replace(/^["']|["']$/g, "");
  if (!ethers.isAddress(trimmed)) {
    throw new Error(
      `${envKey} is not a valid address: "${raw}" (after cleaning: "${trimmed}").`
    );
  }
  return trimmed;
}

/// @notice Read and validate INITIAL_LAUNCH_FEE env var.
///         Expected in wei of this chain's native token.
///         Examples:
///           - Base / Robinhood (0.0005 ETH) : 500000000000000
///           - BOT Chain (0.1 BOT)          : 100000000000000000
///           - Arc Testnet (1 USDC, 18 dec) : 1000000000000000000
export function requireEnvLaunchFee(): bigint {
  const raw = process.env.INITIAL_LAUNCH_FEE;
  if (!raw) {
    throw new Error(
      `Missing env: INITIAL_LAUNCH_FEE. Check .env.${network.name}.\n` +
        `   Examples:\n` +
        `     Base / Robinhood : 500000000000000    (0.0005 ETH)\n` +
        `     BOT Chain        : 100000000000000000 (0.1 BOT)\n` +
        `     Arc Testnet      : 1000000000000000000 (1 USDC, 18 dec)`
    );
  }
  const trimmed = raw.trim();
  if (!/^\d+$/.test(trimmed)) {
    throw new Error(
      `INITIAL_LAUNCH_FEE must be a decimal integer (wei): got "${raw}".`
    );
  }
  const value = BigInt(trimmed);
  if (value <= 0n) {
    throw new Error(`INITIAL_LAUNCH_FEE must be > 0.`);
  }
  return value;
}

// ═════════════════════════════════════════════════════════════════════════
// FULL DEPLOY — used by every deploy-<chain>.ts
// ═════════════════════════════════════════════════════════════════════════

export async function runFullDeploy(chainConfig: QuoteConfig) {
  console.log("\n🚀 Qurve — Full Deployment\n");
  console.log("Loading env...");
  loadEnvForNetwork(network.name);
  console.log("");

  const deployedSoFar: Record<string, string> = {};

  try {
    await deployAll(chainConfig, deployedSoFar);
  } catch (error) {
    if (Object.keys(deployedSoFar).length > 0) {
      console.log(
        "\n⚠️  Deploy failed partway through, BUT some contracts succeeded."
      );
      console.log(
        `   Save this block to .env.${network.name}, then resume with deploy-${network.name}-continue.ts:\n`
      );
      for (const [key, value] of Object.entries(deployedSoFar)) {
        console.log(`   ${key}=${value}`);
      }
      console.log("");
    }
    throw error;
  }
}

async function deployAll(
  chainConfig: QuoteConfig,
  deployedSoFar: Record<string, string>
) {
  const [deployer] = await ethers.getSigners();
  const networkInfo = await ethers.provider.getNetwork();
  const chainId = Number(networkInfo.chainId);

  if (chainId !== chainConfig.chainId) {
    throw new Error(
      `Chain ID mismatch: script expects ${chainConfig.chainId}, ` +
        `but RPC returned ${chainId}. Check .env.${network.name}.`
    );
  }

  const isArc = !chainConfig.requiresWrap;

  console.log(
    "Network:",
    network.name,
    `(${chainConfig.label}, chainId: ${chainId})`
  );
  console.log("Deployer:", deployer.address);
  console.log(
    "Balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    isArc ? "USDC (native, 18 decimals)\n" : "ETH\n"
  );

  // ── Env validation ──
  const uniswapV3Factory = process.env.UNISWAP_V3_FACTORY;
  const positionManager = process.env.UNISWAP_V3_POSITION_MANAGER;
  const swapRouter = process.env.UNISWAP_V3_SWAP_ROUTER;
  const quoteAsset = process.env[chainConfig.envKey];
  const initialLaunchFee = requireEnvLaunchFee();

  if (!uniswapV3Factory || !positionManager) {
    throw new Error(
      "Missing env: UNISWAP_V3_FACTORY, UNISWAP_V3_POSITION_MANAGER. " +
        `Check .env.${network.name}.`
    );
  }
  if (!swapRouter) {
    throw new Error(
      `Missing env: UNISWAP_V3_SWAP_ROUTER. ` +
        `Check .env.${network.name}. ` +
        `AgentSwapRouter needs a SwapRouter02-style address (different ` +
        `from the position manager).`
    );
  }
  if (!quoteAsset) {
    throw new Error(
      `Missing env: ${chainConfig.envKey}. Check .env.${network.name}.`
    );
  }

  const requiresWrap = chainConfig.requiresWrap;
  const nativeToQuoteDecimalOffset = chainConfig.nativeToQuoteDecimalOffset;

  const envRequiresWrap = process.env.GRADUATION_REQUIRES_WRAP;
  if (envRequiresWrap && envRequiresWrap !== String(requiresWrap)) {
    throw new Error(
      `Conflict: chain ${chainId} requires requiresWrap=${requiresWrap}, ` +
        `but env = ${envRequiresWrap}.`
    );
  }
  const envOffset = process.env.GRADUATION_NATIVE_TO_QUOTE_DECIMAL_OFFSET;
  if (envOffset && BigInt(envOffset) !== nativeToQuoteDecimalOffset) {
    throw new Error(
      `Conflict: chain ${chainId} requires offset=${nativeToQuoteDecimalOffset}, ` +
        `but env = ${envOffset}.`
    );
  }

  const officialIdentityRegistry =
    process.env.ERC8004_IDENTITY_REGISTRY || ethers.ZeroAddress;
  const officialReputationRegistry =
    process.env.ERC8004_REPUTATION_REGISTRY || ethers.ZeroAddress;

  const protocolTreasury =
    process.env.PROTOCOL_FEE_RECIPIENT ||
    process.env.PROTOCOL_TREASURY ||
    deployer.address;
  const verifierBackend =
    process.env.VERIFIER_ADDRESS ||
    process.env.VERIFIER_BACKEND ||
    deployer.address;
  const disputer =
    process.env.DISPUTER_ADDRESS || process.env.DISPUTER || deployer.address;
  const adminAddress = process.env.ADMIN_ADDRESS || deployer.address;
  const enableAntiSnipe = process.env.ENABLE_ANTI_SNIPE === "true";

  console.log("Quote Config:");
  console.log(
    "  Chain type           :",
    isArc ? "Arc (native-stablecoin)" : "WETH-style"
  );
  console.log("  Quote env key        :", chainConfig.envKey);
  console.log("  Quote asset          :", quoteAsset);
  console.log("  requiresWrap         :", requiresWrap);
  console.log("  decimalOffset        :", nativeToQuoteDecimalOffset.toString());
  console.log("");
  console.log("Configuration:");
  console.log("  Uniswap V3 Factory   :", uniswapV3Factory);
  console.log("  Position Manager     :", positionManager);
  console.log("  Swap Router          :", swapRouter);
  console.log("  Admin                :", adminAddress);
  console.log("  Protocol Treasury    :", protocolTreasury);
  console.log("  Verifier Backend     :", verifierBackend);
  console.log("  Disputer             :", disputer);
  console.log(
    "  Anti-snipe           :",
    enableAntiSnipe ? "ENABLED" : "disabled"
  );
  console.log(
    "  Initial launch fee   :",
    initialLaunchFee.toString(),
    `(${ethers.formatEther(initialLaunchFee)} native)`
  );
  console.log("");

  // ═══════════════════════════════════════════════════════════
  // 1. AgentLaunchRegistry
  // ═══════════════════════════════════════════════════════════
  console.log("1️⃣  Deploying AgentLaunchRegistry...");
  const Registry = await ethers.getContractFactory("AgentLaunchRegistry");
  const registry = await Registry.deploy(adminAddress, officialIdentityRegistry);
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress();
  await waitForCode("AgentLaunchRegistry", registryAddress);
  deployedSoFar.EXISTING_AGENT_LAUNCH_REGISTRY = registryAddress;
  console.log("   ✅ AgentLaunchRegistry:", registryAddress);

  // 2. AgentTokenFactory
  console.log("\n2️⃣  Deploying AgentTokenFactory...");
  const Factory = await ethers.getContractFactory("AgentTokenFactory");
  const factory = await Factory.deploy(
    registryAddress,
    quoteAsset,
    protocolTreasury,
    adminAddress,
    initialLaunchFee
  );
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  await waitForCode("AgentTokenFactory", factoryAddress);
  deployedSoFar.EXISTING_AGENT_TOKEN_FACTORY = factoryAddress;
  console.log("   ✅ AgentTokenFactory:", factoryAddress);

  // Verify on-chain fee matches expected
  const deployedFee = await factory.launchFee();
  if (deployedFee !== initialLaunchFee) {
    throw new Error(
      `Factory launch fee mismatch: expected ${initialLaunchFee}, ` +
        `got ${deployedFee}.`
    );
  }
  console.log(
    `   ✓ Launch fee verified: ${deployedFee.toString()} wei`
  );

  // 3. Grant FACTORY_ROLE
  console.log("\n3️⃣  Granting FACTORY_ROLE...");
  const factoryRole = await registry.FACTORY_ROLE();
  const tx1 = await registry.grantRole(factoryRole, factoryAddress);
  console.log("   tx:", tx1.hash);
  const receipt1 = await tx1.wait(2);
  if (!receipt1 || receipt1.status !== 1) {
    throw new Error(`FACTORY_ROLE grant reverted: ${tx1.hash}`);
  }
  await verifyWithRetry("FACTORY_ROLE grant", () =>
    registry.hasRole(factoryRole, factoryAddress)
  );
  console.log("   ✅ FACTORY_ROLE granted");

  // 4. ReputationBridge
  console.log("\n4️⃣  Deploying ReputationBridge...");
  const Reputation = await ethers.getContractFactory("ReputationBridge");
  const reputation = await Reputation.deploy(
    registryAddress,
    adminAddress,
    officialReputationRegistry
  );
  await reputation.waitForDeployment();
  const reputationAddress = await reputation.getAddress();
  await waitForCode("ReputationBridge", reputationAddress);
  deployedSoFar.EXISTING_REPUTATION_BRIDGE = reputationAddress;
  console.log("   ✅ ReputationBridge:", reputationAddress);

  // 5. Grant DISPUTER_ROLE
  console.log("\n5️⃣  Granting DISPUTER_ROLE...");
  const disputerRole = await reputation.DISPUTER_ROLE();
  const tx2 = await reputation.grantRole(disputerRole, disputer);
  console.log("   tx:", tx2.hash);
  const receipt2 = await tx2.wait(2);
  if (!receipt2 || receipt2.status !== 1) {
    throw new Error(`DISPUTER_ROLE grant reverted: ${tx2.hash}`);
  }
  await verifyWithRetry("DISPUTER_ROLE grant", () =>
    reputation.hasRole(disputerRole, disputer)
  );
  console.log("   ✅ DISPUTER_ROLE granted");

  // 6. ValidationRegistry
  console.log("\n6️⃣  Deploying ValidationRegistry...");
  const Validation = await ethers.getContractFactory("ValidationRegistry");
  const validation = await Validation.deploy(registryAddress, adminAddress);
  await validation.waitForDeployment();
  const validationAddress = await validation.getAddress();
  await waitForCode("ValidationRegistry", validationAddress);
  deployedSoFar.EXISTING_VALIDATION_REGISTRY = validationAddress;
  console.log("   ✅ ValidationRegistry:", validationAddress);

  // 7. GraduationManager
  console.log("\n7️⃣  Deploying GraduationManager...");
  const Graduation = await ethers.getContractFactory("GraduationManager");
  const graduation = await Graduation.deploy(
    uniswapV3Factory,
    positionManager,
    quoteAsset,
    factoryAddress,
    adminAddress,
    requiresWrap,
    nativeToQuoteDecimalOffset
  );
  await graduation.waitForDeployment();
  const graduationAddress = await graduation.getAddress();
  await waitForCode("GraduationManager", graduationAddress);
  deployedSoFar.EXISTING_GRADUATION_MANAGER = graduationAddress;
  console.log("   ✅ GraduationManager:", graduationAddress);

  // 8. Wire factory ↔ graduation
  console.log("\n8️⃣  Wiring factory ↔ graduation...");
  const tx3 = await factory.setGraduationManager(graduationAddress);
  console.log("   tx:", tx3.hash);
  const receipt3 = await tx3.wait(2);
  if (!receipt3 || receipt3.status !== 1) {
    throw new Error(`setGraduationManager reverted: ${tx3.hash}`);
  }
  await verifyWithRetry("setGraduationManager", async () => {
    const gm = await factory.graduationManager();
    return gm.toLowerCase() === graduationAddress.toLowerCase();
  });
  console.log("   ✅ GraduationManager set on factory");

  // ═══════════════════════════════════════════════════════════
  // 9. AgentSwapRouter
  // ═══════════════════════════════════════════════════════════
  console.log("\n9️⃣  Deploying AgentSwapRouter...");
  const Router = await ethers.getContractFactory("AgentSwapRouter");
  const router = await Router.deploy(
    swapRouter,
    quoteAsset,
    protocolTreasury,
    factoryAddress,
    graduationAddress
  );
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  await waitForCode("AgentSwapRouter", routerAddress);
  deployedSoFar.EXISTING_SWAP_ROUTER = routerAddress;
  console.log("   ✅ AgentSwapRouter:", routerAddress);

  // ═══════════════════════════════════════════════════════════
  // 10. Wire graduation ↔ router
  //
  //  Makes GraduationManager auto-authorize every newly-deployed
  //  HolderRewardsDistributor to receive notifyRewardAmount() from the
  //  router. Distributors that were already deployed before this call
  //  must be setNotifier()'d manually — but at full-deploy time there is
  //  no distributor yet, so this covers 100% of cases.
  // ═══════════════════════════════════════════════════════════
  console.log("\n🔟 Wiring graduation ↔ router...");
  const txRouter = await graduation.setSwapRouter(routerAddress);
  console.log("   tx:", txRouter.hash);
  const receiptRouter = await txRouter.wait(2);
  if (!receiptRouter || receiptRouter.status !== 1) {
    throw new Error(`setSwapRouter reverted: ${txRouter.hash}`);
  }
  await verifyWithRetry("setSwapRouter", async () => {
    const r = await graduation.swapRouter();
    return r.toLowerCase() === routerAddress.toLowerCase();
  });
  console.log("   ✅ AgentSwapRouter wired on GraduationManager");

  // 11. Grant VERIFIER_ROLE
  console.log("\n1️⃣1️⃣  Granting VERIFIER_ROLE...");
  const verifierRole = await registry.VERIFIER_ROLE();
  const tx4 = await registry.grantRole(verifierRole, verifierBackend);
  console.log("   tx:", tx4.hash);
  const receipt4 = await tx4.wait(2);
  if (!receipt4 || receipt4.status !== 1) {
    throw new Error(`VERIFIER_ROLE grant reverted: ${tx4.hash}`);
  }
  await verifyWithRetry("VERIFIER_ROLE grant", () =>
    registry.hasRole(verifierRole, verifierBackend)
  );
  console.log("   ✅ VERIFIER_ROLE granted");

  // 12. Anti-snipe
  if (enableAntiSnipe) {
    console.log("\n1️⃣2️⃣  Enabling anti-snipe...");
    const tx5 = await factory.setAntiSnipeEnabled(true);
    console.log("   tx:", tx5.hash);
    await tx5.wait(2);
    console.log("   ✅ Anti-snipe ENABLED");
  } else {
    console.log("\n1️⃣2️⃣  Anti-snipe: disabled");
  }

  // Save deployment JSON
  const deployment = {
    network: network.name,
    chainId,
    deployedAt: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      AgentLaunchRegistry: registryAddress,
      AgentTokenFactory: factoryAddress,
      ReputationBridge: reputationAddress,
      ValidationRegistry: validationAddress,
      GraduationManager: graduationAddress,
      AgentSwapRouter: routerAddress,
    },
    config: {
      quoteAsset,
      officialIdentityRegistry,
      officialReputationRegistry,
      uniswapV3Factory,
      positionManager,
      swapRouter,
      requiresWrap,
      nativeToQuoteDecimalOffset: nativeToQuoteDecimalOffset.toString(),
      adminAddress,
      protocolTreasury,
      verifierBackend,
      disputer,
      antiSnipeEnabled: enableAntiSnipe,
      initialLaunchFee: initialLaunchFee.toString(),
    },
  };

  const deploymentsDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  const filename = path.join(deploymentsDir, `${network.name}-${chainId}.json`);
  fs.writeFileSync(filename, JSON.stringify(deployment, null, 2));
  console.log(`\n💾 Deployment saved: ${filename}`);

  // ═══════════════════════════════════════════════════════════
  // Summary + .env block
  // ═══════════════════════════════════════════════════════════
  console.log("\n═══════════════════════════════════════════════");
  console.log(`       QURVE DEPLOYMENT — ${chainConfig.label}`);
  console.log("═══════════════════════════════════════════════");
  console.log("");
  console.log("Contracts:");
  console.log("  AgentLaunchRegistry :", registryAddress);
  console.log("  AgentTokenFactory   :", factoryAddress);
  console.log("  ReputationBridge    :", reputationAddress);
  console.log("  ValidationRegistry  :", validationAddress);
  console.log("  GraduationManager   :", graduationAddress);
  console.log("  AgentSwapRouter     :", routerAddress);
  console.log("");
  console.log("Roles:");
  console.log("  DEFAULT_ADMIN_ROLE  :", adminAddress);
  console.log("  FACTORY_ROLE        :", factoryAddress);
  console.log("  DISPUTER_ROLE       :", disputer);
  console.log("  VERIFIER_ROLE       :", verifierBackend);
  console.log("");
  console.log("Launch Fee:");
  console.log(
    "  Initial (wei)       :",
    initialLaunchFee.toString()
  );
  console.log(
    "  Initial (native)    :",
    ethers.formatEther(initialLaunchFee)
  );
  console.log("");
  console.log("═══════════════════════════════════════════════");
  console.log("\n✅ Deployment complete!\n");

  console.log("─────────────────────────────────────────────────");
  console.log(`📋 Copy-paste into .env.${network.name}`);
  console.log("─────────────────────────────────────────────────");
  console.log(`# ───────────── ${chainConfig.label} ─────────────`);
  console.log(`# ChainId: ${chainId}`);
  console.log(``);
  console.log(`REGISTRY_ADDRESS=${registryAddress}`);
  console.log(`FACTORY_ADDRESS=${factoryAddress}`);
  console.log(`REPUTATION_ADDRESS=${reputationAddress}`);
  console.log(`VALIDATION_ADDRESS=${validationAddress}`);
  console.log(`GRADUATION_ADDRESS=${graduationAddress}`);
  console.log(`SWAP_ROUTER_ADDRESS=${routerAddress}`);
  console.log(``);
  console.log(`EXISTING_AGENT_LAUNCH_REGISTRY=${registryAddress}`);
  console.log(`EXISTING_AGENT_TOKEN_FACTORY=${factoryAddress}`);
  console.log(`EXISTING_REPUTATION_BRIDGE=${reputationAddress}`);
  console.log(`EXISTING_VALIDATION_REGISTRY=${validationAddress}`);
  console.log(`EXISTING_GRADUATION_MANAGER=${graduationAddress}`);
  console.log(`EXISTING_SWAP_ROUTER=${routerAddress}`);
  console.log("─────────────────────────────────────────────────");
  console.log("");

  console.log("─────────────────────────────────────────────────");
  console.log(`📋 Frontend .env block`);
  console.log("─────────────────────────────────────────────────");
  console.log(`VITE_REGISTRY_ADDRESS=${registryAddress}`);
  console.log(`VITE_FACTORY_ADDRESS=${factoryAddress}`);
  console.log(`VITE_REPUTATION_ADDRESS=${reputationAddress}`);
  console.log(`VITE_VALIDATION_ADDRESS=${validationAddress}`);
  console.log(`VITE_GRADUATION_ADDRESS=${graduationAddress}`);
  console.log(`VITE_SWAP_ROUTER_ADDRESS=${routerAddress}`);
  console.log("─────────────────────────────────────────────────");
  console.log("");

  console.log("Verify AgentTokenFactory:");
  console.log(
    `   npx hardhat verify --network ${network.name} ${factoryAddress} ` +
      `"${registryAddress}" "${quoteAsset}" "${protocolTreasury}" ` +
      `"${adminAddress}" "${initialLaunchFee}"`
  );
  console.log("");

  console.log("Verify GraduationManager:");
  console.log(
    `   npx hardhat verify --network ${network.name} ${graduationAddress} ` +
      `"${uniswapV3Factory}" "${positionManager}" "${quoteAsset}" ` +
      `"${factoryAddress}" "${adminAddress}" ${requiresWrap} "${nativeToQuoteDecimalOffset}"`
  );
  console.log("");

  console.log("Verify AgentSwapRouter:");
  console.log(
    `   npx hardhat verify --network ${network.name} ${routerAddress} ` +
      `"${swapRouter}" "${quoteAsset}" "${protocolTreasury}" ` +
      `"${factoryAddress}" "${graduationAddress}"`
  );
  console.log("");
}

// ═════════════════════════════════════════════════════════════════════════
// CONTINUE DEPLOY — used by every deploy-<chain>-continue.ts
// ═════════════════════════════════════════════════════════════════════════

export async function runContinueDeploy(chainConfig: QuoteConfig) {
  console.log("\n🔧 Qurve — Resume Deployment\n");
  console.log("Loading env...");
  loadEnvForNetwork(network.name);
  console.log("");

  const [deployer] = await ethers.getSigners();
  const networkInfo = await ethers.provider.getNetwork();
  const chainId = Number(networkInfo.chainId);

  if (chainId !== chainConfig.chainId) {
    throw new Error(
      `Chain ID mismatch: script expects ${chainConfig.chainId}, ` +
        `but RPC returned ${chainId}.`
    );
  }

  const isArc = !chainConfig.requiresWrap;

  console.log(
    "Network:",
    network.name,
    `(${chainConfig.label}, chainId: ${chainId})`
  );
  console.log("Deployer:", deployer.address);
  console.log(
    "Balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    isArc ? "USDC (native, 18 decimals)\n" : "ETH\n"
  );

  // Existing addresses from env
  const registryAddress = requireEnvAddress("EXISTING_AGENT_LAUNCH_REGISTRY");
  const factoryAddress = requireEnvAddress("EXISTING_AGENT_TOKEN_FACTORY");
  const reputationAddress = requireEnvAddress("EXISTING_REPUTATION_BRIDGE");
  const validationAddress = requireEnvAddress("EXISTING_VALIDATION_REGISTRY");

  await waitForCode("AgentLaunchRegistry (existing)", registryAddress);
  await waitForCode("AgentTokenFactory (existing)", factoryAddress);
  await waitForCode("ReputationBridge (existing)", reputationAddress);
  await waitForCode("ValidationRegistry (existing)", validationAddress);
  console.log("✅ 4 existing contracts confirmed to have bytecode.\n");

  const registry = await ethers.getContractAt(
    "AgentLaunchRegistry",
    registryAddress
  );
  const factory = await ethers.getContractAt(
    "AgentTokenFactory",
    factoryAddress
  );

  const uniswapV3Factory = requireEnvAddress("UNISWAP_V3_FACTORY");
  const positionManager = requireEnvAddress("UNISWAP_V3_POSITION_MANAGER");
  const swapRouter = requireEnvAddress("UNISWAP_V3_SWAP_ROUTER");
  const quoteAsset = requireEnvAddress(chainConfig.envKey);

  const requiresWrap = chainConfig.requiresWrap;
  const nativeToQuoteDecimalOffset = chainConfig.nativeToQuoteDecimalOffset;
  const adminAddress = process.env.ADMIN_ADDRESS || deployer.address;
  const protocolTreasury =
    process.env.PROTOCOL_FEE_RECIPIENT ||
    process.env.PROTOCOL_TREASURY ||
    deployer.address;
  const verifierBackend =
    process.env.VERIFIER_ADDRESS ||
    process.env.VERIFIER_BACKEND ||
    deployer.address;

  console.log("GraduationManager configuration:");
  console.log("  Chain type         :", isArc ? "Arc" : "WETH-style");
  console.log("  Uniswap V3 Factory :", uniswapV3Factory);
  console.log("  Position Manager   :", positionManager);
  console.log("  Swap Router        :", swapRouter);
  console.log("  Quote asset        :", quoteAsset);
  console.log("  requiresWrap       :", requiresWrap);
  console.log("  decimalOffset      :", nativeToQuoteDecimalOffset.toString());
  console.log("");

  // Sanity: verify factory launch fee is already set (informational)
  const currentFee = await factory.launchFee();
  console.log(
    "  Factory launchFee  :",
    currentFee.toString(),
    `(${ethers.formatEther(currentFee)} native)`
  );
  console.log("");

  // 7. GraduationManager
  console.log("7️⃣  Deploying GraduationManager...");
  const Graduation = await ethers.getContractFactory("GraduationManager");
  const graduation = await Graduation.deploy(
    uniswapV3Factory,
    positionManager,
    quoteAsset,
    factoryAddress,
    adminAddress,
    requiresWrap,
    nativeToQuoteDecimalOffset
  );
  await graduation.waitForDeployment();
  const graduationAddress = await graduation.getAddress();
  await waitForCode("GraduationManager", graduationAddress);
  console.log("   ✅ GraduationManager:", graduationAddress);

  // 8. Wire factory ↔ graduation
  console.log("\n8️⃣  Wiring factory ↔ graduation...");
  const tx3 = await factory.setGraduationManager(graduationAddress);
  console.log("   tx:", tx3.hash);
  const receipt3 = await tx3.wait(2);
  if (!receipt3 || receipt3.status !== 1) {
    throw new Error(`setGraduationManager reverted: ${tx3.hash}`);
  }
  await verifyWithRetry("setGraduationManager", async () => {
    const gm = await factory.graduationManager();
    return gm.toLowerCase() === graduationAddress.toLowerCase();
  });
  console.log("   ✅ GraduationManager set on factory");

  // 9. AgentSwapRouter
  console.log("\n9️⃣  Deploying AgentSwapRouter...");
  const Router = await ethers.getContractFactory("AgentSwapRouter");
  const router = await Router.deploy(
    swapRouter,
    quoteAsset,
    protocolTreasury,
    factoryAddress,
    graduationAddress
  );
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  await waitForCode("AgentSwapRouter", routerAddress);
  console.log("   ✅ AgentSwapRouter:", routerAddress);

  // 10. Wire graduation ↔ router
  console.log("\n🔟 Wiring graduation ↔ router...");
  const txRouter = await graduation.setSwapRouter(routerAddress);
  console.log("   tx:", txRouter.hash);
  const receiptRouter = await txRouter.wait(2);
  if (!receiptRouter || receiptRouter.status !== 1) {
    throw new Error(`setSwapRouter reverted: ${txRouter.hash}`);
  }
  await verifyWithRetry("setSwapRouter", async () => {
    const r = await graduation.swapRouter();
    return r.toLowerCase() === routerAddress.toLowerCase();
  });
  console.log("   ✅ AgentSwapRouter wired on GraduationManager");

  // 11. VERIFIER_ROLE (skip if already granted)
  const verifierRole = await registry.VERIFIER_ROLE();
  const alreadyHasVerifier = await registry.hasRole(
    verifierRole,
    verifierBackend
  );
  if (alreadyHasVerifier) {
    console.log("\n1️⃣1️⃣  VERIFIER_ROLE already granted, skipping.");
  } else {
    console.log("\n1️⃣1️⃣  Granting VERIFIER_ROLE...");
    const tx4 = await registry.grantRole(verifierRole, verifierBackend);
    console.log("   tx:", tx4.hash);
    const receipt4 = await tx4.wait(2);
    if (!receipt4 || receipt4.status !== 1) {
      throw new Error(`VERIFIER_ROLE grant reverted: ${tx4.hash}`);
    }
    await verifyWithRetry("VERIFIER_ROLE grant", () =>
      registry.hasRole(verifierRole, verifierBackend)
    );
    console.log("   ✅ VERIFIER_ROLE granted");
  }

  // Update deployment JSON
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir))
    fs.mkdirSync(deploymentsDir, { recursive: true });
  const filename = path.join(deploymentsDir, `${network.name}-${chainId}.json`);

  let existing: any = {};
  if (fs.existsSync(filename)) {
    existing = JSON.parse(fs.readFileSync(filename, "utf-8"));
  }
  existing.network = network.name;
  existing.chainId = chainId;
  existing.deployer = deployer.address;
  existing.contracts = {
    ...(existing.contracts ?? {}),
    AgentLaunchRegistry: registryAddress,
    AgentTokenFactory: factoryAddress,
    ReputationBridge: reputationAddress,
    ValidationRegistry: validationAddress,
    GraduationManager: graduationAddress,
    AgentSwapRouter: routerAddress,
  };
  existing.config = {
    ...(existing.config ?? {}),
    quoteAsset,
    uniswapV3Factory,
    positionManager,
    swapRouter,
    requiresWrap,
    nativeToQuoteDecimalOffset: nativeToQuoteDecimalOffset.toString(),
    adminAddress,
    protocolTreasury,
    verifierBackend,
  };
  existing.completedAt = new Date().toISOString();
  fs.writeFileSync(filename, JSON.stringify(existing, null, 2));
  console.log(`\n💾 Deployment record updated: ${filename}`);

  console.log("\n✅ Deployment complete!\n");
  console.log("All contract addresses:");
  console.log("  AgentLaunchRegistry :", registryAddress);
  console.log("  AgentTokenFactory   :", factoryAddress);
  console.log("  ReputationBridge    :", reputationAddress);
  console.log("  ValidationRegistry  :", validationAddress);
  console.log("  GraduationManager   :", graduationAddress);
  console.log("  AgentSwapRouter     :", routerAddress);
  console.log("");

  console.log("─────────────────────────────────────────────────");
  console.log(`📋 Update .env.${network.name}`);
  console.log("─────────────────────────────────────────────────");
  console.log(`# ───────────── ${chainConfig.label} ─────────────`);
  console.log(`# ChainId: ${chainId}`);
  console.log(``);
  console.log(`REGISTRY_ADDRESS=${registryAddress}`);
  console.log(`FACTORY_ADDRESS=${factoryAddress}`);
  console.log(`REPUTATION_ADDRESS=${reputationAddress}`);
  console.log(`VALIDATION_ADDRESS=${validationAddress}`);
  console.log(`GRADUATION_ADDRESS=${graduationAddress}`);
  console.log(`SWAP_ROUTER_ADDRESS=${routerAddress}`);
  console.log(``);
  console.log(`EXISTING_AGENT_LAUNCH_REGISTRY=${registryAddress}`);
  console.log(`EXISTING_AGENT_TOKEN_FACTORY=${factoryAddress}`);
  console.log(`EXISTING_REPUTATION_BRIDGE=${reputationAddress}`);
  console.log(`EXISTING_VALIDATION_REGISTRY=${validationAddress}`);
  console.log(`EXISTING_GRADUATION_MANAGER=${graduationAddress}`);
  console.log(`EXISTING_SWAP_ROUTER=${routerAddress}`);
  console.log("─────────────────────────────────────────────────");
  console.log("");

  console.log("Verify AgentSwapRouter:");
  console.log(
    `   npx hardhat verify --network ${network.name} ${routerAddress} ` +
      `"${swapRouter}" "${quoteAsset}" "${protocolTreasury}" ` +
      `"${factoryAddress}" "${graduationAddress}"`
  );
  console.log("");
}
