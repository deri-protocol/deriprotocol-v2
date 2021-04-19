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
        require(!_mutex, 'PerpetualPool: reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    constructor () {
        _controller = msg.sender;
    }

    function initialize(
        int256[8] memory parameters_,
        address[4] memory addresses_
    ) public override {
        require(_bTokens.length == 0 && _controller == address(0), 'PerpetualPool.initialize: alreadly initialized');

        _controller = msg.sender;
        setParameters(parameters_);
        setAddresses(addresses_);
    }

    function getParameters() public override view returns (int256[8] memory parameters) {
        parameters[0] = _minBToken0Ratio;
        parameters[1] = _minPoolMarginRatio;
        parameters[2] = _minInitialMarginRatio;
        parameters[3] = _minMaintenanceMarginRatio;
        parameters[4] = _minLiquidationReward;
        parameters[5] = _maxLiquidationReward;
        parameters[6] = _liquidationCutRatio;
        parameters[7] = _protocolFeeCollectRatio;
    }

    function getAddresses() public override view returns (address[4] memory addresses) {
        addresses[0] = _pTokenAddress;
        addresses[1] = _lTokenAddress;
        addresses[2] = _liquidatorQualifierAddress;
        addresses[3] = _protocolAddress;
    }

    function getSymbol(uint256 symbolId) public override view returns (SymbolInfo memory) {
        return _symbols[symbolId];
    }

    function getBToken(uint256 bTokenId) public override view returns (BTokenInfo memory) {
        return _bTokens[bTokenId];
    }

    function setParameters(int256[8] memory parameters_) public override _controller_ {
        _minBToken0Ratio = parameters_[0];
        _minPoolMarginRatio = parameters_[1];
        _minInitialMarginRatio = parameters_[2];
        _minMaintenanceMarginRatio = parameters_[3];
        _minLiquidationReward = parameters_[4];
        _maxLiquidationReward = parameters_[5];
        _liquidationCutRatio = parameters_[6];
        _protocolFeeCollectRatio = parameters_[7];
    }

    function setAddresses(address[4] memory addresses_) public override _controller_ {
        _pTokenAddress = addresses_[0];
        _lTokenAddress = addresses_[1];
        _liquidatorQualifierAddress = addresses_[2];
        _protocolAddress = addresses_[3];
    }

    function addSymbol(SymbolInfo memory info) public override _controller_ {
        require(info.cumulativeFundingRate == 0 && info.tradersNetVolume == 0 && info.tradersNetCost == 0,
                'PerpetualPool.addSymbol: invalid symbol');
        _symbols.push(info);
        IPToken(_pTokenAddress).setNumSymbols(_symbols.length);
    }

    function addBToken(BTokenInfo memory info) public override _controller_ {
        require(info.liquidity == 0 && info.pnl == 0 && info.cumulativePnl == 0,
                'PerpetualPool.addBToken: invalid bToken');
        if (_bTokens.length > 0) {
            IERC20(info.bTokenAddress).safeApprove(info.handlerAddress, type(uint256).max);
        }
        _bTokens.push(info);
        IPToken(_pTokenAddress).setNumSymbols(_bTokens.length);
    }


    //================================================================================
    // Interactions
    //================================================================================
    function addLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        require(bTokenId < _bTokens.length, 'PerpetualPool.addLiquidity: invalid bTokenId');
        address owner = msg.sender;
        ILToken lToken = ILToken(_lTokenAddress);
        if (!lToken.exists(owner)) {
            lToken.mint(owner);
        }
        _addLiquidity(owner, bTokenId, bAmount);
    }

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        address owner = msg.sender;
        require(bTokenId < _bTokens.length, 'PerpetualPool.removeLiquidity: invalid bTokenId');
        require(ILToken(_lTokenAddress).exists(owner), 'PerpetualPool.removeLiquidity: nonexistent lp');
        _removeLiquidity(owner, bTokenId, bAmount);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public override {
        require(bTokenId < _bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        address owner = msg.sender;
        IPToken pToken = IPToken(_pTokenAddress);
        if (!pToken.exists(owner)) {
            pToken.mint(owner);
        }
        _addMargin(owner, bTokenId, bAmount);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public override {
        address owner = msg.sender;
        require(bTokenId < _bTokens.length, 'PerpetualPool.removeMargin: invalid bTokenId');
        require(IPToken(_pTokenAddress).exists(owner), 'PerpetualPool.removeMargin: nonexistent trader');
        _removeMargin(owner, bTokenId, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public override {
        address owner = msg.sender;
        require(symbolId < _symbols.length, 'PerpetualPool.trade: invalid symbolId');
        require(IPToken(_pTokenAddress).exists(owner), 'PerpetualPool.trade: add margin before trade');
        _trade(owner, symbolId, tradeVolume);
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
        if (bTokenId == 0) {
            delta = bAmount.utoi() + (cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE;
        } else {
            delta = bAmount.utoi();
            asset.pnl += (cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE;
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
        int256 delta;
        if (bTokenId == 0) {
            delta = pnl;
        } else {
            asset.pnl += pnl;
            if (asset.pnl < 0) {
                delta = -(IBTokenHandler(b.handlerAddress).swapExactB0ForBX((-asset.pnl).itou())).utoi();
                asset.pnl = 0;
            } else if (asset.pnl > 0 && amount >= asset.liquidity) {
                delta = (IBTokenHandler(b.handlerAddress).swapExactB0ForBX(asset.pnl.itou())).utoi();
                asset.pnl = 0;
            }
        }
        asset.lastCumulativePnl = cumulativePnl;

        if (amount >= asset.liquidity || amount >= asset.liquidity + delta) {
            bAmount = (asset.liquidity + delta).itou();
            asset.liquidity = 0;
            b.liquidity -= asset.liquidity;
        } else {
            asset.liquidity += delta - amount;
            b.liquidity += delta - amount;
        }
        lToken.updateAsset(owner, bTokenId, asset);

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        require(_getBToken0Ratio(totalDynamicEquity, dynamicEquities) >= _minBToken0Ratio, 'PerpetualPool.removeLiquidity: insufficient bToken0');
        require(_getPoolMarginRatio(totalDynamicEquity) >= _minPoolMarginRatio, 'PerpetualPool.removeLiquidity: pool insufficient liquidity');

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

        require(_getTraderMarginRatio(owner) >= _minInitialMarginRatio, 'PerpetualPool.removeMargin: insufficient margin');

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
        require(_getPoolMarginRatio(totalDynamicEquity) >= _minPoolMarginRatio, 'PerpetualPool.trade: pool insufficient liquidity');
        require(_getTraderMarginRatio(owner) >= _minInitialMarginRatio, 'PerpetualPool.trade: insufficient margin');

        emit Trade(owner, symbolId, tradeVolume, s.price.itou());
    }


    //================================================================================
    // Helpers
    //================================================================================

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
        for (uint256 i = 0; i < length; i++) {
            _bTokens[i].price = IBTokenHandler(_bTokens[i].bTokenAddress).getPrice().utoi();
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
            totalCost += cost;
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
                    (amountB0, amountBX) = IBTokenHandler(_bTokens[i].handlerAddress).swapBXForExactB0((-margins[0]).itou(), margins[i].itou());
                    margins[0] += amountB0.utoi();
                    margins[i] -= amountBX.utoi();
                }
                if (margins[0] >= 0) break;
            }
            pToken.updateMargins(owner, margins);
        }
    }

    function _getTraderMarginRatio(address owner) internal view returns (int256) {
        int256 totalDynamicEquity;
        int256 totalCost;
        IPToken pToken = IPToken(_pTokenAddress);

        uint256 length = _bTokens.length;
        int256[] memory margins = pToken.getMargins(owner);
        for (uint256 i = 0; i < length; i++) {
            totalDynamicEquity += margins[i] * _bTokens[i].price / ONE * _bTokens[i].discount / ONE;
        }

        length = _symbols.length;
        IPToken.Position[] memory positions = pToken.getPositions(owner);
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
