// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IERC20.sol';

interface ILTokenOption is IERC20 {

    function pool() external view returns (address);

    function setPool(address newPool) external;

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

}
