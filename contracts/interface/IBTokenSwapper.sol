// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IBTokenSwapper {

    function swapExactB0ForBX(uint256 amountB0, uint256 referencePrice) external returns (uint256 resultB0, uint256 resultBX);

    function swapExactBXForB0(uint256 amountBX, uint256 referencePrice) external returns (uint256 resultB0, uint256 resultBX);

    function swapB0ForExactBX(uint256 amountB0, uint256 amountBX, uint256 referencePrice) external returns (uint256 resultB0, uint256 resultBX);

    function swapBXForExactB0(uint256 amountB0, uint256 amountBX, uint256 referencePrice) external returns (uint256 resultB0, uint256 resultBX);

    function getLimitBX() external view returns (uint256);

    function sync() external;

}
