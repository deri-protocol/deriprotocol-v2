// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IVolitilityOracle {

    function getVolitility() external view returns (uint256);

    function updateVolitility(uint256 timestamp_, uint256 volitility_, uint8 v_, bytes32 r_, bytes32 s_) external;

}
