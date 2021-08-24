// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;


import {SafeMath} from "../library/SafeMath.sol";

import "hardhat/console.sol";
/**
 * @title Pricing
 * @author Deri Protocol
 *
 * @notice Parapara Pricing model
 */
contract LinearPricing {
    using SafeMath for uint256;
    using SafeMath for int256;

    int256 constant ONE = 10**18;

    function getMidPrice(int256 timePrice, int256 deltaB, int256 K) external pure returns (int256) {
        int256 midPrice = timePrice * (ONE + K * deltaB / ONE) / ONE;
        return midPrice;
    }

    function queryTradePMM(int256 timePrice, int256 deltaB, int256 volume, int256 K) external pure returns (int256) {
        int256 r = volume + (K / 2) * ((deltaB + volume)**2 - deltaB**2) / ONE / ONE;
        return timePrice * r / ONE;
    }


}
