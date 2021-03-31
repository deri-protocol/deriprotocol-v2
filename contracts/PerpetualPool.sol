// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './interface/IERC20.sol';
import './interface/IBTokenHandler.sol';
import './interface/ISymbolHandler.sol';
import './interface/IPToken.sol';
import './interface/ILToken.sol';
import './interface/IPerpetualPool.sol';
import './SafeMath.sol';
import './SafeERC20.sol';
import './MigratablePool.sol';

contract PerpetualPool is MigratablePool {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    event AddLiquidity(address indexed account, uint256 indexed bTokenId, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed account, uint256 indexed bTokenId, uint256 lShares, uint256 amount1, uint256 amount2);

    event AddMargin(address indexed account, uint256 indexed bTokenId, uint256 bAmount);

    event RemoveMargin(address indexed account, uint256 indexed bTokenId, uint256 bAmount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, uint256 price);

    event Liquidate(address indexed account);

    struct SymbolInfo {
        string  symbol;
        address handlerAddress;
        int256  multiplier;
        int256  feeRatio;
        int256  fundingRateCoefficient;
        int256  price;
        int256  cumuFundingRate;
        int256  tradersNetVolume;
        int256  tradersNetCost;
    }

    struct BTokenInfo {
        address bTokenAddress;
        address lTokenAddress;
        address handlerAddress;
        uint256 decimals;
        int256  discount;
        int256  price;
        int256  liquidity;
        int256  pnl;
    }

    int256  constant ONE  = 10**18;
    uint256 constant UONE = 10**18;

    address public pTokenAddress;

    int256  public minPoolMarginRatio;

    int256  public minInitialMarginRatio;

    int256  public minMaintenanceMarginRatio;

    int256  public minLiquidationReward;

    int256  public maxLiquidationReward;

    int256  public liquidationCutRatio;

    SymbolInfo[] public symbols;    // symbolId indexed

    BTokenInfo[] public bTokens;    // bTokenId indexed

    uint256 lastUpdateBTokenStatusBlock;

    bool private _mutex;

    modifier _lock_() {
        require(!_mutex, 'PerpetualPool: reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    constructor () {
        controller = msg.sender;
    }

    function initialize(
        SymbolInfo[] calldata _symbols,
        BTokenInfo[] calldata _bTokens,
        int256[] calldata _parameters,
        address _pTokenAddress,
        address _controller
    ) public {
        require(controller == address(0) && symbols.length == 0 && bTokens.length == 0 && pTokenAddress == address(0),
                'PerpetualPool.initialize: already initialized');

        for (uint256 i = 0; i < _symbols.length; i++) {
            require(_symbols[i].price == 0 && _symbols[i].cumuFundingRate == 0 && _symbols[i].tradersNetVolume == 0 && _symbols[i].tradersNetCost == 0,
                    'PerpetualPool.initialize: invalid initial symbols');
            symbols.push(_symbols[i]);
        }

        for (uint256 i = 0; i < _bTokens.length; i++) {
            require(_bTokens[i].price == 0 && _bTokens[i].liquidity == 0 && _bTokens[i].pnl == 0,
                    'PerpetualPool.initialize: invalid initial bTokens');
            bTokens.push(_bTokens[i]);
        }

        minPoolMarginRatio = _parameters[0];
        minInitialMarginRatio = _parameters[1];
        minMaintenanceMarginRatio = _parameters[2];
        minLiquidationReward = _parameters[3];
        maxLiquidationReward = _parameters[4];
        liquidationCutRatio = _parameters[5];
        pTokenAddress = _pTokenAddress;
        controller = _controller;

        for (uint256 i = 0; i < bTokens.length; i++) {
            IERC20(bTokens[i].bTokenAddress).safeApprove(bTokens[i].handlerAddress, type(uint256).max);
        }
    }


    //================================================================================
    // Migration logics
    //================================================================================

    // In migration process, this function is to be called from source pool
    function approveMigration() public override _controller_ {
        require(migrationTimestamp != 0 && block.timestamp >= migrationTimestamp, 'PerpetualPool.approveMigration: timestamp not met yet');
        // approve new pool to pull all base tokens from this pool
        for (uint256 i = 0; i < bTokens.length; i++) {
            IERC20(bTokens[i].bTokenAddress).safeApprove(migrationDestination, type(uint256).max);
        }
        // set pToken/lToken to new pool, after redirecting pToken/lToken to new pool, this pool will stop functioning
        IPToken(pTokenAddress).setPool(migrationDestination);
        for (uint256 i = 0; i < bTokens.length; i++) {
            ILToken(bTokens[i].lTokenAddress).setPool(migrationDestination);
        }
    }

    // In migration process, this function is to be called from target pool
    function executeMigration(address source) public override _controller_ {
        uint256 migrationTimestamp = IPerpetualPool(source).migrationTimestamp();
        address migrationDestination = IPerpetualPool(source).migrationDestination();
        require(migrationTimestamp != 0 && block.timestamp >= migrationTimestamp, 'PerpetualPool.executeMigration: timestamp not met yet');
        require(migrationDestination == address(this), 'PerpetualPool.executeMigration: not to destination pool');

        // copy state values for each symbol
        IPerpetualPool.SymbolInfo[] memory sourceSymbols = IPerpetualPool(source).symbols();
        for (uint256 i = 0; i < sourceSymbols.length; i++) {
            require(keccak256(bytes(symbols[i].symbol)) == keccak256(bytes(sourceSymbols[i].symbol)), 'PerpetualPool.executeMigration: symbol not match');
            symbols[i].price = sourceSymbols[i].price;
            symbols[i].cumuFundingRate = sourceSymbols[i].cumuFundingRate;
            symbols[i].tradersNetVolume = sourceSymbols[i].tradersNetVolume;
            symbols[i].tradersNetCost = sourceSymbols[i].tradersNetCost;
        }

        // copy state values for each bToken, and transfer bToken to this new pool
        IPerpetualPool.BTokenInfo[] memory sourceBTokens = IPerpetualPool(source).bTokens();
        for (uint256 i = 0; i < sourceBTokens.length; i++) {
            require(bTokens[i].bTokenAddress == sourceBTokens[i].bTokenAddress && bTokens[i].lTokenAddress == sourceBTokens[i].lTokenAddress,
                    'PerpetualPool.executeMigration: bToken not match');
            bTokens[i].price = sourceBTokens[i].price;
            bTokens[i].liquidity = sourceBTokens[i].liquidity;
            bTokens[i].pnl = sourceBTokens[i].pnl;

            IERC20(sourceBTokens[i].bTokenAddress).safeTransferFrom(source, address(this), IERC20(sourceBTokens[i].bTokenAddress).balanceOf(source));
        }

        emit ExecuteMigration(migrationTimestamp, source, address(this));
    }


    //================================================================================
    // Pool interactions
    //================================================================================
    function addLiquidity(uint256 bTokenId, uint256 bAmount) public {
        _addLiquidity(bTokenId, bAmount);
    }

    function removeLiquidity(uint256 bTokenId, uint256 lShares) public {
        _removeLiquidity(bTokenId, lShares);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public {
        _addMargin(bTokenId, bAmount);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public {
        _removeMargin(bTokenId, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public {
        _trade(symbolId, tradeVolume);
    }

    function liquidate(address account) public {
        _liquidate(account);
    }


    //================================================================================
    // Pool core logics
    //================================================================================

    function _addLiquidity(uint256 bTokenId, uint256 bAmount) internal _lock_ {
        require(bTokenId < bTokens.length, 'PerpetualPool.addLiquidity: invalid bTokenId');
        _updateBTokenStatus();

        BTokenInfo storage b = bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, msg.sender, address(this), bAmount);

        uint256 totalLiquidity = (b.liquidity * b.price / ONE * b.discount / ONE + b.pnl).itou();
        uint256 totalSupply = ILToken(b.lTokenAddress).totalSupply();
        uint256 lShares = totalLiquidity == 0 ? bAmount : bAmount * (b.price * b.discount / ONE).itou() / UONE * totalSupply / totalLiquidity;

        ILToken(b.lTokenAddress).mint(msg.sender, lShares);
        b.liquidity += bAmount.utoi();

        emit AddLiquidity(msg.sender, bTokenId, lShares, bAmount);
    }

    function _removeLiquidity(uint256 bTokenId, uint256 lShares) internal _lock_ {
        require(bTokenId < bTokens.length, 'PerpetualPool.removeLiquidity: invalid bTokenId');
        _updateBTokenStatus();
        _coverBTokenDebt(bTokenId);

        BTokenInfo storage b = bTokens[bTokenId];
        require(b.pnl >= 0, 'PerpetualPool.removeLiquidity: negative bToken pnl');
        require(lShares > 0 && lShares <= ILToken(b.lTokenAddress).balanceOf(msg.sender),
                'PerpetualPool.removeLiquidity: invalid lShares');

        uint256 amount1;
        uint256 amount2;
        uint256 totalSupply = ILToken(b.lTokenAddress).totalSupply();
        amount1 = lShares * b.liquidity.itou() / totalSupply;
        amount2 = lShares * b.pnl.itou() / totalSupply;
        amount1 = amount1.reformat(b.decimals);
        amount2 = amount2.reformat(bTokens[0].decimals);

        b.liquidity -= amount1.utoi();
        b.pnl -= amount2.utoi();

        (int256 dynamicEquity, int256 cost) = _getPoolDynamicEquityAndCost();
        require(cost == 0 || dynamicEquity * ONE / cost.abs() >= minPoolMarginRatio, 'PerpetualPool.removeLiquidity: pool insufficient liquidity');

        ILToken(b.lTokenAddress).burn(msg.sender, lShares);
        if (bTokenId == 0) {
            IERC20(b.bTokenAddress).safeTransfer(msg.sender, (amount1 + amount2).rescale(18, b.decimals));
        } else {
            if (amount1 != 0) IERC20(b.bTokenAddress).safeTransfer(msg.sender, amount1.rescale(18, b.decimals));
            if (amount2 != 0) IERC20(bTokens[0].bTokenAddress).safeTransfer(msg.sender, amount2.rescale(18, bTokens[0].decimals));
        }

        emit RemoveLiquidity(msg.sender, bTokenId, lShares, amount1, amount2);
    }

    function _addMargin(uint256 bTokenId, uint256 bAmount) internal _lock_ {
        require(bTokenId < bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        _updateBTokenStatus();

        BTokenInfo storage b = bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, msg.sender, address(this), bAmount);

        if (!IPToken(pTokenAddress).exists(msg.sender)) {
            IPToken(pTokenAddress).mint(msg.sender, bTokenId, bAmount);
        } else {
            IPToken(pTokenAddress).addMargin(msg.sender, bTokenId, bAmount.utoi());
        }

        emit AddMargin(msg.sender, bTokenId, bAmount);
    }

    function _removeMargin(uint256 bTokenId, uint256 bAmount) internal _lock_ {
        require(bTokenId < bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        _updateBTokenStatus();
        _updateTraderStatus(msg.sender);
        _coverTraderDebt(msg.sender);

        BTokenInfo storage b = bTokens[bTokenId];

        bAmount = bAmount.reformat(b.decimals);

        int256 margin = IPToken(pTokenAddress).getMargin(msg.sender, bTokenId);
        require(margin > 0, 'PerpetualPool.removeMargin: insufficient margin');

        if (bAmount > margin.itou()) {
            bAmount = margin.itou();
            margin = 0;
        } else {
            margin -= bAmount.utoi();
        }
        IPToken(pTokenAddress).updateMargin(msg.sender, bTokenId, margin);

        (int256 dynamicEquity, int256 cost) = _getTraderDynamicEquityAndCost(msg.sender);
        require(cost == 0 || dynamicEquity * ONE / cost.abs() >= minInitialMarginRatio, 'PerpetualPool.removeMargin: insufficient margin');

        IERC20(b.bTokenAddress).safeTransfer(msg.sender, bAmount.rescale(18, b.decimals));
        emit RemoveMargin(msg.sender, bTokenId, bAmount);
    }

    function _trade(uint256 symbolId, int256 tradeVolume) internal _lock_ {
        require(symbolId < symbols.length, 'PerpetualPool.trade: invalid symbolId');
        _updateBTokenStatus();
        _updateTraderStatus(msg.sender);

        tradeVolume = tradeVolume.reformat(0);

        SymbolInfo storage s = symbols[symbolId];
        IPToken.Position memory p = IPToken(pTokenAddress).getPosition(msg.sender, symbolId);

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
        IPToken(pTokenAddress).addMargin(msg.sender, 0, (-fee - realizedCost).reformat(bTokens[0].decimals));
        IPToken(pTokenAddress).updatePosition(msg.sender, symbolId, p);

        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += curCost - realizedCost;
        _distributePnlToBTokens(fee);

        int256 dynamicEquity;
        int256 cost;
        (dynamicEquity, cost) = _getPoolDynamicEquityAndCost();
        require(cost == 0 || dynamicEquity * ONE / cost.abs() >= minPoolMarginRatio, 'PerpetualPool.trade: pool insufficient liquidity');
        (dynamicEquity, cost) = _getTraderDynamicEquityAndCost(msg.sender);
        require(cost == 0 || dynamicEquity * ONE / cost.abs() >= minInitialMarginRatio, 'PerpetualPool.trade: insufficient margin');

        emit Trade(msg.sender, symbolId, tradeVolume, s.price.itou());
    }

    function _liquidate(address account) public {
        _updateBTokenStatus();
        _updateTraderStatus(account);

        (int256 dynamicEquity, int256 cost) = _getTraderDynamicEquityAndCost(account);
        require(cost != 0 && dynamicEquity * ONE / cost.abs() < minMaintenanceMarginRatio, 'PerpetualPool.liquidate: cannot liquidate');

        int256 pnl;
        IPToken.Position[] memory positions = IPToken(pTokenAddress).getPositions(account);
        for (uint256 i = 0; i < symbols.length; i++) {
            if (positions[i].volume != 0) {
                symbols[i].tradersNetVolume -= positions[i].volume;
                symbols[i].tradersNetCost -= positions[i].cost;
                pnl += positions[i].volume * symbols[i].price / ONE * symbols[i].multiplier / ONE - positions[i].cost;
            }
        }

        int256[] memory margins = IPToken(pTokenAddress).getMargins(account);
        int256 equity = margins[0];
        for (uint256 i = 1; i < bTokens.length; i++) {
            if (margins[i] != 0) {
                (, uint256 amount2) = IBTokenHandler(bTokens[i].handlerAddress).swap(margins[i].itou(), type(uint256).max);
                equity += amount2.utoi();
            }
        }

        int256 netEquity = pnl + equity;
        int256 reward;
        if (netEquity <= minLiquidationReward) {
            reward = minLiquidationReward;
        } else if (netEquity >= maxLiquidationReward) {
            reward = maxLiquidationReward;
        } else {
            reward = (netEquity - minLiquidationReward) * liquidationCutRatio / ONE + minLiquidationReward;
            reward = reward.reformat(bTokens[0].decimals);
        }

        _distributePnlToBTokens(netEquity - reward);

        IERC20(bTokens[0].bTokenAddress).safeTransfer(msg.sender, reward.itou().rescale(18, bTokens[0].decimals));
        emit Liquidate(account);
    }


    //================================================================================
    // Helpers
    //================================================================================

    function _updateBTokenStatus() internal {
        if (block.number == lastUpdateBTokenStatusBlock) return;

        int256 totalLiquidity;
        int256[] memory liquidities = new int256[](bTokens.length);
        for (uint256 i = 0; i < bTokens.length; i++) {
            BTokenInfo storage b = bTokens[i];
            b.price = IBTokenHandler(b.handlerAddress).getPrice().utoi();
            int256 liquidity = b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
            liquidities[i] = liquidity;
            totalLiquidity += liquidity;
        }

        int256 unsettledPnl;
        for (uint256 i = 0; i < symbols.length; i++) {
            SymbolInfo storage s = symbols[i];
            int256 price = ISymbolHandler(s.handlerAddress).getPrice().utoi();

            int256 r = totalLiquidity != 0 ? s.tradersNetVolume * price / ONE * s.multiplier / ONE * s.fundingRateCoefficient / totalLiquidity : int256(0);
            int256 delta;
            unchecked { delta = r * int256(block.number - lastUpdateBTokenStatusBlock); }
            int256 funding = s.tradersNetVolume * delta / ONE;
            unsettledPnl += funding;
            unchecked { s.cumuFundingRate += delta; }

            int256 pnl = s.tradersNetVolume * (price - s.price) / ONE * s.multiplier / ONE;
            unsettledPnl -= pnl;
            s.price = price;
        }

        if (totalLiquidity != 0 && unsettledPnl != 0) {
            for (uint256 i = 0; i < bTokens.length; i++) {
                bTokens[i].pnl += (unsettledPnl * liquidities[i] / totalLiquidity).reformat(bTokens[i].decimals);
            }
        }

        lastUpdateBTokenStatusBlock = block.number;
    }

    function _updateTraderStatus(address account) internal {
        int256 unsettledPnl;
        IPToken.Position[] memory positions = IPToken(pTokenAddress).getPositions(account);
        for (uint256 i = 0; i < symbols.length; i++) {
            if (positions[i].volume != 0) {
                int256 delta;
                unchecked { delta = symbols[i].cumuFundingRate - positions[i].lastCumuFundingRate; }
                unsettledPnl -= positions[i].volume * delta / ONE;

                positions[i].lastCumuFundingRate = symbols[i].cumuFundingRate;
                IPToken(pTokenAddress).updatePosition(account, i, positions[i]);
            }
        }
        if (unsettledPnl != 0) IPToken(pTokenAddress).addMargin(account, 0, unsettledPnl.reformat(bTokens[0].decimals));
    }

    function _getBTokenLiquidities() internal view returns (int256, int256[] memory) {
        int256 totalLiquidity;
        int256[] memory liquidities = new int256[](bTokens.length);
        for (uint256 i = 0; i < bTokens.length; i++) {
            BTokenInfo storage b = bTokens[i];
            int256 liquidity = b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
            totalLiquidity += liquidity;
            liquidities[i] = liquidity;
        }
        return (totalLiquidity, liquidities);
    }

    function _distributePnlToBTokens(int256 pnl) internal {
        (int256 totalLiquidity, int256[] memory liquidities) = _getBTokenLiquidities();
        if (totalLiquidity != 0 && pnl != 0) {
            for (uint256 i = 0; i < bTokens.length; i++) {
                bTokens[i].pnl += (pnl * liquidities[i] / totalLiquidity).reformat(bTokens[i].decimals);
            }
        }
    }

    function _getPoolDynamicEquityAndCost() internal view returns (int256, int256) {
        int256 totalDynamicEquity;
        int256 totalCost;

        for (uint256 i = 0; i < bTokens.length; i++) {
            BTokenInfo storage b = bTokens[i];
            totalDynamicEquity += b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
        }

        for (uint256 i = 0; i < symbols.length; i++) {
            SymbolInfo storage s = symbols[i];
            int256 cost = s.tradersNetVolume * s.price / ONE * s.multiplier / ONE; // trader's cost
            totalDynamicEquity -= cost - s.tradersNetCost;
            totalCost -= cost; // trader's cost so it is negative for pool
        }

        return (totalDynamicEquity, totalCost);
    }

    function _getTraderDynamicEquityAndCost(address account) internal view returns (int256, int256) {
        int256 totalDynamicEquity;
        int256 totalCost;

        int256[] memory margins = IPToken(pTokenAddress).getMargins(account);
        for (uint256 i = 0; i < bTokens.length; i++) {
            if (margins[i] != 0) {
                totalDynamicEquity += margins[i] * bTokens[i].price / ONE * bTokens[i].discount / ONE;
            }
        }

        IPToken.Position[] memory positions = IPToken(pTokenAddress).getPositions(account);
        for (uint256 i = 0; i < symbols.length; i++) {
            if (positions[i].volume != 0) {
                int256 cost = positions[i].volume * symbols[i].price / ONE * symbols[i].multiplier / ONE;
                totalDynamicEquity += cost - positions[i].cost;
                totalCost += cost;
            }
        }

        return (totalDynamicEquity, totalCost);
    }

    // keeper?
    function _coverBTokenDebt(uint256 bTokenId) internal {
        BTokenInfo storage b = bTokens[bTokenId];
        if (b.pnl < 0) {
            (uint256 amount1, uint256 amount2) = IBTokenHandler(b.handlerAddress).swap(b.liquidity.itou(), (-b.pnl).itou());
            b.liquidity -= amount1.utoi();
            b.pnl += amount2.utoi();
        }
    }

    function _coverTraderDebt(address account) internal {
        int256[] memory margins = IPToken(pTokenAddress).getMargins(account);
        if (margins[0] >= 0) return;
        for (uint256 i = bTokens.length - 1; i > 0; i--) {
            if (margins[i] > 0) {
                (uint256 amount1, uint256 amount2) = IBTokenHandler(bTokens[i].handlerAddress).swap(margins[i].itou(), (-margins[0]).itou());
                margins[i] -= amount1.utoi();
                margins[0] += amount2.utoi();
            }
            if (margins[0] >= 0) break;
        }
        IPToken(pTokenAddress).updateMargins(account, margins);
    }

    function _deflationCompatibleSafeTransferFrom(address bTokenAddress, uint256 decimals, address from, address to, uint256 bAmount) internal returns (uint256) {
        uint256 preBalance = IERC20(bTokenAddress).balanceOf(to);
        IERC20(bTokenAddress).safeTransferFrom(from, to, bAmount.rescale(18, decimals));
        uint256 curBalance = IERC20(bTokenAddress).balanceOf(to);

        uint256 actualReceivedAmount = (curBalance - preBalance).rescale(decimals, 18);
        return actualReceivedAmount;
    }

}
