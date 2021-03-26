// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ILToken {

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

}
