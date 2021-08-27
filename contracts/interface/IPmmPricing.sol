// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;
import {IEverlastingOption} from "./IEverlastingOption.sol";

interface IPmmPricing {

    function getMidPrice(int256 deltaB, IEverlastingOption.PriceInfo memory prices, int256 alpha, int256 liquidity) external pure returns (int256, int256);

//    function getMidPrice(int256 tradersNetRealVolume, int256 delta, int256 theoreticalPrice, int256 underlierPrice, int256 alpha, int256 liquidity) external pure returns (int256, int256);

    function queryTradePMM(int256 deltaB, int256 timePrice, int256 volume, int256 K) external pure returns (int256);

}
