// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IBTokenSwapper.sol';
import '../interface/IERC20.sol';
import '../interface/IUniswapV2Pair.sol';
import '../interface/IUniswapV2Router02.sol';
import '../library/SafeERC20.sol';
import '../library/SafeMath.sol';
import './BTokenSwapper.sol';

// Swapper using two pairs
// E.g. swap (AAA for CCC) or (CCC for AAA) through pairs AAABBB and BBBCCC
contract BTokenSwapper2 is IBTokenSwapper, BTokenSwapper {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable router;
    address public immutable pairBX;
    address public immutable pairB0;
    address public immutable addressMid;
    bool    public immutable isBXToken0;
    bool    public immutable isB0Token0;
    uint256 public immutable liquidityLimitRatio;

    constructor (
        address router_,
        address pairBX_,
        address pairB0_,
        address addressBX_,
        address addressMid_,
        address addressB0_,
        bool    isBXToken0_,
        bool    isB0Token0_,
        uint256 maxSlippageRatio_,
        uint256 liquidityLimitRatio_
    ) BTokenSwapper(addressBX_, addressB0_, maxSlippageRatio_) {
        router = router_;
        pairBX = pairBX_;
        pairB0 = pairB0_;
        addressMid = addressMid_;
        isBXToken0 = isBXToken0_;
        isB0Token0 = isB0Token0_;
        liquidityLimitRatio = liquidityLimitRatio_;

        IERC20(addressBX_).safeApprove(router_, type(uint256).max);
        IERC20(addressB0_).safeApprove(router_, type(uint256).max);
    }

    function getLimitBX() external override view returns (uint256) {
        uint256 reserve;
        if (isBXToken0) {
            (reserve, , ) = IUniswapV2Pair(pairBX).getReserves();
        } else {
            (, reserve, ) = IUniswapV2Pair(pairBX).getReserves();
        }
        return reserve.rescale(decimalsBX, 18) * liquidityLimitRatio / 10**18;
    }

    //================================================================================

    // estimate the tokenB0 amount needed to swap for `amountOutBX` tokenBX
    function _getAmountInB0(uint256 amountOutBX) internal override view returns (uint256) {
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountMid;
        uint256 amountInB0;

        if (isBXToken0) {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pairBX).getReserves();
        } else {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pairBX).getReserves();
        }
        amountMid = IUniswapV2Router02(router).getAmountIn(amountOutBX, reserveIn, reserveOut);

        if (isB0Token0) {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pairB0).getReserves();
        } else {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pairB0).getReserves();
        }
        amountInB0 = IUniswapV2Router02(router).getAmountIn(amountMid, reserveIn, reserveOut);

        return amountInB0;
    }

    // estimate the tokenBX amount needed to swap for `amountOutB0` tokenB0
    function _getAmountInBX(uint256 amountOutB0) internal override view returns (uint256) {
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountMid;
        uint256 amountInBX;

        if (isB0Token0) {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pairB0).getReserves();
        } else {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pairB0).getReserves();
        }
        amountMid = IUniswapV2Router02(router).getAmountIn(amountOutB0, reserveIn, reserveOut);

        if (isBXToken0) {
            (reserveIn, reserveOut, ) = IUniswapV2Pair(pairBX).getReserves();
        } else {
            (reserveOut, reserveIn, ) = IUniswapV2Pair(pairBX).getReserves();
        }
        amountInBX = IUniswapV2Router02(router).getAmountIn(amountMid, reserveIn, reserveOut);

        return amountInBX;
    }

    // low-level swap function
    function _swapExactTokensForTokens(address a, address b, address to) internal override {
        address[] memory path = new address[](3);
        path[0] = a;
        path[1] = addressMid;
        path[2] = b;

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
        address[] memory path = new address[](3);
        path[0] = a;
        path[1] = addressMid;
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
