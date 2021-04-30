// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';
import './Ownable.sol';

abstract contract Migratable is IMigratable, Ownable {

    // migration timestamp, zero means not set
    // migration timestamp can only be set with a grace period, e.x. 3-365 days, and the
    // migration destination must also be set when setting migration timestamp
    // users can use this grace period to verify the desination contract code
    uint256 _migrationTimestamp;

    // the destination address the source contract will migrate to, after the grace period
    address _migrationDestination;

    function migrationTimestamp() public override view returns (uint256) {
        return _migrationTimestamp;
    }

    function migrationDestination() public override view returns (address) {
        return _migrationDestination;
    }

    // prepare a migration process, the timestamp and desination will be set at this stage
    // and the migration grace period starts
    function prepareMigration(address target, uint256 graceDays) public override _controller_ {
        require(target != address(0), 'Migratable: target 0');
        require(graceDays >= 3 && graceDays <= 365, 'Migratable: graceDays must be 3-365');

        _migrationTimestamp = block.timestamp + graceDays * 1 days;
        _migrationDestination = target;

        emit PrepareMigration(_migrationTimestamp, address(this), _migrationDestination);
    }

}
