// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import './MixedSafeMathWithUnit.sol';

contract PerpetualPool {

    event AddLiquidity(address indexed account, uint256 indexed baseId, uint256 lShares, uint256 amount);

    event RemoveLiquidity(address indexed account, uint256 indexed baseId, uint256 lShares, uint256 amount1, uint256 amount2);

    event AddMargin(address indexed account, uint256 indexed baseId, uint256 amount);

    event RemoveMargin(address indexed account, uint256 indexed baseId, uint256 amount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, uint256 price);

    using MixedSafeMathWithUnit for uint256;
    using MixedSafeMathWithUnit for int256;

    struct SymbolInfo {
        string  symbol;
        uint256 multiplier;
        uint256 feeRatio;
        uint256 fundingRateCoefficient;

        uint256 price;
        address oracle;

        int256  cumuFundingRate;
        int256  tradersNetVolume;
        int256  tradersNetCost;
    }

    struct BaseInfo {
        address baseAddress;
        uint256 decimals;
        uint256 discount;
        address lTokenAddress;
        address exchangeAddress;

        uint256 price;
        address oracle;

        uint256 liquidity;
        int256  pnl;
    }

    address public pTokenAddress;

    uint256 public redemptionFeeRatio;

    uint256 public minPoolMarginRatio;

    uint256 public minInitialMarginRatio;

    uint256 public basePnlCoverRatio;

    SymbolInfo[] public symbols; // symbolId indexed

    BaseInfo[] public bases;     // baseId indexed

    uint256 public lastBlockNumber;

    function trade(uint256 symbolId, int256 tradeVolume) public {
        require(symbolId < symbols.length, 'PerpetualPool.trade: invalid symbolId');
        tradeVolume = tradeVolume.reformat(0);
        _updatePrices();

        SymbolInfo storage symbol = symbols[symbolId];

        int256 volume;
        int256 cost;
        int256 lastCumuFundingRate;
        uint256 fee;
        (volume, cost, lastCumuFundingRate) = IPToken(pTokenAddress).getPosition(msg.sender, symbolId);

        int256 funding;
        {
        int256 delta;
        unchecked { delta = symbol.cumuFundingRate - lastCumuFundingRate; }
        funding = volume.mul(delta);
        }

        int256 curCost = tradeVolume.mul(symbol.price).mul(symbol.multiplier);
        fee = symbol.feeRatio.mul(curCost.abs());

        {
        int256 realizedCost;
        if ((volume >= 0 && tradeVolume >= 0) || (volume <= 0 && tradeVolume <= 0)) {

        } else if (volume.abs() <= tradeVolume.abs()) {
            realizedCost = curCost.mul(volume.abs()).div(tradeVolume.abs()) + cost;
        } else {
            realizedCost = cost.mul(tradeVolume.abs()).div(volume.abs()) + curCost;
        }

        volume += tradeVolume;
        cost += curCost - realizedCost;
        uint256 margin0 = IPToken(pTokenAddress).getMargin(msg.sender, 0);
        int256 debt = funding.add(fee) + realizedCost - margin0.utoi();
        if (debt < 0) {
            _coverUserDebt(msg.sender, uint256(-debt));
            margin0 = IPToken(pTokenAddress).getMargin(msg.sender, 0);
        }
        IPToken(pTokenAddress).updateMargin(msg.sender, 0, margin0.sub((funding.add(fee) + realizedCost).reformat(bases[0].decimals)));
        IPToken(pTokenAddress).updatePosition(msg.sender, symbolId, volume, cost, symbol.cumuFundingRate);

        symbol.tradersNetVolume += tradeVolume;
        symbol.tradersNetCost += curCost - realizedCost;
        }

        {
        uint256 totalLiquidity;
        for (uint256 i = 0; i < bases.length; i++) {
            BaseInfo storage b = bases[i];
            totalLiquidity += b.liquidity.mul(b.price).mul(b.discount).add(b.pnl);
        }
        for (uint256 i = 0; i < bases.length; i++) {
            BaseInfo storage b = bases[i];
            b.pnl += fee.mul(b.liquidity.mul(b.price).mul(b.discount).add(b.pnl)).div(totalLiquidity).utoi();
        }
        }

        _checkPoolMargin();
        _checkUserMargin(msg.sender);

        emit Trade(msg.sender, symbolId, tradeVolume, symbols[symbolId].price);
    }

    function addLiquidity(uint256 baseId, uint256 bAmount) public {
        require(baseId < bases.length, 'PerpetualPool.addLiquidity: invalid baseId');
        _updatePrices();

        BaseInfo storage b = bases[baseId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.baseAddress, b.decimals, msg.sender, address(this), bAmount);
        uint256 totalLiquidity = b.liquidity.mul(b.price).mul(b.discount).add(b.pnl);
        uint256 totalSupply = ILToken(b.lTokenAddress).totalSupply();
        uint256 lShares = totalLiquidity == 0 ? bAmount : bAmount.mul(b.price).mul(b.discount).mul(totalSupply).div(totalLiquidity);

        ILToken(b.lTokenAddress).mint(msg.sender, lShares);
        b.liquidity += bAmount;

        emit AddLiquidity(msg.sender, baseId, lShares, bAmount);
    }

    function removeLiquidity(uint256 baseId, uint256 lShares) public {
        require(baseId < bases.length, 'PerpetualPool.removeLiquidity: not supported baseId');
        _updatePrices();
        _coverBaseDebt(baseId);

        uint256 amount1;
        uint256 amount2;

        BaseInfo storage b = bases[baseId];

        uint256 balance = ILToken(b.lTokenAddress).balanceOf(msg.sender);
        if (balance - lShares < 10**18) lShares = balance;

        uint256 totalSupply = ILToken(b.lTokenAddress).totalSupply();
        amount1 = lShares.mul(b.liquidity).div(totalSupply);
        amount2 = lShares.mul(b.pnl).div(totalSupply);
        if (lShares < totalSupply) {
            amount1 -= amount1.mul(redemptionFeeRatio);
            amount2 -= amount2.mul(redemptionFeeRatio);
        }
        amount1 = amount1.reformat(b.decimals);
        amount2 = amount2.reformat(bases[0].decimals);

        b.liquidity -= amount1;
        b.pnl = b.pnl.sub(amount2);

        uint256 totalLiquidity = _getPoolTotalLiquidity();
        int256 totalCost = _getPoolTotalCost();
        require(totalCost == 0 || totalLiquidity.div(totalCost.abs()) >= minPoolMarginRatio, 'PerpetualPool.removeLiquidity: pool insufficient liquidity');

        ILToken(b.lTokenAddress).burn(msg.sender, lShares);
        IERC20(b.baseAddress).transfer(msg.sender, amount1.rescale(18, b.decimals));
        IERC20(bases[0].baseAddress).transfer(msg.sender, amount2.rescale(18, bases[0].decimals));

        emit RemoveLiquidity(msg.sender, baseId, lShares, amount1, amount2);
    }

    function addMargin(uint256 baseId, uint256 bAmount) public {
        require(baseId < bases.length, 'PerpetualPool.addMargin: invalid baseId');
        _updatePrices();

        BaseInfo storage b = bases[baseId];
        bAmount = _deflationCompatibleSafeTransferFrom(b.baseAddress, b.decimals, msg.sender, address(this), bAmount);

        if (!IPToken(pTokenAddress).exists(msg.sender)) {
            IPToken(pTokenAddress).mint(msg.sender, baseId, bAmount);
        } else {
            uint256 margin = IPToken(pTokenAddress).getMargin(msg.sender, baseId);
            IPToken(pTokenAddress).updateMargin(msg.sender, baseId, margin + bAmount);
        }

        emit AddMargin(msg.sender, baseId, bAmount);
    }

    function removeMargin(uint256 baseId, uint256 bAmount) public {
        require(baseId < bases.length, 'PerpetualPool.removeMargin: invalid baseId');
        _updatePrices();

        bAmount = bAmount.reformat(bases[baseId].decimals);

        int256 funding;
        for (uint256 i = 0; i < symbols.length; i++) {
            (int256 volume, int256 cost, int256 lastCumuFundingRate) = IPToken(pTokenAddress).getPosition(msg.sender, i);
            if (volume != 0) {
                int256 delta;
                unchecked { delta = symbols[i].cumuFundingRate - lastCumuFundingRate; }
                funding += delta.mul(volume);
                IPToken(pTokenAddress).updatePosition(msg.sender, i, volume, cost, symbols[i].cumuFundingRate);
            }
        }

        uint256 margin0 = IPToken(pTokenAddress).getMargin(msg.sender, 0);
        if (margin0.utoi() - funding >= 0) {
            IPToken(pTokenAddress).updateMargin(msg.sender, 0, margin0.sub(funding));
        } else {
            uint256 debt = funding.sub(margin0).itou();
            _coverUserDebt(msg.sender, debt);
        }

        uint256 margin = IPToken(pTokenAddress).getMargin(msg.sender, baseId);
        require(margin >= bAmount, 'PerpetualPool.removeMargin: insufficient margin');
        IPToken(pTokenAddress).updateMargin(msg.sender, baseId, margin - bAmount);

        uint256 totalLiquidity = _getUserTotalLiquidity(msg.sender);
        int256 totalCost = _getUserTotalCost(msg.sender);
        require(totalCost == 0 || totalLiquidity.div(totalCost.abs()) >= minInitialMarginRatio, 'PerpetualPool.removeMargin: insufficient margin');

        IERC20(bases[baseId].baseAddress).transfer(msg.sender, bAmount.rescale(18, bases[baseId].decimals));

        emit RemoveMargin(msg.sender, baseId, bAmount);
    }

    function _getUserTotalLiquidity(address account) internal view returns (uint256) {
        uint256 totalLiquidity;
        for (uint256 i = 0; i < bases.length; i++) {
            uint256 margin = IPToken(pTokenAddress).getMargin(account, i);
            totalLiquidity += margin.mul(bases[i].price).mul(bases[i].discount);
        }
        for (uint256 i = 0; i < symbols.length; i++) {
            (int256 volume, int256 cost, ) = IPToken(pTokenAddress).getPosition(account, i);
            int256 pnl = volume.mul(symbols[i].price).mul(symbols[i].multiplier) - cost;
            totalLiquidity = totalLiquidity.add(pnl);
        }
        return totalLiquidity;
    }

    function _getUserTotalCost(address account) internal view returns (int256) {
        int256 totalCost;
        for (uint256 i = 0; i < symbols.length; i++) {
            (int256 volume, , ) = IPToken(pTokenAddress).getPosition(account, i);
            totalCost += volume.mul(symbols[i].price).mul(symbols[i].multiplier);
        }
        return totalCost;
    }

    function _checkUserMargin(address account) internal view {
        uint256 totalLiquidity = _getUserTotalLiquidity(account);
        int256 totalCost = _getUserTotalCost(account);
        require(totalCost == 0 || totalLiquidity.div(totalCost.abs()) >= minInitialMarginRatio, 'PerpetualPool._checkUserMargin: insufficient margin');
    }

    function _getPoolTotalLiquidity() internal view returns (uint256) {
        uint256 totalLiquidity;
        for (uint256 i = 0; i < bases.length; i++) {
            BaseInfo storage b = bases[i];
            totalLiquidity += b.liquidity.mul(b.price).mul(b.discount).add(b.pnl);
        }
        return totalLiquidity;
    }

    function _getPoolTotalCost() internal view returns (int256) {
        int256 totalCost;
        for (uint256 i = 0; i < symbols.length; i++) {
            SymbolInfo storage s = symbols[i];
            totalCost += s.tradersNetVolume.mul(s.price).mul(s.multiplier);
        }
        return totalCost;
    }

    function _checkPoolMargin() internal view {
        uint256 totalLiquidity = _getPoolTotalLiquidity();
        int256 totalCost = _getPoolTotalCost();
        require(totalCost == 0 || totalLiquidity.div(totalCost.abs()) >= minPoolMarginRatio, 'PerpetualPool._checkPoolMargin: insufficient liquidity');
    }

    function _updatePrices() internal {
        if (block.number == lastBlockNumber) return;

        uint256 totalLiquidity;
        for (uint256 i = 0; i < bases.length; i++) {
            BaseInfo storage b = bases[i];
            b.price = IOracle(b.oracle).getPrice();
            totalLiquidity += b.liquidity.mul(b.price).mul(b.discount).add(b.pnl);
        }

        int256 unsettledPnl;
        for (uint256 i = 0; i < symbols.length; i++) {
            SymbolInfo storage s = symbols[i];
            uint256 newPrice = IOracle(s.oracle).getPrice();

            int256 rate = totalLiquidity != 0 ? s.tradersNetVolume.mul(newPrice).mul(s.multiplier).mul(s.fundingRateCoefficient).div(totalLiquidity) : int256(0);
            int256 delta;
            unchecked { delta = rate * (block.number - lastBlockNumber).utoi(); }
            unsettledPnl += s.tradersNetVolume.mul(delta);
            unchecked { s.cumuFundingRate += delta; }

            int256 pnl = s.tradersNetVolume.mul(s.price).mul(s.multiplier) - s.tradersNetVolume.mul(newPrice).mul(s.multiplier);
            unsettledPnl += pnl;
            s.price = newPrice;
        }

        if (totalLiquidity != 0 && unsettledPnl != 0) {
            for (uint256 i = 0; i < bases.length; i++) {
                BaseInfo storage b = bases[i];
                b.pnl += unsettledPnl.mul(b.liquidity.mul(b.price).mul(b.discount).add(b.pnl)).div(totalLiquidity);
            }
        }

        lastBlockNumber = block.number;
    }

    function _coverBaseDebt(uint256 baseId) internal {
        BaseInfo storage b = bases[baseId];
        uint256 amount = b.liquidity.mul(b.price).mul(b.discount).mul(basePnlCoverRatio);
        while (b.pnl < 0) {
            (uint256 amount1, uint256 amount2) = IExchange(b.exchangeAddress).sell(b.liquidity, amount.sub(b.pnl));
            b.liquidity -= amount1;
            b.pnl = b.pnl.add(amount2);
        }
    }

    function _coverUserDebt(address account, uint256 debt) internal {
        uint256 covered = IPToken(pTokenAddress).getMargin(account, 0);
        for (uint256 i = 1; i < bases.length; i++) {
            if (covered >= debt) break;
            uint256 margin = IPToken(pTokenAddress).getMargin(account, i);
            if (margin > 0) {
                (uint256 amount1, uint256 amount2) = IExchange(bases[i].exchangeAddress).sell(margin, debt - covered);
                IPToken(pTokenAddress).updateMargin(account, i, margin - amount1);
                covered += amount2;
            }
        }
        IPToken(pTokenAddress).updateMargin(account, 0, covered);
    }

    function _deflationCompatibleSafeTransferFrom(address baseAddress, uint256 decimals, address from, address to, uint256 bAmount) internal returns (uint256) {
        uint256 preBalance = IERC20(baseAddress).balanceOf(to);
        IERC20(baseAddress).transferFrom(from, to, bAmount.rescale(18, decimals));
        uint256 curBalance = IERC20(baseAddress).balanceOf(to);

        uint256 actualReceivedAmount = (curBalance - preBalance).rescale(decimals, 18);
        return actualReceivedAmount;
    }

}


interface IERC20 {
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IOracle {
    function getPrice() external view returns (uint256);
}

interface ILToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}

interface IPToken {
    function exists(address owner) external view returns (bool);
    function getPosition(address owner, uint256 symbolId) external view returns (int256, int256, int256);
    function mint(address owner, uint256 baseId, uint256 amount) external;
    function getMargin(address owner, uint256 baseId) external view returns (uint256);
    function updateMargin(address owner, uint256 baseId, uint256 amount) external;
    function updatePosition(address owner, uint256 symbolId, int256 volume, int256 cost, int256 lastCumuFundingRate) external;
}

interface IExchange {
    function sell(uint256 amount1, uint256 amount2) external returns (uint256, uint256); // maximumly sell amount1 to get amount2 in base0 token
}
