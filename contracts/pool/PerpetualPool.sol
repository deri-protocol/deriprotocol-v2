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
    int256  private _protocolFeeCollectRatio;

    address private _pTokenAddress;
    address private _liquidatorQualifierAddress;
    address private _protocolAddress;

    SymbolInfo[] private _symbols;    // symbolId indexed
    BTokenInfo[] private _bTokens;    // bTokenId indexed

    int256  private _protocolLiquidity;
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
        int256[7] memory parameters_,
        address[4] memory addresses_
    ) public override {
        require(_controller == address(0) && _symbols.length == 0 && _bTokens.length == 0,
                'PerpetualPool.initialize: already initialized');

        _minPoolMarginRatio = parameters_[0];
        _minInitialMarginRatio = parameters_[1];
        _minMaintenanceMarginRatio = parameters_[2];
        _minLiquidationReward = parameters_[3];
        _maxLiquidationReward = parameters_[4];
        _liquidationCutRatio = parameters_[5];
        _protocolFeeCollectRatio = parameters_[6];

        _pTokenAddress = addresses_[0];
        _liquidatorQualifierAddress = addresses_[1];
        _protocolAddress = addresses_[2];
        _controller = addresses_[3];
    }

    function getParameters() public override view returns (
        int256 minPoolMarginRatio,
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    ) {
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
        address liquidatorQualifierAddress,
        address protocolAddress
    ) {
        pTokenAddress = _pTokenAddress;
        liquidatorQualifierAddress = _liquidatorQualifierAddress;
        protocolAddress = _protocolAddress;
    }

    function getSymbol(uint256 symbolId) public override view returns (SymbolInfo memory) {
        require(symbolId < _symbols.length, 'PerpetualPool.getSymbol: invalid symbolId');
        return _symbols[symbolId];
    }

    function getBToken(uint256 bTokenId) public override view returns (BTokenInfo memory) {
        require(bTokenId < _bTokens.length, 'PerpetualPool.getBToken: invalid bTokenId');
        return _bTokens[bTokenId];
    }

    function setParameters(
        int256 minPoolMarginRatio,
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    ) public override _controller_ {
        _minPoolMarginRatio = minPoolMarginRatio;
        _minInitialMarginRatio = minInitialMarginRatio;
        _minMaintenanceMarginRatio = minMaintenanceMarginRatio;
        _minLiquidationReward = minLiquidationReward;
        _maxLiquidationReward = maxLiquidationReward;
        _liquidationCutRatio = liquidationCutRatio;
        _protocolFeeCollectRatio = protocolFeeCollectRatio;
    }

    function setAddresses(
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address protocolAddress
    ) public override _controller_ {
        _pTokenAddress = pTokenAddress;
        _liquidatorQualifierAddress = liquidatorQualifierAddress;
        _protocolAddress = protocolAddress;
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
        if (_bTokens.length > 0) {
            IERC20(info.bTokenAddress).safeApprove(info.handlerAddress, type(uint256).max);
        }
        _bTokens.push(info);
        IPToken(_pTokenAddress).setNumBTokens(_bTokens.length);
    }


    //================================================================================
    // Pool interactions
    //================================================================================

    function addLiquidity(uint256 bTokenId, uint256 bAmount) public override {
        require(bTokenId < _bTokens.length, 'PerpetualPool.addLiquidity: invalid bTokenId');
        _updateBTokenStatus();
        _addLiquidity(msg.sender, bTokenId, bAmount);
    }

    function removeLiquidity(uint256 bTokenId, uint256 lShares) public override {
        require(bTokenId < _bTokens.length, 'PerpetualPool.removeLiquidity: invalid bTokenId');
        _updateBTokenStatus();
        _coverBTokenDebt(bTokenId);
        _removeLiquidity(msg.sender, bTokenId, lShares);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public override {
        require(bTokenId < _bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        _addMargin(msg.sender, bTokenId, bAmount);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public override {
        address account = msg.sender;
        require(bTokenId < _bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        require(IPToken(_pTokenAddress).exists(account), 'PerpetualPool.removeMargin: trader not exist');
        _updateBTokenStatus();
        _settleTraderFundingFee(account);
        _coverTraderDebt(account);
        _removeMargin(account, bTokenId, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public override {
        address account = msg.sender;
        require(symbolId < _symbols.length, 'PerpetualPool.trade: invalid symbolId');
        require(IPToken(_pTokenAddress).exists(account), 'PerpetualPool.trade: add margin before trade');
        _updateBTokenStatus();
        _settleTraderFundingFee(account);
        _trade(account, symbolId, tradeVolume);
    }

    function liquidate(address account) public override {
        require(_liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(msg.sender),
                'PerpetualPool.liquidate: not qualified liquidator');
        require(IPToken(_pTokenAddress).exists(account), 'PerpetualPool.liquidate: trader not exist');
        _updateBTokenStatus();
        _settleTraderFundingFee(account);
        require(_getTraderMarginRatio(account) < _minMaintenanceMarginRatio, 'PerpetualPool.liquidate: cannot liquidate');
        _liquidate(account);
    }


    //================================================================================
    // Pool core logics
    //================================================================================

    function _addLiquidity(address account, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, account, address(this), bAmount);

        // gas saving
        address lTokenAddress = b.lTokenAddress;
        int256 price = b.price;

        uint256 totalDynamicEquity = (b.liquidity * price / ONE + b.pnl).itou();
        uint256 totalSupply = ILToken(lTokenAddress).totalSupply();
        uint256 lShares = totalDynamicEquity == 0 ? bAmount : bAmount * price.itou() / UONE * totalSupply / totalDynamicEquity;

        ILToken(lTokenAddress).mint(account, lShares);
        b.liquidity += bAmount.utoi();

        emit AddLiquidity(account, bTokenId, lShares, bAmount);
    }

    function _removeLiquidity(address account, uint256 bTokenId, uint256 lShares) internal _lock_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        int256 pnl = b.pnl;
        address lTokenAddress = b.lTokenAddress;
        require(pnl >= 0, 'PerpetualPool.removeLiquidity: negative bToken pnl');
        require(lShares > 0 && lShares <= ILToken(lTokenAddress).balanceOf(account),
                'PerpetualPool.removeLiquidity: invalid lShares');

        uint256 amount1;
        uint256 amount2;
        uint256 totalSupply = ILToken(lTokenAddress).totalSupply();
        amount1 = lShares * b.liquidity.itou() / totalSupply;
        amount2 = lShares * pnl.itou() / totalSupply;
        amount1 = amount1.reformat(b.decimals);
        amount2 = amount2.reformat(_bTokens[0].decimals);

        b.liquidity -= amount1.utoi();
        b.pnl -= amount2.utoi();

        int256 marginRatio = _getPoolMarginRatio();
        require(marginRatio >= _minPoolMarginRatio, 'PerpetualPool.removeLiquidity: pool insufficient liquidity');

        ILToken(lTokenAddress).burn(account, lShares);
        if (bTokenId == 0) {
            address bTokenAddress = b.bTokenAddress;
            uint256 amount = (amount1 + amount2).rescale(18, b.decimals);
            uint256 balance = IERC20(bTokenAddress).balanceOf(address(this));
            if (amount > balance) amount = balance;
            if (amount > 0) IERC20(bTokenAddress).safeTransfer(account, amount);
        } else {
            if (amount1 != 0) {
                address bTokenAddress = b.bTokenAddress;
                amount1 = amount1.rescale(18, b.decimals);
                uint256 balance1 = IERC20(bTokenAddress).balanceOf(address(this));
                if (amount1 > balance1) amount1 = balance1;
                if (amount1 > 0) IERC20(bTokenAddress).safeTransfer(account, amount1);
            }
            if (amount2 != 0) {
                address bTokenAddress = _bTokens[0].bTokenAddress;
                amount2 = amount2.rescale(18, _bTokens[0].decimals);
                uint256 balance2 = IERC20(bTokenAddress).balanceOf(address(this));
                if (amount2 > balance2) amount2 = balance2;
                if (amount2 > 0) IERC20(bTokenAddress).safeTransfer(account, amount2);
            }
        }
        emit RemoveLiquidity(account, bTokenId, lShares, amount1, amount2);
    }

    function _addMargin(address account, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, msg.sender, address(this), bAmount);

        address pTokenAddress = _pTokenAddress;
        if (!IPToken(pTokenAddress).exists(account)) {
            IPToken(pTokenAddress).mint(account, bTokenId, bAmount);
        } else {
            IPToken(pTokenAddress).addMargin(account, bTokenId, bAmount.utoi());
        }

        emit AddMargin(account, bTokenId, bAmount);
    }

    function _removeMargin(address account, uint256 bTokenId, uint256 bAmount) internal _lock_ {
        BTokenInfo storage b = _bTokens[bTokenId];
        bAmount = bAmount.reformat(b.decimals);

        int256 margin = IPToken(_pTokenAddress).getMargin(account, bTokenId);
        require(margin > 0, 'PerpetualPool.removeMargin: insufficient margin');

        if (bAmount > margin.itou()) {
            bAmount = margin.itou();
            margin = 0;
        } else {
            margin -= bAmount.utoi();
        }
        IPToken(_pTokenAddress).updateMargin(account, bTokenId, margin);

        int256 marginRatio = _getTraderMarginRatio(account);
        require(marginRatio >= _minInitialMarginRatio, 'PerpetualPool.removeMargin: insufficient margin');

        IERC20(b.bTokenAddress).safeTransfer(account, bAmount.rescale(18, b.decimals));
        emit RemoveMargin(account, bTokenId, bAmount);
    }

    function _trade(address account, uint256 symbolId, int256 tradeVolume) internal _lock_ {
        tradeVolume = tradeVolume.reformat(0);
        SymbolInfo storage s = _symbols[symbolId];
        IPToken.Position memory p = IPToken(_pTokenAddress).getPosition(account, symbolId);

        int256 curCost = tradeVolume * s.price / ONE * s.multiplier / ONE;
        int256 fee = curCost.abs() * s.feeRatio / ONE;

        int256 realizedCost;
        int256 volume = p.volume;
        if ((volume >= 0 && tradeVolume >= 0) || (volume <= 0 && tradeVolume <= 0)) {

        } else if (volume.abs() <= tradeVolume.abs()) {
            realizedCost = curCost * volume.abs() / tradeVolume.abs() + p.cost;
        } else {
            realizedCost = p.cost * tradeVolume.abs() / volume.abs() + curCost;
        }

        p.volume += tradeVolume;
        p.cost += curCost - realizedCost;
        p.lastCumuFundingRate = s.cumuFundingRate;
        IPToken(_pTokenAddress).addMargin(account, 0, (-fee - realizedCost).reformat(_bTokens[0].decimals));
        IPToken(_pTokenAddress).updatePosition(account, symbolId, p);

        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += curCost - realizedCost;

        int256 protocolFee = fee * _protocolFeeCollectRatio / ONE;
        _protocolLiquidity += protocolFee;
        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        _distributePnlToBTokens(fee - protocolFee, totalDynamicEquity, dynamicEquities);

        int256 marginRatio;
        marginRatio = _getPoolMarginRatio();
        require(marginRatio >= _minPoolMarginRatio, 'PerpetualPool.trade: pool insufficient liquidity');
        marginRatio = _getTraderMarginRatio(account);
        require(marginRatio >= _minInitialMarginRatio, 'PerpetualPool.trade: insufficient margin');

        emit Trade(account, symbolId, tradeVolume, s.price.itou());
    }

    function _liquidate(address account) internal _lock_ {
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

        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        _distributePnlToBTokens(netEquity - reward, totalDynamicEquity, dynamicEquities);

        IPToken(_pTokenAddress).burn(account);
        IERC20(_bTokens[0].bTokenAddress).safeTransfer(msg.sender, reward.itou().rescale(18, _bTokens[0].decimals));

        emit Liquidate(msg.sender, account);
    }


    //================================================================================
    // Helpers
    //================================================================================

    // update bToken/symbol prices
    // distribute undistributedPnl (funding fee and pnl) on BToken side
    function _updateBTokenStatus() internal {
        if (block.number == _lastUpdateBTokenStatusBlock) return;
        _updateBTokenPrices();
        (int256 totalDynamicEquity, int256[] memory dynamicEquities) = _getBTokenDynamicEquities();
        int256 undistributedPnl = _updateSymbolPrices(totalDynamicEquity);
        _distributePnlToBTokens(undistributedPnl, totalDynamicEquity, dynamicEquities);
        _lastUpdateBTokenStatusBlock = block.number;
    }

    // settle trader's funding fee against trader's margin
    // this funding fee is already settled to bTokens in _updateBTokenStatus
    function _settleTraderFundingFee(address account) internal {
        int256 unsettledPnl;
        for (uint256 i = 0; i < _symbols.length; i++) {
            int256 cumuFundingRate = _symbols[i].cumuFundingRate;
            IPToken.Position memory p = IPToken(_pTokenAddress).getPosition(account, i);
            if (p.volume != 0) {
                int256 delta;
                unchecked { delta = cumuFundingRate - p.lastCumuFundingRate; }
                unsettledPnl -= p.volume * delta / ONE;

                p.lastCumuFundingRate = cumuFundingRate;
                IPToken(_pTokenAddress).updatePosition(account, i, p);
            }
        }
        if (unsettledPnl != 0) {
            IPToken(_pTokenAddress).addMargin(account, 0, unsettledPnl.reformat(_bTokens[0].decimals));
        }
    }

    function _updateBTokenPrices() internal {
        for (uint256 i = 1; i < _bTokens.length; i++) {
            _bTokens[i].price = IBTokenHandler(_bTokens[i].handlerAddress).getPrice().utoi();
        }
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

    function _distributePnlToBTokens(int256 pnl, int256 totalDynamicEquity, int256[] memory dynamicEquities) internal {
        uint256 decimals = _bTokens[0].decimals;
        if (totalDynamicEquity > 0 && pnl != 0) {
            for (uint256 i = 0; i < _bTokens.length; i++) {
                _bTokens[i].pnl += (pnl * dynamicEquities[i] / totalDynamicEquity).reformat(decimals);
            }
        }
    }

    function _updateSymbolPrices(int256 totalDynamicEquity) internal returns (int256) {
        int256 undistributedPnl;
        for (uint256 i = 0; i < _symbols.length; i++) {
            SymbolInfo storage s = _symbols[i];
            int256 price = ISymbolHandler(s.handlerAddress).getPrice().utoi();
            // gas saving
            int256 multiplier = s.multiplier;
            int256 tradersNetVolume = s.tradersNetVolume;

            int256 r = totalDynamicEquity != 0
                ? tradersNetVolume * price / ONE * price / ONE * multiplier / ONE * multiplier / ONE * s.fundingRateCoefficient / totalDynamicEquity
                : int256(0);
            int256 delta = r * int256(block.number - _lastUpdateBTokenStatusBlock);
            int256 funding = tradersNetVolume * delta / ONE;
            undistributedPnl += funding;

            int256 pnl = tradersNetVolume * (price - s.price) / ONE * multiplier / ONE;
            undistributedPnl -= pnl;

            s.price = price;
        }
        return undistributedPnl;
    }

    function _coverBTokenDebt(uint256 bTokenId) internal {
        BTokenInfo storage b = _bTokens[bTokenId];
        int256 pnl = b.pnl;
        if (pnl < 0) {
            if (bTokenId == 0) {
                b.liquidity += pnl;
                b.pnl = 0;
            } else {
                int256 liquidity = b.liquidity;
                int256 amount = (liquidity * b.price / ONE / 100).reformat(_bTokens[0].decimals);
                if (amount < -pnl) amount = -pnl;
                (uint256 amount1, uint256 amount2) = IBTokenHandler(b.handlerAddress).swap(liquidity.itou(), amount.itou());
                b.liquidity -= amount1.utoi();
                b.pnl += amount2.utoi();
            }
        }
    }

    function _coverTraderDebt(address account) internal {
        int256[] memory margins = IPToken(_pTokenAddress).getMargins(account);
        if (margins[0] >= 0) return;
        for (uint256 i = _bTokens.length - 1; i > 0; i--) {
            if (margins[i] > 0) {
                uint256 amount1;
                uint256 amount2;
                if (margins[i] * _bTokens[i].price / ONE >= (-margins[0]) * 2) {
                    (amount1, amount2) = IBTokenHandler(_bTokens[i].handlerAddress).swap(margins[i].itou(), (-margins[0]).itou());
                } else {
                    (amount1, amount2) = IBTokenHandler(_bTokens[i].handlerAddress).swap(margins[i].itou(), type(uint256).max);
                }
                margins[i] -= amount1.utoi();
                margins[0] += amount2.utoi();

                if (margins[0] >= 0) break;
            }
        }
        IPToken(_pTokenAddress).updateMargins(account, margins);
    }

    function _getPoolMarginRatio() internal view returns (int256) {
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

        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost.abs();
    }

    function _getTraderMarginRatio(address account) internal view returns (int256) {
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

        return totalCost == 0 ? type(int256).max : totalDynamicEquity * ONE / totalCost.abs();
    }

    function _deflationCompatibleSafeTransferFrom(address bTokenAddress, uint256 decimals, address from, address to, uint256 bAmount)
        internal returns (uint256)
    {
        uint256 preBalance = IERC20(bTokenAddress).balanceOf(to);
        IERC20(bTokenAddress).safeTransferFrom(from, to, bAmount.rescale(18, decimals));
        uint256 curBalance = IERC20(bTokenAddress).balanceOf(to);

        uint256 actualReceivedAmount = (curBalance - preBalance).rescale(decimals, 18);
        return actualReceivedAmount;
    }

}
