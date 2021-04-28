// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IMigratable.sol';

interface IPerpetualPool is IMigratable {

    struct BTokenInfo {
        address bTokenAddress;
        address swapperAddress;
        address oracleAddress;
        uint256 decimals;
        int256  discount;
        int256  price;
        int256  liquidity;
        int256  pnl;
        int256  cumulativePnl;
    }

    struct SymbolInfo {
        string  symbol;
        address oracleAddress;
        int256  multiplier;
        int256  feeRatio;
        int256  fundingRateCoefficient;
        int256  price;
        int256  cumulativeFundingRate;
        int256  tradersNetVolume;
        int256  tradersNetCost;
    }

    event AddLiquidity(address owner, uint256 bTokenId, uint256 bAmount);

    event RemoveLiquidity(address owner, uint256 bTokenId, uint256 bAmount);

    event AddMargin(address owner, uint256 bTokenId, uint256 bAmount);

    event RemoveMargin(address owner, uint256 bTokenId, uint256 bAmount);

    event Trade(address owner, uint256 symbolId, int256 tradeVolume, uint256 price);

    event Liquidate(address liquidator, address owner);

    event ProtocolCollection(uint256 amount);

    function initialize(uint256[8] memory parameters, address[3] memory addresses) external;

    function getParameters() external view returns (
        uint256 minBToken0Ratio,
        uint256 minPoolMarginRatio,
        uint256 minInitialMarginRatio,
        uint256 minMaintenanceMarginRatio,
        uint256 minLiquidationReward,
        uint256 maxLiquidationReward,
        uint256 liquidationCutRatio,
        uint256 protocolFeeCollectRatio
    );

    function setParameters(uint256[8] memory parameters) external;

    function getAddresses() external view returns (
        address lTokenAddress,
        address pTokenAddress,
        address protocolFeeCollectAddress
    );

    function getProtocolLiquidity() external view returns (uint256);

    function collectProtocolLiquidity() external;

    function getBToken(uint256 bTokenId) external view returns (BTokenInfo memory);

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

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

    function setBToken(uint256 bTokenId, address swapperAddress, address oracleAddress, uint256 discount) external;

    function setSymbol(uint256 symbolId, address oracleAddress, uint256 feeRatio, uint256 fundingRateCoefficient) external;

    function addLiquidity(
        address owner,
        uint256 bTokenId,
        uint256 bAmount
    ) external;

    function removeLiquidity(
        address owner,
        uint256 bTokenId,
        uint256 bAmount
    ) external;

    function addMargin(
        address owner,
        uint256 bTokenId,
        uint256 bAmount
    ) external;

    function removeMargin(
        address owner,
        uint256 bTokenId,
        uint256 bAmount
    ) external;

    function trade(
        address owner,
        uint256 symbolId,
        int256 tradeVolume
    ) external;

    function liquidate(
        address liquidator,
        address owner
    ) external;

}
