// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IOwnable {

    function controller() external view returns (address);

    function setNewController(address newController) external;

    function claimNewController() external;

}
