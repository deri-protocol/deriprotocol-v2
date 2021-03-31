// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

contract CloneFactory {

    event Clone(address cloner, address source, address target);

    address public controller;

    address public cloned;

    constructor () {
        controller = msg.sender;
    }

    function setController(address newController) public {
        require(msg.sender == controller, 'CloneFactory.setController: only controller');
        controller = newController;
    }

    function clone(address source) public returns (address target) {
        require(msg.sender == controller, 'CloneFactory.clone: only controller');
        bytes20 sourceBytes = bytes20(source);
        assembly {
            let c := mload(0x40)
            mstore(c, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(c, 0x14), sourceBytes)
            mstore(add(c, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            target := create(0, c, 0x37)
        }
        cloned = target;
        emit Clone(msg.sender, source, target);
    }

}
