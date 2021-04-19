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
        require(target != address(0), 'Migratable.prepareMigration: to 0 address');
        require(graceDays >= 3 && graceDays <= 365, 'Migratable.prepareMigration: graceDays must be 3-365 days');

        _migrationTimestamp = block.timestamp + graceDays * 1 days;
        _migrationDestination = target;

        emit PrepareMigration(_migrationTimestamp, address(this), _migrationDestination);
    }

    function approveMigration() public override virtual {}

    function executeMigration(address source) public override virtual {}

}
