// test/ReputationBridge.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("ReputationBridge", () => {
  async function deployFixture() {
    const [owner, user1, user2, disputer] = await ethers.getSigners();

    const Bridge = await ethers.getContractFactory("ReputationBridge");
    const bridge = await Bridge.deploy(owner.address);

    const DISPUTER_ROLE = await bridge.DISPUTER_ROLE();
    const DEFAULT_ADMIN_ROLE = await bridge.DEFAULT_ADMIN_ROLE();

    await bridge.grantRole(DISPUTER_ROLE, disputer.address);

    return {
      bridge,
      owner,
      user1,
      user2,
      disputer,
      DISPUTER_ROLE,
      DEFAULT_ADMIN_ROLE,
    };
  }

  describe("Deployment", () => {
    it("grants deployer admin role", async () => {
      const { bridge, owner, DEFAULT_ADMIN_ROLE } = await loadFixture(
        deployFixture
      );
      expect(await bridge.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be
        .true;
    });

    it("has non-zero min rater interval", async () => {
      const { bridge } = await loadFixture(deployFixture);
      expect(await bridge.minRaterInterval()).to.be.gt(0n);
    });
  });

  describe("Feedback submission", () => {
    it("accepts valid feedback", async () => {
      const { bridge, user1 } = await loadFixture(deployFixture);
      const taskHash = ethers.keccak256(ethers.toUtf8Bytes("task-1"));

      await bridge
        .connect(user1)
        .submitFeedback(1n, 80, taskHash, "ipfs://comment");

      const [avgScore, count] = await bridge.getAverageScore(1n);
      expect(count).to.equal(1n);
      expect(avgScore).to.equal(80n);
    });

    it("reverts for score > 100", async () => {
      const { bridge, user1 } = await loadFixture(deployFixture);
      const taskHash = ethers.keccak256(ethers.toUtf8Bytes("task-1"));

      await expect(
        bridge.connect(user1).submitFeedback(1n, 101, taskHash, "")
      ).to.be.reverted;
    });

    it("prevents duplicate rating by taskHash", async () => {
      const { bridge, user1 } = await loadFixture(deployFixture);
      const taskHash = ethers.keccak256(ethers.toUtf8Bytes("task-1"));

      await bridge.connect(user1).submitFeedback(1n, 80, taskHash, "");

      await expect(
        bridge.connect(user1).submitFeedback(1n, 90, taskHash, "")
      ).to.be.reverted;
    });

    it("enforces min rater interval", async () => {
      const { bridge, user1 } = await loadFixture(deployFixture);
      const task1 = ethers.keccak256(ethers.toUtf8Bytes("task-1"));
      const task2 = ethers.keccak256(ethers.toUtf8Bytes("task-2"));

      await bridge.connect(user1).submitFeedback(1n, 80, task1, "");

      await expect(
        bridge.connect(user1).submitFeedback(1n, 90, task2, "")
      ).to.be.reverted;

      await time.increase(60 * 60 * 24); // 1 day

      await bridge.connect(user1).submitFeedback(1n, 90, task2, "");
    });

    it("emits FeedbackSubmitted", async () => {
      const { bridge, user1 } = await loadFixture(deployFixture);
      const taskHash = ethers.keccak256(ethers.toUtf8Bytes("task-1"));

      await expect(bridge.connect(user1).submitFeedback(1n, 80, taskHash, ""))
        .to.emit(bridge, "FeedbackSubmitted")
        .withArgs(1n, user1.address, 80, taskHash);
    });
  });

  describe("Admin", () => {
    it("only admin can set min rater interval", async () => {
      const { bridge, user1 } = await loadFixture(deployFixture);
      await expect(bridge.connect(user1).setMinRaterInterval(3600n)).to.be
        .reverted;
    });

    it("admin can set min rater interval", async () => {
      const { bridge, owner } = await loadFixture(deployFixture);
      await bridge.connect(owner).setMinRaterInterval(7200n);
      expect(await bridge.minRaterInterval()).to.equal(7200n);
    });
  });
});
