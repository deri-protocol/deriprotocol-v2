// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IOracle.sol';
import '../interface/IERC20.sol';
import '../interface/IUniswapV2Pair.sol';

contract BTokenOracle2 is IOracle {

    uint256 constant Q112 = 2**112;

    address public immutable pairQ;
    address public immutable pairB;
    address public immutable quote;
    address public immutable mid;
    address public immutable base;
    uint256 public immutable qDecimals;
    uint256 public immutable mDecimals;
    uint256 public immutable bDecimals;
    bool    public immutable isQuoteToken0;
    bool    public immutable isBaseToken0;

    uint256 public qPriceCumulativeLast1;
    uint256 public qPriceCumulativeLast2;
    uint256 public qTimestampLast1;
    uint256 public qTimestampLast2;

    uint256 public bPriceCumulativeLast1;
    uint256 public bPriceCumulativeLast2;
    uint256 public bTimestampLast1;
    uint256 public bTimestampLast2;

    constructor (
        address pairQ_,
        address pairB_,
        address quote_,
        address mid_,
        address base_,
        bool isQuoteToken0_,
        bool isBaseToken0_
    ) {
        pairQ = pairQ_;
        pairB = pairB_;
        quote = quote_;
        mid = mid_;
        base = base_;
        qDecimals = IERC20(quote_).decimals();
        mDecimals = IERC20(mid_).decimals();
        bDecimals = IERC20(base_).decimals();
        isQuoteToken0 = isQuoteToken0_;
        isBaseToken0 = isBaseToken0_;

        IUniswapV2Pair p;
        p = IUniswapV2Pair(pairQ_);
        qPriceCumulativeLast2 = isQuoteToken0_ ? p.price0CumulativeLast() : p.price1CumulativeLast();
        (, , qTimestampLast2) = p.getReserves();

        p = IUniswapV2Pair(pairB_);
        bPriceCumulativeLast2 = isBaseToken0_ ? p.price1CumulativeLast() : p.price0CumulativeLast();
        (, , bTimestampLast2) = p.getReserves();
    }

    function getPrice() public override returns (uint256) {
        IUniswapV2Pair p;
        uint256 reserveQ;
        uint256 reserveB;
        uint256 timestamp;

        p = IUniswapV2Pair(pairQ);
        if (isQuoteToken0) {
            (reserveQ, reserveB, timestamp) = p.getReserves();
        } else {
            (reserveB, reserveQ, timestamp) = p.getReserves();
        }

        if (timestamp != qTimestampLast2) {
            qPriceCumulativeLast1 = qPriceCumulativeLast2;
            qTimestampLast1 = qTimestampLast2;
            qPriceCumulativeLast2 = isQuoteToken0 ? p.price0CumulativeLast() : p.price1CumulativeLast();
            qTimestampLast2 = timestamp;
        }

        uint256 price1;
        if (qTimestampLast1 != 0) {
            price1 = (qPriceCumulativeLast2 - qPriceCumulativeLast1) / (qTimestampLast2 - qTimestampLast1) * 10**(18 + qDecimals - mDecimals) / Q112;
        } else {
            price1 = reserveB * 10**(18 + qDecimals - mDecimals) / reserveQ;
        }

        p = IUniswapV2Pair(pairB);
        if (isBaseToken0) {
            (reserveB, reserveQ, timestamp) = p.getReserves();
        } else {
            (reserveQ, reserveB, timestamp) = p.getReserves();
        }

        if (timestamp != bTimestampLast2) {
            bPriceCumulativeLast1 = bPriceCumulativeLast2;
            bTimestampLast1 = bTimestampLast2;
            bPriceCumulativeLast2 = isBaseToken0 ? p.price1CumulativeLast() : p.price0CumulativeLast();
            bTimestampLast2 = timestamp;
        }

        uint256 price2;
        if (bTimestampLast1 != 0) {
            price2 = (bPriceCumulativeLast2 - bPriceCumulativeLast1) / (bTimestampLast2 - bTimestampLast1) * 10**(18 + mDecimals - bDecimals) / Q112;
        } else {
            price2 = reserveB * 10**(18 + mDecimals - bDecimals) / reserveQ;
        }

        return price1 * price2 / 10**18;
    }

}
