// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IBTokenSwapper.sol';
import '../interface/IERC20.sol';
import '../interface/IUniswapV2Pair.sol';
import '../interface/IUniswapV2Router02.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';

abstract contract BTokenSwapper is IBTokenSwapper {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // address of the quoted token, e.x. WETH
    address public immutable quote;
    // address of the base token, this is the base0 token (settlement token) of PerpetualPool, e.x. USDT
    address public immutable base;
    uint256 public immutable qDecimals;
    uint256 public immutable bDecimals;

    constructor (address quote_, address base_) {
        quote = quote_;
        base = base_;
        qDecimals = IERC20(quote_).decimals();
        bDecimals = IERC20(base_).decimals();
    }

    // swap exact amount of base token `amountB` for quote token
    function swapExactBaseForQuote(uint256 amountB) public override returns (uint256 resultB, uint256 resultQ) {
        address caller = msg.sender;

        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);

        uint256 q1 = q.balanceOf(caller);
        amountB = amountB.rescale(18, bDecimals);
        b.safeTransferFrom(caller, address(this), amountB);
        _swapExactTokensForTokens(base, quote, caller);
        uint256 q2 = q.balanceOf(caller);

        resultB = amountB.rescale(bDecimals, 18);
        resultQ = (q2 - q1).rescale(qDecimals, 18);
    }

    // swap exact amount of quote token `amountQ` for base token
    function swapExactQuoteForBase(uint256 amountQ) public override returns (uint256 resultB, uint256 resultQ) {
        address caller = msg.sender;

        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);

        uint256 b1 = b.balanceOf(caller);
        amountQ = amountQ.rescale(18, qDecimals);
        q.safeTransferFrom(caller, address(this), amountQ);
        _swapExactTokensForTokens(quote, base, caller);
        uint256 b2 = b.balanceOf(caller);

        resultB = (b2 - b1).rescale(bDecimals, 18);
        resultQ = amountQ.rescale(qDecimals, 18);
    }

    // swap max amount of base token `amountB` for exact amount of quote token `amountQ`
    // in case `amountB` is sufficient enough, the remains will be sent back
    // in case `amountB` is insufficient, it will be used up to swap for quote token
    function swapBaseForExactQuote(uint256 amountB, uint256 amountQ) public override returns (uint256 resultB, uint256 resultQ) {
        address caller = msg.sender;

        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);

        uint256 b1 = b.balanceOf(caller);
        uint256 q1 = q.balanceOf(caller);

        amountB = amountB.rescale(18, bDecimals);
        amountQ = amountQ.rescale(18, qDecimals);
        b.safeTransferFrom(caller, address(this), amountB);
        if (amountB >= _getBaseAmountIn(amountQ) * 11 / 10) {
            _swapTokensForExactTokens(base, quote, amountQ, caller);
        } else {
            _swapExactTokensForTokens(base, quote, caller);
        }

        uint256 remainB = b.balanceOf(address(this));
        if (resultB != 0) b.safeTransfer(caller, remainB);

        uint256 b2 = b.balanceOf(caller);
        uint256 q2 = q.balanceOf(caller);

        resultB = (b1 - b2).rescale(bDecimals, 18);
        resultQ = (q2 - q1).rescale(qDecimals, 18);
    }

    // swap max amount of quote token `amountQ` for exact amount of base token `amountB`
    // in case `amountQ` if sufficient enough, the remains will be sent back
    // in case `amountB` is insufficient, it will be used up to swap for base token
    function swapQuoteForExactBase(uint256 amountB, uint256 amountQ) public override returns (uint256 resultB, uint256 resultQ) {
        address caller = msg.sender;

        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);

        uint256 b1 = b.balanceOf(caller);
        uint256 q1 = q.balanceOf(caller);

        amountB = amountB.rescale(18, bDecimals);
        amountQ = amountQ.rescale(18, qDecimals);
        q.safeTransferFrom(caller, address(this), amountQ);
        if (amountQ >= _getQuoteAmountIn(amountB) * 11 / 10) {
            _swapTokensForExactTokens(quote, base, amountB, caller);
        } else {
            _swapExactTokensForTokens(quote, base, caller);
        }

        uint256 remainQ = q.balanceOf(address(this));
        if (remainQ != 0) q.safeTransfer(caller, remainQ);

        uint256 b2 = b.balanceOf(caller);
        uint256 q2 = q.balanceOf(caller);

        resultB = (b2 - b1).rescale(bDecimals, 18);
        resultQ = (q1 - q2).rescale(qDecimals, 18);
    }

    // in case someone send base/quote tokens to this contract,
    // the previous functions might be blocked
    // anyone can call this function to withdraw any remaining base/quote tokens in this contract
    // idealy, this contract should have no balance for base/quote tokens
    function sync() public override {
        IERC20 b = IERC20(base);
        IERC20 q = IERC20(quote);
        if (b.balanceOf(address(this)) != 0) b.safeTransfer(msg.sender, b.balanceOf(address(this)));
        if (q.balanceOf(address(this)) != 0) q.safeTransfer(msg.sender, q.balanceOf(address(this)));
    }

    //================================================================================

    // estimate the base token amount needed to swap for `quoteAmountOut` quote tokens
    function _getBaseAmountIn(uint256 quoteAmountOut) internal virtual view returns (uint256);

    // estimate the quote token amount needed to swap for `baseAmountOut` base tokens
    function _getQuoteAmountIn(uint256 baseAmountOut) internal virtual view returns (uint256);

    // low-level swap function
    function _swapExactTokensForTokens(address a, address b, address to) internal virtual;

    // low-level swap function
    function _swapTokensForExactTokens(address a, address b, uint256 amount, address to) internal virtual;

}
