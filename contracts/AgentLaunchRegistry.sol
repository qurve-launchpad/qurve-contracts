// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAgentLaunchRegistry} from "./interfaces/IAgentLaunchRegistry.sol";

/// @dev Interface minimal ke ERC-8004 Identity Registry RESMI (bukan yang
///      kita deploy sendiri). Cuma butuh signature `register(string)` —
///      versi tanpa on-chain metadata tambahan. Alamat resmi per jaringan
///      (mis. Arc mainnet, Ethereum, Base, dst) semuanya sama:
///      0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 (mainnet, via CREATE2).
interface IERC8004IdentityRegistry {
    function register(string calldata agentURI) external returns (uint256 agentId);
}

/// @title AgentLaunchRegistry
/// @notice ERC-8004 Identity Registry. Setiap agen = 1 ERC-721 soulbound
///         dengan metadata on-chain, plus sync opsional ke ERC-8004 Identity
///         Registry RESMI (mis. 0x8004A169... di kebanyakan mainnet EVM
///         termasuk Arc).
///
///         PRINSIP DESAIN (biar gak ada revert berantai gara-gara dependency
///         eksternal):
///         1. Semua panggilan ke `officialIdentityRegistry` dibungkus
///            try/catch — kalau sync-nya gagal/revert, itu KETANGKEP di
///            catch block dan gak pernah nge-revert transaksi utama.
///            Gas sengaja gak dibatasi eksplisit (forward semua sisa gas
///            apa adanya) karena panggilan ini adalah operasi TERAKHIR di
///            `registerAgent()` — gak ada logic penting lagi setelahnya
///            yang bisa ke-starve gas kalau sync-nya boros.
///         2. Registrasi internal (mint NFT, simpan metadata) SELALU jalan
///            duluan dan gak pernah gantung ke hasil sync eksternal.
///         3. Kalau sync eksternal berhasil, NFT identity resmi (yang
///            awalnya ke-mint ke kontrak ini sebagai `msg.sender`) LANGSUNG
///            di-forward ke agent owner yang sebenarnya dalam transaksi
///            yang sama (lihat `onERC721Received`). Kalau forward-nya
///            gagal, ada `claimOfficialIdentityNFT()` sebagai fallback.
///         4. Kalau sync eksternal gagal total, ada
///            `retryOfficialRegistration()` yang permissionless — bisa
///            dicoba ulang belakangan (misal proxy resmi awalnya masih
///            placeholder, lalu di-upgrade).
///         5. Admin bisa matiin sync eksternal total via
///            `setOfficialSyncEnabled(false)` tanpa redeploy.
contract AgentLaunchRegistry is ERC721, AccessControl, IAgentLaunchRegistry, IERC721Receiver {
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    uint256 private _nextId = 1;
    uint256 public endpointUpdateCooldown = 1 hours;

    /// @notice Alamat ERC-8004 Identity Registry RESMI buat dual-registration
    ///         (mis. 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 di Arc
    ///         mainnet). address(0) = fitur ini off permanen (immutable),
    ///         gak divalidasi non-zero di constructor.
    address public immutable officialIdentityRegistry;

    /// @notice Saklar admin buat matiin sync ke registry resmi tanpa perlu
    ///         redeploy — dipisah dari `officialIdentityRegistry` (yang
    ///         immutable) supaya bisa direspon cepat kalau ada masalah
    ///         berulang di sisi eksternal (mis. proxy resmi lagi bermasalah).
    bool public officialSyncEnabled = true;

    mapping(uint256 => AgentMetadata) private _agents;
    mapping(address => uint256) private _agentIdByToken;
    mapping(uint256 => uint256) private _lastEndpointUpdate;

    /// @notice Agent internal yang lagi dalam proses sync ke registry
    ///         resmi — dipakai `onERC721Received` buat tau NFT identity
    ///         resmi yang baru masuk itu punya siapa, biar bisa langsung
    ///         di-forward ke agent owner yang sebenarnya dalam TRANSAKSI
    ///         YANG SAMA. 0 = lagi gak ada proses sync berjalan. Aman
    ///         dipakai sekarang karena gas call eksternal udah gak
    ///         dibatasi (lihat _trySyncOfficialIdentity) — auto-forward
    ///         gak lagi berisiko bikin kehabisan gas kayak sebelumnya.
    uint256 private _pendingOfficialSyncAgentId;

    error NotAgentOwner();
    error AgentNotFound();
    error SoulboundToken();
    error ZeroAddress();
    error EndpointCooldown();
    error OfficialSyncDisabled();
    error AlreadySyncedOfficially();

    event EndpointCooldownUpdated(uint256 oldValue, uint256 newValue);
    event OfficialSyncEnabledUpdated(bool enabled);
    /// @notice Dipancarkan setiap kali NFT identity resmi berhasil
    ///         berpindah ke agent owner — baik lewat auto-forward di
    ///         `onERC721Received` (langsung pas registrasi) maupun lewat
    ///         `claimOfficialIdentityNFT()` (fallback manual belakangan).
    ///         Dipakai UI/backend buat nampilin-sembunyiin tombol "Claim"
    ///         tanpa perlu polling `ownerOf()` terus-terusan.
    event OfficialNFTClaimed(uint256 indexed agentId, address indexed to);

    constructor(address admin, address officialIdentityRegistry_)
        ERC721("Qurve Agent Identity", "AGENT-ID")
    {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // officialIdentityRegistry_ BOLEH address(0) — artinya dual-
        // registration di-skip sepenuhnya, gak divalidasi non-zero di sini.
        officialIdentityRegistry = officialIdentityRegistry_;
    }

    function setOfficialSyncEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        officialSyncEnabled = enabled;
        emit OfficialSyncEnabledUpdated(enabled);
    }

    function registerAgent(
        address owner_,
        address token_,
        address curve_,
        string calldata name_,
        string calldata agentURI_,
        string calldata endpoint_
    ) external override onlyRole(FACTORY_ROLE) returns (uint256 agentId) {
        agentId = _nextId++;

        _agents[agentId] = AgentMetadata({
            name: name_,
            agentURI: agentURI_,
            endpoint: endpoint_,
            token: token_,
            curve: curve_,
            owner: owner_,
            createdAt: uint64(block.timestamp),
            endpointVerified: false,
            officialAgentId: 0
        });

        _agentIdByToken[token_] = agentId;
        _safeMint(owner_, agentId);

        emit AgentRegistered(agentId, owner_, token_, endpoint_);

        // Registrasi internal di atas SELALU sukses sampai titik ini —
        // sync ke resmi cuma best-effort tambahan, gak pernah bisa
        // mempengaruhi hasil di atas (lihat _trySyncOfficialIdentity).
        _trySyncOfficialIdentity(agentId, agentURI_);
    }

    /// @notice Coba ulang sync ke ERC-8004 Identity Registry resmi buat
    ///         agent yang gagal ke-sync pas registerAgent() (mis. proxy
    ///         resmi lagi placeholder/down waktu itu). Permissionless —
    ///         siapa aja boleh trigger, gak ada downside karena ini murni
    ///         best-effort read-then-write yang non-fatal.
    function retryOfficialRegistration(uint256 agentId) external {
        AgentMetadata storage agent = _agents[agentId];
        if (agent.owner == address(0)) revert AgentNotFound();
        if (agent.officialAgentId != 0) revert AlreadySyncedOfficially();
        if (!officialSyncEnabled || officialIdentityRegistry == address(0)) {
            revert OfficialSyncDisabled();
        }
        _trySyncOfficialIdentity(agentId, agent.agentURI);
    }

    /// @dev Helper internal dipakai bareng oleh registerAgent() dan
    ///      retryOfficialRegistration() — satu implementasi, gak ada
    ///      duplikasi logic yang bisa ketinggalan sinkron kalau salah satu
    ///      diubah belakangan.
    function _trySyncOfficialIdentity(uint256 agentId, string memory agentURI_) private {
        if (!officialSyncEnabled || officialIdentityRegistry == address(0)) return;

        // Set SEBELUM call eksternal — dibaca oleh onERC721Received() yang
        // ke-trigger DI DALAM call ini (mint NFT identity resmi memicu
        // callback secara synchronous, sebelum register() return).
        _pendingOfficialSyncAgentId = agentId;

        // Try/catch tanpa gas cap eksplisit — ini panggilan TERAKHIR di
        // registerAgent()/retryOfficialRegistration(), jadi gak ada logic
        // internal penting lagi yang bisa ke-starve gas kalau sync-nya
        // ternyata boros. Kalau gagal (apa pun sebabnya, termasuk OOG di
        // sub-call), tetap ketangkep di catch block, non-fatal.
        try IERC8004IdentityRegistry(officialIdentityRegistry).register(agentURI_)
            returns (uint256 officialId)
        {
            _agents[agentId].officialAgentId = officialId;
            emit OfficialAgentRegistered(agentId, officialId);
        } catch (bytes memory reason) {
            emit OfficialRegistrationFailed(agentId, reason);
        }

        // WAJIB direset tanpa syarat (sukses maupun gagal) — Solidity gak
        // punya try/finally, jadi ini ditulis eksplisit di luar try/catch,
        // bukan di masing-masing cabang, biar gak ada jalur yang kelewat
        // reset dan ninggalin state basi buat sync berikutnya.
        _pendingOfficialSyncAgentId = 0;
    }

    /// @notice Callback wajib ERC-721 buat kontrak yang mau bisa nerima NFT
    ///         lewat `_safeMint`/`safeTransferFrom`. Di sini dipakai KHUSUS
    ///         buat nerima NFT identity dari registry resmi pas sync (lihat
    ///         `_trySyncOfficialIdentity`), lalu LANGSUNG forward ke agent
    ///         owner yang sebenarnya dalam transaksi yang sama — aman
    ///         dilakukan sekarang karena gas call eksternal udah gak
    ///         dibatasi (beda dari desain sebelumnya yang mikirin gas
    ///         budget). Kontrak ini gak didesain jadi wallet penyimpan NFT
    ///         permanen.
    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256 tokenId,
        bytes calldata /* data */
    ) external override returns (bytes4) {
        // Cuma auto-forward kalau ini beneran datang dari registry resmi
        // DAN lagi dalam proses sync yang kita mulai sendiri — NFT lain
        // yang gak sengaja/gak diminta dikirim ke sini tetap DITERIMA
        // (biar gak bikin transfer pengirim gagal), tapi dibiarkan diam
        // di kontrak ini sampai admin sweep manual (lihat sweepStrayNFT).
        if (msg.sender == officialIdentityRegistry && _pendingOfficialSyncAgentId != 0) {
            address realOwner = _agents[_pendingOfficialSyncAgentId].owner;
            // forward HANYA kalau owner valid & bukan alamat ini sendiri —
            // try/catch di sini: kalau forward gagal (mis. realOwner
            // kontrak tanpa IERC721Receiver juga), JANGAN revert seluruh
            // proses register — biarkan NFT tetap di kontrak ini,
            // recoverable belakangan via claimOfficialIdentityNFT/sweepStrayNFT.
            if (realOwner != address(0) && realOwner != address(this)) {
                try IERC721(officialIdentityRegistry).safeTransferFrom(address(this), realOwner, tokenId) {
                    emit OfficialNFTClaimed(_pendingOfficialSyncAgentId, realOwner);
                } catch {
                    // dibiarkan diam di kontrak ini, recoverable belakangan
                }
            }
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Fallback manual kalau auto-forward di `onERC721Received`
    ///         gagal (mis. waktu registrasi, `agent.owner` sempat berupa
    ///         kontrak yang belum siap nerima NFT). Permissionless — siapa
    ///         aja boleh trigger, gak ada downside karena tujuannya udah
    ///         pasti (`agent.owner`, gak bisa diarahkan ke alamat lain oleh
    ///         pemanggil).
    function claimOfficialIdentityNFT(uint256 agentId) external {
        AgentMetadata storage agent = _agents[agentId];
        if (agent.owner == address(0)) revert AgentNotFound();
        if (agent.officialAgentId == 0) revert OfficialSyncDisabled();

        address currentHolder = IERC721(officialIdentityRegistry).ownerOf(agent.officialAgentId);
        if (currentHolder != address(this)) revert AlreadySyncedOfficially(); // udah pernah di-forward/claim

        IERC721(officialIdentityRegistry).safeTransferFrom(address(this), agent.owner, agent.officialAgentId);
        emit OfficialNFTClaimed(agentId, agent.owner);
    }

    /// @notice Sapu NFT (atau token lain) yang gak sengaja nyangkut di
    ///         kontrak ini — jaring pengaman terakhir kalau auto-forward
    ///         DAN `claimOfficialIdentityNFT` dua-duanya gagal. Admin-only,
    ///         karena kontrak ini gak didesain nyimpen aset apa pun secara
    ///         permanen.
    function sweepStrayNFT(address nftContract, uint256 tokenId, address to)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (to == address(0)) revert ZeroAddress();
        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
    }

    function updateEndpoint(uint256 agentId, string calldata newEndpoint)
        external
        override
    {
        AgentMetadata storage agent = _agents[agentId];
        if (agent.owner == address(0)) revert AgentNotFound();
        if (ownerOf(agentId) != msg.sender) revert NotAgentOwner();

        if (block.timestamp < _lastEndpointUpdate[agentId] + endpointUpdateCooldown) {
            revert EndpointCooldown();
        }
        _lastEndpointUpdate[agentId] = block.timestamp;

        agent.endpoint = newEndpoint;
        agent.endpointVerified = false;

        emit EndpointUpdated(agentId, newEndpoint);
    }

    function setEndpointVerified(uint256 agentId, bool verified)
        external
        override
        onlyRole(VERIFIER_ROLE)
    {
        AgentMetadata storage agent = _agents[agentId];
        if (agent.owner == address(0)) revert AgentNotFound();

        agent.endpointVerified = verified;
        emit EndpointVerified(agentId, verified);
    }

    function getAgent(uint256 agentId)
        external
        view
        override
        returns (AgentMetadata memory)
    {
        AgentMetadata memory agent = _agents[agentId];
        if (agent.owner == address(0)) revert AgentNotFound();
        return agent;
    }

    function agentIdByToken(address token)
        external
        view
        override
        returns (uint256)
    {
        return _agentIdByToken[token];
    }

    function totalAgents() external view override returns (uint256) {
        return _nextId - 1;
    }

    /// @notice FIX M3: revert dengan AgentNotFound kalau agentId tidak
    ///         pernah di-mint. Sebelumnya mengembalikan string kosong,
    ///         yang membuat wallet/explorer bingung karena mereka tidak
    ///         bisa membedakan "agent ada tapi metadata kosong" dengan
    ///         "agent tidak ada sama sekali".
    ///
    ///         Sesuai dengan EIP-721 yang menspesifikasikan tokenURI
    ///         SHOULD throw untuk tokenId yang tidak valid. OpenZeppelin
    ///         default juga revert; sebelumnya kontrak ini sengaja
    ///         menyimpang (return empty), sekarang sudah konsisten.
    function tokenURI(uint256 agentId) public view override returns (string memory) {
        if (_agents[agentId].owner == address(0)) revert AgentNotFound();
        return _agents[agentId].agentURI;
    }

    function lastEndpointUpdate(uint256 agentId) external view returns (uint256) {
        return _lastEndpointUpdate[agentId];
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert SoulboundToken();
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function setEndpointUpdateCooldown(uint256 newCooldown)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 old = endpointUpdateCooldown;
        endpointUpdateCooldown = newCooldown;
        emit EndpointCooldownUpdated(old, newCooldown);
    }
}
