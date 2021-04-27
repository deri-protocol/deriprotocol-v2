// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IOwnable.sol';

interface IDeriRouter is IOwnable {

    struct BToken {
        string  symbol;
        address oracleAddress;
    }

    struct Symbol {
        string  symbol;
        address oracleAddress;
    }

    function pool() external view returns (address);

    function liquidatorQualifier() external view returns (address);

    function setPool(address poolAddress) external;

    function setLiquidatorQualifier(address qualifier) external;

    function addBToken(
        string memory symbol,
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

    function addLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function removeLiquidity(uint256 bTokenId, uint256 bAmount) external;

    function addMargin(uint256 bTokenId, uint256 bAmount) external;

    function removeMargin(uint256 bTokenId, uint256 bAmount) external;

    function trade(uint256 symbolId, int256 tradeVolume) external;

    function liquidate(address owner) external;

}
