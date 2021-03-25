// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import './ERC20.sol';

contract LToken is ERC20 {

    address public pool;

    uint256 public marginId;

    modifier _pool_() {
        require(msg.sender == pool, 'LToken: can only be called by pool');
        _;
    }

    constructor (string memory _name, string memory _symbol, address _pool, uint256 _marginId) ERC20(_name, _symbol) {
        pool = _pool;
        marginId = _marginId;
    }

    function setPool(address newPool) public _pool_ {
        require(newPool != address(0), 'LToken.setPool: to 0 address');
        pool = newPool;
    }

    function mint(address account, uint256 amount) public _pool_ {
        require(account != address(0), 'LToken.mint: to 0 address');

        balances[account] += amount;
        totalSupply += amount;

        emit Transfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) public _pool_ {
        require(balances[account] >= amount, 'LToken.burn: amount exceeds balance');

        balances[account] -= amount;
        totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

}
