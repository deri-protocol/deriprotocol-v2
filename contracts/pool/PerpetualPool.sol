// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/IOracle.sol';
import '../interface/IBTokenSwapper.sol';
import '../interface/IPToken.sol';
import '../interface/ILToken.sol';
import '../interface/IPerpetualPool.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';

/*
Revert Code:

reentry         : reentry is blocked
router only     : can only called by router
wrong dec       : wrong bToken decimals
insuf't b0      : pool insufficient bToken0
insuf't liq     : pool insufficient liquidity
insuf't margin  : trader insufficient margin
cant liquidate  : cannot liquidate trader
*/

contract PerpetualPool is IPerpetualPool {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256  constant ONE = 10**18;

    // decimals for bToken0 (settlement token), make this immutable to save gas
    uint256 immutable _decimals0;
    int256  immutable _minBToken0Ratio;
    int256  immutable _minPoolMarginRatio;
    int256  immutable _minInitialMarginRatio;
    int256  immutable _minMaintenanceMarginRatio;
    int256  immutable _minLiquidationReward;
    int256  immutable _maxLiquidationReward;
    int256  immutable _liquidationCutRatio;
    int256  immutable _protocolFeeCollectRatio;

    address immutable _lTokenAddress;
    address immutable _pTokenAddress;
    address immutable _routerAddress;
    address immutable _protocolFeeCollector;

    uint256 _lastUpdateBlock;
    int256  _protocolFeeAccrued;

    BTokenInfo[] _bTokens;   // bTokenId indexed
    SymbolInfo[] _symbols;   // symbolId indexed

    bool private _mutex;
    modifier _lock_() {
        require(!_mutex, 'reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    modifier _router_() {
        require(msg.sender == _routerAddress, 'router only');
        _;
    }

    constructor (uint256[9] memory parameters, address[4] memory addresses) {
        _decimals0 = parameters[0];
        _minBToken0Ratio = int256(parameters[1]);
        _minPoolMarginRatio = int256(parameters[2]);
        _minInitialMarginRatio = int256(parameters[3]);
        _minMaintenanceMarginRatio = int256(parameters[4]);
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
        int256  minInitialMarginRatio,
        int256  minMaintenanceMarginRatio,
        int256  minLiquidationReward,
        int256  maxLiquidationReward,
        int256  liquidationCutRatio,
        int256  protocolFeeCollectRatio
    ) {
        decimals0 = _decimals0;
        minBToken0Ratio = _minBToken0Ratio;
        minPoolMarginRatio = _minPoolMarginRatio;
        minInitialMarginRatio = _minInitialMarginRatio;
        minMaintenanceMarginRatio = _minMaintenanceMarginRatio;
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

    function getBTokenOracle(uint256 bTokenId) external override view returns (address) {
        return _bTokens[bTokenId].oracleAddress;
    }

    function getSymbolOracle(uint256 symbolId) external override view returns (address) {
        return _symbols[symbolId].oracleAddress;
    }

    function getLastUpdateBlock() external override view returns (uint256) {
        return _lastUpdateBlock;
    }

    function getProtocolFeeAccrued() external override view returns (int256) {
        return _protocolFeeAccrued;
    }

    function collectProtocolFee() external override {
        IERC20 token = IERC20(_bTokens[0].bTokenAddress);
        uint256 amount = _protocolFeeAccrued.itou().rescale(18, _decimals0);
        if (amount > token.balanceOf(address(this))) amount = token.balanceOf(address(this));
        _protocolFeeAccrued -= amount.rescale(_decimals0, 18).utoi();
        token.safeTransfer(_protocolFeeCollector, amount);
        emit ProtocolFeeCollection(_protocolFeeCollector, amount.rescale(_decimals0, 18));
    }

    function addBToken(BTokenInfo memory info) external override _router_ {
        if (_bTokens.length > 0) {
            // approve for non bToken0 swappers
            IERC20(_bTokens[0].bTokenAddress).safeApprove(info.swapperAddress, type(uint256).max);
            IERC20(info.bTokenAddress).safeApprove(info.swapperAddress, type(uint256).max);
            info.price = IOracle(info.oracleAddress).getPrice().utoi();
        } else {
            require(info.decimals == _decimals0, 'wrong dec');
            info.price = ONE;
        }
        _bTokens.push(info);
        ILToken(_lTokenAddress).setNumBTokens(_bTokens.length);
        IPToken(_pTokenAddress).setNumBTokens(_bTokens.length);
    }

    function addSymbol(SymbolInfo memory info) external override _router_ {
        _symbols.push(info);
        IPToken(_pTokenAddress).setNumSymbols(_symbols.length);
    }

    function setBTokenParameters(uint256 bTokenId, address swapperAddress, address oracleAddress, uint256 discount) external override _router_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        b.swapperAddress = swapperAddress;
        if (bTokenId != 0) {
            IERC20(_bTokens[0].bTokenAddress).safeApprove(swapperAddress, 0);
            IERC20(_bTokens[bTokenId].bTokenAddress).safeApprove(swapperAddress, 0);
            IERC20(_bTokens[0].bTokenAddress).safeApprove(swapperAddress, type(uint256).max);
            IERC20(_bTokens[bTokenId].bTokenAddress).safeApprove(swapperAddress, type(uint256).max);
        }
        b.oracleAddress = oracleAddress;
        b.discount = int256(discount);
    }

    function setSymbolParameters(uint256 symbolId, address oracleAddress, uint256 feeRatio, uint256 fundingRateCoefficient) external override _router_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.oracleAddress = oracleAddress;
        s.feeRatio = int256(feeRatio);
        s.fundingRateCoefficient = int256(fundingRateCoefficient);
    }

    // during a migration, this function is intended to be called in the source pool
    function approvePoolMigration(address targetPool) external override _router_ {
        for (uint256 i = 0; i < _bTokens.length; i++) {
            IERC20(_bTokens[i].bTokenAddress).safeApprove(targetPool, type(uint256).max);
        }
        ILToken(_lTokenAddress).setPool(targetPool);
        IPToken(_pTokenAddress).setPool(targetPool);
    }

    // during a migration, this function is intended to be called in the target pool
    function executePoolMigration(address sourcePool) external override _router_ {
        // (uint256 blength, uint256 slength) = IPerpetualPool(sourcePool).getLengths();
        // for (uint256 i = 0; i < blength; i++) {
        //     BTokenInfo memory b = IPerpetualPool(sourcePool).getBToken(i);
        //     IERC20(b.bTokenAddress).safeTransferFrom(sourcePool, address(this), IERC20(b.bTokenAddress).balanceOf(sourcePool));
        //     _bTokens.push(b);
        // }
        // for (uint256 i = 0; i < slength; i++) {
        //     _symbols.push(IPerpetualPool(sourcePool).getSymbol(i));
        // }
        // _protocolFeeAccrued = IPerpetualPool(sourcePool).getProtocolFeeAccrued();
    }


    //================================================================================
    // Core Logics
    //================================================================================

    function addLiquidity(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) external override _router_ _lock_ {
        ILToken lToken = ILToken(_lTokenAddress);
        if(!lToken.exists(owner)) lToken.mint(owner);

        _updateBTokenPrice(bTokenId);
        _updatePricesAndDistributePnl(blength, slength);

        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, owner, address(this), bAmount);

        int256 cumulativePnl = b.cumulativePnl;
        ILToken.Asset memory asset = lToken.getAsset(owner, bTokenId);

        int256 delta; // owner's liquidity change amount for bTokenId
        int256 pnl = (cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE; // owner's pnl as LP since last settlement
        if (bTokenId == 0) {
            delta = bAmount.utoi() + pnl.reformat(_decimals0);
            b.pnl -= pnl; // this pnl comes from b.pnl, thus should be deducted from b.pnl
            _protocolFeeAccrued += pnl - pnl.reformat(_decimals0); // deal with accuracy tail
        } else {
            delta = bAmount.utoi();
            asset.pnl += pnl;
        }
        asset.liquidity += delta;
        asset.lastCumulativePnl = cumulativePnl;
        b.liquidity += delta;

        lToken.updateAsset(owner, bTokenId, asset);

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities(blength);
        require(_getBToken0Ratio(totalDynamicEquity, dynamicEquities) >= _minBToken0Ratio, "insuf't b0");

        emit AddLiquidity(owner, bTokenId, bAmount);
    }

    function removeLiquidity(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) external override _router_ _lock_ {
        _updateBTokenPrice(bTokenId);
        _updatePricesAndDistributePnl(blength, slength);

        BTokenInfo storage b = _bTokens[bTokenId];
        ILToken lToken = ILToken(_lTokenAddress);
        ILToken.Asset memory asset = lToken.getAsset(owner, bTokenId);
        uint256 decimals = b.decimals;
        bAmount = bAmount.reformat(decimals);

        { // scope begin
        int256 cumulativePnl = b.cumulativePnl;
        int256 amount = bAmount.utoi();
        int256 pnl = (cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE;
        int256 deltaLiquidity;
        int256 deltaPnl;
        if (bTokenId == 0) {
            deltaLiquidity = pnl.reformat(_decimals0);
            deltaPnl = -pnl;
            _protocolFeeAccrued += pnl - pnl.reformat(_decimals0); // deal with accuracy tail
        } else {
            asset.pnl += pnl;
            if (asset.pnl < 0) {
                (uint256 amountB0, uint256 amountBX) = IBTokenSwapper(b.swapperAddress).swapBXForExactB0(
                    (-asset.pnl).ceil(_decimals0).itou(), asset.liquidity.itou(), b.price.itou()
                );
                deltaLiquidity = -amountBX.utoi();
                deltaPnl = amountB0.utoi();
                asset.pnl += amountB0.utoi();
            } else if (asset.pnl > 0 && amount >= asset.liquidity) {
                (, uint256 amountBX) = IBTokenSwapper(b.swapperAddress).swapExactB0ForBX(asset.pnl.itou(), b.price.itou());
                deltaLiquidity = amountBX.utoi();
                deltaPnl = -asset.pnl;
                _protocolFeeAccrued += asset.pnl - asset.pnl.reformat(_decimals0); // deal with accuracy tail
                asset.pnl = 0;
            }
        }
        asset.lastCumulativePnl = cumulativePnl;

        if (amount >= asset.liquidity || amount >= asset.liquidity + deltaLiquidity) {
            bAmount = (asset.liquidity + deltaLiquidity).itou();
            b.liquidity -= asset.liquidity;
            asset.liquidity = 0;
        } else {
            asset.liquidity += deltaLiquidity - amount;
            b.liquidity += deltaLiquidity - amount;
        }
        b.pnl += deltaPnl;
        lToken.updateAsset(owner, bTokenId, asset);
        } // scope end

        (int256 totalDynamicEquity, ) = _getBTokenDynamicEquities(blength);
        require(_getPoolMarginRatio(totalDynamicEquity, slength) >= _minPoolMarginRatio, "insuf't liq");

        IERC20(b.bTokenAddress).safeTransfer(owner, bAmount.rescale(18, decimals));
        emit RemoveLiquidity(owner, bTokenId, bAmount);
    }

    function addMargin(address owner, uint256 bTokenId, uint256 bAmount) external override _router_ _lock_ {
        IPToken pToken = IPToken(_pTokenAddress);
        if (!pToken.exists(owner)) pToken.mint(owner);

        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, owner, address(this), bAmount);

        int256 margin = pToken.getMargin(owner, bTokenId) + bAmount.utoi();

        pToken.updateMargin(owner, bTokenId, margin);
        emit AddMargin(owner, bTokenId, bAmount);
    }

    function removeMargin(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) external override _router_ _lock_ {
        _updatePricesAndDistributePnl(blength, slength);
        _settleTraderFundingFee(owner, slength);
        _coverTraderDebt(owner, blength);

        IPToken pToken = IPToken(_pTokenAddress);
        BTokenInfo storage b = _bTokens[bTokenId];
        uint256 decimals = b.decimals;
        bAmount = bAmount.reformat(decimals);

        int256 amount = bAmount.utoi();
        int256 margin = pToken.getMargin(owner, bTokenId);

        if (amount >= margin) {
            bAmount = margin.itou();
            if (bTokenId == 0) _protocolFeeAccrued += margin - margin.reformat(_decimals0); // deal with accuracy tail
            margin = 0;
        } else {
            margin -= amount;
        }
        pToken.updateMargin(owner, bTokenId, margin);

        require(_getTraderMarginRatio(owner, blength, slength) >= _minInitialMarginRatio, "insuf't margin");

        IERC20(b.bTokenAddress).safeTransfer(owner, bAmount.rescale(18, decimals));
        emit RemoveMargin(owner, bTokenId, bAmount);
    }

    // struct for temp use in trade function, to prevent stack too deep error
    struct TradeParams {
        int256 curCost;
        int256 fee;
        int256 realizedCost;
        int256 protocolFee;
    }

    function trade(address owner, uint256 symbolId, int256 tradeVolume, uint256 blength, uint256 slength) external override _router_ _lock_ {
        _updatePricesAndDistributePnl(blength, slength);
        _settleTraderFundingFee(owner, slength);

        SymbolInfo storage s = _symbols[symbolId];
        IPToken.Position memory p = IPToken(_pTokenAddress).getPosition(owner, symbolId);

        TradeParams memory params;

        tradeVolume = tradeVolume.reformat(0);
        params.curCost = tradeVolume * s.price / ONE * s.multiplier / ONE;
        params.fee = params.curCost.abs() * s.feeRatio / ONE;

        if (!(p.volume >= 0 && tradeVolume >= 0) && !(p.volume <= 0 && tradeVolume <= 0)) {
            int256 absVolume = p.volume.abs();
            int256 absTradeVolume = tradeVolume.abs();
            if (absVolume <= absTradeVolume) {
                params.realizedCost = params.curCost * absVolume / absTradeVolume + p.cost;
            } else {
                params.realizedCost = p.cost * absTradeVolume / absVolume + params.curCost;
            }
        }

        p.volume += tradeVolume;
        p.cost += params.curCost - params.realizedCost;
        p.lastCumulativeFundingRate = s.cumulativeFundingRate;
        IPToken(_pTokenAddress).updateMargin(
            owner, 0, IPToken(_pTokenAddress).getMargin(owner, 0) - params.fee - params.realizedCost
        );
        IPToken(_pTokenAddress).updatePosition(owner, symbolId, p);

        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += params.curCost - params.realizedCost;

        params.protocolFee = params.fee * _protocolFeeCollectRatio / ONE;
        _protocolFeeAccrued += params.protocolFee;

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities(blength);
        _distributePnlToBTokens(params.fee - params.protocolFee, totalDynamicEquity, dynamicEquities, blength);
        require(_getPoolMarginRatio(totalDynamicEquity, slength) >= _minPoolMarginRatio, "insuf't liq");
        require(_getTraderMarginRatio(owner, blength, slength) >= _minInitialMarginRatio, "insuf't margin");

        emit Trade(owner, symbolId, tradeVolume, s.price.itou());
    }

    function liquidate(address liquidator, address owner, uint256 blength, uint256 slength) external override _router_ _lock_ {
        _updateAllBTokenPrices(blength);
        _updatePricesAndDistributePnl(blength, slength);
        _settleTraderFundingFee(owner, slength);
        require(_getTraderMarginRatio(owner, blength, slength) < _minMaintenanceMarginRatio, 'cant liquidate');

        IPToken pToken = IPToken(_pTokenAddress);
        IPToken.Position[] memory positions = pToken.getPositions(owner);
        int256 netEquity;
        for (uint256 i = 0; i < slength; i++) {
            if (positions[i].volume != 0) {
                _symbols[i].tradersNetVolume -= positions[i].volume;
                _symbols[i].tradersNetCost -= positions[i].cost;
                netEquity += positions[i].volume * _symbols[i].price / ONE * _symbols[i].multiplier / ONE - positions[i].cost;
            }
        }

        int256[] memory margins = pToken.getMargins(owner);
        netEquity += margins[0];
        for (uint256 i = 1; i < blength; i++) {
            if (margins[i] > 0) {
                (uint256 amountB0, ) = IBTokenSwapper(_bTokens[i].swapperAddress).swapExactBXForB0(margins[i].itou(), _bTokens[i].price.itou());
                netEquity += amountB0.utoi();
            }
        }

        int256 reward;
        int256 minReward = _minLiquidationReward;
        int256 maxReward = _maxLiquidationReward;
        if (netEquity <= minReward) {
            reward = minReward;
        } else if (netEquity >= maxReward) {
            reward = maxReward;
        } else {
            reward = ((netEquity - minReward) * _liquidationCutRatio / ONE + minReward).reformat(_decimals0);
        }

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities(blength);
        _distributePnlToBTokens(netEquity - reward, totalDynamicEquity, dynamicEquities, blength);

        pToken.burn(owner);
        IERC20(_bTokens[0].bTokenAddress).safeTransfer(liquidator, reward.itou().rescale(18, _decimals0));

        emit Liquidate(owner, liquidator, reward.itou());
    }


    //================================================================================
    // Helpers
    //================================================================================

    // update bTokens/symbols prices
    // distribute pnl to bTokens, which is generated since last update, including pnl and funding fees for opening positions
    // by calling this function at the beginning of each block, all LP/Traders status are settled
    function _updatePricesAndDistributePnl(uint256 blength, uint256 slength) internal {
        uint256 blocknumber = block.number;
        if (blocknumber > _lastUpdateBlock) {
            (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities(blength);
            int256 undistributedPnl = _updateSymbolPrices(totalDynamicEquity, slength);
            _distributePnlToBTokens(undistributedPnl, totalDynamicEquity, dynamicEquities, blength);
            _lastUpdateBlock = blocknumber;
        }
    }

    function _updateAllBTokenPrices(uint256 blength) internal {
        for (uint256 i = 1; i < blength; i++) {
            _bTokens[i].price = IOracle(_bTokens[i].oracleAddress).getPrice().utoi();
        }
    }

    function _updateBTokenPrice(uint256 bTokenId) internal {
        if (bTokenId != 0) _bTokens[bTokenId].price = IOracle(_bTokens[bTokenId].oracleAddress).getPrice().utoi();
    }

    function _getBTokenDynamicEquities(uint256 blength) internal view returns (int256, int256[] memory) {
        int256 totalDynamicEquity;
        int256[] memory dynamicEquities = new int256[](blength);
        for (uint256 i = 0; i < blength; i++) {
            BTokenInfo storage b = _bTokens[i];
            int256 liquidity = b.liquidity;
            // dynamic equities for bTokens are discounted
            int256 equity = liquidity * b.price / ONE * b.discount / ONE + b.pnl;
            if (liquidity > 0 && equity > 0) {
                totalDynamicEquity += equity;
                dynamicEquities[i] = equity;
            }
        }
        return (totalDynamicEquity, dynamicEquities);
    }

    function _distributePnlToBTokens(int256 pnl, int256 totalDynamicEquity, int256[] memory dynamicEquities, uint256 blength) internal {
        if (totalDynamicEquity > 0 && pnl != 0) {
            for (uint256 i = 0; i < blength; i++) {
                if (dynamicEquities[i] > 0) {
                    BTokenInfo storage b = _bTokens[i];
                    int256 distributedPnl = pnl * dynamicEquities[i] / totalDynamicEquity;
                    b.pnl += distributedPnl;
                    // cumulativePnl is as in per liquidity, thus b.liquidity in denominator
                    b.cumulativePnl += distributedPnl * ONE / b.liquidity;
                }
            }
        }
    }

    // update symbol prices and calculate funding and unrealized pnl for all positions since last call
    // the returned undistributedPnl will be distributed and shared by all LPs
    //
    //                 tradersNetVolume * price * multiplier
    // ratePerBlock = --------------------------------------- * price * multiplier * fundingRateCoefficient
    //                         totalDynamicEquity
    //
    function _updateSymbolPrices(int256 totalDynamicEquity, uint256 slength) internal returns (int256) {
        if (totalDynamicEquity <= 0) return 0;
        int256 undistributedPnl;
        for (uint256 i = 0; i < slength; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 price = IOracle(s.oracleAddress).getPrice().utoi();
            int256 tradersNetVolume = s.tradersNetVolume;
            if (tradersNetVolume != 0) {
                int256 multiplier = s.multiplier;
                int256 ratePerBlock = tradersNetVolume * price / ONE * price / ONE * multiplier / ONE * multiplier / ONE * s.fundingRateCoefficient / totalDynamicEquity;
                int256 delta = ratePerBlock * int256(block.number - _lastUpdateBlock);

                undistributedPnl += tradersNetVolume * delta / ONE;
                undistributedPnl -= tradersNetVolume * (price - s.price) / ONE * multiplier / ONE;

                unchecked { s.cumulativeFundingRate += delta; }
            }
            s.price = price;
        }
        return undistributedPnl;
    }

    function _getBToken0Ratio(int256 totalDynamicEquity, int256[] memory dynamicEquities) internal pure returns (int256) {
        return totalDynamicEquity == 0 ? type(int256).max : dynamicEquities[0] * ONE / totalDynamicEquity;
    }

    function _getPoolMarginRatio(int256 totalDynamicEquity, uint256 slength) internal view returns (int256) {
        int256 totalCost;
        for (uint256 i = 0; i < slength; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 tradersNetVolume = s.tradersNetVolume;
            if (tradersNetVolume != 0) {
                int256 cost = tradersNetVolume * s.price / ONE * s.multiplier / ONE;
                totalDynamicEquity -= cost - s.tradersNetCost;
                totalCost += cost.abs(); // netting costs cross symbols is forbidden
            }
        }
        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost;
    }

    // setting funding fee on trader's side
    // this funding fee is already settled to bTokens in `_update`, thus distribution is not needed
    function _settleTraderFundingFee(address owner, uint256 slength) internal {
        IPToken pToken = IPToken(_pTokenAddress);
        int256 funding;
        IPToken.Position[] memory positions = pToken.getPositions(owner);
        for (uint256 i = 0; i < slength; i++) {
            IPToken.Position memory p = positions[i];
            if (p.volume != 0) {
                int256 cumulativeFundingRate = _symbols[i].cumulativeFundingRate;
                int256 delta;
                unchecked { delta = cumulativeFundingRate - p.lastCumulativeFundingRate; }
                funding += p.volume * delta / ONE;

                p.lastCumulativeFundingRate = cumulativeFundingRate;
                pToken.updatePosition(owner, i, p);
            }
        }
        if (funding != 0) {
            int256 margin = pToken.getMargin(owner, 0) - funding;
            pToken.updateMargin(owner, 0, margin);
        }
    }

    function _coverTraderDebt(address owner, uint256 blength) internal {
        IPToken pToken = IPToken(_pTokenAddress);
        int256[] memory margins = pToken.getMargins(owner);
        if (margins[0] < 0) {
            uint256 amountB0;
            uint256 amountBX;
            for (uint256 i = blength - 1; i > 0; i--) {
                if (margins[i] > 0) {
                    (amountB0, amountBX) = IBTokenSwapper(_bTokens[i].swapperAddress).swapBXForExactB0(
                        (-margins[0]).ceil(_decimals0).itou(), margins[i].itou(), _bTokens[i].price.itou()
                    );
                    margins[0] += amountB0.utoi();
                    margins[i] -= amountBX.utoi();
                }
                if (margins[0] >= 0) break;
            }
            pToken.updateMargins(owner, margins);
        }
    }

    function _getTraderMarginRatio(address owner, uint256 blength, uint256 slength) internal view returns (int256) {
        IPToken pToken = IPToken(_pTokenAddress);

        int256[] memory margins = pToken.getMargins(owner);
        int256 totalDynamicEquity = margins[0];
        int256 totalCost;
        for (uint256 i = 1; i < blength; i++) {
            totalDynamicEquity += margins[i] * _bTokens[i].price / ONE * _bTokens[i].discount / ONE;
        }

        IPToken.Position[] memory positions = pToken.getPositions(owner);
        for (uint256 i = 0; i < slength; i++) {
            if (positions[i].volume != 0) {
                int256 cost = positions[i].volume * _symbols[i].price / ONE * _symbols[i].multiplier / ONE;
                totalDynamicEquity += cost - positions[i].cost;
                totalCost += cost.abs(); // netting costs cross symbols is forbidden
            }
        }

        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost;
    }

    function _deflationCompatibleSafeTransferFrom(address bTokenAddress, uint256 decimals, address from, address to, uint256 bAmount)
        internal returns (uint256)
    {
        IERC20 token = IERC20(bTokenAddress);

        uint256 balance1 = token.balanceOf(to);
        token.safeTransferFrom(from, to, bAmount.rescale(18, decimals));
        uint256 balance2 = token.balanceOf(to);

        return (balance2 - balance1).rescale(decimals, 18);
    }

}
