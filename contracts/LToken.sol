// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './ERC20.sol';

contract LToken is ERC20 {

    address public pool;

    uint256 public bTokenId;

    modifier _pool_() {
        require(msg.sender == pool, 'LToken._pool_: only pool');
        _;
    }

    constructor (string memory _name, string memory _symbol, address _pool, uint256 _bTokenId) ERC20 (_name, _symbol) {
        pool = _pool;
        bTokenId = _bTokenId;
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