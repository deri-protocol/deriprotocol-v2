// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IERC721.sol';

interface IPTokenLite is IERC721 {

    struct Position {
        // position volume, long is positive and short is negative
        int256 volume;
        // the cost the establish this position
        int256 cost;
        // the last cumulativeFundingRate since last funding settlement for this position
        // the overflow for this value in intended
        int256 lastCumulativeFundingRate;
    }

    event UpdateMargin(address indexed owner, int256 amount);

    event UpdatePosition(address indexed owner, uint256 indexed symbolId, int256 volume, int256 cost, int256 lastCumulativeFundingRate);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function pool() external view returns (address);

    function totalMinted() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function setPool(address newPool) external;

    function getActiveSymbolIds() external view returns (uint256[] memory);

    function isActiveSymbolId(uint256 symbolId) external view returns (bool);

    function getNumPositionHolders(uint256 symbolId) external view returns (uint256);

    function addSymbolId(uint256 symbolId) external;

    function removeSymbolId(uint256 symbolId) external;

    function toggleCloseOnly(uint256 symbolId) external;

    function exists(address owner) external view returns (bool);

    function getMargin(address owner) external view returns (int256);

    function updateMargin(address owner, int256 margin) external;

    function addMargin(address owner, int256 delta) external;

    function getPosition(address owner, uint256 symbolId) external view returns (Position memory);

    function updatePosition(address owner, uint256 symbolId, Position memory position) external;

    function mint(address owner) external;

    function burn(address owner) external;

}
