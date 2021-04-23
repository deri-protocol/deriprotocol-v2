// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IOwnable.sol';

interface IDeriRouter is IOwnable {

    struct BToken {
        address bTokenAddress;
        address handlerAddress;
        uint256 decimals;
        uint256 discount;
    }

    struct Symbol {
        string  symbol;
        address handlerAddress;
        uint256 multiplier;
        uint256 feeRatio;
        uint256 fundingRateCoefficient;
    }

    function setPool(address poolAddress) external;

    function setLiquidatorQualifierAddress(address qualifierAddress) external;

    function addBToken(
        address bTokenAddress,
        address handlerAddress,
        uint256 discount
    ) external;

    function addSymbol(
        string  memory symbol,
        address handlerAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 fundingRateCoefficient
    ) external;

    function addLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function addMargin(uint256 bTokenId, uint256 bAmount) external;

    function removeMargin(uint256 bTokenId, uint256 bAmount) external;

    function trade(uint256 symbolId, int256 tradeVolume) external;

    function liquidate(address owner) external;

}
