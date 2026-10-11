// script/deploy-arc.ts
import { runFullDeploy } from "./_helpers";

runFullDeploy({
  chainId: 5042002,
  label: "Arc Testnet",
  requiresWrap: false,
  nativeToQuoteDecimalOffset: 1_000_000_000_000n, // 1e12
  envKey: "USDC_ERC20_INTERFACE",
})
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:\n", error);
    process.exit(1);
  });
