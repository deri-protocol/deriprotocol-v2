// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/IUniswapV2Pair.sol';
import '../interface/IUniswapV2Router02.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';

contract BTokenHandlerDAIUSDT {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant Q112 = 2**112;

    // Kovan
    address public constant uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // WETH-USDT
    address public constant uniswapPair1 = 0x85E2f1bd9136dBbE61dD07e4c2b567a75DB5c33A;
    address public constant weth = 0x2479FA8779C494b47A57e909417AACCe5c2e594d;
    address public constant usdt = 0x77F120dF3A2e518BdFDE4330a6140c77103271DA;
    uint256 public constant decimals10 = 18;
    uint256 public constant decimals11 = 6;

    // WETH-DAI
    address public constant uniswapPair2 = 0xD14f0441cac7E35f79e25f4128725A89Df8f6559;
    address public constant dai = 0x436F052d6163bC714703F6d851dBEa828cf74f23;
    uint256 public constant decimals20 = 18;
    uint256 public constant decimals21 = 18;

    uint256 public price0CumulativeLast11;
    uint256 public price0CumulativeLast12;
    uint256 public blockTimestampLast11;
    uint256 public blockTimestampLast12;

    uint256 public price0CumulativeLast21;
    uint256 public price0CumulativeLast22;
    uint256 public blockTimestampLast21;
    uint256 public blockTimestampLast22;

    uint256 public price;

    constructor () {
        price0CumulativeLast12 = IUniswapV2Pair(uniswapPair1).price0CumulativeLast();
        (, , blockTimestampLast12) = IUniswapV2Pair(uniswapPair1).getReserves();

        price0CumulativeLast22 = IUniswapV2Pair(uniswapPair2).price0CumulativeLast();
        (, , blockTimestampLast22) = IUniswapV2Pair(uniswapPair2).getReserves();

        IERC20(dai).approve(uniswapRouter, type(uint256).max);
    }

    function getPrice() public returns (uint256) {
        (uint256 reserve10, uint256 reserve11, uint256 timestamp1) = IUniswapV2Pair(uniswapPair1).getReserves();
        if (timestamp1 != blockTimestampLast12) {
            price0CumulativeLast11 = price0CumulativeLast12;
            blockTimestampLast11 = blockTimestampLast12;
            price0CumulativeLast12 = IUniswapV2Pair(uniswapPair1).price0CumulativeLast();
            blockTimestampLast12 = timestamp1;
        }

        (uint256 reserve20, uint256 reserve21, uint256 timestamp2) = IUniswapV2Pair(uniswapPair2).getReserves();
        if (timestamp2 != blockTimestampLast22) {
            price0CumulativeLast21 = price0CumulativeLast22;
            blockTimestampLast21 = blockTimestampLast22;
            price0CumulativeLast22 = IUniswapV2Pair(uniswapPair2).price0CumulativeLast();
            blockTimestampLast22 = timestamp2;
        }

        uint256 price1;
        if (blockTimestampLast11 != 0) {
            price1 = (price0CumulativeLast12 - price0CumulativeLast11) / (blockTimestampLast12 - blockTimestampLast11) * 10**(decimals10 - decimals11 + 18) / Q112;
        } else {
            price1 = reserve11 * 10**(decimals10 - decimals11 + 18) / reserve10;
        }

        uint256 price2;
        if (blockTimestampLast21 != 0) {
            price2 = (price0CumulativeLast22 - price0CumulativeLast21) / (blockTimestampLast22 - blockTimestampLast21) * 10**(decimals20 - decimals21 + 18) / Q112;
        } else {
            price2 = reserve21 * 10**(decimals20 - decimals21 + 18) / reserve20;
        }

        price = price1 * 10**18 / price2;
        return price;
    }

    function swap(uint256 maxAmountIn, uint256 minAmountOut) public returns (uint256, uint256) {
        IERC20(dai).safeTransferFrom(msg.sender, address(this), maxAmountIn.rescale(18, decimals21));
        uint256 balance01 = IERC20(dai).balanceOf(address(this));

        address[] memory path = new address[](3);
        path[0] = dai;
        path[1] = weth;
        path[2] = usdt;
        IUniswapV2Router02(uniswapRouter).swapTokensForExactTokens(
            minAmountOut.rescale(18, decimals11),
            balance01,
            path,
            address(this),
            block.timestamp + 3600
        );

        uint256 balance02 = IERC20(dai).balanceOf(address(this));
        uint256 balance12 = IERC20(usdt).balanceOf(address(this));
        IERC20(dai).safeTransfer(msg.sender, balance02);
        IERC20(usdt).safeTransfer(msg.sender, balance12);

        return ((balance01 - balance02).rescale(decimals21, 18), balance12.rescale(decimals11, 18));
    }

}
