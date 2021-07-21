// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IVolatilityOracle {

    function getVolatility() external view returns (uint256);

    function updateVolatility(uint256 timestamp_, uint256 volatility_, uint8 v_, bytes32 r_, bytes32 s_) external;

}
