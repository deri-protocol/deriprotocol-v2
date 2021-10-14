// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IPerpetualPoolLiteOld.sol';
import '../interface/IPerpetualPoolLite.sol';
import '../interface/ILTokenLite.sol';
import '../interface/IPTokenLite.sol';
import '../interface/IERC20.sol';
import '../interface/IOracleViewer.sol';
import '../interface/IOracleWithUpdate.sol';
import '../interface/ILiquidatorQualifier.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';
import '../library/DpmmPricerFutures.sol';
import '../utils/Migratable.sol';

contract PerpetualPoolLite is IPerpetualPoolLite, Migratable {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256  constant ONE = 10**18;

    uint256 immutable _decimals;
    int256  immutable _poolMarginRatio;
    int256  immutable _initialMarginRatio;
    int256  immutable _maintenanceMarginRatio;
    int256  immutable _minLiquidationReward;
    int256  immutable _maxLiquidationReward;
    int256  immutable _liquidationCutRatio;
    int256  immutable _protocolFeeCollectRatio;

    address immutable _bTokenAddress;
    address immutable _lTokenAddress;
    address immutable _pTokenAddress;
    address immutable _liquidatorQualifierAddress;
    address immutable _protocolFeeCollector;

    // funding period in seconds, funding collected for each volume during this period will be (dpmmPrice - indexPrice)
    int256  _fundingPeriod = 3 * 24 * 3600 * ONE;

    int256  _liquidity;
    uint256 _lastTimestamp;
    int256  _protocolFeeAccrued;

    // symbolId => SymbolInfo
    mapping (uint256 => SymbolInfo) _symbols;

    bool private _mutex;
    modifier _lock_() {
        require(!_mutex, 'reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    constructor (uint256[7] memory parameters, address[5] memory addresses) {
        _poolMarginRatio = int256(parameters[0]);
        _initialMarginRatio = int256(parameters[1]);
        _maintenanceMarginRatio = int256(parameters[2]);
        _minLiquidationReward = int256(parameters[3]);
        _maxLiquidationReward = int256(parameters[4]);
        _liquidationCutRatio = int256(parameters[5]);
        _protocolFeeCollectRatio = int256(parameters[6]);

        _bTokenAddress = addresses[0];
        _lTokenAddress = addresses[1];
        _pTokenAddress = addresses[2];
        _liquidatorQualifierAddress = addresses[3];
        _protocolFeeCollector = addresses[4];

        _decimals = IERC20(addresses[0]).decimals();

        _controller = msg.sender;
    }

    // during a migration, this function is intended to be called in the source pool
    function approveMigration() external override _controller_ {
        require(_migrationTimestamp != 0 && block.timestamp >= _migrationTimestamp, 'PerpetualPool: migrationTimestamp not met yet');
        // approve new pool to pull all base tokens from this pool
        IERC20(_bTokenAddress).safeApprove(_migrationDestination, type(uint256).max);
        // set lToken/pToken to new pool, after redirecting pToken/lToken to new pool, this pool will stop functioning
        ILTokenLite(_lTokenAddress).setPool(_migrationDestination);
        IPTokenLite(_pTokenAddress).setPool(_migrationDestination);
    }

    // during a migration, this function is intended to be called in the target pool
    // the original `executeMigration` is just a place holder, instead `executeMigrationSwitchToTimestamp` will be executed during migration
    // in order to change the funding calculation from blocks to timestamp
    function executeMigration(address source) external override _controller_ {}

    function executeMigrationSwitchToTimestamp(address source, uint256 lastBlockNumber, uint256 lastBlockTimestamp) external _controller_ {
        uint256 migrationTimestamp_ = IPerpetualPoolLiteOld(source).migrationTimestamp();
        address migrationDestination_ = IPerpetualPoolLiteOld(source).migrationDestination();

        // transfer bToken to this address
        IERC20(_bTokenAddress).safeTransferFrom(source, address(this), IERC20(_bTokenAddress).balanceOf(source));

        // transfer symbol infos
        uint256[] memory symbolIds = IPTokenLite(_pTokenAddress).getActiveSymbolIds();
        for (uint256 i = 0; i < symbolIds.length; i++) {
            uint256 symbolId = symbolIds[i];
            IPerpetualPoolLiteOld.SymbolInfo memory pre = IPerpetualPoolLiteOld(source).getSymbol(symbolId);
            SymbolInfo memory cur = _symbols[symbolId];
            cur.symbolId = pre.symbolId;
            cur.symbol = pre.symbol;
            cur.oracleAddress = pre.oracleAddress;
            cur.multiplier = pre.multiplier;
            cur.feeRatio = pre.feeRatio;
            cur.alpha = ONE * 3 / 10;
            cur.tradersNetVolume = pre.tradersNetVolume;
            cur.tradersNetCost = pre.tradersNetCost;
            cur.cumulativeFundingRate = pre.cumulativeFundingRate;
        }

        // transfer state values
        _liquidity = IPerpetualPoolLiteOld(source).getLiquidity();
        _protocolFeeAccrued = IPerpetualPoolLiteOld(source).getProtocolFeeAccrued();

        require(IPerpetualPoolLiteOld(source).getLastUpdateBlock() == lastBlockNumber, 'lastBlock mismatch');
        _lastTimestamp = lastBlockTimestamp;

        emit ExecuteMigration(migrationTimestamp_, source, migrationDestination_);
    }

    function getParameters() external override view returns (
        int256 poolMarginRatio,
        int256 initialMarginRatio,
        int256 maintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    ) {
        return (
            _poolMarginRatio,
            _initialMarginRatio,
            _maintenanceMarginRatio,
            _minLiquidationReward,
            _maxLiquidationReward,
            _liquidationCutRatio,
            _protocolFeeCollectRatio
        );
    }

    function getAddresses() external override view returns (
        address bTokenAddress,
        address lTokenAddress,
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address protocolFeeCollector
    ) {
        return (
            _bTokenAddress,
            _lTokenAddress,
            _pTokenAddress,
            _liquidatorQualifierAddress,
            _protocolFeeCollector
        );
    }

    function getSymbol(uint256 symbolId) external override view returns (SymbolInfo memory) {
        return _symbols[symbolId];
    }

    function getPoolStateValues() external view override returns (int256 liquidity, uint256 lastTimestamp, int256 protocolFeeAccrued) {
        return (_liquidity, _lastTimestamp, _protocolFeeAccrued);
    }

    function collectProtocolFee() external override {
        uint256 balance = IERC20(_bTokenAddress).balanceOf(address(this)).rescale(_decimals, 18);
        uint256 amount = _protocolFeeAccrued.itou();
        if (amount > balance) amount = balance;
        _protocolFeeAccrued -= amount.utoi();
        _transferOut(_protocolFeeCollector, amount);
        emit ProtocolFeeCollection(_protocolFeeCollector, amount);
    }

    function getFundingPeriod() external view override returns (int256) {
        return _fundingPeriod;
    }

    function setFundingPeriod(uint256 period) external override _controller_ {
        _fundingPeriod = int256(period);
    }

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        address oracleAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 alpha
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.symbolId = symbolId;
        s.symbol = symbol;
        s.oracleAddress = oracleAddress;
        s.multiplier = int256(multiplier);
        s.feeRatio = int256(feeRatio);
        s.alpha = int256(alpha);
        IPTokenLite(_pTokenAddress).addSymbolId(symbolId);
    }

    function removeSymbol(uint256 symbolId) external override _controller_ {
        delete _symbols[symbolId];
        IPTokenLite(_pTokenAddress).removeSymbolId(symbolId);
    }

    function toggleCloseOnly(uint256 symbolId) external override _controller_ {
        IPTokenLite(_pTokenAddress).toggleCloseOnly(symbolId);
    }

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        uint256 feeRatio,
        uint256 alpha
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.oracleAddress = oracleAddress;
        s.feeRatio = int256(feeRatio);
        s.alpha = int256(alpha);
    }

    //================================================================================
    // Interactions
    //================================================================================

    function addLiquidity(uint256 bAmount, SignedPrice[] memory prices) external override {
        _updateSymbolPrices(prices);
        _addLiquidity(msg.sender, bAmount);
    }

    function removeLiquidity(uint256 lShares, SignedPrice[] memory prices) external override {
        require(lShares > 0, '0 lShares');
        _updateSymbolPrices(prices);
        _removeLiquidity(msg.sender, lShares);
    }

    function addMargin(uint256 bAmount) external override {
        _addMargin(msg.sender, bAmount);
    }

    function removeMargin(uint256 bAmount, SignedPrice[] memory prices) external override {
        address account = msg.sender;
        require(bAmount > 0, '0 bAmount');
        require(IPTokenLite(_pTokenAddress).exists(account), 'no pToken');
        _updateSymbolPrices(prices);
        _removeMargin(account, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume, SignedPrice[] memory prices) external override {
        address account = msg.sender;
        require(IPTokenLite(_pTokenAddress).isActiveSymbolId(symbolId), 'inv symbolId');
        require(IPTokenLite(_pTokenAddress).exists(account), 'no pToken');
        require(tradeVolume != 0 && tradeVolume / ONE * ONE == tradeVolume, 'inv volume');
        _updateSymbolPrices(prices);
        _trade(account, symbolId, tradeVolume);
    }

    function liquidate(address account, SignedPrice[] memory prices) external override {
        address liquidator = msg.sender;
        require(
            _liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(liquidator),
            'unqualified'
        );
        require(IPTokenLite(_pTokenAddress).exists(account), 'no pToken');
        _updateSymbolPrices(prices);
        _liquidate(liquidator, account);
    }


    //================================================================================
    // Core logics
    //================================================================================

    function _addLiquidity(address account, uint256 bAmount) internal _lock_ {
        bAmount = _transferIn(account, bAmount);
        ILTokenLite lToken = ILTokenLite(_lTokenAddress);
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);

        int256 poolDynamicEquity = _getPoolPnl(symbols) + _liquidity;
        uint256 totalSupply = lToken.totalSupply();
        uint256 lShares;
        if (totalSupply == 0) {
            lShares = bAmount;
        } else {
            lShares = bAmount * totalSupply / poolDynamicEquity.itou();
        }

        lToken.mint(account, lShares);
        _liquidity += bAmount.utoi();

        emit AddLiquidity(account, lShares, bAmount);
    }

    function _removeLiquidity(address account, uint256 lShares) internal _lock_ {
        ILTokenLite lToken = ILTokenLite(_lTokenAddress);
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);

        int256 liquidity = _liquidity;
        int256 poolPnlBefore = _getPoolPnl(symbols);
        uint256 totalSupply = lToken.totalSupply();
        uint256 bAmount = lShares * (liquidity + poolPnlBefore).itou() / totalSupply;

        liquidity -= bAmount.utoi();
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            s.K = DpmmPricerFutures._calculateK(s.indexPrice, liquidity, s.alpha);
            s.dpmmPrice = DpmmPricerFutures._calculateDpmmPrice(s.indexPrice, s.K, s.tradersNetPosition);
        }
        int256 poolPnlAfter = _getPoolPnl(symbols);

        uint256 compensation = (poolPnlBefore - poolPnlAfter).itou() * lShares / totalSupply;
        bAmount -= compensation;

        int256 poolRequiredMargin = _getPoolRequiredMargin(symbols);
        require(liquidity + poolPnlAfter >= poolRequiredMargin, 'pool insuf liq');

        _liquidity -= bAmount.utoi();
        lToken.burn(account, lShares);
        _transferOut(account, bAmount);

        emit RemoveLiquidity(account, lShares, bAmount);
    }

    function _addMargin(address account, uint256 bAmount) internal _lock_ {
        bAmount = _transferIn(account, bAmount);
        IPTokenLite pToken = IPTokenLite(_pTokenAddress);
        if (!pToken.exists(account)) pToken.mint(account);

        pToken.addMargin(account, bAmount.utoi());
        emit AddMargin(account, bAmount);
    }

    function _removeMargin(address account, uint256 bAmount) internal _lock_ {
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);
        (IPTokenLite.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

        // remove all available margin when bAmount >= margin
        int256 amount = bAmount.utoi();
        if (amount > margin) {
            amount = margin;
            bAmount = amount.itou();
        }
        margin -= amount;

        (bool initialMarginSafe, ) = _getTraderMarginStatus(symbols, positions, margin);
        require(initialMarginSafe, 'insuf margin');

        _updateTraderPortfolio(account, symbols, positions, margin);
        _transferOut(account, bAmount);

        emit RemoveMargin(account, bAmount);
    }

    function _trade(address account, uint256 symbolId, int256 tradeVolume) internal _lock_ {
        DataSymbol[] memory symbols = _updateFundingRates(symbolId);
        (IPTokenLite.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

        // get pool pnl before trading
        int256 poolPnl = _getPoolPnl(symbols);

        DataSymbol memory s = symbols[0];
        IPTokenLite.Position memory p = positions[0];

        int256 curCost = DpmmPricerFutures._calculateDpmmCost(
            s.indexPrice,
            s.K,
            s.tradersNetPosition,
            tradeVolume * s.multiplier / ONE
        );

        emit Trade(account, symbolId, tradeVolume, curCost, _liquidity, s.tradersNetVolume, s.indexPrice);

        int256 fee = curCost.abs() * s.feeRatio / ONE;

        int256 realizedCost;
        if (!(p.volume >= 0 && tradeVolume >= 0) && !(p.volume <= 0 && tradeVolume <= 0)) {
            int256 absVolume = p.volume.abs();
            int256 absTradeVolume = tradeVolume.abs();
            if (absVolume <= absTradeVolume) {
                // previous position is totally closed
                realizedCost = curCost * absVolume / absTradeVolume + p.cost;
            } else {
                // previous position is partially closed
                realizedCost = p.cost * absTradeVolume / absVolume + curCost;
            }
        }
        int256 toAddCost = curCost - realizedCost;

        p.volume += tradeVolume;
        p.cost += toAddCost;
        p.lastCumulativeFundingRate = s.cumulativeFundingRate;

        margin -= fee + realizedCost;

        s.positionUpdated = true;
        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += toAddCost;
        s.tradersNetPosition = s.tradersNetVolume * s.multiplier / ONE;

        _symbols[symbolId].tradersNetVolume += tradeVolume;
        _symbols[symbolId].tradersNetCost += toAddCost;

        int256 protocolFee = fee * _protocolFeeCollectRatio / ONE;
        _protocolFeeAccrued += protocolFee;
        _liquidity += fee - protocolFee + realizedCost;

        require(_liquidity + poolPnl >= _getPoolRequiredMargin(symbols), 'insuf liquidity');
        (bool initialMarginSafe, ) = _getTraderMarginStatus(symbols, positions, margin);
        require(initialMarginSafe, 'insuf margin');

        _updateTraderPortfolio(account, symbols, positions, margin);
    }

    function _liquidate(address liquidator, address account) internal _lock_ {
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);
        (IPTokenLite.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

        (, bool maintenanceMarginSafe) = _getTraderMarginStatus(symbols, positions, margin);
        require(!maintenanceMarginSafe, 'cant liq');

        int256 netEquity = margin;
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            IPTokenLite.Position memory p = positions[i];
            if (p.volume != 0) {
                int256 curCost = DpmmPricerFutures._calculateDpmmCost(
                    s.indexPrice,
                    s.K,
                    s.tradersNetPosition,
                    -p.volume * s.multiplier / ONE
                );
                netEquity -= curCost + p.cost;
                _symbols[s.symbolId].tradersNetVolume -= p.volume;
                _symbols[s.symbolId].tradersNetCost -= p.cost;
            }
        }

        int256 reward;
        if (netEquity <= _minLiquidationReward) {
            reward = _minLiquidationReward;
        } else if (netEquity >= _maxLiquidationReward) {
            reward = _maxLiquidationReward;
        } else {
            reward = (netEquity - _minLiquidationReward) * _liquidationCutRatio / ONE + _minLiquidationReward;
        }

        _liquidity += margin - reward;
        IPTokenLite(_pTokenAddress).burn(account);
        _transferOut(liquidator, reward.itou());

        emit Liquidate(account, liquidator, reward.itou());
    }


    //================================================================================
    // Helpers
    //================================================================================

    function _updateSymbolPrices(SignedPrice[] memory prices) internal {
        for (uint256 i = 0; i < prices.length; i++) {
            uint256 symbolId = prices[i].symbolId;
            IOracleWithUpdate(_symbols[symbolId].oracleAddress).updatePrice(
                prices[i].timestamp,
                prices[i].price,
                prices[i].v,
                prices[i].r,
                prices[i].s
            );
        }
    }

    struct DataSymbol {
        uint256 symbolId;
        int256  multiplier;
        int256  feeRatio;
        int256  alpha;
        int256  indexPrice;
        int256  dpmmPrice;
        int256  K;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativeFundingRate;
        int256  tradersNetPosition; // volume * multiplier
        bool    positionUpdated;
    }

    // Gether data for valid symbols for later use
    // Calculate those symbol parameters that will not change during this transaction
    // Symbols with no position holders are excluded
    function _getSymbols(uint256 tradeSymbolId) internal view returns (DataSymbol[] memory symbols) {
        IPTokenLite pToken = IPTokenLite(_pTokenAddress);
        uint256[] memory activeSymbolIds = pToken.getActiveSymbolIds();
        uint256[] memory symbolIds = new uint256[](activeSymbolIds.length);
        uint256 count;
        if (tradeSymbolId != type(uint256).max) {
            symbolIds[0] = tradeSymbolId;
            count = 1;
        }
        for (uint256 i = 0; i < activeSymbolIds.length; i++) {
            if (activeSymbolIds[i] != tradeSymbolId && pToken.getNumPositionHolders(activeSymbolIds[i]) != 0) {
                symbolIds[count++] = activeSymbolIds[i];
            }
        }

        symbols = new DataSymbol[](count);
        int256 liquidity = _liquidity;
        for (uint256 i = 0; i < count; i++) {
            SymbolInfo storage ss = _symbols[symbolIds[i]];
            DataSymbol memory s = symbols[i];
            s.symbolId = symbolIds[i];
            s.multiplier = ss.multiplier;
            s.feeRatio = ss.feeRatio;
            s.alpha = ss.alpha;
            s.indexPrice = IOracleViewer(ss.oracleAddress).getPrice().utoi();
            s.tradersNetVolume = ss.tradersNetVolume;
            s.tradersNetCost = ss.tradersNetCost;
            s.cumulativeFundingRate = ss.cumulativeFundingRate;
            s.tradersNetPosition = s.tradersNetVolume * s.multiplier / ONE;
            s.K = DpmmPricerFutures._calculateK(s.indexPrice, liquidity, s.alpha);
            s.dpmmPrice = DpmmPricerFutures._calculateDpmmPrice(s.indexPrice, s.K, s.tradersNetPosition);
        }
    }

    function _updateFundingRates(uint256 tradeSymbolId) internal returns (DataSymbol[] memory symbols) {
        uint256 preTimestamp = _lastTimestamp;
        uint256 curTimestamp = block.timestamp;
        symbols = _getSymbols(tradeSymbolId);
        if (curTimestamp > preTimestamp) {
            int256 fundingPeriod = _fundingPeriod;
            for (uint256 i = 0; i < symbols.length; i++) {
                DataSymbol memory s = symbols[i];
                int256 ratePerSecond = (s.dpmmPrice - s.indexPrice) * s.multiplier / fundingPeriod;
                int256 diff = ratePerSecond * int256(curTimestamp - preTimestamp);
                unchecked { s.cumulativeFundingRate += diff; }
                _symbols[s.symbolId].cumulativeFundingRate = s.cumulativeFundingRate;
            }
        }
        _lastTimestamp = curTimestamp;
    }

    function _getPoolPnl(DataSymbol[] memory symbols) internal pure returns (int256 poolPnl) {
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            int256 cost = s.tradersNetPosition * s.dpmmPrice / ONE;
            poolPnl -= cost - s.tradersNetCost;
        }
    }

    function _getPoolRequiredMargin(DataSymbol[] memory symbols) internal view returns (int256 poolRequiredMargin) {
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            int256 notional = s.tradersNetPosition * s.indexPrice / ONE;
            poolRequiredMargin += notional.abs() * _poolMarginRatio / ONE;
        }
    }

    function _settleTraderFundingFee(address account, DataSymbol[] memory symbols)
    internal returns (IPTokenLite.Position[] memory positions, int256 margin)
    {
        IPTokenLite pToken = IPTokenLite(_pTokenAddress);
        positions = new IPTokenLite.Position[](symbols.length);
        margin = pToken.getMargin(account);

        int256 funding;
        for (uint256 i = 0; i < symbols.length; i++) {
            IPTokenLite.Position memory p = pToken.getPosition(account, symbols[i].symbolId);
            if (p.volume != 0) {
                int256 diff;
                unchecked { diff = symbols[i].cumulativeFundingRate - p.lastCumulativeFundingRate; }
                funding += p.volume * diff / ONE;
                p.lastCumulativeFundingRate = symbols[i].cumulativeFundingRate;
                symbols[i].positionUpdated = true;
                positions[i] = p;
            }
        }

        margin -= funding;
        _liquidity += funding;
    }

    function _getTraderMarginStatus(
        DataSymbol[] memory symbols,
        IPTokenLite.Position[] memory positions,
        int256 margin
    ) internal view returns (bool initialMarginSafe, bool maintenanceMarginSafe)
    {
        int256 dynamicMargin = margin;
        int256 requiredInitialMargin;
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            IPTokenLite.Position memory p = positions[i];
            if (p.volume != 0) {
                int256 cost = p.volume * s.dpmmPrice / ONE * s.multiplier / ONE;
                dynamicMargin += cost - p.cost;
                int256 notional = p.volume * s.indexPrice / ONE * s.multiplier / ONE;
                requiredInitialMargin += notional.abs() * _initialMarginRatio / ONE;
            }
        }
        int256 requiredMaintenanceMargin = requiredInitialMargin * _maintenanceMarginRatio / _initialMarginRatio;
        return (
            dynamicMargin >= requiredInitialMargin,
            dynamicMargin >= requiredMaintenanceMargin
        );
    }

    function _updateTraderPortfolio(
        address account,
        DataSymbol[] memory symbols,
        IPTokenLite.Position[] memory positions,
        int256 margin
    ) internal {
        IPTokenLite pToken = IPTokenLite(_pTokenAddress);
        for (uint256 i = 0; i < symbols.length; i++) {
            if (symbols[i].positionUpdated) {
                pToken.updatePosition(account, symbols[i].symbolId, positions[i]);
            }
        }
        pToken.updateMargin(account, margin);
    }

    function _transferIn(address from, uint256 bAmount) internal returns (uint256) {
        uint256 amount = bAmount.rescale(18, _decimals);
        require(amount > 0, '0 bAmount');
        IERC20 bToken = IERC20(_bTokenAddress);
        uint256 balance1 = bToken.balanceOf(address(this));
        bToken.safeTransferFrom(from, address(this), amount);
        uint256 balance2 = bToken.balanceOf(address(this));
        return (balance2 - balance1).rescale(_decimals, 18);
    }

    function _transferOut(address to, uint256 bAmount) internal {
        uint256 amount = bAmount.rescale(18, _decimals);
        uint256 leftover = bAmount - amount.rescale(_decimals, 18);
        // leftover due to decimal precision is accrued to _protocolFeeAccrued
        _protocolFeeAccrued += leftover.utoi();
        IERC20(_bTokenAddress).safeTransfer(to, amount);
    }

}
