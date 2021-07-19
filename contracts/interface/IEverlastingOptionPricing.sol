// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IEverlastingOptionPricing {

    function getEverlastingCallPrice(int256 S, int256 K, int256 V, int256 T) external pure returns (int256);

    function getEverlastingPutPrice(int256 S, int256 K, int256 V, int256 T) external pure returns (int256);

}
