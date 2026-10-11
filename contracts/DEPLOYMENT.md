# Deployment Checklist

Urutan deploy & wiring manual yang WAJIB dilakukan (kontrak sengaja tidak
melakukan ini otomatis supaya role assignment tetap eksplisit & auditable).

1. Deploy `AgentLaunchRegistry` (Identity Registry) → constructor: `admin`.
2. Deploy `ReputationBridge` (Reputation Registry) → constructor: `registry address`, `admin`.
3. Deploy `ValidationRegistry` (Validation Registry) → constructor: `registry address`, `admin`.
4. Deploy `AgentTokenFactory` → constructor: `registry`, `weth`, `protocolFeeRecipient`, `initialOwner`.
5. Deploy `GraduationManager` → constructor: `uniswapV3Factory`, `positionManager`, `weth`, `agentFactory`, `initialOwner`.
6. **WAJIB** — tanpa langkah ini semua `launchAgent()` akan revert:
   ```solidity
   agentLaunchRegistry.grantRole(FACTORY_ROLE, address(agentTokenFactory));
   ```
7. **WAJIB** — tanpa ini graduasi curve tidak bisa jalan:
   ```solidity
   agentTokenFactory.setGraduationManager(address(graduationManager));
   ```
8. Opsional tapi disarankan sebelum publik:
   ```solidity
   agentLaunchRegistry.grantRole(VERIFIER_ROLE, address(verifierAddress));
   reputationBridge.grantRole(DISPUTER_ROLE, address(disputerAddress));
   validationRegistry.addValidator(address(validatorWallet)); // ulangi per validator
   ```
9. `antiSnipeEnabled` di factory default `false` — aktifkan lewat
   `setAntiSnipeEnabled(true)` kalau mau surtax anti-snipe aktif.

## Install dependency Uniswap V3 (untuk `GraduationManager`)

`GraduationManager.sol` sekarang import interface RESMI, bukan versi minimal
buatan sendiri lagi:

```bash
npm install @uniswap/v3-core@1.0.1 @uniswap/v3-periphery@1.4.4
npm install @openzeppelin/contracts@^5.0.0
```

### ⚠️ Isu kompatibilitas yang WAJIB diketahui

`@uniswap/v3-periphery` versi apa pun (termasuk yang terbaru) di dalam
`INonfungiblePositionManager.sol` masih import OpenZeppelin dengan path lama:

```solidity
import '@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol';
```

Path ini sudah dipindah ke folder `extensions/` sejak OpenZeppelin v4+ (proyek
ini pakai v5, kelihatan dari `Ownable(initialOwner)`). Uniswap sendiri belum
pernah beresin ini (lihat [issue #335](https://github.com/Uniswap/v3-periphery/issues/335)).
Efeknya, kalau kompilasi gagal dengan error semacam:

```
HH404: File @openzeppelin/contracts/token/ERC721/IERC721Metadata.sol,
imported from @uniswap/v3-periphery/..., not found.
```

lakukan salah satu ini:

- **Pakai `npm install` biasa (bukan `pnpm`/`yarn` strict).** Di kebanyakan
  kasus ini otomatis aman — npm akan naruh copy `@openzeppelin/contracts`
  versi lama (yang jadi dependency bawaan `v3-periphery` sendiri) secara
  *nested* di `node_modules/@uniswap/v3-periphery/node_modules/...`, jadi gak
  bentrok sama `@openzeppelin/contracts` v5 di top-level project. Hardhat
  resolve import ini sesuai struktur node_modules itu.
- **Kalau tetap error (sering kejadian di `pnpm` atau `yarn` mode strict):**
  tambahkan `overrides`/`resolutions` di `package.json` yang mem-vendor ulang
  dua file itu, ATAU paling gampang: copy `INonfungiblePositionManager.sol`
  dari package ke folder lokal proyek lo, ganti 2 baris import di atas jadi:
  ```solidity
  import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
  import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol';
  ```
  lalu import versi lokal itu dari `GraduationManager.sol` sebagai pengganti
  path npm langsung. Ini fix satu baris yang udah umum dipakai komunitas.
- Alternatif paling praktis: pakai **Foundry** dengan `forge install` +
  `remappings.txt` — lebih gampang ngatur remap `@openzeppelin/contracts` khusus
  untuk subtree `lib/v3-periphery` tanpa bentrok versi.

## Yang masih perlu diaudit terpisah sebelum mainnet

- Math bonding curve (constant product + partial-fill clamp di `_executeBuy`)
  belum di-fuzz test — rawan off-by-one di kasus ekstrem (sell-out persis pas
  threshold, virtualEthReserve sangat kecil).
- Belum ada mekanisme pause/emergency-stop di `AgentBondingCurve` maupun
  `AgentTokenFactory` — pertimbangkan tambah `Pausable` kalau butuh circuit
  breaker.
