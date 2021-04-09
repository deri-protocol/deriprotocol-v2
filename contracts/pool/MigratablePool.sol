// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratablePool.sol';

abstract contract MigratablePool is IMigratablePool {

    address _controller;

    address _newController;

    uint256 _migrationTimestamp;

    address _migrationDestination;

    modifier _controller_() {
        require(msg.sender == _controller, 'MigratablePool: only controller');
        _;
    }

    function migrationTimestamp() public override view returns (uint256) {
        return _migrationTimestamp;
    }

    function migrationDestination() public override view returns (address) {
        return _migrationDestination;
    }

    function controller() public override view returns (address) {
        return _controller;
    }

    function setNewController(address newController_) public override _controller_ {
        _newController = newController_;
    }

    function claimNewController() public override {
        require(msg.sender == _newController, 'MigratablePool.claimNewController: not allowed');
        _controller = _newController;
    }

    function prepareMigration(address newPool, uint256 graceDays) public override _controller_ {
        require(newPool != address(0), 'MigratablePool.prepareMigration: to 0 address');
        require(graceDays >= 3 && graceDays <= 365, 'MigratablePool.prepareMigration: graceDays must be 3-365 days');

        _migrationTimestamp = block.timestamp + graceDays * 1 days;
        _migrationDestination = newPool;

        emit PrepareMigration(_migrationTimestamp, address(this), _migrationDestination);
    }

}
