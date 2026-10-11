// test/HolderRewardsDistributor.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  loadFixture,
  time,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("HolderRewardsDistributor", () => {
  async function deployFixture() {
    const [owner, staker1, staker2, other] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockERC20");
    const stakingToken = await MockToken.deploy("Agent Token", "AGT", 18);

    // ── Constructor: (stakingToken, initialNotifier, initialOwner) ──
    const Distributor = await ethers.getContractFactory(
      "HolderRewardsDistributor"
    );
    const distributor = await Distributor.deploy(
      await stakingToken.getAddress(),
      owner.address, // initialNotifier
      owner.address  // initialOwner
    );

    await stakingToken.mint(staker1.address, ethers.parseEther("1000"));
    await stakingToken.mint(staker2.address, ethers.parseEther("1000"));

    return { distributor, stakingToken, owner, staker1, staker2, other };
  }

  describe("Deployment", () => {
    it("stores staking token", async () => {
      const { distributor, stakingToken } = await loadFixture(deployFixture);
      expect(await distributor.stakingToken()).to.equal(
        await stakingToken.getAddress()
      );
    });

    it("starts with zero total staked", async () => {
      const { distributor } = await loadFixture(deployFixture);
      expect(await distributor.totalStaked()).to.equal(0n);
    });

    it("has 2-day grace period", async () => {
      const { distributor } = await loadFixture(deployFixture);
      expect(await distributor.GRACE_PERIOD()).to.equal(2n * 24n * 3600n);
    });
  });

  describe("Staking", () => {
    it("requires approval", async () => {
      const { distributor, staker1 } = await loadFixture(deployFixture);
      const amount = ethers.parseEther("100");

      await expect(distributor.connect(staker1).stake(amount)).to.be.reverted;
    });

    it("accepts stake after approval", async () => {
      const { distributor, stakingToken, staker1 } = await loadFixture(
        deployFixture
      );
      const amount = ethers.parseEther("100");

      await stakingToken
        .connect(staker1)
        .approve(await distributor.getAddress(), amount);

      await distributor.connect(staker1).stake(amount);

      expect(await distributor.totalStaked()).to.equal(amount);
      expect(await distributor.stakedBalance(staker1.address)).to.equal(amount);
    });

    it("emits Staked event", async () => {
      const { distributor, stakingToken, staker1 } = await loadFixture(
        deployFixture
      );
      const amount = ethers.parseEther("100");

      await stakingToken
        .connect(staker1)
        .approve(await distributor.getAddress(), amount);

      await expect(distributor.connect(staker1).stake(amount))
        .to.emit(distributor, "Staked")
        .withArgs(staker1.address, amount);
    });

    it("reverts on zero amount", async () => {
      const { distributor, staker1 } = await loadFixture(deployFixture);
      await expect(distributor.connect(staker1).stake(0n)).to.be.reverted;
    });
  });

  describe("Unstaking", () => {
    it("respects cooldown", async () => {
      const { distributor, stakingToken, staker1 } = await loadFixture(
        deployFixture
      );
      const amount = ethers.parseEther("100");

      await stakingToken
        .connect(staker1)
        .approve(await distributor.getAddress(), amount);
      await distributor.connect(staker1).stake(amount);

      await expect(distributor.connect(staker1).unstake(amount)).to.be
        .reverted;
    });

    it("allows unstake after cooldown", async () => {
      const { distributor, stakingToken, staker1 } = await loadFixture(
        deployFixture
      );
      const amount = ethers.parseEther("100");

      await stakingToken
        .connect(staker1)
        .approve(await distributor.getAddress(), amount);
      await distributor.connect(staker1).stake(amount);

      await time.increase(25 * 60);

      await distributor.connect(staker1).unstake(amount);
      expect(await distributor.totalStaked()).to.equal(0n);
    });
  });

  describe("Finalize initial pool", () => {
    it("finalizes after grace period", async () => {
      const { distributor, owner } = await loadFixture(deployFixture);

      // Cannot finalize before grace period
      await expect(distributor.connect(owner).finalizeInitialPool()).to.be
        .reverted;

      // Advance past grace period
      await time.increase(2 * 24 * 3600 + 1);

      await distributor.connect(owner).finalizeInitialPool();
      expect(await distributor.initialPoolFinalized()).to.be.true;
    });
  });
});
