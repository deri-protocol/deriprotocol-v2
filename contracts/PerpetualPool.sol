// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './interface/IERC20.sol';
import './interface/IBHandler.sol';
import './interface/ISHandler.sol';
import './interface/IPToken.sol';
import './interface/ILToken.sol';
import './SafeMath.sol';
import './SafeERC20.sol';

contract PerpetualPool {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    event AddLiquidity(address indexed account, uint256 indexed bTokenId, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed account, uint256 indexed bTokenId, uint256 lShares, uint256 amount1, uint256 amount2);

    event AddMargin(address indexed account, uint256 indexed bTokenId, uint256 bAmount);

    event RemoveMargin(address indexed account, uint256 indexed bTokenId, uint256 bAmount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, uint256 price);

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

    int256  public redemptionFeeRatio;

    int256  public minPoolMarginRatio;

    int256  public minInitialMarginRatio;

    int256  public debtCoverRatio;

    SymbolInfo[] public symbols;    // symbolId indexed

    BTokenInfo[] public bTokens;    // bTokenId indexed

    uint256 lastUpdateLpStatusBlock;


    function addLiquidity(uint256 bTokenId, uint256 bAmount) public {
        require(bTokenId < bTokens.length, 'PerpetualPool.addLiquidity: invalid bTokenId');
        _updateLpStatus();

        BTokenInfo storage b = bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, msg.sender, address(this), bAmount);

        uint256 totalLiquidity = (b.liquidity * b.price / ONE * b.discount / ONE + b.pnl).itou();
        uint256 totalSupply = ILToken(b.lTokenAddress).totalSupply();
        uint256 lShares = totalLiquidity == 0 ? bAmount : bAmount * (b.price * b.discount / ONE).itou() / UONE * totalSupply / totalLiquidity;

        ILToken(b.lTokenAddress).mint(msg.sender, lShares);
        b.liquidity += bAmount.utoi();

        emit AddLiquidity(msg.sender, bTokenId, lShares, bAmount);
    }

    function removeLiquidity(uint256 bTokenId, uint256 lShares) public {
        require(bTokenId < bTokens.length, 'PerpetualPool.removeLiquidity: invalid bTokenId');
        _updateLpStatus();
        _coverBTokenDebt(bTokenId);

        BTokenInfo storage b = bTokens[bTokenId];
        require(b.pnl >= 0, 'PerpetualPool.removeLiquidity: negative bToken pnl');

        // uint256 balance = ILToken(b.lTokenAddress).balanceOf(msg.sender);
        // if (lShares >= balance || balance - lShares < UONE) lShares = balance;

        uint256 totalSupply = ILToken(b.lTokenAddress).totalSupply();
        uint256 amount1;
        uint256 amount2;
        if (lShares < totalSupply) {
            amount1 = lShares * b.liquidity.itou() / totalSupply * (UONE - redemptionFeeRatio.itou()) / UONE;
            amount2 = lShares * b.pnl.itou() / totalSupply * (UONE - redemptionFeeRatio.itou()) / UONE;
        } else {
            amount1 = b.liquidity.itou();
            amount2 = b.pnl.itou();
        }
        amount1 = amount1.reformat(b.decimals);
        amount2 = amount2.reformat(bTokens[0].decimals);

        b.liquidity -= amount1.utoi();
        b.pnl -= amount2.utoi();

        (int256 equity, int256 cost) = _getLpDynamics();
        require(cost == 0 || equity * ONE / cost.abs() >= minPoolMarginRatio, 'PerpetualPool.removeLiquidity: pool insufficient liquidity');

        ILToken(b.lTokenAddress).burn(msg.sender, lShares);
        if (bTokenId == 0) {
            IERC20(b.bTokenAddress).safeTransfer(msg.sender, (amount1 + amount2).rescale(18, b.decimals));
        } else {
            if (amount1 != 0) IERC20(b.bTokenAddress).safeTransfer(msg.sender, amount1.rescale(18, b.decimals));
            if (amount2 != 0) IERC20(bTokens[0].bTokenAddress).safeTransfer(msg.sender, amount2.rescale(18, bTokens[0].decimals));
        }

        emit RemoveLiquidity(msg.sender, bTokenId, lShares, amount1, amount2);
    }

    function addMargin(uint256 bTokenId, uint256 bAmount) public {
        require(bTokenId < bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        _updateLpStatus();

        BTokenInfo storage b = bTokens[bTokenId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.bTokenAddress, b.decimals, msg.sender, address(this), bAmount);

        if (!IPToken(pTokenAddress).exists(msg.sender)) {
            IPToken(pTokenAddress).mint(msg.sender, bTokenId, bAmount);
        } else {
            IPToken(pTokenAddress).addMargin(msg.sender, bTokenId, bAmount.utoi());
        }

        emit AddMargin(msg.sender, bTokenId, bAmount);
    }

    function removeMargin(uint256 bTokenId, uint256 bAmount) public {
        require(bTokenId < bTokens.length, 'PerpetualPool.addMargin: invalid bTokenId');
        _updateLpStatus();
        _updateTraderStatus(msg.sender);
        _coverTraderDebt(msg.sender);

        BTokenInfo storage b = bTokens[bTokenId];

        bAmount = bAmount.reformat(b.decimals);

        int256 margin = IPToken(pTokenAddress).getMargin(msg.sender, bTokenId);
        require(margin >= 0, 'PerpetualPool.removeMargin: negative margin');

        if (bAmount > margin.itou()) {
            bAmount = margin.itou();
            margin = 0;
        } else {
            margin -= bAmount.utoi();
        }
        IPToken(pTokenAddress).updateMargin(msg.sender, bTokenId, margin);

        (int256 equity, int256 cost) = _getTraderDynamics(msg.sender);
        require(cost == 0 || equity * ONE / cost.abs() >= minInitialMarginRatio, 'PerpetualPool.removeMargin: insufficient margin');

        IERC20(b.bTokenAddress).safeTransfer(msg.sender, bAmount.rescale(18, b.decimals));
        emit RemoveMargin(msg.sender, bTokenId, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume) public {
        require(symbolId < symbols.length, 'PerpetualPool.trade: invalid symbolId');
        _updateLpStatus();
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
        IPToken(pTokenAddress).addMargin(msg.sender, 0, -fee - realizedCost);
        IPToken(pTokenAddress).updatePosition(msg.sender, symbolId, p);

        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += curCost - realizedCost;
        _distributeLpPnl(fee);

        int256 equity;
        int256 cost;
        (equity, cost) = _getLpDynamics();
        require(cost == 0 || equity * ONE / cost.abs() >= minPoolMarginRatio, 'PerpetualPool.trade: pool insufficient liquidity');
        (equity, cost) = _getTraderDynamics(msg.sender);
        require(cost == 0 || equity * ONE / cost.abs() >= minInitialMarginRatio, 'PerpetualPool.trade: insufficient margin');

        emit Trade(msg.sender, symbolId, tradeVolume, s.price.itou());
    }

    function _updateLpStatus() internal {
        if (block.number == lastUpdateLpStatusBlock) return;

        int256 totalLiquidity;
        int256[] memory liquidities = new int256[](bTokens.length);
        for (uint256 i = 0; i < bTokens.length; i++) {
            BTokenInfo storage b = bTokens[i];
            b.price = IBHandler(b.handlerAddress).getPrice().utoi();
            int256 liquidity = b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
            liquidities[i] = liquidity;
            totalLiquidity += liquidity;
        }

        int256 unsettledPnl;
        for (uint256 i = 0; i < symbols.length; i++) {
            SymbolInfo storage s = symbols[i];
            int256 price = ISHandler(s.handlerAddress).getPrice().utoi();

            int256 rate = totalLiquidity != 0 ? s.tradersNetVolume * price / ONE * s.multiplier / ONE * s.fundingRateCoefficient / totalLiquidity : int256(0);
            int256 delta;
            unchecked { delta = rate * int256(block.number - lastUpdateLpStatusBlock); }
            int256 funding = s.tradersNetVolume * delta;
            unsettledPnl += funding;
            unchecked { s.cumuFundingRate += delta; }

            int256 pnl = s.tradersNetVolume * (price - s.price) / ONE * s.multiplier / ONE;
            unsettledPnl -= pnl;
            s.price = price;
        }

        if (totalLiquidity != 0 && unsettledPnl != 0) {
            for (uint256 i = 0; i < bTokens.length; i++) {
                bTokens[i].pnl += unsettledPnl * liquidities[i] / totalLiquidity;
            }
        }

        lastUpdateLpStatusBlock = block.number;
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
        if (unsettledPnl != 0) IPToken(pTokenAddress).addMargin(account, 0, unsettledPnl);
    }

    function _getLpLiquidities() internal view returns (int256, int256[] memory) {
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

    function _distributeLpPnl(int256 pnl) internal {
        (int256 totalLiquidity, int256[] memory liquidities) = _getLpLiquidities();
        if (totalLiquidity != 0 && pnl != 0) {
            for (uint256 i = 0; i < bTokens.length; i++) {
                bTokens[i].pnl += pnl * liquidities[i] / totalLiquidity;
            }
        }
    }

    function _getLpDynamics() internal view returns (int256, int256) {
        int256 totalDynamicEquity;
        int256 totalCost;

        for (uint256 i = 0; i < bTokens.length; i++) {
            BTokenInfo storage b = bTokens[i];
            totalDynamicEquity += b.liquidity * b.price / ONE * b.discount / ONE + b.pnl;
        }

        for (uint256 i = 0; i < symbols.length; i++) {
            SymbolInfo storage s = symbols[i];
            int256 cost = s.tradersNetVolume * s.price / ONE * s.multiplier / ONE;
            totalDynamicEquity -= cost - s.tradersNetCost;
            totalCost -= cost;
        }

        return (totalDynamicEquity, totalCost);
    }

    function _getTraderDynamics(address account) internal view returns (int256, int256) {
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

    function _coverBTokenDebt(uint256 bTokenId) internal {
        BTokenInfo storage b = bTokens[bTokenId];
        if (b.pnl < 0) {
            (uint256 amount1, uint256 amount2) = IBHandler(b.handlerAddress).swap(b.liquidity.itou(), (-b.pnl).itou());
            b.liquidity -= amount1.utoi();
            b.pnl += amount2.utoi();
        }
    }

    function _coverTraderDebt(address account) internal {
        int256[] memory margins = IPToken(pTokenAddress).getMargins(account);
        if (margins[0] >= 0) return;
        for (uint256 i = bTokens.length - 1; i > 0; i--) {
            if (margins[i] > 0) {
                (uint256 amount1, uint256 amount2) = IBHandler(bTokens[i].handlerAddress).swap(margins[i].itou(), (-margins[0]).itou());
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
