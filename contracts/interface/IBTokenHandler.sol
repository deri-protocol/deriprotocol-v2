// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IBTokenHandler {

    function getPrice() external view returns (uint256);

    function swap(uint256 maxAmountIn, uint256 minAmountOut) external returns (uint256, uint256);

}
