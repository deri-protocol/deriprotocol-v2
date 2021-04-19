// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IBTokenHandler {

    function getPrice() external view returns (uint256);

    function swapExactB0ForBX(uint256 amountB0) external returns (uint256 amountBX);

    function swapExactBXForB0(uint256 amountBX) external returns (uint256 amountB0);

    function swapB0ForExactBX(uint256 maxAmountB0, uint256 exactAmountBX) external returns (uint256 amountB0, uint256 amountBX);

    function swapBXForExactB0(uint256 exactAmountB0, uint256 maxAmountBX) external returns (uint256 amountB0, uint256 amountBX);

}
