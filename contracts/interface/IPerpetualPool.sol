// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IMigratablePool.sol';

interface IPerpetualPool is IMigratablePool {

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

    event AddLiquidity(address indexed account, uint256 indexed bTokenId, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed account, uint256 indexed bTokenId, uint256 lShares, uint256 amount1, uint256 amount2);

    event AddMargin(address indexed account, uint256 indexed bTokenId, uint256 bAmount);

    event RemoveMargin(address indexed account, uint256 indexed bTokenId, uint256 bAmount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, uint256 price);

    event Liquidate(address indexed liquidator, address indexed account);

    function initialize(int256[7] memory parameters_, address[4] memory addresses_) external;

    function getParameters() external view returns (
        int256 minPoolMarginRatio,
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 daoFeeCollectRatio
    );

    function getAddresses() external view returns (
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address daoAddress
    );

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function getBToken(uint256 bTokenId) external view returns (BTokenInfo memory);

    function setParameters(
        int256 minPoolMarginRatio,
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 daoFeeCollectRatio
    ) external;

    function setAddresses(
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address daoAddress
    ) external;

    function setSymbolParameters(uint256 symbolId, address handlerAddress, int256 feeRatio, int256 fundingRateCoefficient) external;

    function setBTokenParameters(uint256 bTokenId, address handlerAddress, int256 discount) external;

    function addSymbol(SymbolInfo memory info) external;

    function addBToken(BTokenInfo memory info) external;

    function addLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function removeLiquidity(uint256 bTokenId, uint256 lShares) external;

    function addMargin(uint256 bTokenId, uint256 bAmount) external;

    function removeMargin(uint256 bTokenId, uint256 bAmount) external;

    function trade(uint256 symbolId, int256 tradeVolume) external;

    function liquidate(address account) external;

}
