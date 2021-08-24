// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;
import "../interface/IEverlastingOption.sol";
import '../interface/ILTokenOption.sol';
import '../interface/IPTokenOption.sol';
import '../interface/IERC20.sol';
import '../interface/IOracleViewer.sol';
import '../interface/IOracleWithUpdate.sol';
import '../interface/IVolatilityOracle.sol';
import '../interface/ILiquidatorQualifier.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';
import '../utils/Migratable.sol';
import {LinearPricing} from '../library/LinearPricing.sol';
import {ExponentialPricing} from '../library/ExponentialPricing.sol';
import {IEverlastingOptionPricing} from '../interface/IEverlastingOptionPricing.sol';

import "hardhat/console.sol";


contract EverlastingOption is IEverlastingOption, Migratable {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

//    PMMPricing public PmmPricer;
    LinearPricing public PmmPricer;
//    ExponentialPricing public PmmPricer;
    IEverlastingOptionPricing public OptionPricer;
    int256 constant ONE = 10**18;
    int256 constant MinInitialMarginRatio = 10**16;
    int256 public _T = 10**18 / int256(365); // premium funding period = 1 day
    int256 public _premiumFundingCoefficient = 10**18 / int256(3600*24); // premium funding rate per second

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


    constructor (address pricingAddress,
        address everlastingPricingOptionAddress,
        uint256[6] memory parameters,
        address[5] memory addresses) {
        PmmPricer = LinearPricing(pricingAddress);
        OptionPricer = IEverlastingOptionPricing(everlastingPricingOptionAddress);
        _controller = msg.sender;
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

        _decimals = IERC20(addresses[0]).decimals();
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
        uint256 migrationTimestamp_ = IEverlastingOption(source).migrationTimestamp();
        address migrationDestination_ = IEverlastingOption(source).migrationDestination();
        require(migrationTimestamp_ != 0 && block.timestamp >= migrationTimestamp_, 'time inv');
        require(migrationDestination_ == address(this), 'not dest');

        // transfer bToken to this address
        IERC20(_bTokenAddress).safeTransferFrom(source, address(this), IERC20(_bTokenAddress).balanceOf(source));

        // transfer symbol infos
        uint256[] memory symbolIds = IPTokenOption(_pTokenAddress).getActiveSymbolIds();
        for (uint256 i = 0; i < symbolIds.length; i++) {
            _symbols[symbolIds[i]] = IEverlastingOption(source).getSymbol(symbolIds[i]);
        }

        // transfer state values
        _liquidity = IEverlastingOption(source).getLiquidity();
        _lastTimestamp = IEverlastingOption(source).getLastTimestamp();
        _protocolFeeAccrued = IEverlastingOption(source).getProtocolFeeAccrued();

        emit ExecuteMigration(migrationTimestamp_, source, migrationDestination_);
    }


    function getParameters() external override view returns (
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

    function getLiquidity() external override view returns (int256) {
        return _liquidity;
    }

    function getLastTimestamp() external override view returns (uint256) {
        return _lastTimestamp;
    }

    function getProtocolFeeAccrued() external override view returns (int256) {
        return _protocolFeeAccrued;
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
        uint256 strikePrice,
        bool    isCall,
        address oracleAddress,
        address volatilityAddress,
        uint256 multiplier,
        uint256 feeRatio,
        int256 alpha
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.symbolId = symbolId;
        s.symbol = symbol;
        s.strikePrice = int256(strikePrice);
        s.isCall = isCall;
        s.oracleAddress = oracleAddress;
        s.volatilityAddress = volatilityAddress;
        s.multiplier = int256(multiplier);
        s.feeRatio = int256(feeRatio);
        s.alpha = alpha;
        IPTokenOption(_pTokenAddress).addSymbolId(symbolId);
    }

    function removeSymbol(uint256 symbolId) external override _controller_ {
        delete _symbols[symbolId];
        IPTokenOption(_pTokenAddress).removeSymbolId(symbolId);
    }

    function toggleCloseOnly(uint256 symbolId) external override _controller_ {
        IPTokenOption(_pTokenAddress).toggleCloseOnly(symbolId);
    }

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        address volatilityAddress,
        uint256 feeRatio,
        int256 alpha
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.oracleAddress = oracleAddress;
        s.volatilityAddress = volatilityAddress;
        s.feeRatio = int256(feeRatio);
        s.alpha = alpha;
    }

    function setPoolParameters(uint256 premiumFundingCoefficient, int256 T, address everlastingPricingOptionAddress) external _controller_ {
        _premiumFundingCoefficient = int256(premiumFundingCoefficient);
        _T = T;
        OptionPricer = IEverlastingOptionPricing(everlastingPricingOptionAddress);
    }


    //================================================================================
    // Interactions with offchain volatility
    //================================================================================

    function addLiquidity(uint256 bAmount, SignedPrice[] memory volatility) external override {
        require(bAmount > 0, '0 bAmount');
        _updateSymbolVolatility(volatility);
        _addLiquidity(msg.sender, bAmount);
    }

    function removeLiquidity(uint256 lShares, SignedPrice[] memory volatility) external override {
        require(lShares > 0, '0 lShares');
        _updateSymbolVolatility(volatility);
        _removeLiquidity(msg.sender, lShares);
    }

    function addMargin(uint256 bAmount) external override {
        require(bAmount > 0, '0 bAmount');
        _addMargin(msg.sender, bAmount);
    }

    function removeMargin(uint256 bAmount, SignedPrice[] memory volatility) external override {
        require(bAmount > 0, '0 bAmount');
        _updateSymbolVolatility(volatility);
        _removeMargin(msg.sender, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume, SignedPrice[] memory volatility) external override {
        require(IPTokenOption(_pTokenAddress).isActiveSymbolId(symbolId), 'inv symbolId');
        require(tradeVolume != 0 && tradeVolume / ONE * ONE == tradeVolume, 'inv Vol');
        _updateSymbolVolatility(volatility);
        _trade(msg.sender, symbolId, tradeVolume);
    }

    function liquidate(address account, SignedPrice[] memory volatility) external override {
        address liquidator = msg.sender;
        require(
            _liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(liquidator),
            'unqualified'
        );
        _updateSymbolVolatility(volatility);
        _liquidate(liquidator, account);
    }


    //================================================================================
    // Core logics
    //================================================================================
    function _addLiquidity(address account, uint256 bAmount) internal _lock_ {
        (int256 totalDynamicEquity, , ,) = _updateSymbolPricesAndFundingRates();

        bAmount = _transferIn(account, bAmount);
        ILTokenOption lToken = ILTokenOption(_lTokenAddress);

        uint256 totalSupply = lToken.totalSupply();
        uint256 lShares;
        if (totalSupply == 0) {
            lShares = bAmount;
        } else {
            lShares = bAmount * totalSupply / totalDynamicEquity.itou();
        }

        lToken.mint(account, lShares);
        _liquidity += bAmount.utoi();

        emit AddLiquidity(account, lShares, bAmount);
    }

    function _removeLiquidity(address account, uint256 lShares) internal _lock_ {
        (int256 totalDynamicEquity, int256 minPoolRequiredMargin, ,) = _updateSymbolPricesAndFundingRates();
        ILTokenOption lToken = ILTokenOption(_lTokenAddress);

        uint256 totalSupply = lToken.totalSupply();
        uint256 bAmount = lShares * totalDynamicEquity.itou() / totalSupply;

        _liquidity -= bAmount.utoi();
        require((totalDynamicEquity - bAmount.utoi()) >= minPoolRequiredMargin,
            'pool insuf margin'
        );
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
        _updateSymbolPricesAndFundingRates();
        (uint256[] memory symbolIds,
         IPTokenOption.Position[] memory positions,
         bool[] memory positionUpdates,
         int256 margin) = _settleTraderFundingFee(account);

        int256 amount = bAmount.utoi();
        if (amount >= margin) {
            amount = margin;
            bAmount = amount.itou();
            margin = 0;
        } else {
            margin -= amount;
        }

        (bool initialMarginSafe,) = _getTraderMarginStatus(symbolIds, positions, margin);
        require(initialMarginSafe, 'insuf margin');
        _updateTraderPortfolio(account, symbolIds, positions, positionUpdates, margin);

        _transferOut(account, bAmount);

        emit RemoveMargin(account, bAmount);
    }

    // struct for temp use in trade function, to prevent stack too deep error
    struct TradeParams {
        uint256 index;
        int256 tradersNetVolume;
        int256 intrinsicPrice;
        int256 pmmPrice;
        int256 multiplier;
        int256 curCost;
        int256 fee;
        int256 realizedCost;
        int256 protocolFee;
        int256 oraclePrice;
        int256 strikePrice;
        bool isCall;
        int256 changeOfNotionalValue;
    }

    function _trade(address account, uint256 symbolId, int256 tradeVolume) internal _lock_ {

        (int256 totalDynamicEquity, int256 minPoolRequiredMargin, int256[] memory basePrices, int256[] memory Ks) = _updateSymbolPricesAndFundingRates();


        (uint256[] memory symbolIds,
         IPTokenOption.Position[] memory positions,
         bool[] memory positionUpdates,
         int256 margin) = _settleTraderFundingFee(account);

        TradeParams memory params;
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (symbolId == symbolIds[i]) {
                params.index = i;
                break;
            }
        }

        params.curCost = _queryTradePMM(symbolId, tradeVolume * _symbols[symbolId].multiplier / ONE, basePrices[params.index], Ks[params.index]);
        params.tradersNetVolume = _symbols[symbolId].tradersNetVolume;
        params.intrinsicPrice = _symbols[symbolId].intrinsicPrice;
        params.pmmPrice = _symbols[symbolId].pmmPrice;
        params.multiplier = _symbols[symbolId].multiplier;

        params.fee = params.curCost.abs() * _symbols[symbolId].feeRatio / ONE;
        params.oraclePrice = getOraclePrice(_symbols[symbolId].oracleAddress);
        params.strikePrice = _symbols[symbolId].strikePrice;
        params.isCall = _symbols[symbolId].isCall;
        params.changeOfNotionalValue  = ((params.tradersNetVolume + tradeVolume).abs() - params.tradersNetVolume.abs()) *
            params.oraclePrice / ONE * params.multiplier / ONE;

        if (!(positions[params.index].volume >= 0 && tradeVolume >= 0) && !(positions[params.index].volume <= 0 && tradeVolume <= 0)) {
            int256 absVolume = positions[params.index].volume.abs();
            int256 absTradeVolume = tradeVolume.abs();
            if (absVolume <= absTradeVolume) {
                // previous position is totally closed
                params.realizedCost = params.curCost * absVolume / absTradeVolume + positions[params.index].cost;
            } else {
                // previous position is partially closed
                params.realizedCost = positions[params.index].cost * absTradeVolume / absVolume + params.curCost;
            }
        }

        positions[params.index].volume += tradeVolume;
        positions[params.index].cost += params.curCost - params.realizedCost;
        positions[params.index].lastCumulativePremiumFundingRate = _symbols[symbolId].cumulativePremiumFundingRate;
        margin -= params.fee + params.realizedCost;
        positionUpdates[params.index] = true;

        _symbols[symbolId].tradersNetVolume += tradeVolume;
        _symbols[symbolId].tradersNetCost += params.curCost - params.realizedCost;

        params.protocolFee = params.fee * _protocolFeeCollectRatio / ONE;
        _protocolFeeAccrued += params.protocolFee;
        _liquidity += params.fee - params.protocolFee + params.realizedCost;

        minPoolRequiredMargin += params.changeOfNotionalValue * _dynamicInitialMarginRatio(params.oraclePrice, params.strikePrice, params.isCall) * 10 / ONE;
        require(totalDynamicEquity >= minPoolRequiredMargin, 'insuf liquidity');
        (bool initialMarginSafe,) = _getTraderMarginStatus(symbolIds, positions, margin);
        require(initialMarginSafe, 'insuf margin');

        _updateTraderPortfolio(account, symbolIds, positions, positionUpdates, margin);

        emit Trade(account, symbolId, tradeVolume, params.intrinsicPrice.itou(), params.pmmPrice.itou());
    }

    function _liquidate(address liquidator, address account) internal _lock_ {
        ( , , int256[] memory basePrices, int256[] memory Ks) = _updateSymbolPricesAndFundingRates();

        (uint256[] memory symbolIds, IPTokenOption.Position[] memory positions, , int256 margin) = _settleTraderFundingFee(account);

        (,bool maintenanceMarginSafe) = _getTraderMarginStatus(symbolIds, positions, margin);
        require( !maintenanceMarginSafe, 'cant liq');


        int256 netEquity = margin;
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (positions[i].volume != 0) {
                int256 curCost = _queryTradePMM(symbolIds[i], -positions[i].volume * _symbols[symbolIds[i]].multiplier / ONE, basePrices[i], Ks[i]);
                _symbols[symbolIds[i]].tradersNetVolume -= positions[i].volume;
                _symbols[symbolIds[i]].tradersNetCost -= positions[i].cost;
                netEquity -= curCost + positions[i].cost;
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
    function _updateSymbolVolatility(SignedPrice[] memory volatility) internal {
        for (uint256 i = 0; i < volatility.length; i++) {
            uint256 symbolId = volatility[i].symbolId;
            IVolatilityOracle(_symbols[symbolId].volatilityAddress).updateVolatility(
                volatility[i].timestamp,
                volatility[i].price,
                volatility[i].v,
                volatility[i].r,
                volatility[i].s
            );
        }
    }

    function getOraclePrice(address oracleAddress) internal view returns (int256) {
        return IOracleViewer(oracleAddress).getPrice().utoi();
    }

    function getMidPrice(uint256 symbolId) external view returns (int256, int256) {
        SymbolInfo storage s = _symbols[symbolId];
        int256 oraclePrice = getOraclePrice(s.oracleAddress);
        int256 intrinsicPrice = s.isCall ? (oraclePrice - s.strikePrice).max(0) : (s.strikePrice - oraclePrice).max(0);
        int256 volatility = IVolatilityOracle(s.volatilityAddress).getVolatility().utoi();
        (int256 timePrice, int256 delta) = OptionPricer.getEverlastingTimeValueAndDelta(oraclePrice, s.strikePrice, volatility, _T);
        if (s.isCall && intrinsicPrice > 0) {
                delta = delta + ONE ;
            } else if (!s.isCall && intrinsicPrice > 0) {
                delta = delta - ONE;
            } else {
                delta = delta;
            }

        int256 K;
        if (_liquidity == 0) {
            K = 0;
        } else {
            K =((oraclePrice * oraclePrice) / (timePrice + intrinsicPrice)) * delta.abs() * s.alpha / _liquidity / ONE;
        }

        int256 pmmPrice = PmmPricer.getMidPrice(timePrice + intrinsicPrice, (s.tradersNetVolume * s.multiplier / ONE), K);
        return (timePrice + intrinsicPrice, pmmPrice);
    }

    function _getMidPrice(uint256 symbolId, int256 oraclePrice, int256 intrinsicPrice) internal view returns (int256, int256, int256) {
        SymbolInfo storage s = _symbols[symbolId];
        int256 volatility = IVolatilityOracle(s.volatilityAddress).getVolatility().utoi();
        (int256 timePrice, int256 delta) = OptionPricer.getEverlastingTimeValueAndDelta(oraclePrice, s.strikePrice, volatility, _T);
        if (s.isCall && intrinsicPrice > 0) {
                delta = delta + ONE ;
            } else if (!s.isCall && intrinsicPrice > 0) {
                delta = delta - ONE;
            } else {
                delta = delta;
            }
        int256 K;
        if (_liquidity == 0) {
            K = 0;
        } else {
            K =((oraclePrice * oraclePrice) / (timePrice + intrinsicPrice)) * delta.abs() * s.alpha / _liquidity / ONE;
        }
        int256 pmmPrice = PmmPricer.getMidPrice(timePrice + intrinsicPrice, (s.tradersNetVolume * s.multiplier / ONE), K);
        return (timePrice + intrinsicPrice, pmmPrice, K);
    }

    function _queryTradePMM(uint256 symbolId, int256 volume, int256 basePrice, int256 K) internal view returns (int256 cost) {
        require(volume != 0, "inv Vol");
        SymbolInfo storage s = _symbols[symbolId];
        cost = PmmPricer.queryTradePMM(basePrice, (s.tradersNetVolume * s.multiplier / ONE), volume, K);
    }


    function _updateSymbolPricesAndFundingRates() internal returns (int256 totalDynamicEquity, int256 minPoolRequiredMargin, int256[] memory basePrices, int256[] memory Ks) {
        uint256 preTimestamp = _lastTimestamp;
        uint256 curTimestamp = block.timestamp;
        uint256[] memory symbolIds = IPTokenOption(_pTokenAddress).getActiveSymbolIds();
        basePrices = new int256[](symbolIds.length);
        Ks = new int256[](symbolIds.length);
        totalDynamicEquity = _liquidity;
        for (uint256 i = 0; i < symbolIds.length; i++) {
            SymbolInfo storage s = _symbols[symbolIds[i]];
            int256 oraclePrice = getOraclePrice(s.oracleAddress);
            int256 intrinsicPrice = s.isCall ? (oraclePrice - s.strikePrice).max(0) : (s.strikePrice - oraclePrice).max(0);
            s.intrinsicPrice = intrinsicPrice;
            (int256 basePrice, int256 pmmPrice, int256 K) = _getMidPrice(symbolIds[i], oraclePrice, intrinsicPrice);
            basePrices[i] = basePrice;
            Ks[i] = K;
            s.pmmPrice = pmmPrice;

            if (s.tradersNetVolume != 0) {
                int256 cost = s.tradersNetVolume *  pmmPrice / ONE * s.multiplier / ONE;
                totalDynamicEquity -= cost - s.tradersNetCost;
                int256 notionalValue = (s.tradersNetVolume * oraclePrice / ONE * s.multiplier / ONE);
                minPoolRequiredMargin += notionalValue.abs() * _dynamicInitialMarginRatio(oraclePrice, s.strikePrice, s.isCall) * 10 / ONE;
            }
        }

        if (curTimestamp > preTimestamp && _liquidity > 0) {
            for (uint256 i = 0; i < symbolIds.length; i++) {
                SymbolInfo storage s = _symbols[symbolIds[i]];
                // ratePerSec may be negative in some case
                int256 ratePerSec = (s.pmmPrice - s.intrinsicPrice) * s.multiplier / ONE  * _premiumFundingCoefficient / ONE;
                int256 offset = ratePerSec * int256(curTimestamp - preTimestamp);
                unchecked { s.cumulativePremiumFundingRate += offset; }
            }
        }
        _lastTimestamp = curTimestamp;
    }

    function _getTraderPortfolio(address account) internal view returns (
        uint256[] memory symbolIds,
        IPTokenOption.Position[] memory positions,
        bool[] memory positionUpdates,
        int256 margin
    ) {
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        symbolIds = pToken.getActiveSymbolIds();

        positions = new IPTokenOption.Position[](symbolIds.length);
        positionUpdates = new bool[](symbolIds.length);
        for (uint256 i = 0; i < symbolIds.length; i++) {
            positions[i] = pToken.getPosition(account, symbolIds[i]);
        }

        margin = pToken.getMargin(account);
    }

    function _updateTraderPortfolio(
        address account,
        uint256[] memory symbolIds,
        IPTokenOption.Position[] memory positions,
        bool[] memory positionUpdates,
        int256 margin
    ) internal {
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (positionUpdates[i]) {
                pToken.updatePosition(account, symbolIds[i], positions[i]);
            }
        }
        pToken.updateMargin(account, margin);
    }

    function _settleTraderFundingFee(address account) internal returns (
        uint256[] memory symbolIds,
        IPTokenOption.Position[] memory positions,
        bool[] memory positionUpdates,
        int256 margin
    ) {
        (symbolIds, positions, positionUpdates, margin) = _getTraderPortfolio(account);
        int256 funding;
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (positions[i].volume != 0) {
                int256 delta;
                int256 cumulativePremiumFundingRate = _symbols[symbolIds[i]].cumulativePremiumFundingRate;
                unchecked { delta = cumulativePremiumFundingRate - positions[i].lastCumulativePremiumFundingRate; }
                funding += positions[i].volume * delta / ONE;
                positions[i].lastCumulativePremiumFundingRate = cumulativePremiumFundingRate;
                positionUpdates[i] = true;
            }
        }
        if (funding != 0) {
            margin -= funding;
            _liquidity += funding;
        }
    }

    function _getTraderMarginStatus(
        uint256[] memory symbolIds,
        IPTokenOption.Position[] memory positions,
        int256 margin
    ) internal view returns (bool, bool) {
        int256 totalDynamicMargin = margin;
        int256 totalMinInitialMargin;
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (positions[i].volume != 0) {
                SymbolInfo memory s = _symbols[symbolIds[i]];
                int256 cost = positions[i].volume *  s.pmmPrice / ONE * s.multiplier / ONE;
                totalDynamicMargin += cost - positions[i].cost;

                int256 oraclePrice = getOraclePrice(s.oracleAddress);
                int256 notionalValue = (positions[i].volume * oraclePrice / ONE * s.multiplier / ONE);
                totalMinInitialMargin += notionalValue.abs() * _dynamicInitialMarginRatio(oraclePrice, s.strikePrice, s.isCall) / ONE;
            }
        }
        int256 totalMinMaintenanceMargin = totalMinInitialMargin * _maintenanceMarginRatio / _initialMarginRatio;
        return (totalDynamicMargin >= totalMinInitialMargin, totalDynamicMargin >= totalMinMaintenanceMargin);
    }

    function _dynamicInitialMarginRatio(int256 spotPrice, int256 strikePrice, bool isCall) view internal returns (int256) {
        if ((strikePrice>=spotPrice && !isCall) || (strikePrice<=spotPrice && isCall)) {
            return _initialMarginRatio;
        }
        else {
            int256 OTMRatio = isCall? ((strikePrice - spotPrice) * ONE / strikePrice) : ((spotPrice - strikePrice) * ONE /strikePrice);
            int256 dynInitialMarginRatio = ((ONE - OTMRatio * 3) * _initialMarginRatio / ONE).max(MinInitialMarginRatio);
            return dynInitialMarginRatio;
        }
    }

    function _transferIn(address from, uint256 bAmount) internal returns (uint256) {
        IERC20 bToken = IERC20(_bTokenAddress);
        uint256 balance1 = bToken.balanceOf(address(this));
        bToken.safeTransferFrom(from, address(this), bAmount.rescale(18, _decimals));
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
