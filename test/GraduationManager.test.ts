// test/GraduationManager.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployFullSuite } from "./helpers/fixtures";

describe("GraduationManager", () => {
  const deployFixture = deployFullSuite;

  describe("Deployment", () => {
    it("stores correct weth address", async () => {
      const { graduation, weth } = await loadFixture(deployFixture);
      expect(await graduation.weth()).to.equal(await weth.getAddress());
    });

    it("has non-zero default slippage", async () => {
      const { graduation } = await loadFixture(deployFixture);
      expect(await graduation.graduationSlippageBps()).to.be.gt(0);
    });

    it("starts with zero holder reward tokens", async () => {
      const { graduation } = await loadFixture(deployFixture);
      expect(await graduation.holderRewardTokensCount()).to.equal(0n);
    });

    it("MAX_SLIPPAGE_BPS is 1000", async () => {
      const { graduation } = await loadFixture(deployFixture);
      expect(await graduation.MAX_SLIPPAGE_BPS()).to.equal(1000n);
    });
  });

  describe("Admin", () => {
    it("only owner can set slippage", async () => {
      const { graduation, other } = await loadFixture(deployFixture);
      await expect(
        graduation.connect(other).setGraduationSlippageBps(500)
      ).to.be.reverted;
    });

    it("owner can set slippage within bounds", async () => {
      const { graduation, owner } = await loadFixture(deployFixture);
      await graduation.connect(owner).setGraduationSlippageBps(500);
      expect(await graduation.graduationSlippageBps()).to.equal(500);
    });

    it("reverts if slippage exceeds max", async () => {
      const { graduation, owner } = await loadFixture(deployFixture);
      await expect(graduation.connect(owner).setGraduationSlippageBps(10001))
        .to.be.reverted;
    });

    it("only owner can set swap router", async () => {
      const { graduation, other } = await loadFixture(deployFixture);
      await expect(
        graduation.connect(other).setSwapRouter(other.address)
      ).to.be.reverted;
    });

    it("owner can set swap router", async () => {
      const { graduation, owner, other } = await loadFixture(deployFixture);
      await graduation.connect(owner).setSwapRouter(other.address);
      expect(await graduation.swapRouter()).to.equal(other.address);
    });
  });

  describe("Holder reward tokens tracking", () => {
    it("returns empty list initially", async () => {
      const { graduation } = await loadFixture(deployFixture);
      const tokens = await graduation.getHolderRewardTokens(0n, 10n);
      expect(tokens.length).to.equal(0);
    });
  });
});
