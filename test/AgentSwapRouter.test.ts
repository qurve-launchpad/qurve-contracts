// test/AgentSwapRouter.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployFullSuite } from "./helpers/fixtures";

describe("AgentSwapRouter", () => {
  const deployFixture = deployFullSuite;

  describe("Configuration", () => {
    it("stores correct swap router", async () => {
      const { swapRouter, owner } = await loadFixture(deployFixture);
      expect(await swapRouter.swapRouter()).to.equal(owner.address);
    });

    it("stores correct quote asset (weth)", async () => {
      const { swapRouter, weth } = await loadFixture(deployFixture);
      expect(await swapRouter.quoteAsset()).to.equal(await weth.getAddress());
    });

    it("has PLATFORM_FEE_BPS = 50", async () => {
      const { swapRouter } = await loadFixture(deployFixture);
      expect(await swapRouter.PLATFORM_FEE_BPS()).to.equal(50n);
    });

    it("has FLEX_FEE_BPS = 50", async () => {
      const { swapRouter } = await loadFixture(deployFixture);
      expect(await swapRouter.FLEX_FEE_BPS()).to.equal(50n);
    });

    it("total fee equals 1%", async () => {
      const { swapRouter } = await loadFixture(deployFixture);
      const p = await swapRouter.PLATFORM_FEE_BPS();
      const f = await swapRouter.FLEX_FEE_BPS();
      expect(p + f).to.equal(100n);
    });

    it("stores pool fee tier", async () => {
      const { swapRouter } = await loadFixture(deployFixture);
      expect(await swapRouter.POOL_FEE()).to.equal(3000n);
    });

    it("stores requiresWrap = false", async () => {
      const { swapRouter } = await loadFixture(deployFixture);
      expect(await swapRouter.requiresWrap()).to.be.false;
    });

    it("stores nativeToQuoteDecimalOffset = 1", async () => {
      const { swapRouter } = await loadFixture(deployFixture);
      expect(await swapRouter.nativeToQuoteDecimalOffset()).to.equal(1n);
    });
  });
});
