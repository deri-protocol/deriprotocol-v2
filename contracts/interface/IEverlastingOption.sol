// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';

interface IEverlastingOption is IMigratable {

    struct SymbolInfo {
        uint256 symbolId;
        string  symbol;
        address oracleAddress; // spot price oracle
        address volatilityAddress; // iv oracle
        int256  multiplier;
        int256  feeRatio;
        int256  strikePrice;
        bool    isCall;
        int256  deltaFundingCoefficient; // intrisic value
        int256  cumulativeDeltaFundingRate;
        int256  intrinsicValue;
        int256  cumulativePremiumFundingRate;
        int256  timeValue;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  quote_balance_offset;
        uint256 K;
    }

    struct SignedPrice {
        uint256 symbolId;
        uint256 timestamp;
        uint256 price;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    enum Side {FLAT, SHORT, LONG} // POOL STATUS 例如LONG代表池子LONG, 此时池子的baseBalance > baseTarget

    struct VirtualBalance {
        uint256 baseTarget;
        uint256 baseBalance;
        uint256 quoteTarget;
        uint256 quoteBalance;
        Side newSide;
    }

    event AddLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event AddMargin(address indexed account, uint256 bAmount);

    event RemoveMargin(address indexed account, uint256 bAmount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, uint256 intrinsicValue, uint256 timeValue);

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
        address protocolFeeCollector
    );

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function getLiquidity() external view returns (int256);

    function getLastTimestamp() external view returns (uint256);

    function getProtocolFeeAccrued() external view returns (int256);

    function collectProtocolFee() external;

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        uint256 strikePrice,
        bool    isCall,
        address oracleAddress,
        address volatilityAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 deltaFundingCoefficient,
        uint256 k
    ) external;

    function removeSymbol(uint256 symbolId) external;

    function toggleCloseOnly(uint256 symbolId) external;

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        address volatilityAddress,
        uint256 feeRatio,
        uint256 deltaFundingCoefficient,
        uint256 k
    ) external;

    function addLiquidity(uint256 bAmount, SignedPrice[] memory volatility) external;

    function removeLiquidity(uint256 lShares, SignedPrice[] memory volatility) external;

    function addMargin(uint256 bAmount) external;

    function removeMargin(uint256 bAmount, SignedPrice[] memory volatility) external;

    function trade(uint256 symbolId, int256 tradeVolume, SignedPrice[] memory volatility) external;

    function liquidate(address account, SignedPrice[] memory volatility) external;




}
