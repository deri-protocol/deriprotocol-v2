// SPDX-License-Identifier: MIT

import '../interface/IERC20.sol';
import '../interface/IOracleWithUpdate.sol';
import '../interface/IPToken.sol';
import '../interface/ILToken.sol';
import '../interface/IPerpetualPool.sol';
import '../interface/IPerpetualPoolRouter.sol';
import '../interface/ILiquidatorQualifier.sol';
import '../utils/Migratable.sol';

pragma solidity >=0.8.0 <0.9.0;

contract PerpetualPoolRouter is IPerpetualPoolRouter, Migratable {

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

    function pool() public override view returns (address) {
        return _pool;
    }

    function liquidatorQualifier() public override view returns (address) {
        return _liquidatorQualifierAddress;
    }

    function setPool(address poolAddress) public override _controller_ {
        _pool = poolAddress;
    }

    function setLiquidatorQualifier(address qualifierAddress) public override _controller_ {
        _liquidatorQualifierAddress = qualifierAddress;
    }

    // during a migration, this function is intended to be called in the source router
    function approveMigration() public override _controller_ {
        require(_migrationTimestamp != 0 && block.timestamp >= _migrationTimestamp, 'migration time not met');
        address targetPool = IPerpetualPoolRouter(_migrationDestination).pool();
        IPerpetualPool(_pool).approvePoolMigration(targetPool);
    }

    // during a migration, this function is intended to be called in the target router
    function executeMigration(address sourceRouter) public override _controller_ {
        uint256 migrationTimestamp_ = IPerpetualPoolRouter(sourceRouter).migrationTimestamp();
        address migrationDestination_ = IPerpetualPoolRouter(sourceRouter).migrationDestination();

        require(migrationTimestamp_ != 0 && block.timestamp >= migrationTimestamp_, 'migration time not met');
        require(migrationDestination_ == address(this), 'migration wrong target');

        address sourcePool = IPerpetualPoolRouter(sourceRouter).pool();
        IPerpetualPool(_pool).executePoolMigration(sourcePool);
    }

    function addBToken(
        address bTokenAddress,
        address swapperAddress,
        address oracleAddress,
        uint256 discount
    )
        public override _controller_
    {
        IPerpetualPool.BTokenInfo memory b;
        b.bTokenAddress = bTokenAddress;
        b.swapperAddress = swapperAddress;
        b.oracleAddress = oracleAddress;
        b.decimals = IERC20(bTokenAddress).decimals();
        b.discount = int256(discount);
        IPerpetualPool(_pool).addBToken(b);
    }

    function addSymbol(
        string memory symbol,
        address oracleAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 fundingRateCoefficient
    )
        public override _controller_
    {
        IPerpetualPool.SymbolInfo memory s;
        s.symbol = symbol;
        s.oracleAddress = oracleAddress;
        s.multiplier = int256(multiplier);
        s.feeRatio = int256(feeRatio);
        s.fundingRateCoefficient = int256(fundingRateCoefficient);
        IPerpetualPool(_pool).addSymbol(s);
    }

    function setBTokenParameters(
        uint256 bTokenId,
        address swapperAddress,
        address oracleAddress,
        uint256 discount
    )
        public override _controller_
    {
        IPerpetualPool(_pool).setBTokenParameters(bTokenId, swapperAddress, oracleAddress, discount);
    }

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        uint256 feeRatio,
        uint256 fundingRateCoefficient
    )
        public override _controller_
    {
        IPerpetualPool(_pool).setSymbolParameters(symbolId, oracleAddress, feeRatio, fundingRateCoefficient);
    }


    //================================================================================
    // Interactions Set1
    //================================================================================

    function addLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, uint256 slength) = p.getLengths();

        require(bTokenId < blength, 'invalid bTokenId');

        p.addLiquidity(msg.sender, bTokenId, bAmount, blength, slength);
    }

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, uint256 slength) = p.getLengths();

        address owner = msg.sender;
        require(bTokenId < blength, 'invalid bTokenId');
        require(ILToken(_lTokenAddress).exists(owner), 'not lp');

        p.removeLiquidity(owner, bTokenId, bAmount, blength, slength);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, ) = p.getLengths();

        require(bTokenId < blength, 'invalid bTokenId');

        p.addMargin(msg.sender, bTokenId, bAmount);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, uint256 slength) = p.getLengths();

        address owner = msg.sender;
        require(bTokenId < blength, 'invalid bTokenId');
        require(IPToken(_pTokenAddress).exists(owner), 'no trade / no pos');

        p.removeMargin(owner, bTokenId, bAmount, blength, slength);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, uint256 slength) = p.getLengths();

        address owner = msg.sender;
        require(symbolId < slength, 'invalid symbolId');
        require(IPToken(_pTokenAddress).exists(owner), 'no trade / no pos');

        p.trade(owner, symbolId, tradeVolume, blength, slength);
    }

    function liquidate(address owner) public override {
        IPerpetualPool p = IPerpetualPool(_pool);
        (uint256 blength, uint256 slength) = p.getLengths();

        address liquidator = msg.sender;
        require(IPToken(_pTokenAddress).exists(owner), 'no trade / no pos');
        require(_liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(liquidator),
                'not qualified');

        p.liquidate(liquidator, owner, blength, slength);
    }


    //================================================================================
    // Interactions Set2 (supporting oracles which need manual update)
    //================================================================================

    function addLiquidityWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) public override {
        _updateSymbolOracles(infos);
        addLiquidity(bTokenId, bAmount);
    }

    function removeLiquidityWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) public override {
        _updateSymbolOracles(infos);
        removeLiquidity(bTokenId, bAmount);
    }

    function addMarginWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) public override {
        _updateSymbolOracles(infos);
        addMargin(bTokenId, bAmount);
    }

    function removeMarginWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) public override {
        _updateSymbolOracles(infos);
        removeMargin(bTokenId, bAmount);
    }

    function tradeWithPrices(uint256 symbolId, int256 tradeVolume, PriceInfo[] memory infos) public override {
        _updateSymbolOracles(infos);
        trade(symbolId, tradeVolume);
    }

    function liquidateWithPrices(address owner, PriceInfo[] memory infos) public override {
        _updateSymbolOracles(infos);
        liquidate(owner);
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

}
