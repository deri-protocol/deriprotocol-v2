// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IBTokenSwapper.sol';
import '../interface/IERC20.sol';
import '../interface/IUniswapV2Pair.sol';
import '../interface/IUniswapV2Router02.sol';
import '../library/SafeERC20.sol';
import './BTokenSwapper.sol';

contract BTokenSwapper1 is IBTokenSwapper, BTokenSwapper {

    using SafeERC20 for IERC20;

    address public immutable router;
    address public immutable pair;
    bool    public immutable isQuoteToken0;

    constructor (address router_, address pair_, address quote_, address base_, bool isQuoteToken0_) BTokenSwapper(quote_, base_) {
        router = router_;
        pair = pair_;
        isQuoteToken0 = isQuoteToken0_;

        IERC20(quote_).safeApprove(router_, type(uint256).max);
        IERC20(base_).safeApprove(router_, type(uint256).max);
    }

    //================================================================================

    // estimate the base token amount needed to swap for `quoteAmountOut` quote tokens
    function _getBaseAmountIn(uint256 quoteAmountOut) internal override view returns (uint256) {
        uint256 reserveIn;
        uint256 reserveOut;
        if (isQuoteToken0) {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pair).getReserves();
        } else {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pair).getReserves();
        }
        return IUniswapV2Router02(router).getAmountIn(quoteAmountOut, reserveIn, reserveOut);
    }

    // estimate the quote token amount needed to swap for `baseAmountOut` base tokens
    function _getQuoteAmountIn(uint256 baseAmountOut) internal override view returns (uint256) {
        uint256 reserveIn;
        uint256 reserveOut;
        if (isQuoteToken0) {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pair).getReserves();
        } else {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pair).getReserves();
        }
        return IUniswapV2Router02(router).getAmountIn(baseAmountOut, reserveIn, reserveOut);
    }

    // low-level swap function
    function _swapExactTokensForTokens(address a, address b, address to) internal override {
        address[] memory path = new address[](2);
        path[0] = a;
        path[1] = b;

        IUniswapV2Router02(router).swapExactTokensForTokens(
            IERC20(a).balanceOf(address(this)),
            0,
            path,
            to,
            block.timestamp + 3600
        );
    }

    // low-level swap function
    function _swapTokensForExactTokens(address a, address b, uint256 amount, address to) internal override {
        address[] memory path = new address[](2);
        path[0] = a;
        path[1] = b;

        IUniswapV2Router02(router).swapTokensForExactTokens(
            amount,
            IERC20(a).balanceOf(address(this)),
            path,
            to,
            block.timestamp + 3600
        );
    }

}
