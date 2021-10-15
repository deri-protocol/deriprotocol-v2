// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/ILTokenOption.sol';
import '../interface/IPTokenOption.sol';
import '../interface/IEverlastingOptionPricing.sol';
import '../interface/IOracleViewer.sol';
import '../interface/IVolatilityOracle.sol';
import '../interface/ILiquidatorQualifier.sol';
import "../interface/IEverlastingOption.sol";
import "../interface/IEverlastingOptionOld.sol";
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';
import '../utils/Migratable.sol';

contract EverlastingOption is IEverlastingOption, Migratable {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256 constant ONE = 1e18;
    int256 constant MIN_INITIAL_MARGIN_RATIO = 1e16;       // 0.01
    int256 constant FUNDING_PERIOD = ONE / 365;            // funding period = 1 day
    int256 constant FUNDING_COEFFICIENT = ONE / 24 / 3600; // funding rate per second

    uint256 immutable _decimals;
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
    address immutable _optionPricerAddress;

    int256  _poolMarginMultiplier = 10;

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

    constructor (uint256[6] memory parameters, address[6] memory addresses) {
        _initialMarginRatio = int256(parameters[0]);
        _maintenanceMarginRatio = int256(parameters[1]);
        _minLiquidationReward = int256(parameters[2]);
        _maxLiquidationReward = int256(parameters[3]);
        _liquidationCutRatio = int256(parameters[4]);
        _protocolFeeCollectRatio = int256(parameters[5]);

        _bTokenAddress = addresses[0];
        _lTokenAddress = addresses[1];
        _pTokenAddress = addresses[2];
        _liquidatorQualifierAddress = addresses[3];
        _protocolFeeCollector = addresses[4];
        _optionPricerAddress = addresses[5];

        _decimals = IERC20(addresses[0]).decimals();

        _controller = msg.sender;
    }

    // during a migration, this function is intended to be called in the source pool
    function approveMigration() external override _controller_ {
        require(_migrationTimestamp != 0 && block.timestamp >= _migrationTimestamp, 'time inv');
        // approve new pool to pull all base tokens from this pool
        IERC20(_bTokenAddress).safeApprove(_migrationDestination, type(uint256).max);
        // set lToken/pToken to new pool, after redirecting pToken/lToken to new pool, this pool will stop functioning
        ILTokenOption(_lTokenAddress).setPool(_migrationDestination);
        IPTokenOption(_pTokenAddress).setPool(_migrationDestination);
    }

    // during a migration, this function is intended to be called in the target pool
    function executeMigration(address source) external override _controller_ {
        uint256 migrationTimestamp_ = IEverlastingOptionOld(source).migrationTimestamp();
        address migrationDestination_ = IEverlastingOptionOld(source).migrationDestination();
        require(migrationTimestamp_ != 0 && block.timestamp >= migrationTimestamp_, 'time inv');
        require(migrationDestination_ == address(this), 'not dest');

        // transfer bToken to this address
        IERC20(_bTokenAddress).safeTransferFrom(source, address(this), IERC20(_bTokenAddress).balanceOf(source));

        // transfer symbol infos
        uint256[] memory symbolIds = IPTokenOption(_pTokenAddress).getActiveSymbolIds();
        for (uint256 i = 0; i < symbolIds.length; i++) {
            uint256 symbolId = symbolIds[i];
            IEverlastingOptionOld.SymbolInfo memory pre = IEverlastingOptionOld(source).getSymbol(symbolId);
            SymbolInfo storage cur = _symbols[symbolId];
            cur.symbolId = pre.symbolId;
            cur.symbol = pre.symbol;
            cur.oracleAddress = pre.oracleAddress;
            cur.volatilityAddress = pre.volatilityAddress;
            cur.isCall = pre.isCall;
            cur.strikePrice = pre.strikePrice;
            cur.multiplier = pre.multiplier;
            cur.feeRatioITM = ONE * 15 / 10000;
            cur.feeRatioOTM = ONE * 4 / 100;
            cur.alpha = pre.alpha;
            cur.tradersNetVolume = pre.tradersNetVolume;
            cur.tradersNetCost = pre.tradersNetCost;
            cur.cumulativeFundingRate = pre.cumulativeFundingRate;
        }

        // transfer state values
        (_liquidity, _lastTimestamp, _protocolFeeAccrued) = IEverlastingOptionOld(source).getPoolStateValues();

        emit ExecuteMigration(migrationTimestamp_, source, migrationDestination_);
    }

    function getParameters() external view override returns (
        int256 initialMarginRatio,
        int256 maintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    ) {
        return (
            _initialMarginRatio,
            _maintenanceMarginRatio,
            _minLiquidationReward,
            _maxLiquidationReward,
            _liquidationCutRatio,
            _protocolFeeCollectRatio
        );
    }

    function getAddresses() external view override returns (
        address bTokenAddress,
        address lTokenAddress,
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address protocolFeeCollector,
        address optionPricerAddress
    ) {
        return (
            _bTokenAddress,
            _lTokenAddress,
            _pTokenAddress,
            _liquidatorQualifierAddress,
            _protocolFeeCollector,
            _optionPricerAddress
        );
    }

    function getSymbol(uint256 symbolId) external view override returns (SymbolInfo memory) {
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

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        address oracleAddress,
        address volatilityAddress,
        bool    isCall,
        uint256 strikePrice,
        uint256 multiplier,
        uint256 feeRatioITM,
        uint256 feeRatioOTM,
        uint256 alpha
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.symbolId = symbolId;
        s.symbol = symbol;
        s.oracleAddress = oracleAddress;
        s.volatilityAddress = volatilityAddress;
        s.isCall = isCall;
        s.strikePrice = int256(strikePrice);
        s.multiplier = int256(multiplier);
        s.feeRatioITM = int256(feeRatioITM);
        s.feeRatioOTM = int256(feeRatioOTM);
        s.alpha = int256(alpha);
        IPTokenOption(_pTokenAddress).addSymbolId(symbolId);
    }

    function removeSymbol(uint256 symbolId) external override _controller_ {
        delete _symbols[symbolId];
        IPTokenOption(_pTokenAddress).removeSymbolId(symbolId);
    }

    function toggleCloseOnly(uint256 symbolId) external override _controller_ {
        IPTokenOption(_pTokenAddress).toggleCloseOnly(symbolId);
    }

    function getPoolMarginMultiplier() external override view returns (int256) {
        return _poolMarginMultiplier;
    }

    function setPoolMarginMulitplier(uint256 multiplier) external override _controller_ {
        _poolMarginMultiplier = int256(multiplier);
    }

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        address volatilityAddress,
        uint256 feeRatioITM,
        uint256 feeRatioOTM,
        uint256 alpha
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.oracleAddress = oracleAddress;
        s.volatilityAddress = volatilityAddress;
        s.feeRatioITM = int256(feeRatioITM);
        s.feeRatioOTM = int256(feeRatioOTM);
        s.alpha = int256(alpha);
    }


    //================================================================================
    // Interactions with offchain volatility
    //================================================================================

    function addLiquidity(uint256 bAmount, SignedValue[] memory volatilities) external override {
        _updateSymbolVolatilities(volatilities);
        _addLiquidity(msg.sender, bAmount);
    }

    function removeLiquidity(uint256 lShares, SignedValue[] memory volatilities) external override {
        require(lShares > 0, '0 lShares');
        _updateSymbolVolatilities(volatilities);
        _removeLiquidity(msg.sender, lShares);
    }

    function addMargin(uint256 bAmount) external override {
        _addMargin(msg.sender, bAmount);
    }

    function removeMargin(uint256 bAmount, SignedValue[] memory volatilities) external override {
        address account = msg.sender;
        require(bAmount > 0, '0 bAmount');
        require(IPTokenOption(_pTokenAddress).exists(account), 'no pToken');
        _updateSymbolVolatilities(volatilities);
        _removeMargin(account, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume, SignedValue[] memory volatilities) external override {
        address account = msg.sender;
        require(IPTokenOption(_pTokenAddress).isActiveSymbolId(symbolId), 'inv symbolId');
        require(IPTokenOption(_pTokenAddress).exists(account), 'no pToken');
        require(tradeVolume != 0 && tradeVolume / ONE * ONE == tradeVolume, 'inv volume');
        _updateSymbolVolatilities(volatilities);
        _trade(account, symbolId, tradeVolume);
    }

    function liquidate(address account, SignedValue[] memory volatilities) public override {
        address liquidator = msg.sender;
        require(
            _liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(liquidator),
            'unqualified'
        );
        require(IPTokenOption(_pTokenAddress).exists(account), 'no pToken');
        _updateSymbolVolatilities(volatilities);
        _liquidate(liquidator, account);
    }

    function liquidate(uint256 pTokenId, SignedValue[] memory volatilities) external override {
        liquidate(IPTokenOption(_pTokenAddress).ownerOf(pTokenId), volatilities);
    }


    //================================================================================
    // Core logics
    //================================================================================

    function _addLiquidity(address account, uint256 bAmount) internal _lock_ {
        bAmount = _transferIn(account, bAmount);
        ILTokenOption lToken = ILTokenOption(_lTokenAddress);
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
        ILTokenOption lToken = ILTokenOption(_lTokenAddress);
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);

        int256 liquidity = _liquidity;
        int256 poolPnlBefore = _getPoolPnl(symbols);
        uint256 totalSupply = lToken.totalSupply();
        uint256 bAmount = lShares * (liquidity + poolPnlBefore).itou() / totalSupply;

        liquidity -= bAmount.utoi();
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            (s.K, s.dpmmPrice) = _calculateDpmmPrice(
                s.spotPrice, s.theoreticalPrice, s.delta, s.alpha, s.tradersNetPosition, liquidity
            );
        }
        int256 poolPnlAfter = _getPoolPnl(symbols);

        uint256 compensation = (poolPnlBefore - poolPnlAfter).itou();
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
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        if (!pToken.exists(account)) pToken.mint(account);

        pToken.addMargin(account, bAmount.utoi());
        emit AddMargin(account, bAmount);
    }

    function _removeMargin(address account, uint256 bAmount) internal _lock_ {
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);
        (IPTokenOption.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

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
        (IPTokenOption.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

        // get pool pnl before trading
        int256 poolPnl = _getPoolPnl(symbols);

        DataSymbol memory s = symbols[0];
        IPTokenOption.Position memory p = positions[0];

        int256 curCost = _queryTradeDpmm(
            s.tradersNetPosition,
            s.theoreticalPrice,
            tradeVolume * s.multiplier / ONE,
            s.K
        );

        emit Trade(account, symbolId, tradeVolume, curCost, _liquidity, s.tradersNetVolume, s.spotPrice, s.volatility);

        int256 fee;
        if (s.intrinsicValue > 0) {
            fee = s.spotPrice * tradeVolume.abs() / ONE * s.multiplier / ONE * s.feeRatioITM / ONE;
        } else {
            fee = curCost.abs() * s.feeRatioOTM / ONE;
        }

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
        (IPTokenOption.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

        (, bool maintenanceMarginSafe) = _getTraderMarginStatus(symbols, positions, margin);
        require(!maintenanceMarginSafe, 'cant liq');

        int256 netEquity = margin;
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            IPTokenOption.Position memory p = positions[i];
            if (p.volume != 0) {
                int256 curCost = _queryTradeDpmm(
                    s.tradersNetPosition,
                    s.theoreticalPrice,
                    -p.volume * s.multiplier / ONE,
                    s.K
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
        IPTokenOption(_pTokenAddress).burn(account);
        _transferOut(liquidator, reward.itou());

        emit Liquidate(account, liquidator, reward.itou());
    }


    //================================================================================
    // Helpers
    //================================================================================

    function _updateSymbolVolatilities(SignedValue[] memory volatilities) internal {
        for (uint256 i = 0; i < volatilities.length; i++) {
            uint256 symbolId = volatilities[i].symbolId;
            IVolatilityOracle(_symbols[symbolId].volatilityAddress).updateVolatility(
                volatilities[i].timestamp,
                volatilities[i].value,
                volatilities[i].v,
                volatilities[i].r,
                volatilities[i].s
            );
        }
    }

    struct DataSymbol {
        uint256 symbolId;
        bool    isCall;
        int256  multiplier;
        int256  feeRatioITM;
        int256  feeRatioOTM;
        int256  strikePrice;
        int256  spotPrice;
        int256  volatility;
        int256  intrinsicValue;
        int256  timeValue;
        int256  theoreticalPrice;
        int256  dpmmPrice;
        int256  delta;
        int256  alpha;
        int256  K;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativeFundingRate;
        int256  tradersNetPosition; // volume * multiplier
        int256  dynamicInitialMarginRatio;
        bool    positionUpdated;
    }

    // Gether data for valid symbols for later use
    // Calculate those symbol parameters that will not change during this transaction
    // Symbols with no position holders are excluded
    function _getSymbols(uint256 tradeSymbolId) internal view returns (DataSymbol[] memory symbols) {
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
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
            s.isCall = ss.isCall;
            s.multiplier = ss.multiplier;
            s.feeRatioITM = ss.feeRatioITM;
            s.feeRatioOTM = ss.feeRatioOTM;
            s.strikePrice = ss.strikePrice;
            s.spotPrice = IOracleViewer(ss.oracleAddress).getPrice().utoi();
            s.volatility = IVolatilityOracle(ss.volatilityAddress).getVolatility().utoi();
            s.intrinsicValue = s.isCall ? (s.spotPrice - s.strikePrice).max(0) : (s.strikePrice - s.spotPrice).max(0);
            (s.timeValue, s.delta) = IEverlastingOptionPricing(_optionPricerAddress).getEverlastingTimeValueAndDelta(
                s.spotPrice, s.strikePrice, s.volatility, FUNDING_PERIOD
            );
            s.theoreticalPrice = s.intrinsicValue + s.timeValue;
            if (s.intrinsicValue > 0) {
                if (s.isCall) s.delta += ONE;
                else s.delta -= ONE;
            }
            else if (s.spotPrice == s.strikePrice) {
                if (s.isCall) s.delta = ONE / 2;
                else s.delta = -ONE / 2;
            }
            s.alpha = ss.alpha;
            s.tradersNetVolume = ss.tradersNetVolume;
            s.tradersNetCost = ss.tradersNetCost;
            s.cumulativeFundingRate = ss.cumulativeFundingRate;
            s.tradersNetPosition = s.tradersNetVolume * s.multiplier / ONE;
            (s.K, s.dpmmPrice) = _calculateDpmmPrice(s.spotPrice, s.theoreticalPrice, s.delta, s.alpha, s.tradersNetPosition, liquidity);
            if (s.intrinsicValue > 0 || s.spotPrice == s.strikePrice) {
                s.dynamicInitialMarginRatio = _initialMarginRatio;
            } else {
                int256 otmRatio = (s.spotPrice - s.strikePrice).abs() * ONE / s.strikePrice;
                s.dynamicInitialMarginRatio = ((ONE - otmRatio * 3) * _initialMarginRatio / ONE).max(MIN_INITIAL_MARGIN_RATIO);
            }
        }
    }

    function _calculateDpmmPrice(
        int256 spotPrice,
        int256 theoreticalPrice,
        int256 delta,
        int256 alpha,
        int256 tradersNetPosition,
        int256 liquidity
    ) internal pure returns (int256 K, int256 dpmmPrice) {
        K = spotPrice ** 2 / theoreticalPrice * delta.abs() * alpha / liquidity / ONE;
        dpmmPrice = theoreticalPrice * (ONE + K * tradersNetPosition / ONE) / ONE;
    }

    function _updateFundingRates(uint256 tradeSymbolId) internal returns (DataSymbol[] memory symbols) {
        uint256 preTimestamp = _lastTimestamp;
        uint256 curTimestamp = block.timestamp;
        symbols = _getSymbols(tradeSymbolId);
        if (curTimestamp > preTimestamp) {
            for (uint256 i = 0; i < symbols.length; i++) {
                DataSymbol memory s = symbols[i];
                int256 ratePerSecond = (s.dpmmPrice - s.intrinsicValue) * s.multiplier / ONE * FUNDING_COEFFICIENT / ONE;
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
            poolPnl += _queryTradeDpmm(s.tradersNetPosition, s.theoreticalPrice, -s.tradersNetPosition, s.K) + s.tradersNetCost;
        }
    }

    function _getPoolRequiredMargin(DataSymbol[] memory symbols) internal view returns (int256 poolRequiredMargin) {
        int256 poolMarginMultiplier = _poolMarginMultiplier;
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            int256 notional = (s.tradersNetPosition * s.spotPrice / ONE).abs();
            // pool margin requirement is 10x trader margin requirement
            poolRequiredMargin += notional * s.dynamicInitialMarginRatio * poolMarginMultiplier / ONE;
        }
    }

    function _settleTraderFundingFee(address account, DataSymbol[] memory symbols)
    internal returns (IPTokenOption.Position[] memory positions, int256 margin)
    {
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        positions = new IPTokenOption.Position[](symbols.length);
        margin = pToken.getMargin(account);

        int256 funding;
        for (uint256 i = 0; i < symbols.length; i++) {
            IPTokenOption.Position memory p = pToken.getPosition(account, symbols[i].symbolId);
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
        IPTokenOption.Position[] memory positions,
        int256 margin
    ) internal view returns (bool initialMarginSafe, bool maintenanceMarginSafe)
    {
        int256 dynamicMargin = margin;
        int256 requiredInitialMargin;
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            IPTokenOption.Position memory p = positions[i];
            if (p.volume != 0) {
                dynamicMargin -= _queryTradeDpmm(s.tradersNetPosition, s.theoreticalPrice, -p.volume * s.multiplier / ONE, s.K) + p.cost;
                int256 notional = (p.volume * s.spotPrice / ONE * s.multiplier / ONE).abs();
                requiredInitialMargin += notional * s.dynamicInitialMarginRatio / ONE;
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
        IPTokenOption.Position[] memory positions,
        int256 margin
    ) internal {
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        for (uint256 i = 0; i < symbols.length; i++) {
            if (symbols[i].positionUpdated) {
                pToken.updatePosition(account, symbols[i].symbolId, positions[i]);
            }
        }
        pToken.updateMargin(account, margin);
    }

    function _queryTradeDpmm(
        int256 tradersNetPosition,
        int256 theoreticalPrice,
        int256 tradePosition,
        int256 K
    ) internal pure returns (int256 cost) {
        int256 r = ((tradersNetPosition + tradePosition) ** 2 - tradersNetPosition ** 2) / ONE * K / ONE / 2 + tradePosition;
        cost = theoreticalPrice * r / ONE;
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
