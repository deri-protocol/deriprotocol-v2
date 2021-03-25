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
        int256 margin = IPToken(pTokenAddress).getMargin(msg.sender, 0);
        IPToken(pTokenAddress).updateMargin(msg.sender, 0, margin - (funding.add(fee) + realizedCost).reformat(bases[0].decimals));
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

    function _checkPoolMargin() view internal {
        uint256 totalLiquidity;
        for (uint256 i = 0; i < bases.length; i++) {
            BaseInfo storage b = bases[i];
            totalLiquidity += b.liquidity.mul(b.price).mul(b.discount).add(b.pnl);
        }
        int256 totalCost;
        for (uint256 i = 0; i < symbols.length; i++) {
            SymbolInfo storage s = symbols[i];
            totalCost += s.tradersNetVolume.mul(s.price).mul(s.multiplier);
        }

        require(totalCost == 0 || totalLiquidity.div(totalCost.abs()) >= minPoolMarginRatio, 'PerpetualPool._checkPoolMargin: insufficient liquidity');
    }

    function _checkUserMargin(address account) view internal {
        int256 totalLiquidity;
        int256 totalCost;
        for (uint256 i = 0; i < bases.length; i++) {
            int256 margin = IPToken(pTokenAddress).getMargin(account, i);
            totalLiquidity += margin.mul(bases[i].price).mul(bases[i].discount);
        }
        for (uint256 i = 0; i < symbols.length; i++) {
            (int256 volume, int256 cost, int256 lastCumuFundingRate) = IPToken(pTokenAddress).getPosition(account, i);
            int256 delta;
            unchecked { delta = symbols[i].cumuFundingRate - lastCumuFundingRate; }
            int256 funding = volume.mul(delta);
            int256 pnl = volume.mul(symbols[i].price).mul(symbols[i].multiplier) - cost;
            totalLiquidity += pnl - funding;
            totalCost += cost;
        }

        require(totalLiquidity >= 0 && (totalCost == 0 || totalLiquidity.div(totalCost.abs()) >= minInitialMarginRatio.utoi()),
                'PerpetualPool._checkUserMargin: insufficient margin');
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

        uint256 amount1;
        uint256 amount2;

        BaseInfo storage b = bases[baseId];
        while (b.pnl < 0) {
            amount1 = b.liquidity.mul(uint256(10**17));
            amount2 = IExchange(b.exchangeAddress).sell(amount1);
            b.liquidity -= amount1;
            b.pnl = b.pnl.add(amount2);
        }

        uint256 balance = ILToken(b.lTokenAddress).balanceOf(msg.sender);
        if (balance - lShares < 10*18) lShares = balance;

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

        uint256 totalLiquidity;
        for (uint256 i = 0; i < bases.length; i++) {
            totalLiquidity += bases[i].liquidity.mul(bases[i].price).mul(bases[i].discount).add(bases[i].pnl);
        }
        int256  totalCost;
        for (uint256 i = 0; i < symbols.length; i++) {
            totalCost += symbols[i].tradersNetVolume.mul(symbols[i].price).mul(symbols[i].multiplier);
        }
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
            int256 margin = IPToken(pTokenAddress).getMargin(msg.sender, baseId);
            IPToken(pTokenAddress).updateMargin(msg.sender, baseId, margin + bAmount.utoi());
        }

        emit AddMargin(msg.sender, baseId, bAmount);
    }

    function removeMargin(uint256 baseId, uint256 bAmount) public {
        require(baseId < bases.length, 'PerpetualPool.removeMargin: invalid baseId');
        _updatePrices();

        bAmount = bAmount.reformat(bases[baseId].decimals);

        int256 funding;
        int256 volume; int256 cost; int256 lastCumuFundingRate;
        for (uint256 i = 0; i < symbols.length; i++) {
            (volume, cost, lastCumuFundingRate) = IPToken(pTokenAddress).getPosition(msg.sender, i);
            if (volume != 0) {
                funding += (symbols[i].cumuFundingRate - lastCumuFundingRate).mul(volume);
                IPToken(pTokenAddress).updatePosition(msg.sender, i, volume, cost, symbols[i].cumuFundingRate);
            }
        }

        int256 margin0 = IPToken(pTokenAddress).getMargin(msg.sender, 0);
        IPToken(pTokenAddress).updateMargin(msg.sender, 0, margin0 - funding);

        int256 margin = IPToken(pTokenAddress).getMargin(msg.sender, baseId);
        require(margin >= bAmount.utoi(), 'PerpetualPool.removeMargin: exceeds balance');
        IPToken(pTokenAddress).updateMargin(msg.sender, baseId, margin - bAmount.utoi());

        int256 totalLiquidity;
        for (uint256 i = 0; i < bases.length; i++) {
            margin = IPToken(pTokenAddress).getMargin(msg.sender, i);
            totalLiquidity += margin.mul(bases[i].price).mul(bases[i].discount);
        }
        int256 totalCost;
        for (uint256 i = 0; i < symbols.length; i++) {
            (volume, cost, lastCumuFundingRate) = IPToken(pTokenAddress).getPosition(msg.sender, i);
            totalCost += cost;
        }

        require(totalLiquidity >= 0 && (totalCost == 0 || totalLiquidity.div(totalCost.abs()).itou() >= minInitialMarginRatio),
                'PerpetualPool.removeMargin: cause insufficient margin');

        IERC20(bases[baseId].baseAddress).transfer(msg.sender, bAmount.rescale(18, bases[baseId].decimals));

        emit RemoveMargin(msg.sender, baseId, bAmount);
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

            int256 pnl = s.tradersNetVolume.mul(s.price) - s.tradersNetVolume.mul(newPrice);
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

    function _deflationCompatibleSafeTransferFrom(address baseAddress, uint256 decimals, address from, address to, uint256 bAmount) internal returns (uint256) {
        uint256 preBalance = IERC20(baseAddress).balanceOf(to);
        IERC20(baseAddress).transferFrom(from, to, bAmount.rescale(18, decimals));
        uint256 curBalance = IERC20(baseAddress).balanceOf(to);

        uint256 actualReceivedAmount = (curBalance - preBalance).rescale(decimals, 18);
        return actualReceivedAmount;
    }

}


interface IERC20 {
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
    function getMargin(address owner, uint256 baseId) external view returns (int256);
    function updateMargin(address owner, uint256 baseId, int256 amount) external;
    function updatePosition(address owner, uint256 symbolId, int256 volume, int256 cost, int256 lastCumuFundingRate) external;
}

interface IExchange {
    function sell(uint256 amount) external returns (uint256);
}
