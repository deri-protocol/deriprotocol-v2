// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

abstract contract MigratablePool {

    event PrepareMigration(uint256 migrationTimestamp, address source, address target);

    event ExecuteMigration(uint256 migrationTimestamp, address source, address target);

    address public controller;

    uint256 public migrationTimestamp;

    address public migrationDestination;

    modifier _controller_() {
        require(msg.sender == controller, 'MigratablePool: only controller');
        _;
    }

    function setController(address newController) public _controller_ {
        require(newController != address(0), 'MigratablePool.setController: to 0 address');
        controller = newController;
    }

    function prepareMigration(address newPool, uint256 graceDays) public _controller_ {
        require(newPool != address(0), 'MigratablePool.prepareMigration: to 0 address');
        require(graceDays >= 3 && graceDays <= 365, 'MigratablePool.prepareMigration: graceDays must be 3-365 days');

        migrationTimestamp = block.timestamp + graceDays * 1 days;
        migrationDestination = newPool;

        emit PrepareMigration(migrationTimestamp, address(this), migrationDestination);
    }

    function approveMigration() public virtual;

    function executeMigration(address source) public virtual;

}
