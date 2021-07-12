// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;
import "../interface/IEverlastingOption.sol";
import '../interface/ILTokenOption.sol';
import '../interface/IPTokenOption.sol';
import '../interface/IERC20.sol';
import '../interface/IOracle.sol';
import '../interface/ILiquidatorQualifier.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';
import '../utils/Migratable.sol';
//import '.。/utils/Ownable.sol';
import {Pricing} from '../pricing/Pricing.sol';
import {EverlastingOptionPricing} from '../library/EverlastingOptionPricing.sol';
import "hardhat/console.sol";


contract EverlastingOption is IEverlastingOption, Migratable {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    Pricing public PRICING;
    EverlastingOptionPricing public OPTIONPRICING;
    int256  constant ONE = 10**18;
    uint256 public _T = 10**18 / uint256(365); // premium funding period = 1 hour (in one year scale)
    int256 public _premiumFundingCoefficient = 10**18 / int256(3600*24); // premium funding rate per sec

    uint256 immutable _decimals;
    int256  immutable _minPoolMarginRatio;
    int256  immutable _minInitialMarginRatio;
    int256  immutable _minMaintenanceMarginRatio;
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
        uint256[7] memory parameters,
        address[5] memory addresses) {
        PRICING = Pricing(pricingAddress);
        OPTIONPRICING = EverlastingOptionPricing(everlastingPricingOptionAddress);
        _controller = msg.sender;
        _minPoolMarginRatio = int256(parameters[0]);
        _minInitialMarginRatio = int256(parameters[1]);
        _minMaintenanceMarginRatio = int256(parameters[2]);
        _minLiquidationReward = int256(parameters[3]);
        _maxLiquidationReward = int256(parameters[4]);
        _liquidationCutRatio = int256(parameters[5]);
        _protocolFeeCollectRatio = int256(parameters[6]);

        _bTokenAddress = addresses[0];
        _lTokenAddress = addresses[1];
        _pTokenAddress = addresses[2];
        _liquidatorQualifierAddress = addresses[3];
        _protocolFeeCollector = addresses[4];

        // only supports bToken of decimals 18
        _decimals = IERC20(addresses[0]).decimals();
    }

    // during a migration, this function is intended to be called in the source pool
    function approveMigration() external override _controller_ {
        require(_migrationTimestamp != 0 && block.timestamp >= _migrationTimestamp, 'PerpetualPool: migrationTimestamp not met yet');
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
        require(migrationTimestamp_ != 0 && block.timestamp >= migrationTimestamp_, 'PerpetualPool: migrationTimestamp not met yet');
        require(migrationDestination_ == address(this), 'PerpetualPool: not destination pool');

        // transfer bToken to this address
        IERC20(_bTokenAddress).safeTransferFrom(source, address(this), IERC20(_bTokenAddress).balanceOf(source));

        // transfer symbol infos
        uint256[] memory symbolIds = IPTokenOption(_pTokenAddress).getActiveSymbolIds();
        for (uint256 i = 0; i < symbolIds.length; i++) {
            _symbols[symbolIds[i]] = IEverlastingOption(source).getSymbol(symbolIds[i]);
        }

        // transfer state values
        _liquidity = IEverlastingOption(source).getLiquidity();
        _protocolFeeAccrued = IEverlastingOption(source).getProtocolFeeAccrued();

        emit ExecuteMigration(migrationTimestamp_, source, migrationDestination_);
    }


    function getParameters() external override view returns (
        int256 minPoolMarginRatio,
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    ) {
        return (
            _minPoolMarginRatio,
            _minInitialMarginRatio,
            _minMaintenanceMarginRatio,
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

    function getProtocolFeeAccrued() external override view returns (int256) {
        return _protocolFeeAccrued;
    }

    function collectProtocolFee() external override {
        uint256 balance = IERC20(_bTokenAddress).balanceOf(address(this));
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
        uint256 multiplier,
        uint256 feeRatio,
        uint256 diseqFundingCoefficient,
        uint256 volatility,
        uint256 k
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.symbolId = symbolId;
        s.symbol = symbol;
        s.strikePrice = int256(strikePrice);
        s.isCall = isCall;
        s.oracleAddress = oracleAddress;
        s.multiplier = int256(multiplier);
        s.feeRatio = int256(feeRatio);
        s.diseqFundingCoefficient = int256(diseqFundingCoefficient);
        s.volatility = int256(volatility);
        s.K = k;
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
        uint256 feeRatio,
        uint256 diseqFundingCoefficient,
        uint256 volatility,
        uint256 k
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.oracleAddress = oracleAddress;
        s.feeRatio = int256(feeRatio);
        s.diseqFundingCoefficient = int256(diseqFundingCoefficient);
        s.volatility = int256(volatility);
        s.K = k;
    }

    function setPoolParameters(uint256 premiumFundingCoefficient, uint256 T) external _controller_ {
        _premiumFundingCoefficient = int256(premiumFundingCoefficient);
        _T = T;
    }


    //================================================================================
    // Interactions
    //================================================================================

    function addLiquidity(uint256 bAmount, OraclePrice[] memory prices) external override {
        require(bAmount > 0, 'PerpetualPool: 0 bAmount');
        _addLiquidity(msg.sender, bAmount);
    }

    function removeLiquidity(uint256 lShares, OraclePrice[] memory prices) external override {
        require(lShares > 0, 'PerpetualPool: 0 lShares');
        _removeLiquidity(msg.sender, lShares);
    }

    function addMargin(uint256 bAmount, OraclePrice[] memory prices) external override {
        require(bAmount > 0, 'PerpetualPool: 0 bAmount');
        _addMargin(msg.sender, bAmount);
    }

    function removeMargin(uint256 bAmount, OraclePrice[] memory prices) external override {
        require(bAmount > 0, 'PerpetualPool: 0 bAmount');
        _removeMargin(msg.sender, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume, OraclePrice[] memory prices) external override {
        require(IPTokenOption(_pTokenAddress).isActiveSymbolId(symbolId), 'PerpetualPool: invalid symbolId');
        require(tradeVolume != 0 && tradeVolume / ONE * ONE == tradeVolume, 'PerpetualPool: invalid tradeVolume');
        _trade(msg.sender, symbolId, tradeVolume);
    }

    function liquidate(address account, OraclePrice[] memory prices) external override {
        address liquidator = msg.sender;
        require(
            _liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(liquidator),
            'PerpetualPool: not qualified liquidator'
        );
        _liquidate(liquidator, account);
    }


    //================================================================================
    // Core logics
    //================================================================================

    function _addLiquidity(address account, uint256 bAmount) internal _lock_ {
        (int256 totalDynamicEquity, ) = _updateSymbolPricesAndFundingRates();

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
        (int256 totalDynamicEquity, int256 totalAbsCost) = _updateSymbolPricesAndFundingRates();
        ILTokenOption lToken = ILTokenOption(_lTokenAddress);

        uint256 totalSupply = lToken.totalSupply();
        uint256 bAmount = lShares * totalDynamicEquity.itou() / totalSupply;

        _liquidity -= bAmount.utoi();
        require(
            totalAbsCost == 0 || (totalDynamicEquity - bAmount.utoi()) * ONE / totalAbsCost >= _minPoolMarginRatio,
            'PerpetualPool: pool insufficient margin'
        );
//        console.log("_removeLiquidity: totalSupply", totalSupply);
//        console.log("_removeLiquidity: totalDynamicEquity");
//        console.logInt(totalDynamicEquity);
//        console.log("_removeLiquidity: lShares", lShares);
//        console.log("_removeLiquidity: bAmount", bAmount);
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

        require(_getTraderMarginRatio(symbolIds, positions, margin) >= _minInitialMarginRatio, 'PerpetualPool: insufficient margin');
        _updateTraderPortfolio(account, symbolIds, positions, positionUpdates, margin);
        _transferOut(account, bAmount);

        emit RemoveMargin(account, bAmount);
    }

    // struct for temp use in trade function, to prevent stack too deep error
    struct TradeParams {
        int256 tradersNetVolume;
        int256 intrinsicValue;
        int256 timeValue;
        int256 multiplier;
        int256 curCost;
        int256 fee;
        int256 realizedCost;
        int256 protocolFee;
    }

    function _trade(address account, uint256 symbolId, int256 tradeVolume) internal _lock_ {
        (int256 totalDynamicEquity, int256 totalAbsCost) = _updateSymbolPricesAndFundingRates();
        console.log("_trade1");
        console.logInt(totalAbsCost);

        (uint256[] memory symbolIds,
         IPTokenOption.Position[] memory positions,
         bool[] memory positionUpdates,
         int256 margin) = _settleTraderFundingFee(account);

        uint256 index;
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (symbolId == symbolIds[i]) {
                index = i;
                break;
            }
        }

        TradeParams memory params;

        int256 tvCost = _queryTradePMM(symbolId, tradeVolume * _symbols[symbolId].multiplier / ONE);

        _updateQuoteBalance(symbolId, tvCost);
        params.tradersNetVolume = _symbols[symbolId].tradersNetVolume;
        params.intrinsicValue = _symbols[symbolId].intrinsicValue;
        params.timeValue = _symbols[symbolId].timeValue;
        params.multiplier = _symbols[symbolId].multiplier;
        params.curCost = tradeVolume * params.intrinsicValue / ONE * params.multiplier / ONE + tvCost;
        params.fee = params.curCost.abs() * _symbols[symbolId].feeRatio / ONE;

        if (!(positions[index].volume >= 0 && tradeVolume >= 0) && !(positions[index].volume <= 0 && tradeVolume <= 0)) {
            int256 absVolume = positions[index].volume.abs();
            int256 absTradeVolume = tradeVolume.abs();
            if (absVolume <= absTradeVolume) {
                // previous position is totally closed
                params.realizedCost = params.curCost * absVolume / absTradeVolume + positions[index].cost;
            } else {
                // previous position is partially closed
                params.realizedCost = positions[index].cost * absTradeVolume / absVolume + params.curCost;
            }
        }

        // adjust totalAbsCost after trading
//        totalAbsCost -= (positions[index].volume * (params.intrinsicValue + params.timeValue) / ONE * params.multiplier / ONE).abs();
//        console.log("_trade2");
//        console.logInt(totalAbsCost);
//        totalAbsCost += ((positions[index].volume + tradeVolume) * (params.intrinsicValue + params.timeValue) / ONE * params.multiplier / ONE).abs();
//        console.log("_trade3");
//        console.logInt(totalAbsCost);

        totalAbsCost += ((params.tradersNetVolume + tradeVolume).abs() - params.tradersNetVolume.abs()) *
                        (params.intrinsicValue + params.timeValue) / ONE * params.multiplier / ONE;

        positions[index].volume += tradeVolume;
        positions[index].cost += params.curCost - params.realizedCost;
        positions[index].lastCumulativeDiseqFundingRate = _symbols[symbolId].cumulativeDiseqFundingRate;
        positions[index].lastCumulativePremiumFundingRate = _symbols[symbolId].cumulativePremiumFundingRate;
        margin -= params.fee + params.realizedCost;
        positionUpdates[index] = true;

        _symbols[symbolId].tradersNetVolume += tradeVolume;
        _symbols[symbolId].tradersNetCost += params.curCost - params.realizedCost;

        params.protocolFee = params.fee * _protocolFeeCollectRatio / ONE;
        _protocolFeeAccrued += params.protocolFee;
        _liquidity += params.fee - params.protocolFee + params.realizedCost;

        console.log("EO.trade totalAbsCost totalDynamicEquity");
        console.logInt(totalAbsCost);
        console.logInt(totalDynamicEquity);
        require(totalAbsCost == 0 || totalDynamicEquity * ONE / totalAbsCost >= _minPoolMarginRatio, 'PerpetualPool: insufficient liquidity');
        _updateTraderPortfolio(account, symbolIds, positions, positionUpdates, margin);
        require(_getTraderMarginRatio(symbolIds, positions, margin) >= _minInitialMarginRatio, 'PerpetualPool: insufficient margin');
        emit Trade(account, symbolId, tradeVolume, params.intrinsicValue.itou(), params.timeValue.itou());
    }

    function _liquidate(address liquidator, address account) internal _lock_ {
        _updateSymbolPricesAndFundingRates();

        (uint256[] memory symbolIds, IPTokenOption.Position[] memory positions, , int256 margin) = _settleTraderFundingFee(account);
        require(_getTraderMarginRatio(symbolIds, positions, margin) < _minMaintenanceMarginRatio, 'PerpetualPool: cannot liquidate');

        int256 netEquity = margin;
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (positions[i].volume != 0) {
                int256 tvCost = _queryTradePMM(symbolIds[i], -positions[i].volume * _symbols[symbolIds[i]].multiplier / ONE);
                _symbols[symbolIds[i]].tradersNetVolume -= positions[i].volume;
                _symbols[symbolIds[i]].tradersNetCost -= positions[i].cost;
                int256 curCost = -positions[i].volume * _symbols[symbolIds[i]].intrinsicValue / ONE * _symbols[symbolIds[i]].multiplier / ONE + tvCost;
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
    function _getIntrinsicValuePrice(uint256 symbolId) public view returns (int256 price) {
        SymbolInfo storage s = _symbols[symbolId];
        int256 oraclePrice = IOracle(s.oracleAddress).getPrice().utoi();
        price = s.isCall ? (oraclePrice - s.strikePrice).max(0) : (s.strikePrice - oraclePrice).max(0);
    }

    function _getTimeValuePrice(uint256 symbolId) public view returns (int256) {
        int256 intrinsicPrice = _getIntrinsicValuePrice(symbolId);
        SymbolInfo storage s = _symbols[symbolId];
        uint256 oraclePrice = IOracle(s.oracleAddress).getPrice();
//        console.log('oraclePrice %s, strikePrice %s votatility %s', oraclePrice, s.strikePrice.itou(), s.volatility.itou());
//        console.log("_T", _T);
//        if (s.isCall) console.log("isCall");
//        int256 optionPrice = s.isCall
//            ? OPTIONPRICING.pricingCall(oraclePrice, s.strikePrice.itou(), s.volatility.itou(), _T, 10)
//            : OPTIONPRICING.pricingPut(oraclePrice, s.strikePrice.itou(), s.volatility.itou(), _T, 10);
        int256 optionPrice = s.isCall
            ? OPTIONPRICING.getEverlastingCallPriceConvergeEarlyStop(oraclePrice, s.strikePrice.itou(), s.volatility.itou(), _T, 10**15)
            : OPTIONPRICING.getEverlastingPutPriceConvergeEarlyStop(oraclePrice, s.strikePrice.itou(), s.volatility.itou(), _T, 10**15);
//        console.log("getTimeValuePrice");
//        console.logInt(optionPrice);
//        console.log("getIntrinsicPrice");
//        console.logInt(intrinsicPrice);
        int256 price = optionPrice - intrinsicPrice;
        return price;
    }

    function _getTvMidPrice(uint256 symbolId) public view returns (int256) {
        int256 timePrice = _getTimeValuePrice(symbolId);
        if (_liquidity <= 0) return timePrice;
        SymbolInfo storage s = _symbols[symbolId];
        Side side = s.tradersNetVolume == 0 ? Side.FLAT : (s.tradersNetVolume > 0 ? Side.SHORT : Side.LONG);
        VirtualBalance memory updateBalance = PRICING.getExpectedTargetExt(
            side, (_liquidity + s.quote_balance_premium).itou(), timePrice.itou(), (s.tradersNetVolume * s.multiplier / ONE).abs().itou(), s.K
        ); // 用_liquidity 而不是 totalDynamicEquity

//        console.log("_getTimeValuePrice.updateBalance baseBalance %s baseTarget %s", updateBalance.baseBalance/10**18, updateBalance.baseTarget/10**18);
//        console.log("_getTimeValuePrice.updateBalance quoteBalance %s quoteTarget %s", updateBalance.quoteBalance/10**18, updateBalance.quoteTarget/10**18);
        int256 midPrice = (PRICING.getMidPrice(updateBalance, timePrice.itou(), s.K)).utoi();
        return midPrice;
    }



    function _queryTradePMM(uint256 symbolId, int256 volume) public view returns (int256 tvCost) {
        require(volume != 0, "invalid tradeVolume");
        int256 timePrice = _getTimeValuePrice(symbolId);
        SymbolInfo storage s = _symbols[symbolId];
        Side side = s.tradersNetVolume == 0 ? Side.FLAT : (s.tradersNetVolume > 0 ? Side.SHORT : Side.LONG);
        VirtualBalance memory updateBalance = PRICING.getExpectedTargetExt(
            side, (_liquidity + s.quote_balance_premium).itou(), timePrice.itou(), (s.tradersNetVolume * s.multiplier / ONE).abs().itou() , s.K
        ); // 用_liquidity 而不是 totalDynamicEquity

//        console.log("_queryTradeWithPMM.oraclePrice", timePrice.itou());
//        console.log("_queryTradeWithPMM.updateBalance baseBalance %s baseTarget %s", updateBalance.baseBalance, updateBalance.baseTarget);
//        console.log("_queryTradeWithPMM.updateBalance quoteBalance %s quoteTarget %s", updateBalance.quoteBalance, updateBalance.quoteTarget);
//        if (updateBalance.newSide == Side.FLAT) console.log("_queryTradeWithPMM.updateBalance.newSide is FLAT");
//        if (updateBalance.newSide == Side.LONG) console.log("_queryTradeWithPMM.updateBalance.newSide is LONG");
//        if (updateBalance.newSide == Side.SHORT) console.log("_queryTradeWithPMM.updateBalance.newSide is SHORT");
        uint256 deltaQuote;
        if (volume >= 0) {
            (deltaQuote, ) = PRICING._queryBuyBaseToken(
                updateBalance, timePrice.itou(), s.K, volume.itou()
            );
            tvCost = deltaQuote.utoi();
        } else {
            (deltaQuote, ) = PRICING._querySellBaseToken(
                updateBalance, timePrice.itou(), s.K, (- volume).itou()
            );
            tvCost = -(deltaQuote.utoi());
        }
    }

    function _updateQuoteBalance(uint256 symbolId, int256 addBalance) internal {
        SymbolInfo storage s = _symbols[symbolId];
        s.quote_balance_premium += addBalance;
    }

//    function _getTotalDynamicEquity() public view returns (int256 totalDynamicEquity, int256 totalAbsCost) {
//        uint256[] memory symbolIds = IPTokenOption(_pTokenAddress).getActiveSymbolIds();
//        totalDynamicEquity = _liquidity;
//        for (uint256 i = 0; i < symbolIds.length; i++) {
//            SymbolInfo storage s = _symbols[symbolIds[i]];
//            int256 intrinsicPrice = _getIntrinsicValuePrice(symbolIds[i]);
//            int256 timePrice = _getTvMidPrice(symbolIds[i]);
//
//            if (s.tradersNetVolume != 0) {
//                int256 cost = s.tradersNetVolume * (intrinsicPrice + timePrice) / ONE * s.multiplier / ONE;
//                totalDynamicEquity -= cost - s.tradersNetCost;
//                totalAbsCost += cost.abs();
//            }
//        }
//    }


    function _updateSymbolPricesAndFundingRates() internal returns (int256 totalDynamicEquity, int256 totalAbsCost) {
        uint256 preTimestamp = _lastTimestamp;
        uint256 curTimestamp = block.timestamp;
        uint256[] memory symbolIds = IPTokenOption(_pTokenAddress).getActiveSymbolIds();

        totalDynamicEquity = _liquidity;
        int256[] memory lastTvMidPirce = new int256[](symbolIds.length);
        for (uint256 i = 0; i < symbolIds.length; i++) {
            SymbolInfo storage s = _symbols[symbolIds[i]];
            int256 intrinsicPrice = _getIntrinsicValuePrice(symbolIds[i]);
            int256 timePrice = _getTvMidPrice(symbolIds[i]);
            s.intrinsicValue = intrinsicPrice;
            lastTvMidPirce[i] = s.timeValue;
            s.timeValue = timePrice;

            if (s.tradersNetVolume != 0) {
                int256 cost = s.tradersNetVolume * (intrinsicPrice + timePrice) / ONE * s.multiplier / ONE;
                totalDynamicEquity -= cost - s.tradersNetCost;
                totalAbsCost += cost.abs();
            }
        }

        if (curTimestamp > preTimestamp && _liquidity > 0) {
            for (uint256 i = 0; i < symbolIds.length; i++) {
                SymbolInfo storage s = _symbols[symbolIds[i]];
                if (s.tradersNetVolume != 0) {
                    int256 ratePerSec1 = s.tradersNetVolume * s.intrinsicValue / ONE * s.intrinsicValue / ONE * s.multiplier / ONE * s.multiplier / ONE * s.diseqFundingCoefficient / totalDynamicEquity;
                    int256 delta1 = ratePerSec1 * int256(curTimestamp - preTimestamp);
                    unchecked { s.cumulativeDiseqFundingRate += delta1; }

                    int256 ratePerSec2 = lastTvMidPirce[i] * s.multiplier / ONE  * _premiumFundingCoefficient / ONE;
                    int256 delta2 = ratePerSec2 * int256(curTimestamp - preTimestamp);
                    unchecked { s.cumulativePremiumFundingRate += delta2; }
                }
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
                int256 cumulativeDiseqFundingRate = _symbols[symbolIds[i]].cumulativeDiseqFundingRate;
                int256 delta;
                unchecked { delta = cumulativeDiseqFundingRate - positions[i].lastCumulativeDiseqFundingRate; }
                funding += positions[i].volume * delta / ONE;
//                console.log("_settleTraderFundingFee1 _settleTraderFundingFee2 i %s, delta %s", i, delta.itou());
//                console.log("position[i].volume");
//                console.logInt(positions[i].volume);
//                console.logInt(positions[i].volume * delta / ONE);

                positions[i].lastCumulativeDiseqFundingRate = cumulativeDiseqFundingRate;

                int256 cumulativePremiumFundingRate = _symbols[symbolIds[i]].cumulativePremiumFundingRate;
                unchecked { delta = cumulativePremiumFundingRate - positions[i].lastCumulativePremiumFundingRate; }
//                console.log("_settleTraderFundingFee1 _settleTraderFundingFee2 i %s, delta %s", i, delta.itou());
                funding += positions[i].volume * delta / ONE;
//                console.logInt(positions[i].volume * delta / ONE);
                positions[i].lastCumulativePremiumFundingRate = cumulativePremiumFundingRate;

                positionUpdates[i] = true;
            }
        }
        if (funding != 0) {
            margin -= funding;
            _liquidity += funding;
        }
    }

    function _getTraderMarginRatio(
        uint256[] memory symbolIds,
        IPTokenOption.Position[] memory positions,
        int256 margin
    ) internal view returns (int256) {
        int256 totalDynamicEquity = margin;
        int256 totalAbsCost;
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (positions[i].volume != 0) {
                int256 cost = positions[i].volume * (_symbols[symbolIds[i]].intrinsicValue+_symbols[symbolIds[i]].timeValue) / ONE * _symbols[symbolIds[i]].multiplier / ONE;
                totalDynamicEquity += cost - positions[i].cost;
                totalAbsCost += cost.abs();
            }
        }
        int256 marginRatio = totalAbsCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalAbsCost;
//        console.log("_getTraderMarginRatio");
//        console.logInt(marginRatio);
        return marginRatio;
    }

    function _deflationCompatibleSafeTransferFrom(address from, address to, uint256 bAmount) internal returns (uint256) {
        IERC20 bToken = IERC20(_bTokenAddress);
        uint256 balance1 = bToken.balanceOf(to);
        bToken.safeTransferFrom(from, to, bAmount);
        uint256 balance2 = bToken.balanceOf(to);
        return balance2 - balance1;
    }

    function _transferIn(address from, uint256 bAmount) internal returns (uint256) {
        uint256 amount = _deflationCompatibleSafeTransferFrom(from, address(this), bAmount.rescale(18, _decimals));
        return amount.rescale(_decimals, 18);
    }

    function _transferOut(address to, uint256 bAmount) internal {
        uint256 amount = bAmount.rescale(18, _decimals);
        uint256 leftover = bAmount - amount.rescale(_decimals, 18);
        // leftover due to decimal precision is accrued to _protocolFeeAccrued
        _protocolFeeAccrued += leftover.utoi();
        IERC20(_bTokenAddress).safeTransfer(to, amount);
    }

}
