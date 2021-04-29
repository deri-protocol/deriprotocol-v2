// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/IOracle.sol';
import '../interface/IBTokenSwapper.sol';
import '../interface/IPToken.sol';
import '../interface/ILToken.sol';
import '../interface/IPerpetualPool.sol';
import '../interface/ILiquidatorQualifier.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';

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

    uint256 _lastUpdateBlock;
    int256  _protocolFeeCollected;

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
        require(msg.sender == _routerAddress, 'only router');
        _;
    }

    constructor (uint256[9] memory parameters, address[3] memory addresses) {
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
    }

    function getParameters() public override view returns (
        uint256 decimals0,
        uint256 minBToken0Ratio,
        uint256 minPoolMarginRatio,
        uint256 minInitialMarginRatio,
        uint256 minMaintenanceMarginRatio,
        uint256 minLiquidationReward,
        uint256 maxLiquidationReward,
        uint256 liquidationCutRatio,
        uint256 protocolFeeCollectRatio
    ) {
        decimals0 = _decimals0;
        minBToken0Ratio = uint256(_minBToken0Ratio);
        minPoolMarginRatio = uint256(_minPoolMarginRatio);
        minInitialMarginRatio = uint256(_minInitialMarginRatio);
        minMaintenanceMarginRatio = uint256(_minMaintenanceMarginRatio);
        minLiquidationReward = uint256(_minLiquidationReward);
        maxLiquidationReward = uint256(_maxLiquidationReward);
        liquidationCutRatio = uint256(_liquidationCutRatio);
        protocolFeeCollectRatio = uint256(_protocolFeeCollectRatio);
    }

    function getAddresses() public override view returns (
        address lTokenAddress,
        address pTokenAddress,
        address routerAddress
    ) {
        lTokenAddress = _lTokenAddress;
        pTokenAddress = _pTokenAddress;
        routerAddress = _routerAddress;
    }

    function getLength() public override view returns (uint256, uint256) {
        return (_bTokens.length, _symbols.length);
    }

    function getBToken(uint256 bTokenId) public override view returns (BTokenInfo memory) {
        return _bTokens[bTokenId];
    }

    function getSymbol(uint256 symbolId) public override view returns (SymbolInfo memory) {
        return _symbols[symbolId];
    }

    function getBTokenOracle(uint256 bTokenId) public override view returns (address) {
        return _bTokens[bTokenId].oracleAddress;
    }

    function getSymbolOracle(uint256 symbolId) public override view returns (address) {
        return _symbols[symbolId].oracleAddress;
    }

    function getProtocolFeeCollected() public override view returns (uint256) {
        return uint256(_protocolFeeCollected);
    }

    function collectProtocolFee(address collector) public override _router_ {
        uint256 amount = uint256(_protocolFeeCollected);
        IERC20(_bTokens[0].bTokenAddress).safeTransfer(collector, amount.rescale(18, _decimals0));
        _protocolFeeCollected = 0;
        emit ProtocolFeeCollection(collector, amount);
    }

    function addBToken(BTokenInfo memory info) public override _router_ {
        if (_bTokens.length > 0) {
            IERC20(_bTokens[0].bTokenAddress).safeApprove(info.swapperAddress, type(uint256).max);
            IERC20(info.bTokenAddress).safeApprove(info.swapperAddress, type(uint256).max);
        } else {
            require(info.decimals == _decimals0, 'wrong decimals');
            info.price = ONE;
        }
        _bTokens.push(info);
        ILToken(_lTokenAddress).setNumBTokens(_bTokens.length);
        IPToken(_pTokenAddress).setNumBTokens(_bTokens.length);
    }

    function addSymbol(SymbolInfo memory info) public override _router_ {
        _symbols.push(info);
        IPToken(_pTokenAddress).setNumSymbols(_symbols.length);
    }

    /// low-level function called from router which should perform critical checks
    function setBTokenParameters(uint256 bTokenId, address swapperAddress, address oracleAddress, uint256 discount) public override _router_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        b.swapperAddress = swapperAddress;
        b.oracleAddress = oracleAddress;
        b.discount = int256(discount);
    }

    /// low-level function called from router which should perform critical checks
    function setSymbolParameters(uint256 symbolId, address oracleAddress, uint256 feeRatio, uint256 fundingRateCoefficient) public override _router_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.oracleAddress = oracleAddress;
        s.feeRatio = int256(feeRatio);
        s.fundingRateCoefficient = int256(fundingRateCoefficient);
    }

    function approvePoolMigration(address targetPool) public override _router_ {
        for (uint256 i = 0; i < _bTokens.length; i++) {
            IERC20(_bTokens[i].bTokenAddress).safeApprove(targetPool, type(uint256).max);
        }
        ILToken(_lTokenAddress).setPool(targetPool);
        IPToken(_pTokenAddress).setPool(targetPool);
    }

    function executePoolMigration(address sourcePool) public override _router_ {
        (uint256 blength, uint256 slength) = IPerpetualPool(sourcePool).getLength();
        for (uint256 i = 0; i < blength; i++) {
            BTokenInfo memory b = IPerpetualPool(sourcePool).getBToken(i);
            IERC20(b.bTokenAddress).safeTransferFrom(sourcePool, address(this), IERC20(b.bTokenAddress).balanceOf(sourcePool));
            _bTokens.push(b);
        }
        for (uint256 i = 0; i < slength; i++) {
            _symbols.push(IPerpetualPool(sourcePool).getSymbol(i));
        }
        _protocolFeeCollected = int256(IPerpetualPool(sourcePool).getProtocolFeeCollected());
    }


    //================================================================================
    // Core Logics
    //================================================================================

    function addLiquidity(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) public override _router_ _lock_ {
        ILToken lToken = ILToken(_lTokenAddress);
        if(!lToken.exists(owner)) lToken.mint(owner);

        _update(blength, slength);

        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, owner, address(this), bAmount);

        int256 cumulativePnl = b.cumulativePnl;
        ILToken.Asset memory asset = lToken.getAsset(owner, bTokenId);

        int256 delta;
        int256 pnl = ((cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE).reformat(_decimals0);
        if (bTokenId == 0) {
            delta = bAmount.utoi() + pnl;
            b.pnl -= pnl; // this pnl comes from b.pnl, thus should be deducted from b.pnl
        } else {
            delta = bAmount.utoi();
            asset.pnl += pnl;
        }
        asset.liquidity += delta;
        asset.lastCumulativePnl = cumulativePnl;
        b.liquidity += delta;

        lToken.updateAsset(owner, bTokenId, asset);

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities(blength);
        require(_getBToken0Ratio(totalDynamicEquity, dynamicEquities) >= _minBToken0Ratio, 'insufficient bToken0');

        emit AddLiquidity(owner, bTokenId, bAmount);
    }

    function removeLiquidity(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) public override _router_ _lock_ {
        _update(blength, slength);

        BTokenInfo storage b = _bTokens[bTokenId];
        ILToken lToken = ILToken(_lTokenAddress);
        ILToken.Asset memory asset = lToken.getAsset(owner, bTokenId);
        uint256 decimals = b.decimals;
        bAmount = bAmount.reformat(decimals);

        { // scope begin
        int256 cumulativePnl = b.cumulativePnl;
        int256 amount = bAmount.utoi();
        int256 pnl = ((cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE).reformat(_decimals0);
        int256 deltaLiquidity;
        int256 deltaPnl;
        if (bTokenId == 0) {
            deltaLiquidity = pnl;
            deltaPnl = -pnl;
        } else {
            asset.pnl += pnl;
            if (asset.pnl < 0) {
                (uint256 amountB0, uint256 amountBX) = IBTokenSwapper(b.swapperAddress).swapQuoteForExactBase((-asset.pnl).itou(), asset.liquidity.itou());
                deltaLiquidity = -amountBX.utoi();
                deltaPnl = amountB0.utoi();
                asset.pnl += amountB0.utoi();
            } else if (asset.pnl > 0 && amount >= asset.liquidity) {
                (, uint256 amountBX) = IBTokenSwapper(b.swapperAddress).swapExactBaseForQuote(asset.pnl.itou());
                deltaLiquidity = amountBX.utoi();
                deltaPnl = -asset.pnl;
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

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities(blength);
        require(_getBToken0Ratio(totalDynamicEquity, dynamicEquities) >= _minBToken0Ratio, 'insufficient bToken0');
        require(_getPoolMarginRatio(totalDynamicEquity, slength) >= _minPoolMarginRatio, 'pool insufficient liquidity');

        IERC20(b.bTokenAddress).safeTransfer(owner, bAmount.rescale(18, decimals));
        emit RemoveLiquidity(owner, bTokenId, bAmount);
    }

    function addMargin(address owner, uint256 bTokenId, uint256 bAmount) public override _router_ _lock_ {
        IPToken pToken = IPToken(_pTokenAddress);
        if (!pToken.exists(owner)) pToken.mint(owner);

        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, owner, address(this), bAmount);

        int256 margin = pToken.getMargin(owner, bTokenId) + bAmount.utoi();

        pToken.updateMargin(owner, bTokenId, margin);
        emit AddMargin(owner, bTokenId, bAmount);
    }

    function removeMargin(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) public override _router_ _lock_ {
        _update(blength, slength);
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
            margin = 0;
        } else {
            margin -= amount;
        }
        pToken.updateMargin(owner, bTokenId, margin);

        require(_getTraderMarginRatio(owner, blength, slength) >= _minInitialMarginRatio, 'insufficient margin');

        IERC20(b.bTokenAddress).safeTransfer(owner, bAmount.rescale(18, decimals));
        emit RemoveMargin(owner, bTokenId, bAmount);
    }

    struct TradeParams {
        int256 curCost;
        int256 fee;
        int256 realizedCost;
        int256 protocolFee;
    }

    function trade(address owner, uint256 symbolId, int256 tradeVolume, uint256 blength, uint256 slength) public override _router_ _lock_ {
        _update(blength, slength);
        _settleTraderFundingFee(owner, slength);

        SymbolInfo storage s = _symbols[symbolId];
        IPToken.Position memory p = IPToken(_pTokenAddress).getPosition(owner, symbolId);

        TradeParams memory params;

        tradeVolume = tradeVolume.reformat(0);
        params.curCost = tradeVolume * s.price / ONE * s.multiplier / ONE;
        params.fee = params.curCost.abs() * s.feeRatio / ONE;

        if ((p.volume >= 0 && tradeVolume >= 0) || (p.volume <= 0 && tradeVolume <= 0)) {

        } else if (p.volume.abs() <= tradeVolume.abs()) {
            params.realizedCost = params.curCost * p.volume.abs() / tradeVolume.abs() + p.cost;
        } else {
            params.realizedCost = p.cost * tradeVolume.abs() / p.volume.abs() + params.curCost;
        }

        p.volume += tradeVolume;
        p.cost += params.curCost - params.realizedCost;
        p.lastCumulativeFundingRate = s.cumulativeFundingRate;
        IPToken(_pTokenAddress).updateMargin(
            owner, 0, IPToken(_pTokenAddress).getMargin(owner, 0) + (-params.fee - params.realizedCost).reformat(_decimals0)
        );
        IPToken(_pTokenAddress).updatePosition(owner, symbolId, p);

        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += params.curCost - params.realizedCost;

        params.protocolFee = params.fee * _protocolFeeCollectRatio / ONE;
        _protocolFeeCollected += params.protocolFee;

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities(blength);
        _distributePnlToBTokens(params.fee - params.protocolFee, totalDynamicEquity, dynamicEquities, blength);
        require(_getPoolMarginRatio(totalDynamicEquity, slength) >= _minPoolMarginRatio, 'pool insufficient liquidity');
        require(_getTraderMarginRatio(owner, blength, slength) >= _minInitialMarginRatio, 'insufficient margin');

        emit Trade(owner, symbolId, tradeVolume, s.price.itou());
    }

    function liquidate(address liquidator, address owner, uint256 blength, uint256 slength) public override _router_ _lock_ {
        _update(blength, slength);
        _settleTraderFundingFee(owner, slength);
        require(_getTraderMarginRatio(owner, blength, slength) < _minMaintenanceMarginRatio, 'cannot liquidate');

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
                (uint256 amountB0, ) = IBTokenSwapper(_bTokens[i].swapperAddress).swapExactQuoteForBase(margins[i].itou());
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
    function _update(uint256 blength, uint256 slength) internal {
        uint256 blocknumber = block.number;
        if (blocknumber != _lastUpdateBlock) {
            _updateBTokenPrices(blength);
            (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities(blength);
            int256 undistributedPnl = _updateSymbolPrices(totalDynamicEquity, slength);
            _distributePnlToBTokens(undistributedPnl, totalDynamicEquity, dynamicEquities, blength);
            _lastUpdateBlock = blocknumber;
        }
    }

    function _updateBTokenPrices(uint256 blength) internal {
        for (uint256 i = 1; i < blength; i++) {
            _bTokens[i].price = IOracle(_bTokens[i].oracleAddress).getPrice().utoi();
        }
    }

    function _getBTokenDynamicEquities(uint256 blength) internal view returns (int256, int256[] memory) {
        int256 totalDynamicEquity;
        int256[] memory dynamicEquities = new int256[](blength);
        for (uint256 i = 0; i < blength; i++) {
            BTokenInfo storage b = _bTokens[i];
            int256 liquidity = b.liquidity;
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
                    int256 distributedPnl = (pnl * dynamicEquities[i] / totalDynamicEquity).reformat(_decimals0);
                    b.pnl += distributedPnl;
                    b.cumulativePnl += distributedPnl * ONE / b.liquidity;
                }
            }
        }
    }

    function _updateSymbolPrices(int256 totalDynamicEquity, uint256 slength) internal returns (int256) {
        if (totalDynamicEquity <= 0) return 0;
        int256 undistributedPnl;
        for (uint256 i = 0; i < slength; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 price = IOracle(s.oracleAddress).getPrice().utoi();
            int256 tradersNetVolume = s.tradersNetVolume;
            if (tradersNetVolume != 0) {
                int256 multiplier = s.multiplier;
                int256 r = tradersNetVolume * price / ONE * price / ONE * multiplier / ONE * multiplier / ONE * s.fundingRateCoefficient / totalDynamicEquity;
                int256 delta = r * int256(block.number - _lastUpdateBlock);

                undistributedPnl += tradersNetVolume * delta / ONE;
                undistributedPnl -= tradersNetVolume * (price - s.price) / ONE * multiplier / ONE;

                unchecked { s.cumulativeFundingRate += delta; }
            }
            s.price = price;
        }
        return undistributedPnl;
    }

    function _getBToken0Ratio(int256 totalDynamicEquity, int256[] memory dynamicEquities) internal pure returns (int256) {
        return totalDynamicEquity == 0 ? int256(0) : dynamicEquities[0] * ONE / totalDynamicEquity;
    }

    function _getPoolMarginRatio(int256 totalDynamicEquity, uint256 slength) internal view returns (int256) {
        int256 totalCost;
        for (uint256 i = 0; i < slength; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 tradersNetVolume = s.tradersNetVolume;
            if (tradersNetVolume != 0) {
                int256 cost = tradersNetVolume * s.price / ONE * s.multiplier / ONE;
                totalDynamicEquity -= cost - s.tradersNetCost;
                totalCost -= cost;
            }
        }
        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost.abs();
    }

    // setting funding fee trader's side
    // this funding fee is already settled to bTokens in `_update`
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
            int256 margin = pToken.getMargin(owner, 0) - funding.reformat(_decimals0);
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
                    (amountB0, amountBX) = IBTokenSwapper(_bTokens[i].swapperAddress).swapQuoteForExactBase((-margins[0]).itou(), margins[i].itou());
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
                totalCost += cost;
            }
        }

        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost.abs();
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
