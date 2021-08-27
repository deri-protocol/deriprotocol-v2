// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;


import {SafeMath} from "../library/SafeMath.sol";
import "hardhat/console.sol";
import "../interface/IPmmPricing.sol";
import {IEverlastingOption} from "../interface/IEverlastingOption.sol";
/**
 * @title Pricing
 * @author Deri Protocol
 *
 * @notice Parapara Pricing model
 */
contract LinearPricing is IPmmPricing {
    using SafeMath for uint256;
    using SafeMath for int256;

    int256 constant ONE = 10**18;
//
    function getMidPrice(int256 tradersNetRealVolume, IEverlastingOption.PriceInfo memory prices, int256 alpha, int256 liquidity) external override pure returns (int256, int256) {
        int256 K;
        int256 theoreticalPrice = prices.timeValue + prices.intrinsicValue;
        if (liquidity == 0) {
            K = 0;
        } else {
            K =((prices.underlierPrice ** 2 ) / theoreticalPrice) * prices.delta.abs() * alpha / liquidity / ONE;
        }

        int256 midPrice = theoreticalPrice * (ONE + K * tradersNetRealVolume / ONE) / ONE;
        return (midPrice, K);
    }

//    function getMidPrice(int256 tradersNetRealVolume, int256 delta, int256 theoreticalPrice, int256 underlierPrice, int256 alpha, int256 liquidity) external override pure returns (int256, int256) {
//        int256 K;
//        if (liquidity == 0) {
//            K = 0;
//        } else {
//            K =((underlierPrice ** 2 ) / theoreticalPrice) * delta.abs() * alpha / liquidity / ONE;
//        }
//
//        int256 midPrice = theoreticalPrice * (ONE + K * tradersNetRealVolume / ONE) / ONE;
//        return (midPrice, K);
//    }


    function queryTradePMM(int256 tradersNetRealVolume, int256 theoreticalPrice, int256 volume, int256 K) external override pure returns (int256) {
        int256 r = volume + (K / 2) * ((tradersNetRealVolume + volume)**2 - tradersNetRealVolume**2) / ONE / ONE;
        return theoreticalPrice * r / ONE;
    }


//
//    function getMidPrice(int256 timeValue, int256 deltaB, int256 K) external pure returns (int256) {
//        int256 midPrice = timeValue * (ONE + K * deltaB / ONE) / ONE;
//        return midPrice;
//    }
//
//    function queryTradePMM(int256 timeValue, int256 deltaB, int256 volume, int256 K) external pure returns (int256) {
//        int256 r = volume + (K / 2) * ((deltaB + volume)**2 - deltaB**2) / ONE / ONE;
//        return timeValue * r / ONE;
//    }


}
