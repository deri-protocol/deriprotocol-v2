// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';

interface IPerpetualPoolLite is IMigratable {

    struct SymbolInfo {
        uint256 symbolId;
        string  symbol;
        address oracleAddress;
        int256  multiplier;
        int256  feeRatio;
        int256  alpha;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativeFundingRate;
    }

    struct SignedPrice {
        uint256 symbolId;
        uint256 timestamp;
        uint256 price;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    event AddLiquidity(address indexed lp, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed lp, uint256 lShares, uint256 bAmount);

    event AddMargin(address indexed trader, uint256 bAmount);

    event RemoveMargin(address indexed trader, uint256 bAmount);

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
        int256 poolMarginRatio,
        int256 initialMarginRatio,
        int256 maintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    );

    function getAddresses() external view returns (
        address bTokenAddress,
        address lTokenAddress,
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address protocolFeeCollector
    );

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function getPoolStateValues() external view returns (int256 liquidity, uint256 lastTimestamp, int256 protocolFeeAccrued);

    function collectProtocolFee() external;

    function getFundingPeriod() external view returns (int256);

    function setFundingPeriod(uint256 period) external;

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        address oracleAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 alpha
    ) external;

    function removeSymbol(uint256 symbolId) external;

    function toggleCloseOnly(uint256 symbolId) external;

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        uint256 feeRatio,
        uint256 alpha
    ) external;

    function addLiquidity(uint256 bAmount, SignedPrice[] memory prices) external;

    function removeLiquidity(uint256 lShares, SignedPrice[] memory prices) external;

    function addMargin(uint256 bAmount) external;

    function removeMargin(uint256 bAmount, SignedPrice[] memory prices) external;

    function trade(uint256 symbolId, int256 tradeVolume, SignedPrice[] memory prices) external;

    function liquidate(address account, SignedPrice[] memory prices) external;

    function liquidate(uint256 pTokenId, SignedPrice[] memory prices) external;

}
