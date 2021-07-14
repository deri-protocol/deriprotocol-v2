// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IPerpetualPool {

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

    event AddLiquidity(address indexed owner, uint256 indexed bTokenId, uint256 bAmount);

    event RemoveLiquidity(address indexed owner, uint256 indexed bTokenId, uint256 bAmount);

    event AddMargin(address indexed owner, uint256 indexed bTokenId, uint256 bAmount);

    event RemoveMargin(address indexed owner, uint256 indexed bTokenId, uint256 bAmount);

    event Trade(address indexed owner, uint256 indexed symbolId, int256 tradeVolume, uint256 price);

    event Liquidate(address indexed owner, address indexed liquidator, uint256 reward);

    event ProtocolFeeCollection(address indexed collector, uint256 amount);

    function getParameters() external view returns (
        uint256 decimals0,
        int256  minBToken0Ratio,
        int256  minPoolMarginRatio,
        int256  minInitialMarginRatio,
        int256  minMaintenanceMarginRatio,
        int256  minLiquidationReward,
        int256  maxLiquidationReward,
        int256  liquidationCutRatio,
        int256  protocolFeeCollectRatio
    );

    function getAddresses() external view returns (
        address lTokenAddress,
        address pTokenAddress,
        address routerAddress,
        address protocolFeeCollector
    );

    function getLengths() external view returns (uint256, uint256);

    function getBToken(uint256 bTokenId) external view returns (BTokenInfo memory);

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function getBTokenOracle(uint256 bTokenId) external view returns (address);

    function getSymbolOracle(uint256 symbolId) external view returns (address);

    function getLastUpdateBlock() external view returns (uint256);

    function getProtocolFeeAccrued() external view returns (int256);

    function collectProtocolFee() external;

    function addBToken(BTokenInfo memory info) external;

    function addSymbol(SymbolInfo memory info) external;

    function setBTokenParameters(uint256 bTokenId, address swapperAddress, address oracleAddress, uint256 discount) external;

    function setSymbolParameters(uint256 symbolId, address oracleAddress, uint256 feeRatio, uint256 fundingRateCoefficient) external;

    function approvePoolMigration(address targetPool) external;

    function executePoolMigration(address sourcePool) external;

    function addLiquidity(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) external;

    function removeLiquidity(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) external;

    function addMargin(address owner, uint256 bTokenId, uint256 bAmount) external;

    function removeMargin(address owner, uint256 bTokenId, uint256 bAmount, uint256 blength, uint256 slength) external;

    function trade(address owner, uint256 symbolId, int256 tradeVolume, uint256 blength, uint256 slength) external;

    function liquidate(address liquidator, address owner, uint256 blength, uint256 slength) external;

}
