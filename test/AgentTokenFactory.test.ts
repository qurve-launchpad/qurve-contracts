// test/AgentTokenFactory.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {
  defaultLaunchParams,
  deployFullSuite,
  launchDefaultAgent,
  LAUNCH_FEE,
  REWARD_MODE_CREATOR,
  REWARD_MODE_HOLDERS,
  TOTAL_SUPPLY,
  VIRTUAL_TOKEN_RESERVE,
} from "./helpers/fixtures";

describe("AgentTokenFactory", () => {
  const deployFixture = deployFullSuite;

  describe("Launch", () => {
    it("deploys token + curve in one tx", async () => {
      const { factory, creator } = await loadFixture(deployFixture);
      const params = defaultLaunchParams();

      await expect(
        factory.connect(creator).launchAgent(params, { value: LAUNCH_FEE })
      ).to.emit(factory, "AgentLaunched");
    });

    it("mints full supply to curve", async () => {
      const { factory, creator, registry } = await loadFixture(deployFixture);

      const { curve } = await launchDefaultAgent(factory, creator);

      const agent = await registry.getAgent(1n);
      const token = await ethers.getContractAt("AgentToken", agent.token);
      expect(await token.totalSupply()).to.equal(TOTAL_SUPPLY);
      expect(await token.balanceOf(curve)).to.equal(VIRTUAL_TOKEN_RESERVE);
    });

    it("registers creator as agent owner", async () => {
      const { factory, creator, registry } = await loadFixture(deployFixture);

      await launchDefaultAgent(factory, creator);

      const agent = await registry.getAgent(1n);
      expect(agent.owner).to.equal(creator.address);
    });

    it("reverts if msg.value < launch fee", async () => {
      const { factory, creator } = await loadFixture(deployFixture);
      const params = defaultLaunchParams();

      await expect(
        factory.connect(creator).launchAgent(params, { value: 0n })
      ).to.be.reverted;
    });

    it("sets CREATOR reward mode", async () => {
      const { factory, creator } = await loadFixture(deployFixture);

      const { curve } = await launchDefaultAgent(factory, creator, {
        rewardMode: REWARD_MODE_CREATOR,
      });

      const curveContract = await ethers.getContractAt(
        "AgentBondingCurve",
        curve
      );
      expect(await curveContract.rewardMode()).to.equal(REWARD_MODE_CREATOR);
    });

    it("sets HOLDERS reward mode", async () => {
      const { factory, creator } = await loadFixture(deployFixture);

      const { curve } = await launchDefaultAgent(factory, creator, {
        rewardMode: REWARD_MODE_HOLDERS,
      });

      const curveContract = await ethers.getContractAt(
        "AgentBondingCurve",
        curve
      );
      expect(await curveContract.rewardMode()).to.equal(REWARD_MODE_HOLDERS);
    });

    it("increments totalLaunched", async () => {
      const { factory, creator } = await loadFixture(deployFixture);

      expect(await factory.totalLaunched()).to.equal(0n);
      await launchDefaultAgent(factory, creator);
      expect(await factory.totalLaunched()).to.equal(1n);
    });
  });

  describe("Admin", () => {
    it("only owner can set anti-snipe", async () => {
      const { factory, creator } = await loadFixture(deployFixture);

      await expect(factory.connect(creator).setAntiSnipeEnabled(false)).to.be
        .reverted;
    });

    it("owner can toggle anti-snipe", async () => {
      const { factory, owner } = await loadFixture(deployFixture);

      await factory.connect(owner).setAntiSnipeEnabled(false);
      expect(await factory.antiSnipeEnabled()).to.be.false;
    });
  });
});
