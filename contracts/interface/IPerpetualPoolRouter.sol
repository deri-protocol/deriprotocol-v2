// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';

interface IPerpetualPoolRouter is IMigratable {

    struct PriceInfo {
        uint256 symbolId;
        uint256 timestamp;
        uint256 price;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function pool() external view returns (address);

    function liquidatorQualifier() external view returns (address);

    function setPool(address poolAddress) external;

    function setLiquidatorQualifier(address qualifier) external;

    function addBToken(
        address bTokenAddress,
        address swapperAddress,
        address oracleAddress,
        uint256 discount
    ) external;

    function addSymbol(
        string memory symbol,
        address oracleAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 fundingRateCoefficient
    ) external;

    function setBTokenParameters(
        uint256 bTokenId,
        address swapperAddress,
        address oracleAddress,
        uint256 discount
    ) external;

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        uint256 feeRatio,
        uint256 fundingRateCoefficient
    ) external;


    function addLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function addMargin(uint256 bTokenId, uint256 bAmount) external;

    function removeMargin(uint256 bTokenId, uint256 bAmount) external;

    function trade(uint256 symbolId, int256 tradeVolume) external;

    function liquidate(address owner) external;

    function addLiquidityWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) external;

    function removeLiquidityWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) external;

    function addMarginWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) external;

    function removeMarginWithPrices(uint256 bTokenId, uint256 bAmount, PriceInfo[] memory infos) external;

    function tradeWithPrices(uint256 symbolId, int256 tradeVolume, PriceInfo[] memory infos) external;

    function liquidateWithPrices(address owner, PriceInfo[] memory infos) external;

}
