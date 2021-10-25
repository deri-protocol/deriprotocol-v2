// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IPerpetualPoolOld.sol';
import '../interface/IPerpetualPool.sol';
import '../interface/IERC20.sol';
import '../interface/IOracle.sol';
import '../interface/IPToken.sol';
import '../interface/ILToken.sol';
import '../interface/IBTokenSwapper.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';
import '../library/DpmmPricerFutures.sol';

contract PerpetualPool is IPerpetualPool {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256  constant ONE = 10**18;

    // decimals for bToken0 (settlement token), make this immutable to save gas
    uint256 immutable _decimals0;
    int256  immutable _minBToken0Ratio;
    int256  immutable _minPoolMarginRatio;
    int256  immutable _initialMarginRatio;
    int256  immutable _maintenanceMarginRatio;
    int256  immutable _minLiquidationReward;
    int256  immutable _maxLiquidationReward;
    int256  immutable _liquidationCutRatio;
    int256  immutable _protocolFeeCollectRatio;

    address immutable _lTokenAddress;
    address immutable _pTokenAddress;
    address immutable _routerAddress;
    address immutable _protocolFeeCollector;

    BTokenInfo[] _bTokens;   // bTokenId indexed
    SymbolInfo[] _symbols;   // symbolId indexed

    // funding period in seconds, funding collected for each volume during this period will be (dpmmPrice - indexPrice)
    int256 constant _fundingPeriod = 3 * 24 * 3600 * ONE;

    uint256 _lastTimestamp;
    int256  _protocolFeeAccrued;

    bool private _mutex;
    modifier _lock_() {
        require(!_mutex, 'reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    constructor (uint256[9] memory parameters, address[4] memory addresses) {
        _decimals0 = parameters[0];
        _minBToken0Ratio = int256(parameters[1]);
        _minPoolMarginRatio = int256(parameters[2]);
        _initialMarginRatio = int256(parameters[3]);
        _maintenanceMarginRatio = int256(parameters[4]);
        _minLiquidationReward = int256(parameters[5]);
        _maxLiquidationReward = int256(parameters[6]);
        _liquidationCutRatio = int256(parameters[7]);
        _protocolFeeCollectRatio = int256(parameters[8]);

        _lTokenAddress = addresses[0];
        _pTokenAddress = addresses[1];
        _routerAddress = addresses[2];
        _protocolFeeCollector = addresses[3];
    }

    function getParameters() external override view returns (
        uint256 decimals0,
        int256  minBToken0Ratio,
        int256  minPoolMarginRatio,
        int256  initialMarginRatio,
        int256  maintenanceMarginRatio,
        int256  minLiquidationReward,
        int256  maxLiquidationReward,
        int256  liquidationCutRatio,
        int256  protocolFeeCollectRatio
    ) {
        decimals0 = _decimals0;
        minBToken0Ratio = _minBToken0Ratio;
        minPoolMarginRatio = _minPoolMarginRatio;
        initialMarginRatio = _initialMarginRatio;
        maintenanceMarginRatio = _maintenanceMarginRatio;
        minLiquidationReward = _minLiquidationReward;
        maxLiquidationReward = _maxLiquidationReward;
        liquidationCutRatio = _liquidationCutRatio;
        protocolFeeCollectRatio = _protocolFeeCollectRatio;
    }

    function getAddresses() external override view returns (
        address lTokenAddress,
        address pTokenAddress,
        address routerAddress,
        address protocolFeeCollector
    ) {
        lTokenAddress = _lTokenAddress;
        pTokenAddress = _pTokenAddress;
        routerAddress = _routerAddress;
        protocolFeeCollector = _protocolFeeCollector;
    }

    function getLengths() external override view returns (uint256, uint256) {
        return (_bTokens.length, _symbols.length);
    }

    function getBToken(uint256 bTokenId) external override view returns (BTokenInfo memory) {
        return _bTokens[bTokenId];
    }

    function getSymbol(uint256 symbolId) external override view returns (SymbolInfo memory) {
        return _symbols[symbolId];
    }

    function getSymbolOracle(uint256 symbolId) external override view returns (address) {
        return _symbols[symbolId].oracleAddress;
    }

    function getPoolStateValues() external override view returns (uint256 lastTimestamp, int256 protocolFeeAccrued) {
        return (_lastTimestamp, _protocolFeeAccrued);
    }

    function collectProtocolFee() external override {
        IERC20 token = IERC20(_bTokens[0].bTokenAddress);
        uint256 amount = _protocolFeeAccrued.itou().rescale(18, _decimals0);
        // if (amount > token.balanceOf(address(this))) amount = token.balanceOf(address(this));
        _protocolFeeAccrued -= amount.rescale(_decimals0, 18).utoi();
        token.safeTransfer(_protocolFeeCollector, amount);
        emit ProtocolFeeCollection(_protocolFeeCollector, amount.rescale(_decimals0, 18));
    }

    function addBToken(BTokenInfo memory info) external override {
        _checkRouter();
        _addBToken(info);
        ILToken(_lTokenAddress).setNumBTokens(_bTokens.length);
        IPToken(_pTokenAddress).setNumBTokens(_bTokens.length);
    }

    function addSymbol(SymbolInfo memory info) external override {
        _checkRouter();
        _symbols.push(info);
        IPToken(_pTokenAddress).setNumSymbols(_symbols.length);
    }

    function setBTokenParameters(
        uint256 bTokenId,
        address swapperAddress,
        address oracleAddress,
        uint256 discount
    ) external override {
        _checkRouter();
        BTokenInfo storage b = _bTokens[bTokenId];
        b.swapperAddress = swapperAddress;
        if (bTokenId != 0) {
            IERC20(_bTokens[0].bTokenAddress).safeApprove(swapperAddress, 0);
            IERC20(_bTokens[bTokenId].bTokenAddress).safeApprove(swapperAddress, 0);
            IERC20(_bTokens[0].bTokenAddress).safeApprove(swapperAddress, type(uint256).max);
            IERC20(_bTokens[bTokenId].bTokenAddress).safeApprove(swapperAddress, type(uint256).max);
        }
        b.oracleAddress = oracleAddress;
        b.discount = discount.utoi();
    }

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        uint256 feeRatio,
        uint256 alpha
    ) external override {
        _checkRouter();
        SymbolInfo storage s = _symbols[symbolId];
        s.oracleAddress = oracleAddress;
        s.feeRatio = feeRatio.utoi();
        s.alpha = alpha.utoi();
    }


    //================================================================================
    // Migration, can only be called during migration process
    //================================================================================

    function approveBTokenForTargetPool(uint256 bTokenId, address targetPool) external override {
        _checkRouter();
        IERC20(_bTokens[bTokenId].bTokenAddress).safeApprove(targetPool, type(uint256).max);
    }

    function setPoolForLTokenAndPToken(address targetPool) external override {
        _checkRouter();
        ILToken(_lTokenAddress).setPool(targetPool);
        IPToken(_pTokenAddress).setPool(targetPool);
    }

    function migrateBToken(
        address sourcePool,
        uint256 balance,
        address bTokenAddress,
        address swapperAddress,
        address oracleAddress,
        uint256 decimals,
        int256  discount,
        int256  liquidity,
        int256  pnl,
        int256  cumulativePnl
    ) external override {
        _checkRouter();
        IERC20(bTokenAddress).safeTransferFrom(sourcePool, address(this), balance);
        BTokenInfo memory b;
        b.bTokenAddress = bTokenAddress;
        b.swapperAddress = swapperAddress;
        b.oracleAddress = oracleAddress;
        b.decimals = decimals;
        b.discount = discount;
        b.liquidity = liquidity;
        b.pnl = pnl;
        b.cumulativePnl = cumulativePnl;
        _addBToken(b);
    }

    function migrateSymbol(
        string memory symbol,
        address oracleAddress,
        int256  multiplier,
        int256  feeRatio,
        int256  alpha,
        int256  distributedUnrealizedPnl,
        int256  tradersNetVolume,
        int256  tradersNetCost,
        int256  cumulativeFundingRate
    ) external override {
        _checkRouter();
        SymbolInfo memory s;
        s.symbol = symbol;
        s.oracleAddress = oracleAddress;
        s.multiplier = multiplier;
        s.feeRatio = feeRatio;
        s.alpha = alpha;
        s.distributedUnrealizedPnl = distributedUnrealizedPnl;
        s.tradersNetVolume = tradersNetVolume;
        s.tradersNetCost = tradersNetCost;
        s.cumulativeFundingRate = cumulativeFundingRate;
        _symbols.push(s);
    }

    function migratePoolStateValues(uint256 lastTimestamp, int256 protocolFeeAccrued) external override {
        _checkRouter();
        _lastTimestamp = lastTimestamp;
        _protocolFeeAccrued = protocolFeeAccrued;
    }


    //================================================================================
    // Interactions
    //================================================================================

    function addLiquidity(address lp, uint256 bTokenId, uint256 bAmount) external override _lock_ {
        _checkRouter();
        Data memory data = _getBTokensAndSymbols(bTokenId, type(uint256).max);
        _distributePnlToBTokens(data);
        BTokenData memory b = data.bTokens[bTokenId];

        ILToken lToken = ILToken(_lTokenAddress);
        if(!lToken.exists(lp)) lToken.mint(lp);
        ILToken.Asset memory asset = lToken.getAsset(lp, bTokenId);

        bAmount = _transferIn(b.bTokenAddress, b.decimals, lp, bAmount);

        int256 deltaLiquidity = bAmount.utoi(); // lp's liquidity change amount for bTokenId
        int256 deltaEquity = deltaLiquidity * b.price / ONE * b.discount / ONE;
        b.equity += deltaEquity;
        data.totalEquity += deltaEquity;

        asset.pnl += (b.cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE; // lp's pnl as LP since last settlement
        if (bTokenId == 0) {
            deltaLiquidity += _accrueTail(asset.pnl);
            b.pnl -= asset.pnl; // this pnl comes from b.pnl, thus should be deducted
            asset.pnl = 0;
        }

        asset.liquidity += deltaLiquidity;
        asset.lastCumulativePnl = b.cumulativePnl;
        b.liquidity += deltaLiquidity;

        _updateBTokensAndSymbols(data);
        lToken.updateAsset(lp, bTokenId, asset);

        require(data.bTokens[0].equity * ONE >= data.totalEquity * _minBToken0Ratio, "insuf't b0");

        emit AddLiquidity(lp, bTokenId, bAmount);
    }

    function removeLiquidity(address lp, uint256 bTokenId, uint256 bAmount) external override _lock_ {
        _checkRouter();
        Data memory data = _getBTokensAndSymbols(bTokenId, type(uint256).max);
        BTokenData memory b = data.bTokens[bTokenId];

        ILToken lToken = ILToken(_lTokenAddress);
        ILToken.Asset memory asset = lToken.getAsset(lp, bTokenId);

        int256 amount = bAmount.utoi();
        if (amount > asset.liquidity) amount = asset.liquidity;

        // compensation caused by dpmmPrice change when removing liquidity
        int256 totalEquity = data.totalEquity + data.undistributedPnl - amount * b.price / ONE * b.discount / ONE;
        if (totalEquity > 0) {
            int256 compensation;
            for (uint256 i = 0; i < data.symbols.length; i++) {
                SymbolData memory s = data.symbols[i];
                if (s.active) {
                    int256 K = DpmmPricerFutures._calculateK(s.indexPrice, totalEquity, s.alpha);
                    int256 newPnl = -DpmmPricerFutures._calculateDpmmCost(s.indexPrice, K, s.tradersNetPosition, -s.tradersNetPosition) - s.tradersNetCost;
                    compensation += newPnl - s.pnl;
                }
            }
            asset.pnl -= compensation;
            b.pnl -= compensation;
            b.equity -= compensation;
            data.totalEquity -= compensation;
            data.undistributedPnl += compensation;
        }

        _distributePnlToBTokens(data);

        int256 deltaLiquidity;
        int256 pnl = (b.cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE;
        asset.pnl += pnl;
        if (bTokenId == 0) {
            deltaLiquidity = _accrueTail(asset.pnl);
            b.pnl -= asset.pnl;
            asset.pnl = 0;
        } else {
            if (asset.pnl < 0) {
                (uint256 amountB0, uint256 amountBX) = IBTokenSwapper(_bTokens[bTokenId].swapperAddress).swapBXForExactB0(
                    (-asset.pnl).ceil(_decimals0).itou(), asset.liquidity.itou(), b.price.itou()
                );
                (int256 b0, int256 bx) = (amountB0.utoi(), amountBX.utoi());
                deltaLiquidity = -bx;
                asset.pnl += b0;
                b.pnl += b0;
            } else if (asset.pnl > 0 && amount >= asset.liquidity) {
                (, uint256 amountBX) = IBTokenSwapper(_bTokens[bTokenId].swapperAddress).swapExactB0ForBX(
                    asset.pnl.itou(), b.price.itou()
                );
                deltaLiquidity = amountBX.utoi();
                b.pnl -= asset.pnl;
                _accrueTail(asset.pnl);
                asset.pnl = 0;
            }
        }

        asset.lastCumulativePnl = b.cumulativePnl;
        if (amount >= asset.liquidity || amount >= asset.liquidity + deltaLiquidity) {
            amount = asset.liquidity + deltaLiquidity;
            b.liquidity -= asset.liquidity;
            asset.liquidity = 0;
        } else {
            b.liquidity -= amount - deltaLiquidity;
            asset.liquidity -= amount - deltaLiquidity;
        }

        int256 deltaEquity = amount * b.price / ONE * b.discount / ONE;
        b.equity -= deltaEquity;
        data.totalEquity -= deltaEquity;

        _updateBTokensAndSymbols(data);
        lToken.updateAsset(lp, bTokenId, asset);

        require(data.totalEquity * ONE >= data.totalNotional * _minPoolMarginRatio, "insuf't liq");

        _transferOut(b.bTokenAddress, b.decimals, lp, amount.itou());
        emit RemoveLiquidity(lp, bTokenId, bAmount);
    }

    function addMargin(address trader, uint256 bTokenId, uint256 bAmount) external override _lock_ {
        _checkRouter();
        IPToken pToken = IPToken(_pTokenAddress);
        if (!pToken.exists(trader)) pToken.mint(trader);

        BTokenInfo storage bb = _bTokens[bTokenId];
        bAmount = _transferIn(bb.bTokenAddress, bb.decimals, trader, bAmount);

        int256 margin = pToken.getMargin(trader, bTokenId) + bAmount.utoi();

        pToken.updateMargin(trader, bTokenId, margin);
        emit AddMargin(trader, bTokenId, bAmount);
    }

    function removeMargin(address trader, uint256 bTokenId, uint256 bAmount) external override _lock_ {
        _checkRouter();
        Data memory data = _getBTokensAndSymbols(bTokenId, type(uint256).max);
        BTokenData memory b = data.bTokens[bTokenId];

        _distributePnlToBTokens(data);
        _getMarginsAndPositions(data, trader);
        _coverTraderDebt(data);

        int256 amount = bAmount.utoi();
        int256 margin = data.margins[bTokenId];
        if (amount >= margin) {
            if (bTokenId == 0) amount = _accrueTail(margin);
            bAmount = amount.itou();
            data.margins[bTokenId] = 0;
        } else {
            data.margins[bTokenId] -= amount;
        }
        b.marginUpdated = true;
        data.totalTraderEquity -= amount * b.price / ONE * b.discount / ONE;

        _updateBTokensAndSymbols(data);
        _updateMarginsAndPositions(data);

        require(data.totalTraderEquity * ONE >= data.totalTraderNontional * _initialMarginRatio, "insuf't margin");

        _transferOut(b.bTokenAddress, b.decimals, trader, bAmount);
        emit RemoveMargin(trader, bTokenId, bAmount);
    }

    function trade(address trader, uint256 symbolId, int256 tradeVolume) external override _lock_ {
        _checkRouter();
        Data memory data = _getBTokensAndSymbols(type(uint256).max, symbolId);
        _getMarginsAndPositions(data, trader);
        SymbolData memory s = data.symbols[symbolId];
        IPToken.Position memory p = data.positions[symbolId];

        tradeVolume = tradeVolume.reformat(0);
        require(tradeVolume != 0, '0 tradeVolume');

        int256 curCost = DpmmPricerFutures._calculateDpmmCost(
            s.indexPrice,
            s.K,
            s.tradersNetPosition,
            tradeVolume * s.multiplier / ONE
        );
        int256 fee = curCost.abs() * s.feeRatio / ONE;

        int256 realizedCost;
        if (!(p.volume >= 0 && tradeVolume >= 0) && !(p.volume <= 0 && tradeVolume <= 0)) {
            int256 absVolume = p.volume.abs();
            int256 absTradeVolume = tradeVolume.abs();
            if (absVolume <= absTradeVolume) {
                realizedCost = curCost * absVolume / absTradeVolume + p.cost;
            } else {
                realizedCost = p.cost * absTradeVolume / absVolume + curCost;
            }
        }

        int256 preVolume = p.volume;
        p.volume += tradeVolume;
        p.cost += curCost - realizedCost;
        p.lastCumulativeFundingRate = s.cumulativeFundingRate;
        s.positionUpdated = true;

        data.margins[0] -= fee + realizedCost;

        int256 protocolFee = fee * _protocolFeeCollectRatio / ONE;
        _protocolFeeAccrued += protocolFee;
        data.undistributedPnl += fee - protocolFee;

        s.distributedUnrealizedPnl += realizedCost;
        _distributePnlToBTokens(data);

        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += curCost - realizedCost;

        data.totalTraderNontional += (p.volume.abs() - preVolume.abs()) * s.indexPrice / ONE * s.multiplier / ONE;
        data.totalNotional += s.tradersNetVolume.abs() * s.indexPrice / ONE * s.multiplier / ONE - s.notional;

        IPToken(_pTokenAddress).updatePosition(trader, symbolId, p);
        _updateBTokensAndSymbols(data);
        _updateMarginsAndPositions(data);

        require(data.totalEquity * ONE >= data.totalNotional * _minPoolMarginRatio, "insuf't liq");
        require(data.totalTraderEquity * ONE >= data.totalTraderNontional * _initialMarginRatio, "insuf't margin");

        emit Trade(trader, symbolId, tradeVolume, curCost);
    }

    function liquidate(address liquidator, address trader) external override _lock_ {
        _checkRouter();
        Data memory data = _getBTokensAndSymbols(type(uint256).max, type(uint256).max);
        _getMarginsAndPositions(data, trader);

        require(data.totalTraderEquity * ONE < data.totalTraderNontional * _maintenanceMarginRatio, 'cant liq');

        int256 netEquity = data.margins[0];
        for (uint256 i = 1; i < data.bTokens.length; i++) {
            if (data.margins[i] > 0) {
                (uint256 amountB0, ) = IBTokenSwapper(_bTokens[i].swapperAddress).swapExactBXForB0(
                    data.margins[i].itou(), data.bTokens[i].price.itou()
                );
                netEquity += amountB0.utoi();
            }
        }

        for (uint256 i = 0; i < data.symbols.length; i++) {
            IPToken.Position memory p = data.positions[i];
            if (p.volume != 0) {
                SymbolData memory s = data.symbols[i];
                s.distributedUnrealizedPnl -= s.traderPnl;
                s.tradersNetVolume -= p.volume;
                s.tradersNetCost -= p.cost;
            }
        }
        netEquity += data.totalTraderPnl;

        int256 reward;
        if (netEquity <= _minLiquidationReward) {
            reward = _minLiquidationReward;
        } else {
            reward = ((netEquity - _minLiquidationReward) * _liquidationCutRatio / ONE + _minLiquidationReward).reformat(_decimals0);
            if (reward > _maxLiquidationReward) reward = _maxLiquidationReward;
        }

        data.undistributedPnl += netEquity - reward;
        _distributePnlToBTokens(data);

        IPToken(_pTokenAddress).burn(trader);
        _updateBTokensAndSymbols(data);

        _transferOut(_bTokens[0].bTokenAddress, _decimals0, liquidator, reward.itou());
        emit Liquidate(trader, liquidator, reward.itou());
    }


    //================================================================================
    // Helpers
    //================================================================================

    function _addBToken(BTokenInfo memory info) internal {
        if (_bTokens.length > 0) {
            // approve for non bToken0 swappers
            IERC20(_bTokens[0].bTokenAddress).safeApprove(info.swapperAddress, type(uint256).max);
            IERC20(info.bTokenAddress).safeApprove(info.swapperAddress, type(uint256).max);
        } else {
            require(info.decimals == _decimals0, 'wrong dec');
        }
        _bTokens.push(info);
    }

    function _checkRouter() internal view {
        require(msg.sender == _routerAddress, 'router only');
    }

    struct BTokenData {
        address bTokenAddress;
        uint256 decimals;
        int256  discount;
        int256  liquidity;
        int256  pnl;
        int256  cumulativePnl;
        int256  price;
        int256  equity;
        // trader
        bool    marginUpdated;
    }

    struct SymbolData {
        bool    active;
        int256  multiplier;
        int256  feeRatio;
        int256  alpha;
        int256  K;
        int256  indexPrice;
        int256  dpmmPrice;
        int256  distributedUnrealizedPnl;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativeFundingRate;
        int256  tradersNetPosition; // tradersNetVolume * multiplier / ONE
        int256  notional;
        int256  pnl;
        // trader
        bool    positionUpdated;
        int256  traderPnl;
    }

    struct Data {
        BTokenData[] bTokens;
        SymbolData[] symbols;
        uint256 preTimestamp;
        uint256 curTimestamp;
        int256  totalEquity;
        int256  totalNotional;
        int256  undistributedPnl;

        address trader;
        int256[] margins;
        IPToken.Position[] positions;
        int256 totalTraderPnl;
        int256 totalTraderNontional;
        int256 totalTraderEquity;
    }

    function _getBTokensAndSymbols(uint256 bTokenId, uint256 symbolId) internal returns (Data memory data) {
        data.preTimestamp = _lastTimestamp;
        data.curTimestamp = block.timestamp;

        data.bTokens = new BTokenData[](_bTokens.length);
        for (uint256 i = 0; i < data.bTokens.length; i++) {
            BTokenData memory b = data.bTokens[i];
            BTokenInfo storage bb = _bTokens[i];
            b.liquidity = bb.liquidity;
            if (i == bTokenId) {
                b.bTokenAddress = bb.bTokenAddress;
                b.decimals = bb.decimals;
            }
            b.discount = bb.discount;
            b.pnl = bb.pnl;
            b.cumulativePnl = bb.cumulativePnl;
            b.price = i == 0 ? ONE : IOracle(bb.oracleAddress).getPrice().utoi();
            b.equity = b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
            data.totalEquity += b.equity;
        }

        data.symbols = new SymbolData[](_symbols.length);
        int256 fundingPeriod = _fundingPeriod;
        for (uint256 i = 0; i < data.symbols.length; i++) {
            SymbolData memory s = data.symbols[i];
            SymbolInfo storage ss = _symbols[i];
            s.tradersNetVolume = ss.tradersNetVolume;
            s.tradersNetCost = ss.tradersNetCost;
            if (i == symbolId || s.tradersNetVolume != 0 || s.tradersNetCost != 0) {
                s.active = true;
                s.multiplier = ss.multiplier;
                s.feeRatio = ss.feeRatio;
                s.alpha = ss.alpha;
                s.indexPrice = IOracle(ss.oracleAddress).getPrice().utoi();
                s.K = DpmmPricerFutures._calculateK(s.indexPrice, data.totalEquity, s.alpha);
                s.dpmmPrice = DpmmPricerFutures._calculateDpmmPrice(s.indexPrice, s.K, s.tradersNetVolume * s.multiplier / ONE);
                s.distributedUnrealizedPnl = ss.distributedUnrealizedPnl;
                s.cumulativeFundingRate = ss.cumulativeFundingRate;

                s.tradersNetPosition = s.tradersNetVolume * s.multiplier / ONE;
                s.notional = (s.tradersNetPosition * s.indexPrice / ONE).abs();
                data.totalNotional += s.notional;
                s.pnl = -DpmmPricerFutures._calculateDpmmCost(s.indexPrice, s.K, s.tradersNetPosition, -s.tradersNetPosition) - s.tradersNetCost;
                data.undistributedPnl -= s.pnl - s.distributedUnrealizedPnl;
                s.distributedUnrealizedPnl = s.pnl;

                if (data.curTimestamp > data.preTimestamp) {
                    int256 ratePerSecond = (s.dpmmPrice - s.indexPrice) * s.multiplier / fundingPeriod;
                    int256 diff = ratePerSecond * int256(data.curTimestamp - data.preTimestamp);
                    data.undistributedPnl += s.tradersNetVolume * diff / ONE;
                    unchecked { s.cumulativeFundingRate += diff; }
                }
            }
        }
    }

    function _updateBTokensAndSymbols(Data memory data) internal {
        _lastTimestamp = data.curTimestamp;

        for (uint256 i = 0; i < data.bTokens.length; i++) {
            BTokenData memory b = data.bTokens[i];
            BTokenInfo storage bb = _bTokens[i];
            bb.liquidity = b.liquidity;
            bb.pnl = b.pnl;
            bb.cumulativePnl = b.cumulativePnl;
        }

        for (uint256 i = 0; i < data.symbols.length; i++) {
            SymbolData memory s = data.symbols[i];
            SymbolInfo storage ss = _symbols[i];
            if (s.active) {
                ss.distributedUnrealizedPnl = s.distributedUnrealizedPnl;
                ss.tradersNetVolume = s.tradersNetVolume;
                ss.tradersNetCost = s.tradersNetCost;
                ss.cumulativeFundingRate = s.cumulativeFundingRate;
            }
        }
    }

    function _distributePnlToBTokens(Data memory data) internal pure {
        if (data.undistributedPnl != 0 && data.totalEquity > 0) {
            for (uint256 i = 0; i < data.bTokens.length; i++) {
                BTokenData memory b = data.bTokens[i];
                if (b.liquidity > 0) {
                    int256 pnl = data.undistributedPnl * b.equity / data.totalEquity;
                    b.pnl += pnl;
                    b.cumulativePnl += pnl * ONE / b.liquidity;
                    b.equity += pnl;
                }
            }
            data.totalEquity += data.undistributedPnl;
            data.undistributedPnl = 0;
        }
    }

    function _getMarginsAndPositions(Data memory data, address trader) internal view {
        data.trader = trader;
        IPToken pToken = IPToken(_pTokenAddress);
        data.margins = pToken.getMargins(trader);
        data.positions = pToken.getPositions(trader);

        data.bTokens[0].marginUpdated = true;

        for (uint256 i = 0; i < data.symbols.length; i++) {
            IPToken.Position memory p = data.positions[i];
            if (p.volume != 0) {
                SymbolData memory s = data.symbols[i];

                int256 diff;
                unchecked { diff = s.cumulativeFundingRate - p.lastCumulativeFundingRate; }
                data.margins[0] -= p.volume * diff / ONE;
                p.lastCumulativeFundingRate = s.cumulativeFundingRate;
                s.positionUpdated = true;

                data.totalTraderNontional += (p.volume * s.indexPrice / ONE * s.multiplier / ONE).abs();
                s.traderPnl = -DpmmPricerFutures._calculateDpmmCost(s.indexPrice, s.K, s.tradersNetPosition, -p.volume * s.multiplier / ONE) - p.cost;
                data.totalTraderPnl += s.traderPnl;
            }
        }

        data.totalTraderEquity = data.totalTraderPnl + data.margins[0];
        for (uint256 i = 1; i < data.bTokens.length; i++) {
            if (data.margins[i] != 0) {
                data.totalTraderEquity += data.margins[i] * data.bTokens[i].price / ONE * data.bTokens[i].discount / ONE;
            }
        }
    }

    function _coverTraderDebt(Data memory data) internal {
        int256[] memory margins = data.margins;
        if (margins[0] < 0) {
            uint256 amountB0;
            uint256 amountBX;
            for (uint256 i = margins.length - 1; i > 0; i--) {
                if (margins[i] > 0) {
                    (amountB0, amountBX) = IBTokenSwapper(_bTokens[i].swapperAddress).swapBXForExactB0(
                        (-margins[0]).ceil(_decimals0).itou(), margins[i].itou(), data.bTokens[i].price.itou()
                    );
                    (int256 b0, int256 bx) = (amountB0.utoi(), amountBX.utoi());
                    margins[0] += b0;
                    margins[i] -= bx;
                    data.totalTraderEquity += b0 - bx * data.bTokens[i].price / ONE * data.bTokens[i].discount / ONE;
                    data.bTokens[i].marginUpdated = true;
                }
                if (margins[0] >= 0) break;
            }
        }
    }

    function _updateMarginsAndPositions(Data memory data) internal {
        IPToken pToken = IPToken(_pTokenAddress);
        for (uint256 i = 0; i < data.margins.length; i++) {
            if (data.bTokens[i].marginUpdated) {
                pToken.updateMargin(data.trader, i, data.margins[i]);
            }
        }
        for (uint256 i = 0; i < data.positions.length; i++) {
            if (data.symbols[i].positionUpdated) {
                pToken.updatePosition(data.trader, i, data.positions[i]);
            }
        }
    }

    function _transferIn(address bTokenAddress, uint256 decimals, address from, uint256 bAmount) internal returns (uint256) {
        bAmount = bAmount.rescale(18, decimals);
        require(bAmount > 0, '0 bAmount');

        IERC20 bToken = IERC20(bTokenAddress);
        uint256 balance1 = bToken.balanceOf(address(this));
        bToken.safeTransferFrom(from, address(this), bAmount);
        uint256 balance2 = bToken.balanceOf(address(this));

        return (balance2 - balance1).rescale(decimals, 18);
    }

    function _transferOut(address bTokenAddress, uint256 decimals, address to, uint256 bAmount) internal {
        bAmount = bAmount.rescale(18, decimals);
        IERC20(bTokenAddress).safeTransfer(to, bAmount);
    }

    function _accrueTail(int256 amount) internal returns (int256) {
        int256 head = amount.reformat(_decimals0);
        if (head == amount) return head;
        if (head > amount) head -= int256(10**(18 - _decimals0));
        _protocolFeeAccrued += amount - head;
        return head;
    }

}
