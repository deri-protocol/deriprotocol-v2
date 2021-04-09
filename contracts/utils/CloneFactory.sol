
// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/ICloneFactory.sol';

contract CloneFactory is ICloneFactory {

    address _controller;

    address _cloned;

    constructor () {
        _controller = msg.sender;
    }

    function controller() public override view returns (address) {
        return _controller;
    }

    function setController(address newController) public override {
        require(msg.sender == _controller, 'CloneFactory.setController: only controller');
        _controller = newController;
    }

    function cloned() public override view returns (address) {
        return _cloned;
    }

    function clone(address source) public override returns (address target) {
        require(msg.sender == _controller, 'CloneFactory.clone: only controller');
        bytes20 sourceBytes = bytes20(source);
        assembly {
            let c := mload(0x40)
            mstore(c, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(c, 0x14), sourceBytes)
            mstore(add(c, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            target := create(0, c, 0x37)
        }
        _cloned = target;
        emit Clone(source, target);
    }

}
