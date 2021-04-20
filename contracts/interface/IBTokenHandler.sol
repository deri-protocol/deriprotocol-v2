// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IBTokenHandler {

    function getPrice() external returns (uint256);

    function swapExactBaseForQuote(uint256 amountB) external returns (uint256 resultB, uint256 resultQ);

    function swapExactQuoteForBase(uint256 amountQ) external returns (uint256 resultB, uint256 resultQ);

    function swapBaseForExactQuote(uint256 amountB, uint256 amountQ) external returns (uint256 resultB, uint256 resultQ);

    function swapQuoteForExactBase(uint256 amountB, uint256 amountQ) external returns (uint256 resultB, uint256 resultQ);

    function sync() external;

}
