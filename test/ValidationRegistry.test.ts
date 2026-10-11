// test/ValidationRegistry.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("ValidationRegistry", () => {
  async function deployFixture() {
    const [owner, validator, requester, user, factorySigner] =
      await ethers.getSigners();

    // ── 1. Deploy AgentLaunchRegistry (needed by ValidationRegistry) ──
    const AgentRegistry = await ethers.getContractFactory("AgentLaunchRegistry");
    const agentRegistry = await AgentRegistry.deploy(
      owner.address,
      ethers.ZeroAddress
    );

    // ── 2. Grant FACTORY_ROLE + register agent #1 ──
    const FACTORY_ROLE = await agentRegistry.FACTORY_ROLE();
    await agentRegistry.grantRole(FACTORY_ROLE, factorySigner.address);

    await agentRegistry
      .connect(factorySigner)
      .registerAgent(
        owner.address,
        owner.address,
        owner.address,
        "Test Agent",
        "ipfs://test",
        "https://example.com"
      );

    // ── 3. Deploy ValidationRegistry(registry, admin) ──
    const Validation = await ethers.getContractFactory("ValidationRegistry");
    const registry = await Validation.deploy(
      await agentRegistry.getAddress(),
      owner.address
    );

    const VALIDATOR_ADMIN_ROLE = await registry.VALIDATOR_ADMIN_ROLE();

    return {
      registry,
      agentRegistry,
      owner,
      validator,
      requester,
      user,
      factorySigner,
      VALIDATOR_ADMIN_ROLE,
    };
  }

  describe("Deployment", () => {
    it("starts with zero requests", async () => {
      const { registry } = await loadFixture(deployFixture);
      expect(await registry.requestCount()).to.equal(0n);
    });

    it("has pass threshold set", async () => {
      const { registry } = await loadFixture(deployFixture);
      expect(await registry.passThreshold()).to.be.gt(0);
    });
  });

  describe("Validator management", () => {
    it("admin can add validator", async () => {
      const { registry, owner, validator } = await loadFixture(deployFixture);
      await registry.connect(owner).addValidator(validator.address);
      expect(await registry.isApprovedValidator(validator.address)).to.be.true;
    });

    it("admin can remove validator", async () => {
      const { registry, owner, validator } = await loadFixture(deployFixture);
      await registry.connect(owner).addValidator(validator.address);
      await registry.connect(owner).removeValidator(validator.address);
      expect(await registry.isApprovedValidator(validator.address)).to.be.false;
    });

    it("non-admin cannot add validator", async () => {
      const { registry, user, validator } = await loadFixture(deployFixture);
      await expect(registry.connect(user).addValidator(validator.address)).to.be
        .reverted;
    });

    it("emits ValidatorAdded", async () => {
      const { registry, owner, validator } = await loadFixture(deployFixture);
      await expect(registry.connect(owner).addValidator(validator.address))
        .to.emit(registry, "ValidatorAdded")
        .withArgs(validator.address);
    });
  });

  describe("Validation flow", () => {
    it("allows requester to request validation", async () => {
      const { registry, owner, validator, requester } = await loadFixture(
        deployFixture
      );

      await registry.connect(owner).addValidator(validator.address);
      const taskHash = ethers.keccak256(ethers.toUtf8Bytes("task-1"));

      await registry
        .connect(requester)
        .requestValidation(1n, validator.address, taskHash, "");

      expect(await registry.requestCount()).to.equal(1n);
    });

    it("emits ValidationRequested", async () => {
      const { registry, owner, validator, requester } = await loadFixture(
        deployFixture
      );

      await registry.connect(owner).addValidator(validator.address);
      const taskHash = ethers.keccak256(ethers.toUtf8Bytes("task-1"));

      await expect(
        registry
          .connect(requester)
          .requestValidation(1n, validator.address, taskHash, "")
      ).to.emit(registry, "ValidationRequested");
    });

    it("approved validator can submit validation", async () => {
      const { registry, owner, validator, requester } = await loadFixture(
        deployFixture
      );

      await registry.connect(owner).addValidator(validator.address);
      const taskHash = ethers.keccak256(ethers.toUtf8Bytes("task-1"));

      await registry
        .connect(requester)
        .requestValidation(1n, validator.address, taskHash, "");

      await registry
        .connect(validator)
        .submitValidation(1n, 85, "ipfs://response");

      const request = await registry.getRequest(1n);
      expect(request.score).to.equal(85);
    });

    it("non-validator cannot submit validation", async () => {
      const { registry, owner, validator, requester, user } = await loadFixture(
        deployFixture
      );

      await registry.connect(owner).addValidator(validator.address);
      const taskHash = ethers.keccak256(ethers.toUtf8Bytes("task-1"));

      await registry
        .connect(requester)
        .requestValidation(1n, validator.address, taskHash, "");

      await expect(registry.connect(user).submitValidation(1n, 85, "")).to.be
        .reverted;
    });
  });
});
