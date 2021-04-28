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
import '../utils/Migratable.sol';

contract PerpetualPool is IPerpetualPool, Migratable {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256  constant ONE = 10**18;

    int256  _minBToken0Ratio;
    int256  _minPoolMarginRatio;
    int256  _minInitialMarginRatio;
    int256  _minMaintenanceMarginRatio;
    int256  _minLiquidationReward;
    int256  _maxLiquidationReward;
    int256  _liquidationCutRatio;
    int256  _protocolFeeCollectRatio;

    address _lTokenAddress;
    address _pTokenAddress;
    address _protocolFeeCollectAddress;

    uint256 _lastUpdateBlock;
    int256  _protocolLiquidity;

    BTokenInfo[] _bTokens;   // bTokenId indexed
    SymbolInfo[] _symbols;   // symbolId indexed

    bool private _mutex;
    modifier _lock_() {
        require(!_mutex, 'reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    constructor () {
        _controller = msg.sender;
    }

    function initialize(uint256[8] memory parameters, address[3] memory addresses) public override _controller_ {
        _minBToken0Ratio = int256(parameters[0]);
        _minPoolMarginRatio = int256(parameters[1]);
        _minInitialMarginRatio = int256(parameters[2]);
        _minMaintenanceMarginRatio = int256(parameters[3]);
        _minLiquidationReward = int256(parameters[4]);
        _maxLiquidationReward = int256(parameters[5]);
        _liquidationCutRatio = int256(parameters[6]);
        _protocolFeeCollectRatio = int256(parameters[7]);

        _lTokenAddress = addresses[0];
        _pTokenAddress = addresses[1];
        _protocolFeeCollectAddress = addresses[2];
    }

    function approveMigration() public override(IMigratable, Migratable) _controller_ {
        require(_migrationTimestamp != 0 && block.timestamp >= _migrationTimestamp, 'migrationTimestamp not met');
        for (uint256 i = 0; i < _bTokens.length; i++) {
            IERC20(_bTokens[i].bTokenAddress).safeApprove(_migrationDestination, type(uint256).max);
        }
        ILToken(_lTokenAddress).setPool(_migrationDestination);
        IPToken(_pTokenAddress).setPool(_migrationDestination);
    }

    function getParameters() public override view returns (
        uint256 minBToken0Ratio,
        uint256 minPoolMarginRatio,
        uint256 minInitialMarginRatio,
        uint256 minMaintenanceMarginRatio,
        uint256 minLiquidationReward,
        uint256 maxLiquidationReward,
        uint256 liquidationCutRatio,
        uint256 protocolFeeCollectRatio
    ) {
        minBToken0Ratio = uint256(_minBToken0Ratio);
        minPoolMarginRatio = uint256(_minPoolMarginRatio);
        minInitialMarginRatio = uint256(_minInitialMarginRatio);
        minMaintenanceMarginRatio = uint256(_minMaintenanceMarginRatio);
        minLiquidationReward = uint256(_minLiquidationReward);
        maxLiquidationReward = uint256(_maxLiquidationReward);
        liquidationCutRatio = uint256(_liquidationCutRatio);
        protocolFeeCollectRatio = uint256(_protocolFeeCollectRatio);
    }

    function setParameters(uint256[8] memory parameters) public override _controller_ {
        _minBToken0Ratio = int256(parameters[0]);
        _minPoolMarginRatio = int256(parameters[1]);
        _minInitialMarginRatio = int256(parameters[2]);
        _minMaintenanceMarginRatio = int256(parameters[3]);
        _minLiquidationReward = int256(parameters[4]);
        _maxLiquidationReward = int256(parameters[5]);
        _liquidationCutRatio = int256(parameters[6]);
        _protocolFeeCollectRatio = int256(parameters[7]);
    }

    function getAddresses() public override view returns (
        address lTokenAddress,
        address pTokenAddress,
        address protocolFeeCollectAddress
    ) {
        lTokenAddress = _lTokenAddress;
        pTokenAddress = _pTokenAddress;
        protocolFeeCollectAddress = _protocolFeeCollectAddress;
    }

    function getProtocolLiquidity() public override view returns (uint256) {
        return uint256(_protocolLiquidity);
    }

    function collectProtocolLiquidity() public override _controller_ {
        uint256 amount = uint256(_protocolLiquidity);
        IERC20(_bTokens[0].bTokenAddress).safeTransfer(_protocolFeeCollectAddress, amount.rescale(18, _bTokens[0].decimals));
        _protocolLiquidity = 0;
        emit ProtocolCollection(amount);
    }

    function getBToken(uint256 bTokenId) public override view returns (BTokenInfo memory) {
        return _bTokens[bTokenId];
    }

    function getSymbol(uint256 symbolId) public override view returns (SymbolInfo memory) {
        return _symbols[symbolId];
    }

    function addBToken(address bTokenAddress, address swapperAddress, address oracleAddress, uint256 discount)
        public override _controller_
    {
        BTokenInfo memory b;
        b.bTokenAddress = bTokenAddress;
        b.swapperAddress = swapperAddress;
        b.oracleAddress = oracleAddress;
        b.decimals = IERC20(bTokenAddress).decimals();
        b.discount = int256(discount);
        if (_bTokens.length > 0) {
            IERC20(_bTokens[0].bTokenAddress).safeApprove(swapperAddress, type(uint256).max);
            IERC20(bTokenAddress).safeApprove(swapperAddress, type(uint256).max);
        } else {
            b.price = ONE;
        }
        _bTokens.push(b);
        IPToken(_pTokenAddress).setNumBTokens(_bTokens.length);
    }

    function addSymbol(string memory symbol, address oracleAddress, uint256 multiplier, uint256 feeRatio, uint256 fundingRateCoefficient)
        public override _controller_
    {
        SymbolInfo memory s;
        s.symbol = symbol;
        s.oracleAddress = oracleAddress;
        s.multiplier = int256(multiplier);
        s.feeRatio = int256(feeRatio);
        s.fundingRateCoefficient = int256(fundingRateCoefficient);
        _symbols.push(s);
        IPToken(_pTokenAddress).setNumSymbols(_symbols.length);
    }

    function setBToken(uint256 bTokenId, address swapperAddress, address oracleAddress, uint256 discount) public override _controller_ {
        require(bTokenId < _bTokens.length, 'invalid bTokenId');
        _bTokens[bTokenId].swapperAddress = swapperAddress;
        _bTokens[bTokenId].oracleAddress = oracleAddress;
        _bTokens[bTokenId].discount = int256(discount);
    }

    function setSymbol(uint256 symbolId, address oracleAddress, uint256 feeRatio, uint256 fundingRateCoefficient) public override _controller_ {
        require(symbolId < _symbols.length, 'invalid symbolId');
        _symbols[symbolId].oracleAddress = oracleAddress;
        _symbols[symbolId].feeRatio = int256(feeRatio);
        _symbols[symbolId].fundingRateCoefficient = int256(fundingRateCoefficient);
    }


    //================================================================================
    // Interactions
    //================================================================================

    function addLiquidity(address owner, uint256 bTokenId, uint256 bAmount) public override {
        require(bTokenId < _bTokens.length, 'invalid bTokenId');
        ILToken lToken = ILToken(_lTokenAddress);
        if (!lToken.exists(owner)) lToken.mint(owner);

        _update();
        _addLiquidity(owner, bTokenId, bAmount);
    }

    function removeLiquidity(address owner, uint256 bTokenId, uint256 bAmount) public override {
        require(bTokenId < _bTokens.length, 'invalid bTokenId');
        require(ILToken(_lTokenAddress).exists(owner), 'not lp');

        _update();
        _removeLiquidity(owner, bTokenId, bAmount);
    }

    function addMargin(address owner, uint256 bTokenId, uint256 bAmount) public override {
        require(bTokenId < _bTokens.length, 'invalid bTokenId');
        IPToken pToken = IPToken(_pTokenAddress);
        if (!pToken.exists(owner)) pToken.mint(owner);

        _addMargin(owner, bTokenId, bAmount);
    }

    function removeMargin(address owner, uint256 bTokenId, uint256 bAmount) public override {
        require(bTokenId < _bTokens.length, 'invalid bTokenId');
        require(IPToken(_pTokenAddress).exists(owner), 'not trader');

        _update();
        _removeMargin(owner, bTokenId, bAmount);
    }

    function trade(address owner, uint256 symbolId, int256 tradeVolume) public override {
        require(symbolId < _symbols.length, 'invalid symbolId');
        require(IPToken(_pTokenAddress).exists(owner), 'not trader');

        _update();
        _trade(owner, symbolId, tradeVolume);
    }

    function liquidate(address liquidator, address owner) public override {
        require(IPToken(_pTokenAddress).exists(owner), 'not trader');

        _update();
        _liquidate(liquidator, owner);
    }


    //================================================================================
    // Core Logics
    //================================================================================

    function _addLiquidity(address owner, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, owner, address(this), bAmount);

        ILToken lToken = ILToken(_lTokenAddress);
        ILToken.Asset memory asset = lToken.getAsset(owner, bTokenId);

        int256 delta;
        int256 pnl = ((b.cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE).reformat(_bTokens[0].decimals);
        if (bTokenId == 0) {
            delta = bAmount.utoi() + pnl;
            b.pnl -= pnl; // this pnl comes from b.pnl, thus should be deducted from b.pnl
        } else {
            delta = bAmount.utoi();
            asset.pnl += pnl;
        }
        asset.liquidity += delta;
        asset.lastCumulativePnl = b.cumulativePnl;
        b.liquidity += delta;

        lToken.updateAsset(owner, bTokenId, asset);

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        require(_getBToken0Ratio(totalDynamicEquity, dynamicEquities) >= _minBToken0Ratio, 'insufficient bToken0');

        emit AddLiquidity(owner, bTokenId, bAmount);
    }

    function _removeLiquidity(address owner, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        ILToken lToken = ILToken(_lTokenAddress);
        ILToken.Asset memory asset = lToken.getAsset(owner, bTokenId);
        bAmount = bAmount.reformat(b.decimals);

        int256 amount = bAmount.utoi();
        int256 pnl = ((b.cumulativePnl - asset.lastCumulativePnl) * asset.liquidity / ONE).reformat(_bTokens[0].decimals);
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
        asset.lastCumulativePnl = b.cumulativePnl;

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
        _settleTraderFundingFee(owner);
        _coverTraderDebt(owner);

        IPToken pToken = IPToken(_pTokenAddress);
        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = bAmount.reformat(b.decimals);

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

        IERC20(b.bTokenAddress).safeTransfer(owner, bAmount.rescale(18, b.decimals));
        emit RemoveMargin(owner, bTokenId, bAmount);
    }

    function _trade(address owner, uint256 symbolId, int256 tradeVolume) internal _lock_ {
        _settleTraderFundingFee(owner);

        SymbolInfo storage s = _symbols[symbolId];
        IPToken.Position memory p = IPToken(_pTokenAddress).getPosition(owner, symbolId);
        tradeVolume = tradeVolume.reformat(0);

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
        IPToken(_pTokenAddress).updateMargin(
            owner, 0, IPToken(_pTokenAddress).getMargin(owner, 0) + (-fee - realizedCost).reformat(_bTokens[0].decimals)
        );
        IPToken(_pTokenAddress).updatePosition(owner, symbolId, p);

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

    function _liquidate(address liquidator, address owner) internal _lock_ {
        _settleTraderFundingFee(owner);
        require(_getTraderMarginRatio(owner) < _minMaintenanceMarginRatio, 'cannot liquidate');

        IPToken pToken = IPToken(_pTokenAddress);
        IPToken.Position[] memory positions = pToken.getPositions(owner);
        int256 netEquity;
        for (uint256 i = 0; i < _symbols.length; i++) {
            if (positions[i].volume != 0) {
                _symbols[i].tradersNetVolume -= positions[i].volume;
                _symbols[i].tradersNetCost -= positions[i].cost;
                netEquity += positions[i].volume * _symbols[i].price / ONE * _symbols[i].multiplier / ONE - positions[i].cost;
            }
        }

        int256[] memory margins = pToken.getMargins(owner);
        netEquity += margins[0];
        for (uint256 i = 1; i < _bTokens.length; i++) {
            if (margins[i] > 0) {
                (uint256 amountB0, ) = IBTokenSwapper(_bTokens[i].swapperAddress).swapExactQuoteForBase(margins[i].itou());
                netEquity += amountB0.utoi();
            }
        }

        int256 reward;
        if (netEquity <= _minLiquidationReward) {
            reward = _minLiquidationReward;
        } else if (netEquity >= _maxLiquidationReward) {
            reward = _maxLiquidationReward;
        } else {
            reward = ((netEquity - _minLiquidationReward) * _liquidationCutRatio / ONE + _minLiquidationReward).reformat(_bTokens[0].decimals);
        }

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        _distributePnlToBTokens(netEquity - reward, totalDynamicEquity, dynamicEquities);

        pToken.burn(owner);
        IERC20(_bTokens[0].bTokenAddress).safeTransfer(liquidator, reward.itou().rescale(18, _bTokens[0].decimals));

        emit Liquidate(liquidator, owner);
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
        for (uint256 i = 1; i < _bTokens.length; i++) {
            _bTokens[i].price = IOracle(_bTokens[i].oracleAddress).getPrice().utoi();
        }
    }

    function _getBTokenDynamicEquities() internal view returns (int256, int256[] memory) {
        int256 totalDynamicEquity;
        int256[] memory dynamicEquities = new int256[](_bTokens.length);
        for (uint256 i = 0; i < _bTokens.length; i++) {
            BTokenInfo storage b = _bTokens[i];
            int256 equity = i == 0 ? b.liquidity + b.pnl : b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
            if (b.liquidity > 0 && equity > 0) {
                totalDynamicEquity += equity;
                dynamicEquities[i] = equity;
            }
        }
        return (totalDynamicEquity, dynamicEquities);
    }

    function _distributePnlToBTokens(int256 pnl, int256 totalDynamicEquity, int256[] memory dynamicEquities) internal {
        if (totalDynamicEquity > 0 && pnl != 0) {
            for (uint256 i = 0; i < _bTokens.length; i++) {
                if (dynamicEquities[i] > 0) {
                    BTokenInfo storage b = _bTokens[i];
                    int256 distributedPnl = (pnl * dynamicEquities[i] / totalDynamicEquity).reformat(_bTokens[0].decimals);
                    b.pnl += distributedPnl;
                    b.cumulativePnl += distributedPnl * ONE / b.liquidity;
                }
            }
        }
    }

    function _updateSymbolPrices(int256 totalDynamicEquity) internal returns (int256) {
        if (totalDynamicEquity <= 0) return 0;
        int256 undistributedPnl;
        for (uint256 i = 0; i < _symbols.length; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 price = IOracle(s.oracleAddress).getPrice().utoi();
            if (s.tradersNetVolume != 0) {
                int256 r = s.tradersNetVolume * price / ONE * price / ONE * s.multiplier / ONE * s.multiplier / ONE * s.fundingRateCoefficient / totalDynamicEquity;
                int256 delta = r * int256(block.number - _lastUpdateBlock);

                undistributedPnl += s.tradersNetVolume * delta / ONE;
                undistributedPnl -= s.tradersNetVolume * (price - s.price) / ONE * s.multiplier / ONE;

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
        for (uint256 i = 0; i < _symbols.length; i++) {
            SymbolInfo storage s = _symbols[i];
            if (s.tradersNetVolume != 0) {
                int256 cost = s.tradersNetVolume * s.price / ONE * s.multiplier / ONE;
                totalDynamicEquity -= cost - s.tradersNetCost;
                totalCost -= cost;
            }
        }
        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost.abs();
    }

    // setting funding fee trader's side
    // this funding fee is already settled to bTokens in `_update`
    function _settleTraderFundingFee(address owner) internal {
        IPToken pToken = IPToken(_pTokenAddress);
        int256 funding;
        IPToken.Position[] memory positions = pToken.getPositions(owner);
        for (uint256 i = 0; i < _symbols.length; i++) {
            IPToken.Position memory p = positions[i];
            if (p.volume != 0) {
                int256 delta;
                unchecked { delta = _symbols[i].cumulativeFundingRate - p.lastCumulativeFundingRate; }
                funding += p.volume * delta / ONE;

                p.lastCumulativeFundingRate = _symbols[i].cumulativeFundingRate;
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
            uint256 amountB0;
            uint256 amountBX;
            for (uint256 i = _bTokens.length - 1; i > 0; i--) {
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

    function _getTraderMarginRatio(address owner) internal view returns (int256) {
        IPToken pToken = IPToken(_pTokenAddress);

        int256[] memory margins = pToken.getMargins(owner);
        int256 totalDynamicEquity = margins[0];
        int256 totalCost;
        for (uint256 i = 1; i < _bTokens.length; i++) {
            totalDynamicEquity += margins[i] * _bTokens[i].price / ONE * _bTokens[i].discount / ONE;
        }

        IPToken.Position[] memory positions = pToken.getPositions(owner);
        for (uint256 i = 0; i < _symbols.length; i++) {
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
