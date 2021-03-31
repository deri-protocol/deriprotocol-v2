// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IERC20.sol';

interface ILToken is IERC20 {

    function pool() external view returns (address);

    function bTokenId() external view returns (uint256);

    function initialize(string memory _name, string memory _symbol, address _pool) external;

    function setPool(address newPool) external;

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

}
