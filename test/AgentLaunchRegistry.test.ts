// test/AgentLaunchRegistry.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("AgentLaunchRegistry", () => {
  async function deployFixture() {
    const [owner, factory, user1, user2] = await ethers.getSigners();

    const Registry = await ethers.getContractFactory("AgentLaunchRegistry");
    const registry = await Registry.deploy(owner.address);

    const FACTORY_ROLE = await registry.FACTORY_ROLE();
    const VERIFIER_ROLE = await registry.VERIFIER_ROLE();
    const DEFAULT_ADMIN_ROLE = await registry.DEFAULT_ADMIN_ROLE();

    await registry.grantRole(FACTORY_ROLE, factory.address);
    await registry.grantRole(VERIFIER_ROLE, owner.address);

    return {
      registry,
      owner,
      factory,
      user1,
      user2,
      FACTORY_ROLE,
      VERIFIER_ROLE,
      DEFAULT_ADMIN_ROLE,
    };
  }

  describe("Deployment", () => {
    it("grants deployer the default admin role", async () => {
      const { registry, owner, DEFAULT_ADMIN_ROLE } = await loadFixture(
        deployFixture
      );
      expect(await registry.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be
        .true;
    });

    it("starts with zero agents", async () => {
      const { registry } = await loadFixture(deployFixture);
      expect(await registry.totalAgents()).to.equal(0n);
    });
  });

  describe("registerAgent", () => {
    it("only callable by FACTORY_ROLE", async () => {
      const { registry, user1 } = await loadFixture(deployFixture);

      await expect(
        registry
          .connect(user1)
          .registerAgent(
            user1.address,
            user1.address,
            user1.address,
            "Test",
            "ipfs://test",
            "https://endpoint.example.com"
          )
      ).to.be.reverted;
    });

    it("mints soulbound NFT to owner", async () => {
      const { registry, factory, user1 } = await loadFixture(deployFixture);

      await registry
        .connect(factory)
        .registerAgent(
          user1.address,
          user1.address,
          user1.address,
          "Test Agent",
          "ipfs://test",
          "https://endpoint.example.com"
        );

      expect(await registry.ownerOf(1n)).to.equal(user1.address);
      expect(await registry.totalAgents()).to.equal(1n);
    });

    it("stores agent metadata correctly", async () => {
      const { registry, factory, user1 } = await loadFixture(deployFixture);

      await registry
        .connect(factory)
        .registerAgent(
          user1.address,
          user1.address,
          user1.address,
          "Alpha Agent",
          "ipfs://alpha",
          "https://alpha.example.com"
        );

      const agent = await registry.getAgent(1n);
      expect(agent.name).to.equal("Alpha Agent");
      expect(agent.agentURI).to.equal("ipfs://alpha");
      expect(agent.endpoint).to.equal("https://alpha.example.com");
      expect(agent.owner).to.equal(user1.address);
    });
  });

  describe("Soulbound behavior", () => {
    it("reverts on transferFrom", async () => {
      const { registry, factory, user1, user2 } = await loadFixture(
        deployFixture
      );

      await registry
        .connect(factory)
        .registerAgent(
          user1.address,
          user1.address,
          user1.address,
          "Test",
          "ipfs://test",
          "https://endpoint.example.com"
        );

      await expect(
        registry
          .connect(user1)
          .transferFrom(user1.address, user2.address, 1n)
      ).to.be.reverted;
    });
  });

  describe("Endpoint verification", () => {
    it("only VERIFIER_ROLE can mark verified", async () => {
      const { registry, factory, owner, user1 } = await loadFixture(
        deployFixture
      );

      await registry
        .connect(factory)
        .registerAgent(
          user1.address,
          user1.address,
          user1.address,
          "Test",
          "ipfs://test",
          "https://endpoint.example.com"
        );

      await registry.connect(owner).setEndpointVerified(1n, true);

      const agent = await registry.getAgent(1n);
      expect(agent.endpointVerified).to.be.true;
    });

    it("reverts for non-verifier", async () => {
      const { registry, factory, user1, user2 } = await loadFixture(
        deployFixture
      );

      await registry
        .connect(factory)
        .registerAgent(
          user1.address,
          user1.address,
          user1.address,
          "Test",
          "ipfs://test",
          "https://endpoint.example.com"
        );

      await expect(registry.connect(user2).setEndpointVerified(1n, true)).to.be
        .reverted;
    });
  });
});
