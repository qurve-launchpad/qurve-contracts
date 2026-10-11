// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

// ── VENDORED dari @uniswap/v3-periphery@1.4.4 ───────────────────────────────
// Isi 100% sama dengan versi resmi. Satu-satunya perubahan: pragma dilonggarkan
// dari terkunci `=0.7.6` menjadi `>=0.7.5`, supaya bisa dipakai bareng project
// yang compile di 0.8.24. Ini interface saja (tidak ada implementasi/logic),
// jadi tidak ada behavior yang berubah — cuma constraint versi compiler-nya.
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @title Interface for WETH9
interface IWETH9 is IERC20 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}
