// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IEverlastingOptionPricing {

    function getEverlastingTimeValue(int256 S, int256 K, int256 V, int256 T) external pure returns (int256);

    function getEverlastingTimeValueAndDelta(int256 S, int256 K, int256 V, int256 T) external pure returns (int256, int256);

}
