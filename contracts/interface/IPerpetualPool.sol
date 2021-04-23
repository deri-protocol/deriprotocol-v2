// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IMigratable.sol';

interface IPerpetualPool is IMigratable {

    struct BTokenInfo {
        address bTokenAddress;
        address handlerAddress;
        uint256 decimals;
        int256  discount;
        int256  price;
        int256  liquidity;
        int256  pnl;
        int256  cumulativePnl;
    }

    struct SymbolInfo {
        string  symbol;
        int256  multiplier;
        int256  feeRatio;
        int256  fundingRateCoefficient;
        int256  price;
        int256  cumulativeFundingRate;
        int256  tradersNetVolume;
        int256  tradersNetCost;
    }

    struct TradeParams {
        int256 curCost;
        int256 fee;
        int256 realizedCost;
        int256 protocolFee;
    }

    event AddLiquidity(address owner, uint256 bTokenId, uint256 bAmount);

    event RemoveLiquidity(address owner, uint256 bTokenId, uint256 bAmount);

    event AddMargin(address owner, uint256 bTokenId, uint256 bAmount);

    event RemoveMargin(address owner, uint256 bTokenId, uint256 bAmount);

    event Trade(address owner, uint256 symbolId, int256 tradeVolume, uint256 price);

    event Liquidate(address liquidator, address owner);

    event ProtocolCollection(uint256 amount);

    function getParameters() external view returns (
        uint256 decimals0,
        uint256 minBToken0Ratio,
        uint256 minPoolMarginRatio,
        uint256 minInitialMarginRatio,
        uint256 minMaintenanceMarginRatio,
        uint256 minLiquidationReward,
        uint256 maxLiquidationReward,
        uint256 liquidationCutRatio,
        uint256 protocolFeeCollectRatio
    );

    function getAddresses() external view returns (
        address routerAddress,
        address pTokenAddress,
        address lTokenAddress,
        address protocolAddress
    );

    function getProtocolLiquidity() external view returns (uint256);

    function collectProtocolLiquidity() external;

    function getBToken(uint256 bTokenId) external view returns (BTokenInfo memory);

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function addBToken(address bTokenAddress, address swapperAddress, uint256 discount) external;

    function addSymbol(
        string memory symbol,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 fundingRateCoefficient
    ) external;

    function addLiquidity(
        address owner,
        uint256 bTokenId,
        uint256 bAmount,
        int256[] memory bPrices,
        int256[] memory sPrices
    ) external;

    function removeLiquidity(
        address owner,
        uint256 bTokenId,
        uint256 bAmount,
        int256[] memory bPrices,
        int256[] memory sPrices
    ) external;

    function addMargin(
        address owner,
        uint256 bTokenId,
        uint256 bAmount
    ) external;

    function removeMargin(
        address owner,
        uint256 bTokenId,
        uint256 bAmount,
        int256[] memory bPrices,
        int256[] memory sPrices
    ) external;

    function trade(
        address owner,
        uint256 symbolId,
        int256 tradeVolume,
        int256[] memory bPrices,
        int256[] memory sPrices
    ) external;

    function liquidate(
        address liquidator,
        address owner,
        int256[] memory bPrices,
        int256[] memory sPrices
    ) external;

}
