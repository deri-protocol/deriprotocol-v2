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
        address handlerAddress;
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

    function initialize(int256[8] memory parameters_, address[4] memory addresses_) external;

    function getParameters() external view returns (int256[8] memory parameters);

    function getAddresses() external view returns (address[4] memory addresses);

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function getBToken(uint256 bTokenId) external view returns (BTokenInfo memory);

    function setParameters(int256[8] memory parameters_) external;

    function setAddresses(address[4] memory addresses_) external;

    function addSymbol(SymbolInfo memory info) external;

    function addBToken(BTokenInfo memory info) external;

    function addLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function addMargin(uint256 bTokenId, uint256 bAmount) external;

    function removeMargin(uint256 bTokenId, uint256 bAmount) external;

    function trade(uint256 symbolId, int256 tradeVolume) external;

}
