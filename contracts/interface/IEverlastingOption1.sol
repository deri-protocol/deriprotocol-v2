// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';

interface IEverlastingOption1 is IMigratable {

    struct SymbolInfo {
        uint256 symbolId;
        string  symbol;
        address oracleAddress;
        address volatilityAddress;
        bool    isCall;
        int256  strikePrice;
        int256  multiplier;
        int256  feeRatio;
        int256  alpha;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativePremiumFundingRate;
    }

    struct SignedValue {
        uint256 symbolId;
        uint256 timestamp;
        uint256 value;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    event AddLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event AddMargin(address indexed account, uint256 bAmount);

    event RemoveMargin(address indexed account, uint256 bAmount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, int256 tradeCost);

    event Liquidate(address indexed account, address indexed liquidator, uint256 reward);

    event ProtocolFeeCollection(address indexed collector, uint256 amount);

    function getParameters() external view returns (
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
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
        address protocolFeeCollector,
        address optionPricerAddress
    );

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function getPoolStateValues() external view returns (int256 liquidity, uint256 lastTimestamp, int256 protocolFeeAccrued);

    function collectProtocolFee() external;

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        address oracleAddress,
        address volatilityAddress,
        bool    isCall,
        uint256 strikePrice,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 alpha
    ) external;

    function removeSymbol(uint256 symbolId) external;

    function toggleCloseOnly(uint256 symbolId) external;

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        address volatilityAddress,
        uint256 feeRatio,
        uint256 alpha
    ) external;

    function addLiquidity(uint256 bAmount, SignedValue[] memory volatilities) external;

    function removeLiquidity(uint256 lShares, SignedValue[] memory volatilities) external;

    function addMargin(uint256 bAmount) external;

    function removeMargin(uint256 bAmount, SignedValue[] memory volatilities) external;

    function trade(uint256 symbolId, int256 tradeVolume, SignedValue[] memory volatilities) external;

    function liquidate(address account, SignedValue[] memory volatilities) external;

}
