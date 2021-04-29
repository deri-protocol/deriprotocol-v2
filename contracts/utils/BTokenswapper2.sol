// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IBTokenSwapper.sol';
import '../interface/IERC20.sol';
import '../interface/IUniswapV2Pair.sol';
import '../interface/IUniswapV2Router02.sol';
import '../library/SafeERC20.sol';
import './BTokenSwapper.sol';

contract BTokenSwapper2 is IBTokenSwapper, BTokenSwapper {

    using SafeERC20 for IERC20;

    address public immutable router;
    address public immutable pairQ;
    address public immutable pairB;
    address public immutable mid;
    bool    public immutable isQuoteToken0;
    bool    public immutable isBaseToken0;

    constructor (
        address router_,
        address pairQ_,
        address pairB_,
        address quote_,
        address mid_,
        address base_,
        bool    isQuoteToken0_,
        bool    isBaseToken0_
    ) BTokenSwapper(quote_, base_) {
        router = router_;
        pairQ = pairQ_;
        pairB = pairB_;
        mid = mid_;
        isQuoteToken0 = isQuoteToken0_;
        isBaseToken0 = isBaseToken0_;

        IERC20(quote_).safeApprove(router_, type(uint256).max);
        IERC20(base_).safeApprove(router_, type(uint256).max);
    }

    //================================================================================

    function _getBaseAmountIn(uint256 quoteAmountOut) internal override view returns (uint256) {
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountMid;
        uint256 baseAmountIn;

        if (isQuoteToken0) {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pairQ).getReserves();
        } else {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pairQ).getReserves();
        }
        amountMid = IUniswapV2Router02(router).getAmountIn(quoteAmountOut, reserveIn, reserveOut);

        if (isBaseToken0) {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pairB).getReserves();
        } else {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pairB).getReserves();
        }
        baseAmountIn = IUniswapV2Router02(router).getAmountIn(amountMid, reserveIn, reserveOut);

        return baseAmountIn;
    }

    function _getQuoteAmountIn(uint256 baseAmountOut) internal override view returns (uint256) {
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountMid;
        uint256 quoteAmountIn;

        if (isBaseToken0) {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pairB).getReserves();
        } else {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pairB).getReserves();
        }
        amountMid = IUniswapV2Router02(router).getAmountIn(baseAmountOut, reserveIn, reserveOut);

        if (isQuoteToken0) {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pairQ).getReserves();
        } else {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pairQ).getReserves();
        }
        quoteAmountIn = IUniswapV2Router02(router).getAmountIn(amountMid, reserveIn, reserveOut);

        return quoteAmountIn;
    }

    function _swapExactTokensForTokens(address a, address b, address to) internal override {
        address[] memory path = new address[](3);
        path[0] = a;
        path[1] = mid;
        path[2] = b;

        IUniswapV2Router02(router).swapExactTokensForTokens(
            IERC20(a).balanceOf(address(this)),
            0,
            path,
            to,
            block.timestamp + 3600
        );
    }

    function _swapTokensForExactTokens(address a, address b, uint256 amount, address to) internal override {
        address[] memory path = new address[](3);
        path[0] = a;
        path[1] = mid;
        path[2] = b;

        IUniswapV2Router02(router).swapTokensForExactTokens(
            amount,
            IERC20(a).balanceOf(address(this)),
            path,
            to,
            block.timestamp + 3600
        );
    }

}
