// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/IOracle.sol';
import '../interface/ILToken.sol';
import '../interface/IPToken.sol';
import '../interface/IDeriRouter.sol';
import '../interface/IPerpetualPool.sol';
import '../interface/ILiquidatorQualifier.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';
import '../utils/Ownable.sol';

contract DeriRouter is IDeriRouter, Ownable {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    address _pool;
    address _liquidatorQualifierAddress;

    BToken[] _bTokens; // bTokenId indexed
    Symbol[] _symbols; // symbolId indexed

    constructor () {
        _controller = msg.sender;
    }

    function setPool(address poolAddress) public override _controller_ {
        _pool = poolAddress;
    }

    function setLiquidatorQualifierAddress(address qualifierAddress) public override _controller_ {
        _liquidatorQualifierAddress = qualifierAddress;
    }

    function addBToken(
        address bTokenAddress,
        address handlerAddress,
        uint256 discount
    ) public override _controller_ {
        BToken memory b;
        b.bTokenAddress = bTokenAddress;
        b.handlerAddress = handlerAddress;
        b.decimals = IERC20(bTokenAddress).decimals();
        b.discount = b.discount;
        _bTokens.push(b);
        IPerpetualPool(_pool).addBToken(bTokenAddress, handlerAddress, discount);
    }

    function addSymbol(
        string  memory symbol,
        address handlerAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 fundingRateCoefficient
    ) public override _controller_ {
        Symbol memory s;
        s.symbol = symbol;
        s.handlerAddress = handlerAddress;
        s.multiplier = multiplier;
        s.feeRatio = feeRatio;
        s.fundingRateCoefficient = fundingRateCoefficient;
        _symbols.push(s);
        IPerpetualPool(_pool).addSymbol(symbol, multiplier, feeRatio, fundingRateCoefficient);
    }


    //================================================================================
    // Interactions
    //================================================================================

    function addLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        int256[] memory bPrices = _getBTokenPrices();
        int256[] memory sPrices = _getSymbolPrices();
        IPerpetualPool(_pool).addLiquidity(msg.sender, bTokenId, bAmount, bPrices, sPrices);
    }

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        int256[] memory bPrices = _getBTokenPrices();
        int256[] memory sPrices = _getSymbolPrices();
        IPerpetualPool(_pool).removeLiquidity(msg.sender, bTokenId, bAmount, bPrices, sPrices);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool(_pool).addMargin(msg.sender, bTokenId, bAmount);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public override {
        int256[] memory bPrices = _getBTokenPrices();
        int256[] memory sPrices = _getSymbolPrices();
        IPerpetualPool(_pool).removeMargin(msg.sender, bTokenId, bAmount, bPrices, sPrices);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public override {
        int256[] memory bPrices = _getBTokenPrices();
        int256[] memory sPrices = _getSymbolPrices();
        IPerpetualPool(_pool).trade(msg.sender, symbolId, tradeVolume, bPrices, sPrices);
    }

    function liquidate(address owner) public override {
        address liquidator = msg.sender;
        address qualifier = _liquidatorQualifierAddress;
        require(qualifier == address(0) || ILiquidatorQualifier(qualifier).isQualifiedLiquidator(liquidator), 'unqualified');

        int256[] memory bPrices = _getBTokenPrices();
        int256[] memory sPrices = _getSymbolPrices();
        IPerpetualPool(_pool).liquidate(liquidator, owner, bPrices, sPrices);
    }

    //================================================================================
    // Helpers
    //================================================================================

    function _getBTokenPrices() internal returns (int256[] memory) {
        uint256 length = _bTokens.length;
        int256[] memory bPrices = new int256[](length);
        for (uint256 i = 1; i < length; i++) {
            bPrices[i] = IOracle(_bTokens[i].handlerAddress).getPrice().utoi();
        }
        return bPrices;
    }

    function _getSymbolPrices() internal returns (int256[] memory) {
        uint256 length = _symbols.length;
        int256[] memory sPrices = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
            sPrices[i] = IOracle(_symbols[i].handlerAddress).getPrice().utoi();
        }
        return sPrices;
    }

}
