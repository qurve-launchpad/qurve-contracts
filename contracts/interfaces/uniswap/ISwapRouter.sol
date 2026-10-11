// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISwapRouter (gaya SwapRouter02)
/// @notice Minimal interface exact-input single-hop buat Uniswap V3.
///         PENTING: ini pakai bentuk SwapRouter02 (TANPA field `deadline` di
///         struct) — bukan ISwapRouter versi v3-periphery lama yang masih
///         punya `deadline`. Base, Base Sepolia, dan mayoritas chain baru
///         deploy versi SwapRouter02. Cek dulu ABI resmi di chain tujuan
///         sebelum deploy — kalau ternyata router di chain itu masih versi
///         lama (ada `deadline`), struct ini perlu ditambah field itu balik.
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}
