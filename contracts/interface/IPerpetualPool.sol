// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IPerpetualPool {

    struct BTokenInfo {
        address bTokenAddress;
        address swapperAddress;
        address oracleAddress;
        uint256 decimals;
        int256  discount;
        int256  liquidity;
        int256  pnl;
        int256  cumulativePnl;
    }

    struct SymbolInfo {
        string  symbol;
        address oracleAddress;
        int256  multiplier;
        int256  feeRatio;
        int256  alpha;
        int256  distributedUnrealizedPnl;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativeFundingRate;
    }

    event AddLiquidity(address indexed lp, uint256 indexed bTokenId, uint256 bAmount);

    event RemoveLiquidity(address indexed lp, uint256 indexed bTokenId, uint256 bAmount);

    event AddMargin(address indexed trader, uint256 indexed bTokenId, uint256 bAmount);

    event RemoveMargin(address indexed trader, uint256 indexed bTokenId, uint256 bAmount);

    event Trade(
        address indexed trader,
        uint256 indexed symbolId,
        int256 indexPrice,
        int256 tradeVolume,
        int256 tradeCost,
        int256 tradeFee // a -1 tradeFee corresponds to a liquidation trade
    );

    event Liquidate(address indexed trader, address indexed liquidator, uint256 reward);

    event ProtocolFeeCollection(address indexed collector, uint256 amount);

    function getParameters() external view returns (
        uint256 decimals0,
        int256  minBToken0Ratio,
        int256  minPoolMarginRatio,
        int256  initialMarginRatio,
        int256  maintenanceMarginRatio,
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

    function getSymbolOracle(uint256 symbolId) external view returns (address);

    function getPoolStateValues() external view returns (uint256 lastTimestamp, int256 protocolFeeAccrued);

    function collectProtocolFee() external;

    function addBToken(BTokenInfo memory info) external;

    function addSymbol(SymbolInfo memory info) external;

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
        uint256 alpha
    ) external;

    function approveBTokenForTargetPool(uint256 bTokenId, address targetPool) external;

    function setPoolForLTokenAndPToken(address targetPool) external;

    function migrateBToken(
        address sourcePool,
        uint256 balance,
        address bTokenAddress,
        address swapperAddress,
        address oracleAddress,
        uint256 decimals,
        int256  discount,
        int256  liquidity,
        int256  pnl,
        int256  cumulativePnl
    ) external;

    function migrateSymbol(
        string memory symbol,
        address oracleAddress,
        int256  multiplier,
        int256  feeRatio,
        int256  alpha,
        int256  dpmmPrice,
        int256  tradersNetVolume,
        int256  tradersNetCost,
        int256  cumulativeFundingRate
    ) external;

    function migratePoolStateValues(uint256 lastTimestamp, int256 protocolFeeAccrued) external;

    function addLiquidity(address lp, uint256 bTokenId, uint256 bAmount) external;

    function removeLiquidity(address lp, uint256 bTokenId, uint256 bAmount) external;

    function addMargin(address trader, uint256 bTokenId, uint256 bAmount) external;

    function removeMargin(address trader, uint256 bTokenId, uint256 bAmount) external;

    function trade(address trader, uint256 symbolId, int256 tradeVolume) external;

    function liquidate(address liquidator, address trader) external;

}
