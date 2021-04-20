// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/IBTokenHandler.sol';
import '../interface/ISymbolHandler.sol';
import '../interface/IPToken.sol';
import '../interface/ILToken.sol';
import '../interface/IPerpetualPool.sol';
import '../interface/ILiquidatorQualifier.sol';
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';
import '../utils/Migratable.sol';

contract PerpetualPool is IPerpetualPool, Migratable {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256  constant ONE  = 10**18;
    uint256 constant UONE = 10**18;

    int256  _minBToken0Ratio;
    int256  _minPoolMarginRatio;
    int256  _minInitialMarginRatio;
    int256  _minMaintenanceMarginRatio;
    int256  _minLiquidationReward;
    int256  _maxLiquidationReward;
    int256  _liquidationCutRatio;
    int256  _protocolFeeCollectRatio;

    address _pTokenAddress;
    address _lTokenAddress;
    address _liquidatorQualifierAddress;
    address _protocolAddress;

    uint256 _lastUpdateBlock;
    int256  _protocolLiquidity;

    SymbolInfo[] _symbols;   // symbolId indexed
    BTokenInfo[] _bTokens;   // bTokenId indexed

    bool private _mutex;
    modifier _lock_() {
        require(!_mutex, 'reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    function initialize(
        int256[8] memory parameters_,
        address[4] memory addresses_
    ) public override {
        require(_bTokens.length == 0 && _controller == address(0), 'intialized');

        _controller = msg.sender;
        setParameters(parameters_);
        setAddresses(addresses_);
    }

    function getParameters() public override view returns (
        int256 minBToken0Ratio,
        int256 minPoolMarginRatio,
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    ) {
        minBToken0Ratio = _minBToken0Ratio;
        minPoolMarginRatio = _minPoolMarginRatio;
        minInitialMarginRatio = _minInitialMarginRatio;
        minMaintenanceMarginRatio = _minMaintenanceMarginRatio;
        minLiquidationReward = _minLiquidationReward;
        maxLiquidationReward = _maxLiquidationReward;
        liquidationCutRatio = _liquidationCutRatio;
        protocolFeeCollectRatio = _protocolFeeCollectRatio;
    }

    function getAddresses() public override view returns (
        address pTokenAddress,
        address lTokenAddress,
        address liquidatorQualifierAddress,
        address protocolAddress
    ) {
        pTokenAddress = _pTokenAddress;
        lTokenAddress = _lTokenAddress;
        liquidatorQualifierAddress = _liquidatorQualifierAddress;
        protocolAddress = _protocolAddress;
    }

    function getSymbol(uint256 symbolId) public override view returns (SymbolInfo memory) {
        return _symbols[symbolId];
    }

    function getBToken(uint256 bTokenId) public override view returns (BTokenInfo memory) {
        return _bTokens[bTokenId];
    }

    function addSymbol(SymbolInfo memory info) public override _controller_ {
        require(info.cumulativeFundingRate == 0 && info.tradersNetVolume == 0 && info.tradersNetCost == 0, 'invalid symbol');
        _symbols.push(info);
        IPToken(_pTokenAddress).setNumSymbols(_symbols.length);
    }

    function addBToken(BTokenInfo memory info) public override _controller_ {
        require(info.liquidity == 0 && info.pnl == 0 && info.cumulativePnl == 0, 'invalid bToken');
        if (_bTokens.length > 0) {
            IERC20(_bTokens[0].bTokenAddress).safeApprove(info.handlerAddress, type(uint256).max);
            IERC20(info.bTokenAddress).safeApprove(info.handlerAddress, type(uint256).max);
        }
        _bTokens.push(info);
        IPToken(_pTokenAddress).setNumBTokens(_bTokens.length);
    }


    //================================================================================
    // Interactions
    //================================================================================
    function addLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        address owner = msg.sender;
        _checkBTokenId(bTokenId);
        ILToken lToken = ILToken(_lTokenAddress);
        if (!lToken.exists(owner)) {
            lToken.mint(owner);
        }
        _addLiquidity(owner, bTokenId, bAmount);
    }

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        address owner = msg.sender;
        _checkBTokenId(bTokenId);
        require(ILToken(_lTokenAddress).exists(owner), 'not lp');
        _removeLiquidity(owner, bTokenId, bAmount);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public override {
        address owner = msg.sender;
        _checkBTokenId(bTokenId);
        IPToken pToken = IPToken(_pTokenAddress);
        if (!pToken.exists(owner)) {
            pToken.mint(owner);
        }
        _addMargin(owner, bTokenId, bAmount);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public override {
        address owner = msg.sender;
        _checkBTokenId(bTokenId);
        _checkTrader(owner);
        _removeMargin(owner, bTokenId, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public override {
        address owner = msg.sender;
        _checkSymbolId(symbolId);
        _checkTrader(owner);
        _trade(owner, symbolId, tradeVolume);
    }

    function liquidate(address owner) public override {
        address qualifier = _liquidatorQualifierAddress;
        require(qualifier == address(0) || ILiquidatorQualifier(qualifier).isQualifiedLiquidator(msg.sender),
                'unqualified liquidator');
        _checkTrader(owner);
        _liquidate(owner);
    }


    //================================================================================
    // Core logics
    //================================================================================

    function _addLiquidity(address owner, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        _update();
        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, owner, address(this), bAmount);

        int256 cumulativePnl = b.cumulativePnl;
        ILToken lToken = ILToken(_lTokenAddress);
        ILToken.Asset memory asset = lToken.getAsset(owner, bTokenId);

        int256 delta;
        int256 pnl = ((cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE).reformat(_bTokens[0].decimals);
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
        emit AddLiquidity(owner, bTokenId, bAmount);
    }

    function _removeLiquidity(address owner, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        _update();
        BTokenInfo storage b = _bTokens[bTokenId];
        ILToken lToken = ILToken(_lTokenAddress);
        ILToken.Asset memory asset = lToken.getAsset(owner, bTokenId);

        int256 cumulativePnl = b.cumulativePnl;
        int256 amount = bAmount.utoi();
        int256 pnl = ((cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE).reformat(_bTokens[0].decimals);
        int256 deltaLiquidity;
        int256 deltaPnl;
        if (bTokenId == 0) {
            deltaLiquidity = pnl;
            deltaPnl = -pnl;
        } else {
            asset.pnl += pnl;
            if (asset.pnl < 0) {
                (uint256 amountB0, uint256 amountBX) = IBTokenHandler(b.handlerAddress).swapQuoteForExactBase((-asset.pnl).itou(), asset.liquidity.itou());
                deltaLiquidity = -amountBX.utoi();
                deltaPnl = amountB0.utoi();
                asset.pnl += amountB0.utoi();
            } else if (asset.pnl > 0 && amount >= asset.liquidity) {
                (, uint256 amountBX) = IBTokenHandler(b.handlerAddress).swapExactBaseForQuote(asset.pnl.itou());
                deltaLiquidity = amountBX.utoi();
                deltaPnl = -asset.pnl;
                asset.pnl = 0;
            }
        }
        asset.lastCumulativePnl = cumulativePnl;

        if (amount >= asset.liquidity || amount >= asset.liquidity + deltaLiquidity) {
            bAmount = (asset.liquidity + deltaLiquidity).itou();
            asset.liquidity = 0;
            b.liquidity -= asset.liquidity;
        } else {
            asset.liquidity += deltaLiquidity - amount;
            b.liquidity += deltaLiquidity - amount;
        }
        b.pnl += deltaPnl;
        lToken.updateAsset(owner, bTokenId, asset);

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        require(_getBToken0Ratio(totalDynamicEquity, dynamicEquities) >= _minBToken0Ratio, 'insufficient bToken0');
        require(_getPoolMarginRatio(totalDynamicEquity) >= _minPoolMarginRatio, 'pool insufficient liquidity');

        IERC20(b.bTokenAddress).safeTransfer(owner, bAmount.rescale(18, b.decimals));
        emit RemoveLiquidity(owner, bTokenId, bAmount);
    }

    function _addMargin(address owner, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, owner, address(this), bAmount);

        IPToken pToken = IPToken(_pTokenAddress);
        int256 margin = pToken.getMargin(owner, bTokenId) + bAmount.utoi();

        pToken.updateMargin(owner, bTokenId, margin);
        emit AddMargin(owner, bTokenId, bAmount);
    }

    function _removeMargin(address owner, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        _update();
        _settleTraderFundingFee(owner);
        _coverTraderDebt(owner);

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

        require(_getTraderMarginRatio(owner) >= _minInitialMarginRatio, 'insufficient margin');

        IERC20(b.bTokenAddress).safeTransfer(owner, bAmount.rescale(18, decimals));
        emit RemoveMargin(owner, bTokenId, bAmount);
    }

    function _trade(address owner, uint256 symbolId, int256 tradeVolume) internal _lock_ {
        _update();
        _settleTraderFundingFee(owner);

        IPToken pToken = IPToken(_pTokenAddress);
        tradeVolume = tradeVolume.reformat(0);
        SymbolInfo storage s = _symbols[symbolId];
        IPToken.Position memory p = pToken.getPosition(owner, symbolId);

        int256 curCost = tradeVolume * s.price / ONE * s.multiplier / ONE;
        int256 fee = curCost.abs() * s.feeRatio / ONE;

        int256 realizedCost;
        if ((p.volume >= 0 && tradeVolume >= 0) || (p.volume <= 0 && tradeVolume <= 0)) {

        } else if (p.volume.abs() <= tradeVolume.abs()) {
            realizedCost = curCost * p.volume.abs() / tradeVolume.abs() + p.cost;
        } else {
            realizedCost = p.cost * tradeVolume.abs() / p.volume.abs() + curCost;
        }

        p.volume += tradeVolume;
        p.cost += curCost - realizedCost;
        p.lastCumulativeFundingRate = s.cumulativeFundingRate;
        pToken.updateMargin(owner, 0, pToken.getMargin(owner, 0) + (-fee - realizedCost).reformat(_bTokens[0].decimals));
        pToken.updatePosition(owner, symbolId, p);

        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += curCost - realizedCost;

        int256 protocolFee = fee * _protocolFeeCollectRatio / ONE;
        _protocolLiquidity += protocolFee;

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        _distributePnlToBTokens(fee - protocolFee, totalDynamicEquity, dynamicEquities);
        require(_getPoolMarginRatio(totalDynamicEquity) >= _minPoolMarginRatio, 'pool insufficient liquidity');
        require(_getTraderMarginRatio(owner) >= _minInitialMarginRatio, 'insufficient margin');

        emit Trade(owner, symbolId, tradeVolume, s.price.itou());
    }

    function _liquidate(address owner) internal _lock_ {
        _update();
        _settleTraderFundingFee(owner);
        require(_getTraderMarginRatio(owner) < _minMaintenanceMarginRatio, 'cannot liquidate');

        IPToken pToken = IPToken(_pTokenAddress);
        IPToken.Position[] memory positions = pToken.getPositions(owner);
        int256 netEquity;
        uint256 length = _symbols.length;
        for (uint256 i = 0; i < length; i++) {
            if (positions[i].volume != 0) {
                _symbols[i].tradersNetVolume -= positions[i].volume;
                _symbols[i].tradersNetCost -= positions[i].cost;
                netEquity += positions[i].volume * _symbols[i].price / ONE * _symbols[i].multiplier / ONE - positions[i].cost;
            }
        }

        int256[] memory margins = pToken.getMargins(owner);
        netEquity += margins[0];
        length = _bTokens.length;
        for (uint256 i = 1; i < length; i++) {
            if (margins[i] > 0) {
                (uint256 amountB0, ) = IBTokenHandler(_bTokens[i].handlerAddress).swapExactQuoteForBase(margins[i].itou());
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
            reward = ((netEquity - minReward) * _liquidationCutRatio / ONE + minReward).reformat(_bTokens[0].decimals);
        }

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        _distributePnlToBTokens(netEquity - reward, totalDynamicEquity, dynamicEquities);

        pToken.burn(owner);
        IERC20(_bTokens[0].bTokenAddress).safeTransfer(msg.sender, reward.itou().rescale(18, _bTokens[0].decimals));

        emit Liquidate(msg.sender, owner);
    }


    //================================================================================
    // Helpers
    //================================================================================

    function setParameters(int256[8] memory parameters_) internal {
        _minBToken0Ratio = parameters_[0];
        _minPoolMarginRatio = parameters_[1];
        _minInitialMarginRatio = parameters_[2];
        _minMaintenanceMarginRatio = parameters_[3];
        _minLiquidationReward = parameters_[4];
        _maxLiquidationReward = parameters_[5];
        _liquidationCutRatio = parameters_[6];
        _protocolFeeCollectRatio = parameters_[7];
    }

    function setAddresses(address[4] memory addresses_) internal {
        _pTokenAddress = addresses_[0];
        _lTokenAddress = addresses_[1];
        _liquidatorQualifierAddress = addresses_[2];
        _protocolAddress = addresses_[3];
    }

    function _checkSymbolId(uint256 symbolId) internal view {
        require(symbolId < _symbols.length, 'invalid symbolId');
    }

    function _checkBTokenId(uint256 bTokenId) internal view {
        require(bTokenId < _bTokens.length, 'invalid bTokenId');
    }

    function _checkTrader(address owner) internal view {
        require(IPToken(_pTokenAddress).exists(owner), 'not trader');
    }

    // update bTokens/symbols prices
    // distribute pnl to bTokens, which is generated since last update, including pnl and funding fees for opening positions
    // by calling this function at the beginning of each block, all LP/Traders status are settled
    function _update() internal {
        uint256 blocknumber = block.number;
        if (blocknumber != _lastUpdateBlock) {
            _updateBTokenPrices();
            (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
            int256 undistributedPnl = _updateSymbolPrices(totalDynamicEquity);
            _distributePnlToBTokens(undistributedPnl, totalDynamicEquity, dynamicEquities);
            _lastUpdateBlock = blocknumber;
        }
    }

    function _updateBTokenPrices() internal {
        uint256 length = _bTokens.length;
        for (uint256 i = 1; i < length; i++) {
            _bTokens[i].price = IBTokenHandler(_bTokens[i].handlerAddress).getPrice().utoi();
        }
    }

    function _getBTokenDynamicEquities() internal view returns (int256, int256[] memory) {
        uint256 length = _bTokens.length;
        int256 totalDynamicEquity;
        int256[] memory dynamicEquities = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
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

    function _distributePnlToBTokens(int256 pnl, int256 totalDynamicEquity, int256[] memory dynamicEquities) internal {
        if (totalDynamicEquity > 0 && pnl != 0) {
            uint256 decimals = _bTokens[0].decimals;
            uint256 length = _bTokens.length;
            for (uint256 i = 0; i < length; i++) {
                if (dynamicEquities[i] > 0) {
                    BTokenInfo storage b = _bTokens[i];
                    int256 distributedPnl = (pnl * dynamicEquities[i] / totalDynamicEquity).reformat(decimals);
                    b.pnl += distributedPnl;
                    b.cumulativePnl += distributedPnl * ONE / b.liquidity;
                }
            }
        }
    }

    function _updateSymbolPrices(int256 totalDynamicEquity) internal returns (int256) {
        if (totalDynamicEquity <= 0) return 0;
        int256 undistributedPnl;
        uint256 length = _symbols.length;
        for (uint256 i = 0; i < length; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 price = ISymbolHandler(s.handlerAddress).getPrice().utoi();

            int256 multiplier = s.multiplier;
            int256 tradersNetVolume = s.tradersNetVolume;
            if (tradersNetVolume != 0) {
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

    function _getPoolMarginRatio(int256 totalDynamicEquity) internal view returns (int256) {
        int256 totalCost;
        uint256 length = _symbols.length;
        for (uint256 i = 0; i < length; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 cost = s.tradersNetVolume * s.price / ONE * s.multiplier / ONE;
            totalDynamicEquity -= cost - s.tradersNetCost;
            totalCost -= cost;
        }
        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost.abs();
    }

    // setting funding fee trader's side
    // this funding fee is already settled to bTokens in `_update`
    function _settleTraderFundingFee(address owner) internal {
        IPToken pToken = IPToken(_pTokenAddress);
        int256 funding;
        uint256 length = _symbols.length;
        IPToken.Position[] memory positions = pToken.getPositions(owner);
        for (uint256 i = 0; i < length; i++) {
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
            int256 margin = pToken.getMargin(owner, 0) - funding.reformat(_bTokens[0].decimals);
            pToken.updateMargin(owner, 0, margin);
        }
    }

    function _coverTraderDebt(address owner) internal {
        IPToken pToken = IPToken(_pTokenAddress);
        int256[] memory margins = pToken.getMargins(owner);
        if (margins[0] < 0) {
            uint256 length = _bTokens.length;
            uint256 amountB0;
            uint256 amountBX;
            for (uint256 i = length - 1; i > 0; i--) {
                if (margins[i] > 0) {
                    (amountB0, amountBX) = IBTokenHandler(_bTokens[i].handlerAddress).swapQuoteForExactBase((-margins[0]).itou(), margins[i].itou());
                    margins[0] += amountB0.utoi();
                    margins[i] -= amountBX.utoi();
                }
                if (margins[0] >= 0) break;
            }
            pToken.updateMargins(owner, margins);
        }
    }

    function _getTraderMarginRatio(address owner) internal view returns (int256) {
        IPToken pToken = IPToken(_pTokenAddress);

        int256[] memory margins = pToken.getMargins(owner);
        int256 totalDynamicEquity = margins[0];
        int256 totalCost;
        uint256 length = _bTokens.length;
        for (uint256 i = 1; i < length; i++) {
            totalDynamicEquity += margins[i] * _bTokens[i].price / ONE * _bTokens[i].discount / ONE;
        }

        IPToken.Position[] memory positions = pToken.getPositions(owner);
        length = _symbols.length;
        for (uint256 i = 0; i < length; i++) {
            if (positions[i].volume != 0) {
                int256 cost = positions[i].volume * _symbols[i].price / ONE * _symbols[i].multiplier / ONE;
                totalDynamicEquity += cost - positions[i].cost;
                totalCost += cost;
            }
        }

        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost.abs();
    }

    function _deflationCompatibleSafeTransferFrom(address bTokenAddress, address from, address to, uint256 bAmount)
        internal returns (uint256)
    {
        IERC20 token = IERC20(bTokenAddress);
        uint256 decimals = token.decimals();

        uint256 balance1 = token.balanceOf(address(to));
        token.safeTransferFrom(from, to, bAmount.rescale(18, decimals));
        uint256 balance2 = token.balanceOf(address(to));

        return (balance2 - balance1).rescale(decimals, 18);
    }

}
