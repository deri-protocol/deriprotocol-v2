// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IBTokenHandler.sol';
import '../interface/IERC20.sol';
import '../interface/IUniswapV2Pair.sol';
import '../interface/IUniswapV2Router02.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';

contract BTokenHandlerSwap2 is IBTokenHandler {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant Q112 = 2**112;

    address public immutable pool;

    address public immutable router;
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

    address public controller;

    modifier _pool_() {
        require(msg.sender == pool, 'BTokenHnadlerSwap2: only pool');
        _;
    }

    constructor (
        address pool_,
        address router_,
        address pairQ_,
        address pairB_,
        address quote_,
        address mid_,
        address base_,
        bool isQuoteToken0_,
        bool isBaseToken0_
    ) {
        pool = pool_;

        router = router_;
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

        IERC20(quote_).safeApprove(router_, type(uint256).max);
        IERC20(base_).safeApprove(router_, type(uint256).max);

        controller = msg.sender;
    }

    function getPrice() public override returns (uint256) {
        IUniswapV2Pair p;
        uint256 reserve0;
        uint256 reserve1;
        uint256 timestamp;

        p = IUniswapV2Pair(pairQ);
        if (isQuoteToken0) {
            (reserve0, reserve1, timestamp) = p.getReserves();
        } else {
            (reserve1, reserve0, timestamp) = p.getReserves();
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
            price1 = reserve1 * 10**(18 + qDecimals - mDecimals) / reserve0;
        }

        p = IUniswapV2Pair(pairB);
        if (isBaseToken0) {
            (reserve1, reserve0, timestamp) = p.getReserves();
        } else {
            (reserve0, reserve1, timestamp) = p.getReserves();
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
            price2 = reserve1 * 10**(18 + mDecimals - bDecimals) / reserve0;
        }

        return price1 * price2 / 10**18;
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
        uint256 reserveQ0;
        uint256 reserveQ1;
        uint256 reserveB0;
        uint256 reserveB1;
        uint256 amountIn;
        if (isQuoteToken0) {
            (reserveQ0, reserveQ1, ) = IUniswapV2Pair(pairQ).getReserves();
        } else {
            (reserveQ1, reserveQ0, ) = IUniswapV2Pair(pairQ).getReserves();
        }
        if (isBaseToken0) {
            (reserveB1, reserveB0, ) = IUniswapV2Pair(pairB).getReserves();
        } else {
            (reserveB0, reserveB1, ) = IUniswapV2Pair(pairB).getReserves();
        }
        if (isBaseIn) {
            uint256 amountMid = IUniswapV2Router02(router).getAmountIn(amountOut, reserveQ1, reserveQ0);
            amountIn = IUniswapV2Router02(router).getAmountIn(amountMid, reserveB1, reserveB0);
        } else {
            uint256 amountMid = IUniswapV2Router02(router).getAmountIn(amountOut, reserveB0, reserveB1);
            amountIn = IUniswapV2Router02(router).getAmountIn(amountMid, reserveQ0, reserveQ1);
        }
        return amountIn;
    }

    function _swapExactTokensForTokens(address a, address b) internal {
        address[] memory path = new address[](3);
        path[0] = a;
        path[1] = mid;
        path[2] = b;

        IUniswapV2Router02(router).swapExactTokensForTokens(
            IERC20(a).balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp + 3600
        );
    }

    function _swapTokensForExactTokens(address a, address b, uint256 amount) internal {
        address[] memory path = new address[](3);
        path[0] = a;
        path[1] = mid;
        path[2] = b;

        IUniswapV2Router02(router).swapTokensForExactTokens(
            amount,
            IERC20(a).balanceOf(address(this)),
            path,
            address(this),
            block.timestamp + 3600
        );
    }

}
