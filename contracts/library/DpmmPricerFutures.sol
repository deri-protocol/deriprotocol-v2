// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

library DpmmPricerFutures {

    int256 constant ONE = 1e18;

    function _calculateK(int256 indexPrice, int256 liquidity, int256 alpha) internal pure returns (int256) {
        return indexPrice * alpha / liquidity;
    }

    function _calculateDpmmPrice(int256 indexPrice, int256 K, int256 tradersNetPosition) internal pure returns (int256) {
        return indexPrice * (ONE + K * tradersNetPosition / ONE) / ONE;
    }

    function _calculateDpmmCost(int256 indexPrice, int256 K, int256 tradersNetPosition, int256 tradePosition) internal pure returns (int256) {
        int256 r = ((tradersNetPosition + tradePosition) ** 2 - tradersNetPosition ** 2) / ONE * K / ONE / 2 + tradePosition;
        return indexPrice * r / ONE;
    }

}
