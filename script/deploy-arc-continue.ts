// script/deploy-arc-continue.ts
import { runContinueDeploy } from "./_helpers";

runContinueDeploy({
  chainId: 5042002,
  label: "Arc Testnet",
  requiresWrap: false,
  nativeToQuoteDecimalOffset: 1_000_000_000_000n,
  envKey: "USDC_ERC20_INTERFACE",
})
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment gagal:\n", error);
    process.exit(1);
  });
