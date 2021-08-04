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

    uint256 constant UONE = 10**18;

    // address of the tokenBX, e.x. WETH
    address public immutable addressBX;
    // address of the tokenB0, this is the base0 token (settlement token) of PerpetualPool, e.x. USDT
    address public immutable addressB0;
    uint256 public immutable decimalsBX;
    uint256 public immutable decimalsB0;
    uint256 public immutable maxSlippageRatio;

    constructor (address addressBX_, address addressB0_, uint256 maxSlippageRatio_) {
        addressBX = addressBX_;
        addressB0 = addressB0_;
        decimalsBX = IERC20(addressBX_).decimals();
        decimalsB0 = IERC20(addressB0_).decimals();
        maxSlippageRatio = maxSlippageRatio_;
    }

    // swap exact `amountB0` amount of tokenB0 for tokenBX
    function swapExactB0ForBX(uint256 amountB0, uint256 referencePrice) external override returns (uint256 resultB0, uint256 resultBX) {
        address caller = msg.sender;

        IERC20 tokenB0 = IERC20(addressB0);
        IERC20 tokenBX = IERC20(addressBX);

        uint256 bx1 = tokenBX.balanceOf(caller);
        amountB0 = amountB0.rescale(18, decimalsB0);

        if (amountB0 == 0) {
            return (0, 0);
        }

        tokenB0.safeTransferFrom(caller, address(this), amountB0);
        _swapExactTokensForTokens(addressB0, addressBX, caller);
        uint256 bx2 = tokenBX.balanceOf(caller);

        resultB0 = amountB0.rescale(decimalsB0, 18);
        resultBX = (bx2 - bx1).rescale(decimalsBX, 18);

        require(
            resultBX * referencePrice >= resultB0  * (UONE - maxSlippageRatio),
            'BTokenSwapper.swapExactB0ForBX: slippage exceeds allowance'
        );
    }

    // swap exact `amountBX` amount of tokenBX token for tokenB0
    function swapExactBXForB0(uint256 amountBX, uint256 referencePrice) external override returns (uint256 resultB0, uint256 resultBX) {
        address caller = msg.sender;

        IERC20 tokenB0 = IERC20(addressB0);
        IERC20 tokenBX = IERC20(addressBX);

        uint256 b01 = tokenB0.balanceOf(caller);
        amountBX = amountBX.rescale(18, decimalsBX);

        if (amountBX == 0) {
            return (0, 0);
        }

        tokenBX.safeTransferFrom(caller, address(this), amountBX);
        _swapExactTokensForTokens(addressBX, addressB0, caller);
        uint256 b02 = tokenB0.balanceOf(caller);

        resultB0 = (b02 - b01).rescale(decimalsB0, 18);
        resultBX = amountBX.rescale(decimalsBX, 18);

        require(
            resultB0 * UONE >= resultBX * referencePrice / UONE * (UONE - maxSlippageRatio),
            'BTokenSwapper.swapExactBXForB0: slippage exceeds allowance'
        );
    }

    // swap max amount of tokenB0 `amountB0` for exact amount of tokenBX `amountBX`
    // in case `amountB0` is sufficient, the remains will be sent back
    // in case `amountB0` is insufficient, it will be used up to swap for tokenBX
    function swapB0ForExactBX(uint256 amountB0, uint256 amountBX, uint256 referencePrice) external override returns (uint256 resultB0, uint256 resultBX) {
        address caller = msg.sender;

        IERC20 tokenB0 = IERC20(addressB0);
        IERC20 tokenBX = IERC20(addressBX);

        uint256 b01 = tokenB0.balanceOf(caller);
        uint256 bx1 = tokenBX.balanceOf(caller);

        amountB0 = amountB0.rescale(18, decimalsB0);
        amountBX = amountBX.rescale(18, decimalsBX);

        if (amountB0 == 0 || amountBX == 0) {
            return (0, 0);
        }

        tokenB0.safeTransferFrom(caller, address(this), amountB0);
        if (amountB0 >= _getAmountInB0(amountBX) * 11 / 10) {
            _swapTokensForExactTokens(addressB0, addressBX, amountBX, caller);
        } else {
            _swapExactTokensForTokens(addressB0, addressBX, caller);
        }

        uint256 remainB0 = tokenB0.balanceOf(address(this));
        if (remainB0 != 0) tokenB0.safeTransfer(caller, remainB0);

        uint256 b02 = tokenB0.balanceOf(caller);
        uint256 bx2 = tokenBX.balanceOf(caller);

        resultB0 = (b01 - b02).rescale(decimalsB0, 18);
        resultBX = (bx2 - bx1).rescale(decimalsBX, 18);

        require(
            resultBX * referencePrice >= resultB0  * (UONE - maxSlippageRatio),
            'BTokenSwapper.swapB0ForExactBX: slippage exceeds allowance'
        );
    }

    // swap max amount of tokenBX `amountBX` for exact amount of tokenB0 `amountB0`
    // in case `amountBX` is sufficient, the remains will be sent back
    // in case `amountBX` is insufficient, it will be used up to swap for tokenB0
    function swapBXForExactB0(uint256 amountB0, uint256 amountBX, uint256 referencePrice) external override returns (uint256 resultB0, uint256 resultBX) {
        address caller = msg.sender;

        IERC20 tokenB0 = IERC20(addressB0);
        IERC20 tokenBX = IERC20(addressBX);

        uint256 b01 = tokenB0.balanceOf(caller);
        uint256 bx1 = tokenBX.balanceOf(caller);

        amountB0 = amountB0.rescale(18, decimalsB0);
        amountBX = amountBX.rescale(18, decimalsBX);

        if (amountB0 == 0 || amountBX == 0) {
            return (0, 0);
        }

        tokenBX.safeTransferFrom(caller, address(this), amountBX);
        if (amountBX >= _getAmountInBX(amountB0) * 11 / 10) {
            _swapTokensForExactTokens(addressBX, addressB0, amountB0, caller);
        } else {
            _swapExactTokensForTokens(addressBX, addressB0, caller);
        }

        uint256 remainBX = tokenBX.balanceOf(address(this));
        if (remainBX != 0) tokenBX.safeTransfer(caller, remainBX);

        uint256 b02 = tokenB0.balanceOf(caller);
        uint256 bx2 = tokenBX.balanceOf(caller);

        resultB0 = (b02 - b01).rescale(decimalsB0, 18);
        resultBX = (bx1 - bx2).rescale(decimalsBX, 18);

        require(
            resultB0 * UONE >= resultBX * referencePrice / UONE * (UONE - maxSlippageRatio),
            'BTokenSwapper.swapBXForExactB0: slippage exceeds allowance'
        );
    }

    // in case someone send tokenB0/tokenBX to this contract,
    // the previous functions might be blocked
    // anyone can call this function to withdraw any remaining tokenB0/tokenBX in this contract
    // idealy, this contract should have no balance for tokenB0/tokenBX
    function sync() external override {
        IERC20 tokenB0 = IERC20(addressB0);
        IERC20 tokenBX = IERC20(addressBX);
        if (tokenB0.balanceOf(address(this)) != 0) tokenB0.safeTransfer(msg.sender, tokenB0.balanceOf(address(this)));
        if (tokenBX.balanceOf(address(this)) != 0) tokenBX.safeTransfer(msg.sender, tokenBX.balanceOf(address(this)));
    }

    //================================================================================

    // estimate the tokenB0 amount needed to swap for `amountOutBX` tokenBX
    function _getAmountInB0(uint256 amountOutBX) internal virtual view returns (uint256);

    // estimate the tokenBX amount needed to swap for `amountOutB0` tokenB0
    function _getAmountInBX(uint256 amountOutB0) internal virtual view returns (uint256);

    // low-level swap function
    function _swapExactTokensForTokens(address a, address b, address to) internal virtual;

    // low-level swap function
    function _swapTokensForExactTokens(address a, address b, uint256 amount, address to) internal virtual;

}
