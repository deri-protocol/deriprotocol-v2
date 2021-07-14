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
        int256  fundingRateCoefficient;
        int256  price;
        int256  cumulativeFundingRate;
        int256  tradersNetVolume;
        int256  tradersNetCost;
    }

    struct SignedPrice {
        uint256 symbolId;
        uint256 timestamp;
        uint256 price;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    event AddLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event AddMargin(address indexed account, uint256 bAmount);

    event RemoveMargin(address indexed account, uint256 bAmount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, uint256 price);

    event Liquidate(address indexed account, address indexed liquidator, uint256 reward);

    event ProtocolFeeCollection(address indexed collector, uint256 amount);

    function getParameters() external view returns (
        int256 minPoolMarginRatio,
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

    function getLastUpdateBlock() external view returns (uint256);

    function getProtocolFeeAccrued() external view returns (int256);

    function collectProtocolFee() external;

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        address oracleAddress,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 fundingRateCoefficient
    ) external;

    function removeSymbol(uint256 symbolId) external;

    function toggleCloseOnly(uint256 symbolId) external;

    function setSymbolParameters(uint256 symbolId, address oracleAddress, uint256 feeRatio, uint256 fundingRateCoefficient) external;

    function addLiquidity(uint256 bAmount) external;

    function removeLiquidity(uint256 lShares) external;

    function addMargin(uint256 bAmount) external;

    function removeMargin(uint256 bAmount) external;

    function trade(uint256 symbolId, int256 tradeVolume) external;

    function liquidate(address account) external;

    function addLiquidity(uint256 bAmount, SignedPrice[] memory prices) external;

    function removeLiquidity(uint256 lShares, SignedPrice[] memory prices) external;

    function addMargin(uint256 bAmount, SignedPrice[] memory prices) external;

    function removeMargin(uint256 bAmount, SignedPrice[] memory prices) external;

    function trade(uint256 symbolId, int256 tradeVolume, SignedPrice[] memory prices) external;

    function liquidate(address account, SignedPrice[] memory prices) external;

}
