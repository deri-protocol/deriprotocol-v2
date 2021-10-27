// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/IBTokenSwapper.sol';
import '../interface/IOracleWithUpdate.sol';
import '../interface/IPToken.sol';
import '../interface/ILToken.sol';
import '../interface/IPerpetualPool.sol';
import '../interface/IPerpetualPoolOld.sol';
import '../interface/IPerpetualPoolRouter.sol';
import '../interface/ILiquidatorQualifier.sol';
import '../library/SafeMath.sol';
import '../utils/Migratable.sol';

contract PerpetualPoolRouter is IPerpetualPoolRouter, Migratable {

    using SafeMath for uint256;
    using SafeMath for int256;

    int256 constant ONE = 1e18;

    address _pool;
    address _liquidatorQualifierAddress;
    address immutable _lTokenAddress;
    address immutable _pTokenAddress;

    constructor (
        address lTokenAddress,
        address pTokenAddress,
        address liquidatorQualifierAddress
    ) {
        _lTokenAddress = lTokenAddress;
        _pTokenAddress = pTokenAddress;
        _liquidatorQualifierAddress = liquidatorQualifierAddress;

        _controller = msg.sender;
    }

    function pool() external override view returns (address) {
        return _pool;
    }

    function liquidatorQualifier() external override view returns (address) {
        return _liquidatorQualifierAddress;
    }

    function setPool(address poolAddress) external override _controller_ {
        _pool = poolAddress;
    }

    function setLiquidatorQualifier(address qualifierAddress) external override _controller_ {
        _liquidatorQualifierAddress = qualifierAddress;
    }

    // during a migration, this function is intended to be called in the source router
    function approveMigration() external override _controller_ {
        require(_migrationTimestamp != 0 && block.timestamp >= _migrationTimestamp, 'migration time not met');
        address targetPool = IPerpetualPoolRouter(_migrationDestination).pool();
        (uint256 blength, ) = IPerpetualPool(_pool).getLengths();
        for (uint256 i = 0; i < blength; i++) {
            IPerpetualPool(_pool).approveBTokenForTargetPool(i, targetPool);
        }
        IPerpetualPool(_pool).setPoolForLTokenAndPToken(targetPool);
    }

    function executeMigration(address sourceRouter) external override _controller_ {}

    // during a migration, this function is intended to be called in the target router
    function executeMigrationWithTimestamp(address sourceRouter, uint256 lastTimestamp) external _controller_ {
        uint256 migrationTimestamp_ = IPerpetualPoolRouter(sourceRouter).migrationTimestamp();
        address migrationDestination_ = IPerpetualPoolRouter(sourceRouter).migrationDestination();
        require(migrationTimestamp_ != 0 && block.timestamp >= migrationTimestamp_, 'migration time not met');
        require(migrationDestination_ == address(this), 'migration wrong target');

        address sourcePool = IPerpetualPoolRouter(sourceRouter).pool();
        (uint256 blength, uint256 slength) = IPerpetualPoolOld(sourcePool).getLengths();

        for (uint256 i = 0; i < blength; i++) {
            IPerpetualPoolOld.BTokenInfo memory b = IPerpetualPoolOld(sourcePool).getBToken(i);
            IPerpetualPool(_pool).migrateBToken(
                sourcePool,
                IERC20(b.bTokenAddress).balanceOf(sourcePool),
                b.bTokenAddress,
                b.swapperAddress,
                b.oracleAddress,
                b.decimals,
                b.discount,
                b.liquidity,
                b.pnl,
                b.cumulativePnl
            );
        }

        for (uint256 i = 0; i < slength; i++) {
            IPerpetualPoolOld.SymbolInfo memory s = IPerpetualPoolOld(sourcePool).getSymbol(i);
            int256 distributedUnrealizedPnl = s.tradersNetVolume * s.price / ONE * s.multiplier / ONE - s.tradersNetCost;
            IPerpetualPool(_pool).migrateSymbol(
                s.symbol,
                s.oracleAddress,
                s.multiplier,
                s.feeRatio,
                ONE * 3 / 10, // alpha 0.3
                distributedUnrealizedPnl,
                s.tradersNetVolume,
                s.tradersNetCost,
                s.cumulativeFundingRate
            );
        }

        IPerpetualPool(_pool).migratePoolStateValues(
            lastTimestamp,
            IPerpetualPoolOld(sourcePool).getProtocolFeeAccrued()
        );
    }

    function addBToken(
        address bTokenAddress,
        address swapperAddress,
        address oracleAddress,
        uint256 discount
    ) external override _controller_ {
        IPerpetualPool.BTokenInfo memory b;
        b.bTokenAddress = bTokenAddress;
        b.swapperAddress = swapperAddress;
        b.oracleAddress = oracleAddress;
        b.decimals = IERC20(bTokenAddress).decimals();
        b.discount = discount.utoi();
        IPerpetualPool(_pool).addBToken(b);
    }

    function addSymbol(
        string memory symbol,
        address oracleAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 alpha
    ) external override _controller_ {
        IPerpetualPool.SymbolInfo memory s;
        s.symbol = symbol;
        s.oracleAddress = oracleAddress;
        s.multiplier = multiplier.utoi();
        s.feeRatio = feeRatio.utoi();
        s.alpha = alpha.utoi();
        IPerpetualPool(_pool).addSymbol(s);
    }

    function setBTokenParameters(
        uint256 bTokenId,
        address swapperAddress,
        address oracleAddress,
        uint256 discount
    ) external override _controller_ {
        IPerpetualPool(_pool).setBTokenParameters(bTokenId, swapperAddress, oracleAddress, discount);
    }

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        uint256 feeRatio,
        uint256 alpha
    ) external override _controller_ {
        IPerpetualPool(_pool).setSymbolParameters(symbolId, oracleAddress, feeRatio, alpha);
    }


    //================================================================================
    // Interactions Set1
    //================================================================================

    function addLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, ) = p.getLengths();

        require(bTokenId < blength, 'invalid bTokenId');

        p.addLiquidity(msg.sender, bTokenId, bAmount);
    }

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, ) = p.getLengths();
        address lp = msg.sender;

        require(bTokenId < blength, 'invalid bTokenId');
        require(ILToken(_lTokenAddress).exists(lp), 'not lp');

        p.removeLiquidity(lp, bTokenId, bAmount);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, ) = p.getLengths();

        require(bTokenId < blength, 'invalid bTokenId');

        p.addMargin(msg.sender, bTokenId, bAmount);
        if (bTokenId != 0) _checkBTokenMarginLimit(bTokenId);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, ) = p.getLengths();
        address trader = msg.sender;

        require(bTokenId < blength, 'invalid bTokenId');
        require(IPToken(_pTokenAddress).exists(trader), 'no trade / no pos');

        p.removeMargin(trader, bTokenId, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (, uint256 slength) = p.getLengths();
        address trader = msg.sender;

        require(symbolId < slength, 'invalid symbolId');
        require(IPToken(_pTokenAddress).exists(trader), 'no trade / no pos');

        p.trade(trader, symbolId, tradeVolume);
    }

    function liquidate(address trader) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        address liquidator = msg.sender;

        require(IPToken(_pTokenAddress).exists(trader), 'no trade / no pos');
        require(
            _liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(liquidator),
            'not qualified'
        );

        p.liquidate(liquidator, trader);
    }

    function liquidate(uint256 pTokenId) public override {
        liquidate(IPToken(_pTokenAddress).ownerOf(pTokenId));
    }


    //================================================================================
    // Interactions Set2 (supporting oracles which need manual update)
    //================================================================================

    function addLiquidityWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) external override {
        _updateSymbolOracles(infos);
        addLiquidity(bTokenId, bAmount);
    }

    function removeLiquidityWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) external override {
        _updateSymbolOracles(infos);
        removeLiquidity(bTokenId, bAmount);
    }

    function addMarginWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) external override {
        _updateSymbolOracles(infos);
        addMargin(bTokenId, bAmount);
    }

    function removeMarginWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) external override {
        _updateSymbolOracles(infos);
        removeMargin(bTokenId, bAmount);
    }

    function tradeWithPrices(uint256 symbolId, int256 tradeVolume, PriceInfo[] memory infos) external override {
        _updateSymbolOracles(infos);
        trade(symbolId, tradeVolume);
    }

    function liquidateWithPrices(address trader, PriceInfo[] memory infos) external override {
        _updateSymbolOracles(infos);
        liquidate(trader);
    }

    function liquidateWithPrices(uint256 pTokenId, PriceInfo[] memory infos) external override {
        _updateSymbolOracles(infos);
        liquidate(pTokenId);
    }


    //================================================================================
    // Helpers
    //================================================================================

    function _updateSymbolOracles(PriceInfo[] memory infos) internal {
        for (uint256 i = 0; i < infos.length; i++) {
            address oracle = IPerpetualPool(_pool).getSymbolOracle(infos[i].symbolId);
            IOracleWithUpdate(oracle).updatePrice(infos[i].timestamp, infos[i].price, infos[i].v, infos[i].r, infos[i].s);
        }
    }

    function _checkBTokenMarginLimit(uint256 bTokenId) internal view {
        IPerpetualPool.BTokenInfo memory b = IPerpetualPool(_pool).getBToken(bTokenId);
        IERC20 bToken = IERC20(b.bTokenAddress);
        uint256 balance = bToken.balanceOf(_pool).rescale(bToken.decimals(), 18);
        uint256 marginBX = balance - b.liquidity.itou();
        uint256 limit = IBTokenSwapper(b.swapperAddress).getLimitBX();
        require(marginBX < limit, 'margin in bTokenX exceeds swapper liquidity limit');
    }

}
