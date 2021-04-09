// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ICloneFactory {

    event Clone(address source, address target);

    function controller() external view returns (address);

    function setController(address newController) external;

    function cloned() external view returns (address);

    function clone(address source) external returns (address);

}
