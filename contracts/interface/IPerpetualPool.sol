// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IPerpetualPool {

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

    function migrationTimestamp() external view returns (uint256);

    function migrationDestination() external view returns (address);

    function initialize(
        SymbolInfo[] calldata _symbols,
        BTokenInfo[] calldata _bTokens,
        int256[] calldata _parameters,
        address[] calldata _addresses
    ) external;

    function symbols() external view returns (SymbolInfo[] memory);

    function bTokens() external view returns (BTokenInfo[] memory);

}
