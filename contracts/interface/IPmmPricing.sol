// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;
import {IEverlastingOption} from "./IEverlastingOption.sol";

interface IPmmPricing {

    function getMidPrice(int256 tradersNetPosition, IEverlastingOption.PriceInfo memory prices, int256 alpha, int256 liquidity) external pure returns (int256, int256);

    function queryTradePMM(int256 tradersNetPosition, int256 timePrice, int256 volume, int256 K) external pure returns (int256);

}
