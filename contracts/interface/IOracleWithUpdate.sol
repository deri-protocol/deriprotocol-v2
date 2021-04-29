// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IOracleWithUpdate {

    function getPrice() external returns (uint256);

    function updatePrice(uint256 timestamp, uint256 price, uint8 v, bytes32 r, bytes32 s) external;

}
