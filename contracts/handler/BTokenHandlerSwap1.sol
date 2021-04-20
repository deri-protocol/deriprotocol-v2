// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IBTokenHandler.sol';
import '../interface/IERC20.sol';
import '../interface/IUniswapV2Pair.sol';
import '../interface/IUniswapV2Router02.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';

contract BTokenHandlerSwap1 is IBTokenHandler {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant Q112 = 2**112;

    address public immutable pool;

    address public immutable router;
    address public immutable pair;
    address public immutable quote;
    address public immutable base;
    uint256 public immutable qDecimals;
    uint256 public immutable bDecimals;
    bool    public immutable isQuoteToken0;

    uint256 public priceCumulativeLast1;
    uint256 public priceCumulativeLast2;
    uint256 public timestampLast1;
    uint256 public timestampLast2;

    address public controller;

    modifier _pool_() {
        // require(msg.sender == pool, 'BTokenHandlerSwap1: only pool');
        _;
    }

    constructor (address pool_, address router_, address pair_, address quote_, address base_, bool isQuoteToken0_) {
        pool = pool_;

        router = router_;
        pair = pair_;
        quote = quote_;
        base = base_;
        qDecimals = IERC20(quote_).decimals();
        bDecimals = IERC20(base_).decimals();
        isQuoteToken0 = isQuoteToken0_;

        IUniswapV2Pair p = IUniswapV2Pair(pair_);
        priceCumulativeLast2 = isQuoteToken0_ ? p.price0CumulativeLast() : p.price1CumulativeLast();
        (, , timestampLast2) = p.getReserves();

        IERC20(quote_).safeApprove(router_, type(uint256).max);
        IERC20(base_).safeApprove(router_, type(uint256).max);

        controller = msg.sender;
    }

    function getPrice() public override _pool_ returns (uint256) {
        IUniswapV2Pair p = IUniswapV2Pair(pair);
        uint256 reserve0;
        uint256 reserve1;
        uint256 timestamp;
        if (isQuoteToken0) {
            (reserve0, reserve1, timestamp) = p.getReserves();
        } else {
            (reserve1, reserve0, timestamp) = p.getReserves();
        }

        if (timestamp != timestampLast2) {
            priceCumulativeLast1 = priceCumulativeLast2;
            timestampLast1 = timestampLast2;
            priceCumulativeLast2 = isQuoteToken0 ? p.price0CumulativeLast() : p.price1CumulativeLast();
            timestampLast2 = timestamp;
        }

        uint256 price;
        if (timestampLast1 != 0) {
            price = (priceCumulativeLast2 - priceCumulativeLast1) / (timestampLast2 - timestampLast1) * 10**(18 + qDecimals - bDecimals) / Q112;
        } else {
            price = reserve1 * 10**(18 + qDecimals - bDecimals) / reserve0;
        }

        return price;
    }

    function swapExactBaseForQuote(uint256 amountB) public override _pool_ returns (uint256 resultB, uint256 resultQ) {
        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);

        resultB = amountB;
        amountB = amountB.rescale(18, bDecimals);
        b.safeTransferFrom(pool, address(this), amountB);
        _swapExactTokensForTokens(base, quote);

        resultQ = q.balanceOf(address(this));
        q.safeTransfer(pool, resultQ);
        resultQ = resultQ.rescale(qDecimals, 18);
    }

    function swapExactQuoteForBase(uint256 amountQ) public override _pool_ returns (uint256 resultB, uint256 resultQ) {
        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);

        resultQ = amountQ;
        amountQ = amountQ.rescale(18, qDecimals);
        q.safeTransferFrom(pool, address(this), amountQ);
        _swapExactTokensForTokens(quote, base);

        resultB = b.balanceOf(address(this));
        b.safeTransfer(pool, resultB);
        resultB = resultB.rescale(bDecimals, 18);
    }

    function swapBaseForExactQuote(uint256 amountB, uint256 amountQ) public override _pool_ returns (uint256 resultB, uint256 resultQ) {
        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);

        uint256 b1 = b.balanceOf(pool);
        uint256 q1 = q.balanceOf(pool);

        amountB = amountB.rescale(18, bDecimals);
        amountQ = amountQ.rescale(18, qDecimals);
        b.safeTransferFrom(pool, address(this), amountB);
        if (amountB >= _getAmountIn(amountQ, true) * 11 / 10) {
            _swapTokensForExactTokens(base, quote, amountQ);
        } else {
            _swapExactTokensForTokens(base, quote);
        }

        b.safeTransfer(pool, b.balanceOf(address(this)));
        q.safeTransfer(pool, q.balanceOf(address(this)));

        uint256 b2 = b.balanceOf(pool);
        uint256 q2 = q.balanceOf(pool);

        resultB = (b1 - b2).rescale(bDecimals, 18);
        resultQ = (q2 - q1).rescale(qDecimals, 18);
    }

    function swapQuoteForExactBase(uint256 amountB, uint256 amountQ) public override _pool_ returns (uint256 resultB, uint256 resultQ) {
        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);

        uint256 b1 = b.balanceOf(pool);
        uint256 q1 = q.balanceOf(pool);

        amountB = amountB.rescale(18, bDecimals);
        amountQ = amountQ.rescale(18, qDecimals);
        q.safeTransferFrom(pool, address(this), amountQ);
        if (amountQ >= _getAmountIn(amountB, false) * 11 / 10) {
            _swapTokensForExactTokens(quote, base, amountB);
        } else {
            _swapExactTokensForTokens(quote, base);
        }

        b.safeTransfer(pool, b.balanceOf(address(this)));
        q.safeTransfer(pool, q.balanceOf(address(this)));

        uint256 b2 = b.balanceOf(pool);
        uint256 q2 = q.balanceOf(pool);

        resultB = (b2 - b1).rescale(bDecimals, 18);
        resultQ = (q1 - q2).rescale(qDecimals, 18);
    }

    function sync() public override {
        require(msg.sender == controller, 'only controller');
        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);
        if (b.balanceOf(address(this)) != 0) b.safeTransfer(controller, b.balanceOf(address(this)));
        if (q.balanceOf(address(this)) != 0) q.safeTransfer(controller, q.balanceOf(address(this)));
    }


    //================================================================================

    function _getAmountIn(uint256 amountOut, bool isBaseIn) internal view returns (uint256) {
        uint256 reserve0;
        uint256 reserve1;
        if (isQuoteToken0) {
            (reserve0, reserve1, ) = IUniswapV2Pair(pair).getReserves();
        } else {
            (reserve1, reserve0, ) = IUniswapV2Pair(pair).getReserves();
        }
        uint amountIn;
        if (isBaseIn) {
            amountIn = IUniswapV2Router02(router).getAmountIn(amountOut, reserve1, reserve0);
        } else {
            amountIn = IUniswapV2Router02(router).getAmountIn(amountOut, reserve0, reserve1);
        }
        return amountIn;
    }

    function _swapExactTokensForTokens(address a, address b) internal {
        address[] memory path = new address[](2);
        path[0] = a;
        path[1] = b;

        IUniswapV2Router02(router).swapExactTokensForTokens(
            IERC20(a).balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp + 3600
        );
    }

    function _swapTokensForExactTokens(address a, address b, uint256 amount) internal {
        address[] memory path = new address[](2);
        path[0] = a;
        path[1] = b;

        IUniswapV2Router02(router).swapTokensForExactTokens(
            amount,
            IERC20(a).balanceOf(address(this)),
            path,
            address(this),
            block.timestamp + 3600
        );
    }

}
