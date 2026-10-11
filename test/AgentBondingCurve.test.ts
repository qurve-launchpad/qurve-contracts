// test/AgentBondingCurve.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  loadFixture,
  time,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {
  deployFullSuite,
  launchDefaultAgent,
  FEE_BPS,
  BPS_DENOM,
} from "./helpers/fixtures";

describe("AgentBondingCurve", () => {
  async function fixture() {
    const suite = await deployFullSuite();
    const { curve, token } = await launchDefaultAgent(
      suite.factory,
      suite.creator
    );
    const curveContract = await ethers.getContractAt("AgentBondingCurve", curve);
    const tokenContract = await ethers.getContractAt("AgentToken", token);
    return { ...suite, curve: curveContract, token: tokenContract };
  }

  describe("Initial state", () => {
    it("has non-zero virtual reserves", async () => {
      const { curve } = await loadFixture(fixture);
      expect(await curve.virtualTokenReserve()).to.be.gt(0n);
      expect(await curve.virtualEthReserve()).to.be.gt(0n);
    });

    it("starts with zero sold", async () => {
      const { curve } = await loadFixture(fixture);
      expect(await curve.tokensSold()).to.equal(0n);
    });

    it("not graduated initially", async () => {
      const { curve } = await loadFixture(fixture);
      expect(await curve.graduated()).to.be.false;
    });
  });

  describe("Buy", () => {
    it("returns tokens for ETH", async () => {
      const { curve, buyer } = await loadFixture(fixture);
      const ethIn = ethers.parseEther("0.1");

      const tokensOut = await curve
        .connect(buyer)
        .buy.staticCall(ethIn, 0n);
      expect(tokensOut).to.be.gt(0n);
    });

    it("increases price after buy", async () => {
      const { curve, buyer } = await loadFixture(fixture);
      const priceBefore = await curve.currentPrice();

      await curve
        .connect(buyer)
        .buy(ethers.parseEther("0.1"), 0n, {
          value: ethers.parseEther("0.1"),
        });

      const priceAfter = await curve.currentPrice();
      expect(priceAfter).to.be.gt(priceBefore);
    });

    it("reverts if slippage exceeded", async () => {
      const { curve, buyer } = await loadFixture(fixture);
      const ethIn = ethers.parseEther("0.1");
      const minTokensOut = ethers.parseUnits("1000000000", 18);

      await expect(
        curve.connect(buyer).buy(ethIn, minTokensOut, { value: ethIn })
      ).to.be.reverted;
    });

    it("emits Buy event", async () => {
      const { curve, buyer } = await loadFixture(fixture);
      const ethIn = ethers.parseEther("0.1");

      await expect(
        curve.connect(buyer).buy(ethIn, 0n, { value: ethIn })
      ).to.emit(curve, "Buy");
    });
  });

  describe("Sell", () => {
    it("returns ETH for tokens after buy", async () => {
      const { curve, token, buyer } = await loadFixture(fixture);
      const ethIn = ethers.parseEther("0.1");

      await curve.connect(buyer).buy(ethIn, 0n, { value: ethIn });
      const balance = await token.balanceOf(buyer.address);

      const ethOut = await curve
        .connect(buyer)
        .sell.staticCall(balance, 0n);
      expect(ethOut).to.be.gt(0n);
    });

    it("emits Sell event", async () => {
      const { curve, token, buyer } = await loadFixture(fixture);
      const ethIn = ethers.parseEther("0.1");

      await curve.connect(buyer).buy(ethIn, 0n, { value: ethIn });
      const balance = await token.balanceOf(buyer.address);

      await expect(curve.connect(buyer).sell(balance, 0n)).to.emit(
        curve,
        "Sell"
      );
    });
  });

  describe("Anti-snipe", () => {
    it("charges surtax immediately after launch", async () => {
      const { curve, buyer } = await loadFixture(fixture);
      const ethIn = ethers.parseEther("0.1");

      const tokensOutEarly = await curve
        .connect(buyer)
        .buy.staticCall(ethIn, 0n);

      await time.increase(61);

      const tokensOutLate = await curve
        .connect(buyer)
        .buy.staticCall(ethIn, 0n);

      expect(tokensOutLate).to.be.gt(tokensOutEarly);
    });
  });

  describe("Quote functions", () => {
    it("quoteBuy returns reasonable value", async () => {
      const { curve, buyer } = await loadFixture(fixture);
      const ethIn = ethers.parseEther("0.1");
      const fee = (ethIn * FEE_BPS) / BPS_DENOM;
      const amountAfterFee = ethIn - fee;

      const quote = await curve.quoteBuy(amountAfterFee);
      const actual = await curve
        .connect(buyer)
        .buy.staticCall(ethIn, 0n);

      expect(actual).to.be.closeTo(quote, quote / 100n);
    });

    it("quoteSell returns reasonable value", async () => {
      const { curve, token, buyer } = await loadFixture(fixture);
      const ethIn = ethers.parseEther("0.1");

      await curve.connect(buyer).buy(ethIn, 0n, { value: ethIn });
      const balance = await token.balanceOf(buyer.address);

      const quote = await curve.quoteSell(balance);
      expect(quote).to.be.gt(0n);
    });
  });
});
