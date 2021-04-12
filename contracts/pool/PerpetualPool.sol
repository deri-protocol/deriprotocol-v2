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
import './MigratablePool.sol';

contract PerpetualPool is IPerpetualPool, MigratablePool {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256  constant ONE  = 10**18;
    uint256 constant UONE = 10**18;

    int256  private _minPoolMarginRatio;

    int256  private _minInitialMarginRatio;

    int256  private _minMaintenanceMarginRatio;

    int256  private _minLiquidationReward;

    int256  private _maxLiquidationReward;

    int256  private _liquidationCutRatio;

    int256  private _daoFeeCollectRatio;

    address private _pTokenAddress;

    address private _liquidatorQualifierAddress;

    address private _daoAddress;

    SymbolInfo[] private _symbols;    // symbolId indexed

    BTokenInfo[] private _bTokens;    // bTokenId indexed

    int256  private _daoLiquidity;

    uint256 private _lastUpdateBTokenStatusBlock;

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

    //================================================================================
    // Migration logics
    //================================================================================

    // In migration process, this function is to be called from source pool
    function approveMigration() public override _controller_ {
        require(_migrationTimestamp != 0 && block.timestamp >= _migrationTimestamp, 'PerpetualPool.approveMigration: timestamp not met yet');
        // approve new pool to pull all base tokens from this pool
        // set pToken/lToken to new pool, after redirecting pToken/lToken to new pool, this pool will stop functioning
        for (uint256 i = 0; i < _bTokens.length; i++) {
            IERC20(_bTokens[i].bTokenAddress).safeApprove(_migrationDestination, type(uint256).max);
            ILToken(_bTokens[i].lTokenAddress).setPool(_migrationDestination);
        }
        IPToken(_pTokenAddress).setPool(_migrationDestination);
    }

    // In migration process, this function is to be called from target pool
    function executeMigration(address source) public override _controller_ {
        // uint256 migrationTimestamp = IPerpetualPool(source).migrationTimestamp();
        // address migrationDestination = IPerpetualPool(source).migrationDestination();
        // require(migrationTimestamp != 0 && block.timestamp >= migrationTimestamp, 'PerpetualPool.executeMigration: timestamp not met yet');
        // require(migrationDestination == address(this), 'PerpetualPool.executeMigration: not to destination pool');

        // // copy state values for each symbol
        // IPerpetualPool.SymbolInfo[] memory sourceSymbols = IPerpetualPool(source).symbols();
        // for (uint256 i = 0; i < sourceSymbols.length; i++) {
        //     require(keccak256(bytes(_symbols[i].symbol)) == keccak256(bytes(sourceSymbols[i].symbol)), 'PerpetualPool.executeMigration: symbol not match');
        //     _symbols[i].cumuFundingRate = sourceSymbols[i].cumuFundingRate;
        //     _symbols[i].tradersNetVolume = sourceSymbols[i].tradersNetVolume;
        //     _symbols[i].tradersNetCost = sourceSymbols[i].tradersNetCost;
        // }

        // // copy state values for each bToken, and transfer bToken to this new pool
        // IPerpetualPool.BTokenInfo[] memory sourceBTokens = IPerpetualPool(source).bTokens();
        // for (uint256 i = 0; i < sourceBTokens.length; i++) {
        //     require(_bTokens[i].bTokenAddress == sourceBTokens[i].bTokenAddress && _bTokens[i].lTokenAddress == sourceBTokens[i].lTokenAddress,
        //             'PerpetualPool.executeMigration: bToken not match');
        //     _bTokens[i].liquidity = sourceBTokens[i].liquidity;
        //     _bTokens[i].pnl = sourceBTokens[i].pnl;

        //     IERC20(sourceBTokens[i].bTokenAddress).safeTransferFrom(source, address(this), IERC20(sourceBTokens[i].bTokenAddress).balanceOf(source));
        // }

        // emit ExecuteMigration(migrationTimestamp, source, address(this));
    }


    //================================================================================
    // Interactions
    //================================================================================

    function initialize(
        int256[] calldata parameters_,
        address[] calldata addresses_
    ) public override {
        require(_controller == address(0) && _symbols.length == 0 && _bTokens.length == 0,
                'PerpetualPool.initialize: already initialized');

        _minPoolMarginRatio = parameters_[0];
        _minInitialMarginRatio = parameters_[1];
        _minMaintenanceMarginRatio = parameters_[2];
        _minLiquidationReward = parameters_[3];
        _maxLiquidationReward = parameters_[4];
        _liquidationCutRatio = parameters_[5];
        _daoFeeCollectRatio = parameters_[6];

        _pTokenAddress = addresses_[0];
        _liquidatorQualifierAddress = addresses_[1];
        _daoAddress = addresses_[2];
        _controller = addresses_[3];
    }

    function parameters() public override view returns (
        int256 minPoolMarginRatio,
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 daoFeeCollectRatio
    ) {
        minPoolMarginRatio = _minPoolMarginRatio;
        minInitialMarginRatio = _minInitialMarginRatio;
        minMaintenanceMarginRatio = _minMaintenanceMarginRatio;
        minLiquidationReward = _minLiquidationReward;
        maxLiquidationReward = _maxLiquidationReward;
        liquidationCutRatio = _liquidationCutRatio;
        daoFeeCollectRatio = _daoFeeCollectRatio;
    }

    function addresses() public override view returns (
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address daoAddress
    ) {
        pTokenAddress = _pTokenAddress;
        liquidatorQualifierAddress = _liquidatorQualifierAddress;
        daoAddress = _daoAddress;
    }

    function symbols() public override view returns (SymbolInfo[] memory) {
        return _symbols;
    }

    function bTokens() public override view returns (BTokenInfo[] memory) {
        return _bTokens;
    }

    function setParameters(
        int256 minPoolMarginRatio,
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 daoFeeCollectRatio
    ) public override _controller_ {
        _minPoolMarginRatio = minPoolMarginRatio;
        _minInitialMarginRatio = minInitialMarginRatio;
        _minMaintenanceMarginRatio = minMaintenanceMarginRatio;
        _minLiquidationReward = minLiquidationReward;
        _maxLiquidationReward = maxLiquidationReward;
        _liquidationCutRatio = liquidationCutRatio;
        _daoFeeCollectRatio = daoFeeCollectRatio;
    }

    function setAddresses(
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address daoAddress
    ) public override _controller_ {
        _pTokenAddress = pTokenAddress;
        _liquidatorQualifierAddress = liquidatorQualifierAddress;
        _daoAddress = daoAddress;
    }

    function setSymbolParameters(uint256 symbolId, address handlerAddress, int256 feeRatio, int256 fundingRateCoefficient) public override _controller_ {
        require(symbolId < _symbols.length, 'PerpetualPool.setSymbolParameters: invalid symbolId');
        SymbolInfo storage s = _symbols[symbolId];
        s.handlerAddress = handlerAddress;
        s.feeRatio = feeRatio;
        s.fundingRateCoefficient = fundingRateCoefficient;
    }

    function setBTokenParameters(uint256 bTokenId, address handlerAddress, int256 discount) public override _controller_ {
        require(bTokenId < _bTokens.length, 'PerpetualPool.setBTokenParameters: invalid bTokenId');
        BTokenInfo storage b = _bTokens[bTokenId];
        b.handlerAddress = handlerAddress;
        b.discount = discount;
    }

    function addSymbol(SymbolInfo memory info) public override _controller_ {
        require(info.price == 0 && info.cumuFundingRate == 0 && info.tradersNetVolume == 0 && info.tradersNetCost == 0,
                'PerpetualPool.addSymbol: invalid symbol');
        _symbols.push(info);
        IPToken(_pTokenAddress).setNumSymbols(_symbols.length);
    }

    function addBToken(BTokenInfo memory info) public override _controller_ {
        require(info.price == 0 && info.liquidity == 0 && info.pnl == 0,
                'PerpetualPool.addBToken: invalid bToken');
        if (_bTokens.length == 0) {
            info.price = 10**18;
            info.handlerAddress = address(0);
        } else {
            IERC20(info.bTokenAddress).safeApprove(info.handlerAddress, type(uint256).max);
        }
        _bTokens.push(info);
        IPToken(_pTokenAddress).setNumBTokens(_bTokens.length);
    }


    //================================================================================
    // Pool interactions
    //================================================================================
    function addLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        _addLiquidity(bTokenId, bAmount);
    }

    function removeLiquidity(uint256 bTokenId, uint256 lShares) public override {
        _removeLiquidity(bTokenId, lShares);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public override {
        _addMargin(bTokenId, bAmount);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public override {
        _removeMargin(bTokenId, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public override {
        _trade(symbolId, tradeVolume);
    }

    function liquidate(address account) public override {
        require(_liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(msg.sender),
                'PerpetualPool.liquidate: not qualified liquidator');
        _liquidate(account);
    }


    //================================================================================
    // Pool core logics
    //================================================================================

    function _addLiquidity(uint256 bTokenId, uint256 bAmount) internal _lock_ {
        require(bTokenId < _bTokens.length, 'PerpetualPool.addLiquidity: invalid bTokenId');
        _updateBTokenStatus();

        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, msg.sender, address(this), bAmount);

        uint256 totalDynamicEquity = (b.liquidity * b.price / ONE * b.discount / ONE + b.pnl).itou();
        uint256 totalSupply = ILToken(b.lTokenAddress).totalSupply();
        uint256 lShares = totalDynamicEquity == 0 ? bAmount : bAmount * (b.price * b.discount / ONE).itou() / UONE * totalSupply / totalDynamicEquity;

        ILToken(b.lTokenAddress).mint(msg.sender, lShares);
        b.liquidity += bAmount.utoi();

        emit AddLiquidity(msg.sender, bTokenId, lShares, bAmount);
    }

    function _removeLiquidity(uint256 bTokenId, uint256 lShares) internal _lock_ {
        require(bTokenId < _bTokens.length, 'PerpetualPool.removeLiquidity: invalid bTokenId');
        _updateBTokenStatus();
        _coverBTokenDebt(bTokenId);

        BTokenInfo storage b = _bTokens[bTokenId];
        require(b.pnl >= 0, 'PerpetualPool.removeLiquidity: negative bToken pnl');
        require(lShares > 0 && lShares <= ILToken(b.lTokenAddress).balanceOf(msg.sender),
                'PerpetualPool.removeLiquidity: invalid lShares');

        uint256 amount1;
        uint256 amount2;
        uint256 totalSupply = ILToken(b.lTokenAddress).totalSupply();
        amount1 = lShares * b.liquidity.itou() / totalSupply;
        amount2 = lShares * b.pnl.itou() / totalSupply;
        amount1 = amount1.reformat(b.decimals);
        amount2 = amount2.reformat(_bTokens[0].decimals);

        b.liquidity -= amount1.utoi();
        b.pnl -= amount2.utoi();

        (int256 dynamicEquity, int256 cost) = _getPoolDynamicEquityAndCost();
        require(cost == 0 || dynamicEquity * ONE / cost.abs() >= _minPoolMarginRatio, 'PerpetualPool.removeLiquidity: pool insufficient liquidity');

        ILToken(b.lTokenAddress).burn(msg.sender, lShares);
        if (bTokenId == 0) {
            IERC20(b.bTokenAddress).safeTransfer(msg.sender, (amount1 + amount2).rescale(18, b.decimals));
        } else {
            if (amount1 != 0) IERC20(b.bTokenAddress).safeTransfer(msg.sender, amount1.rescale(18, b.decimals));
            if (amount2 != 0) IERC20(_bTokens[0].bTokenAddress).safeTransfer(msg.sender, amount2.rescale(18, _bTokens[0].decimals));
        }

        emit RemoveLiquidity(msg.sender, bTokenId, lShares, amount1, amount2);
    }

    function _addMargin(uint256 bTokenId, uint256 bAmount) internal _lock_ {
        require(bTokenId < _bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        // _updateBTokenStatus();

        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, msg.sender, address(this), bAmount);

        if (!IPToken(_pTokenAddress).exists(msg.sender)) {
            IPToken(_pTokenAddress).mint(msg.sender, bTokenId, bAmount);
        } else {
            IPToken(_pTokenAddress).addMargin(msg.sender, bTokenId, bAmount.utoi());
        }

        emit AddMargin(msg.sender, bTokenId, bAmount);
    }

    function _removeMargin(uint256 bTokenId, uint256 bAmount) internal _lock_ {
        require(bTokenId < _bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        _updateBTokenStatus();
        _updateTraderStatus(msg.sender);
        _coverTraderDebt(msg.sender);

        BTokenInfo storage b = _bTokens[bTokenId];

        bAmount = bAmount.reformat(b.decimals);

        int256 margin = IPToken(_pTokenAddress).getMargin(msg.sender, bTokenId);
        require(margin > 0, 'PerpetualPool.removeMargin: insufficient margin');

        if (bAmount > margin.itou()) {
            bAmount = margin.itou();
            margin = 0;
        } else {
            margin -= bAmount.utoi();
        }
        IPToken(_pTokenAddress).updateMargin(msg.sender, bTokenId, margin);

        (int256 dynamicEquity, int256 cost) = _getTraderDynamicEquityAndCost(msg.sender);
        require(cost == 0 || dynamicEquity * ONE / cost.abs() >= _minInitialMarginRatio, 'PerpetualPool.removeMargin: insufficient margin');

        IERC20(b.bTokenAddress).safeTransfer(msg.sender, bAmount.rescale(18, b.decimals));
        emit RemoveMargin(msg.sender, bTokenId, bAmount);
    }

    function _trade(uint256 symbolId, int256 tradeVolume) internal _lock_ {
        require(symbolId < _symbols.length, 'PerpetualPool.trade: invalid symbolId');
        _updateBTokenStatus();
        _updateTraderStatus(msg.sender);

        tradeVolume = tradeVolume.reformat(0);

        SymbolInfo storage s = _symbols[symbolId];
        IPToken.Position memory p = IPToken(_pTokenAddress).getPosition(msg.sender, symbolId);

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
        p.lastCumuFundingRate = s.cumuFundingRate;
        IPToken(_pTokenAddress).addMargin(msg.sender, 0, (-fee - realizedCost).reformat(_bTokens[0].decimals));
        IPToken(_pTokenAddress).updatePosition(msg.sender, symbolId, p);

        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += curCost - realizedCost;

        int256 daoFee = fee * _daoFeeCollectRatio / ONE;
        _daoLiquidity += daoFee;
        _distributePnlToBTokens(fee - daoFee);
        // _distributePnlToBTokens(fee);

        int256 dynamicEquity;
        int256 cost;
        (dynamicEquity, cost) = _getPoolDynamicEquityAndCost();
        require(cost == 0 || dynamicEquity * ONE / cost.abs() >= _minPoolMarginRatio, 'PerpetualPool.trade: pool insufficient liquidity');
        (dynamicEquity, cost) = _getTraderDynamicEquityAndCost(msg.sender);
        require(cost == 0 || dynamicEquity * ONE / cost.abs() >= _minInitialMarginRatio, 'PerpetualPool.trade: insufficient margin');

        emit Trade(msg.sender, symbolId, tradeVolume, s.price.itou());
    }

    function _liquidate(address account) internal _lock_ {
        _updateBTokenStatus();
        _updateTraderStatus(account);

        (int256 dynamicEquity, int256 cost) = _getTraderDynamicEquityAndCost(account);
        require(cost != 0 && dynamicEquity * ONE / cost.abs() < _minMaintenanceMarginRatio, 'PerpetualPool.liquidate: cannot liquidate');

        int256 pnl;
        IPToken.Position[] memory positions = IPToken(_pTokenAddress).getPositions(account);
        for (uint256 i = 0; i < _symbols.length; i++) {
            if (positions[i].volume != 0) {
                _symbols[i].tradersNetVolume -= positions[i].volume;
                _symbols[i].tradersNetCost -= positions[i].cost;
                pnl += positions[i].volume * _symbols[i].price / ONE * _symbols[i].multiplier / ONE - positions[i].cost;
            }
        }

        int256[] memory margins = IPToken(_pTokenAddress).getMargins(account);
        int256 equity = margins[0];
        for (uint256 i = 1; i < _bTokens.length; i++) {
            if (margins[i] != 0) {
                (, uint256 amount2) = IBTokenHandler(_bTokens[i].handlerAddress).swap(margins[i].itou(), type(uint256).max);
                equity += amount2.utoi();
            }
        }

        int256 netEquity = pnl + equity;
        int256 reward;
        if (netEquity <= _minLiquidationReward) {
            reward = _minLiquidationReward;
        } else if (netEquity >= _maxLiquidationReward) {
            reward = _maxLiquidationReward;
        } else {
            reward = (netEquity - _minLiquidationReward) * _liquidationCutRatio / ONE + _minLiquidationReward;
            reward = reward.reformat(_bTokens[0].decimals);
        }

        _distributePnlToBTokens(netEquity - reward);

        IPToken(_pTokenAddress).burn(account);
        IERC20(_bTokens[0].bTokenAddress).safeTransfer(msg.sender, reward.itou().rescale(18, _bTokens[0].decimals));

        emit Liquidate(msg.sender, account);
    }


    //================================================================================
    // Helpers
    //================================================================================

    function _updateBTokenStatus() internal {
        if (block.number == _lastUpdateBTokenStatusBlock) return;

        int256 totalDynamicEquity;
        int256[] memory dynamicEquities = new int256[](_bTokens.length);
        for (uint256 i = 0; i < _bTokens.length; i++) {
            BTokenInfo storage b = _bTokens[i];
            if (i != 0) b.price = IBTokenHandler(b.handlerAddress).getPrice().utoi();
            int256 dynamicEquity = b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
            dynamicEquities[i] = dynamicEquity;
            totalDynamicEquity += dynamicEquity;
        }

        int256 undistributedPnl;
        for (uint256 i = 0; i < _symbols.length; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 price = ISymbolHandler(s.handlerAddress).getPrice().utoi();

            int256 r = totalDynamicEquity != 0
                ? s.tradersNetVolume * price / ONE * price / ONE * s.multiplier / ONE * s.multiplier / ONE * s.fundingRateCoefficient / totalDynamicEquity
                : int256(0);
            int256 delta = r * int256(block.number - _lastUpdateBTokenStatusBlock);
            int256 funding = s.tradersNetVolume * delta / ONE;
            undistributedPnl += funding;
            unchecked { s.cumuFundingRate += delta; }

            int256 pnl = s.tradersNetVolume * (price - s.price) / ONE * s.multiplier / ONE;
            undistributedPnl -= pnl;
            s.price = price;
        }

        if (totalDynamicEquity != 0 && undistributedPnl != 0) {
            for (uint256 i = 0; i < _bTokens.length; i++) {
                _bTokens[i].pnl += (undistributedPnl * dynamicEquities[i] / totalDynamicEquity).reformat(_bTokens[i].decimals);
            }
        }

        _lastUpdateBTokenStatusBlock = block.number;
    }

    function _updateTraderStatus(address account) internal {
        int256 unsettledPnl;
        IPToken.Position[] memory positions = IPToken(_pTokenAddress).getPositions(account);
        for (uint256 i = 0; i < _symbols.length; i++) {
            if (positions[i].volume != 0) {
                int256 delta;
                unchecked { delta = _symbols[i].cumuFundingRate - positions[i].lastCumuFundingRate; }
                unsettledPnl -= positions[i].volume * delta / ONE;

                positions[i].lastCumuFundingRate = _symbols[i].cumuFundingRate;
                IPToken(_pTokenAddress).updatePosition(account, i, positions[i]);
            }
        }
        if (unsettledPnl != 0) IPToken(_pTokenAddress).addMargin(account, 0, unsettledPnl.reformat(_bTokens[0].decimals));
    }

    function _getBTokenDynamicEquities() internal view returns (int256, int256[] memory) {
        int256 totalDynamicEquity;
        int256[] memory dynamicEquities = new int256[](_bTokens.length);
        for (uint256 i = 0; i < _bTokens.length; i++) {
            BTokenInfo storage b = _bTokens[i];
            int256 dynamicEquity = b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
            totalDynamicEquity += dynamicEquity;
            dynamicEquities[i] = dynamicEquity;
        }
        return (totalDynamicEquity, dynamicEquities);
    }

    function _distributePnlToBTokens(int256 pnl) internal {
        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        if (totalDynamicEquity != 0 && pnl != 0) {
            for (uint256 i = 0; i < _bTokens.length; i++) {
                _bTokens[i].pnl += (pnl * dynamicEquities[i] / totalDynamicEquity).reformat(_bTokens[i].decimals);
            }
        }
    }

    function _getPoolDynamicEquityAndCost() internal view returns (int256, int256) {
        int256 totalDynamicEquity;
        int256 totalCost;

        for (uint256 i = 0; i < _bTokens.length; i++) {
            BTokenInfo storage b = _bTokens[i];
            totalDynamicEquity += b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
        }

        for (uint256 i = 0; i < _symbols.length; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 cost = s.tradersNetVolume * s.price / ONE * s.multiplier / ONE; // trader's cost
            totalDynamicEquity -= cost - s.tradersNetCost;
            totalCost -= cost; // trader's cost so it is negative for pool
        }

        return (totalDynamicEquity, totalCost);
    }

    function _getTraderDynamicEquityAndCost(address account) internal view returns (int256, int256) {
        int256 totalDynamicEquity;
        int256 totalCost;

        int256[] memory margins = IPToken(_pTokenAddress).getMargins(account);
        for (uint256 i = 0; i < _bTokens.length; i++) {
            if (margins[i] != 0) {
                totalDynamicEquity += margins[i] * _bTokens[i].price / ONE * _bTokens[i].discount / ONE;
            }
        }

        IPToken.Position[] memory positions = IPToken(_pTokenAddress).getPositions(account);
        for (uint256 i = 0; i < _symbols.length; i++) {
            if (positions[i].volume != 0) {
                int256 cost = positions[i].volume * _symbols[i].price / ONE * _symbols[i].multiplier / ONE;
                totalDynamicEquity += cost - positions[i].cost;
                totalCost += cost;
            }
        }

        return (totalDynamicEquity, totalCost);
    }

    function _coverBTokenDebt(uint256 bTokenId) internal {
        BTokenInfo storage b = _bTokens[bTokenId];
        if (b.pnl < 0) {
            uint256 amount1;
            uint256 amount2;
            if (bTokenId != 0) {
                (amount1, amount2) = IBTokenHandler(b.handlerAddress).swap(b.liquidity.itou(), (-b.pnl).itou());
            } else {
                amount1 = (-b.pnl).itou();
                amount2 = amount1;
            }
            b.liquidity -= amount1.utoi();
            b.pnl += amount2.utoi();
        }
    }

    function _coverTraderDebt(address account) internal {
        int256[] memory margins = IPToken(_pTokenAddress).getMargins(account);
        if (margins[0] >= 0) return;
        for (uint256 i = _bTokens.length - 1; i > 0; i--) {
            if (margins[i] > 0) {
                (uint256 amount1, uint256 amount2) = IBTokenHandler(_bTokens[i].handlerAddress).swap(margins[i].itou(), (-margins[0]).itou());
                margins[i] -= amount1.utoi();
                margins[0] += amount2.utoi();
            }
            if (margins[0] >= 0) break;
        }
        IPToken(_pTokenAddress).updateMargins(account, margins);
    }

    function _deflationCompatibleSafeTransferFrom(address bTokenAddress, uint256 decimals, address from, address to, uint256 bAmount) internal returns (uint256) {
        uint256 preBalance = IERC20(bTokenAddress).balanceOf(to);
        IERC20(bTokenAddress).safeTransferFrom(from, to, bAmount.rescale(18, decimals));
        uint256 curBalance = IERC20(bTokenAddress).balanceOf(to);

        uint256 actualReceivedAmount = (curBalance - preBalance).rescale(decimals, 18);
        return actualReceivedAmount;
    }

}
