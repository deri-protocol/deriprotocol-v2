// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';
import './Ownable.sol';

abstract contract Migratable is IMigratable, Ownable {

    uint256 _migrationTimestamp;

    address _migrationDestination;

    function migrationTimestamp() public override view returns (uint256) {
        return _migrationTimestamp;
    }

    function migrationDestination() public override view returns (address) {
        return _migrationDestination;
    }

    function prepareMigration(address target, uint256 graceDays) public override _controller_ {
        require(target != address(0), 'Migratable: target 0');
        require(graceDays >= 3 && graceDays <= 365, 'Migratable: graceDays must be 3-365');

        _migrationTimestamp = block.timestamp + graceDays * 1 days;
        _migrationDestination = target;

        emit PrepareMigration(_migrationTimestamp, address(this), _migrationDestination);
    }

    function approveMigration() public override virtual {}

    function executeMigration(address source) public override virtual {}

}
