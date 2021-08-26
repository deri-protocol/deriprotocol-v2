// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;
import {IEverlastingOption} from "./IEverlastingOption.sol";

interface IPmmPricing {

    function getMidPrice(int256 tradersNetRealVolume, IEverlastingOption.PriceInfo memory prices, int256 alpha, int256 liquidity) external pure returns (int256, int256);

    function queryTradePMM(int256 tradersNetRealVolume, int256 theoreticalPrice, int256 volume, int256 K) external pure returns (int256);


}
