// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/ILToken.sol';
import './ERC20.sol';

contract LToken is ILToken, ERC20 {

    address _pool;

    modifier _pool_() {
        require(msg.sender == _pool, 'LToken._pool_: only pool');
        _;
    }

    constructor () ERC20('', '') {
        _pool = msg.sender;
    }

    function initialize(string memory name_, string memory symbol_, address pool_) public override {
        require(bytes(_name).length == 0 && bytes(_symbol).length == 0 && _pool == address(0), 'LToken.initialize: already initialized');
        _name = name_;
        _symbol = symbol_;
        _pool = pool_;
    }

    function pool() public override view returns (address) {
        return _pool;
    }

    function setPool(address newPool) public override _pool_ {
        require(newPool != address(0), 'LToken.setPool: to 0 address');
        _pool = newPool;
    }

    function mint(address account, uint256 amount) public override _pool_ {
        require(account != address(0), 'LToken.mint: to 0 address');

        _balances[account] += amount;
        _totalSupply += amount;

        emit Transfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) public override _pool_ {
        require(_balances[account] >= amount, 'LToken.burn: amount exceeds balance');

        _balances[account] -= amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

}
