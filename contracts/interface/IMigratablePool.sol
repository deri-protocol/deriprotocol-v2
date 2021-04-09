// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IMigratablePool {

    event PrepareMigration(uint256 migrationTimestamp, address source, address target);

    event ExecuteMigration(uint256 migrationTimestamp, address source, address target);

    function migrationTimestamp() external view returns (uint256);

    function migrationDestination() external view returns (address);

    function controller() external view returns (address);

    function setNewController(address newController_) external;

    function claimNewController() external;

    function prepareMigration(address newPool, uint256 graceDays) external;

    function approveMigration() external;

    function executeMigration(address source) external;

}
