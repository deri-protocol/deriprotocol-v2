// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IERC721.sol';

interface IPToken is IERC721 {

    struct Position {
        int256 volume;
        int256 cost;
        int256 lastCumuFundingRate;
    }

    struct Portfolio {
        mapping (uint256 => Position) positions;    // symbolId indexed
        mapping (uint256 => int256) margins;        // bTokenId indexed
    }

    event UpdateMargin(address indexed owner, uint256 indexed bTokenId, int256 amount);

    event UpdatePosition(address indexed owner, uint256 indexed symbolId, int256 volume, int256 cost, int256 lastCumuFundingRate);

    function initialize(string memory _name, string memory _symbol, uint256 _numSymbols, uint256 _numBTokens, address _pool) external;

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function pool() external view returns (address);

    function totalMinted() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function numSymbols() external view returns (uint256);

    function numBTokens() external view returns (uint256);

    function setPool(address newPool) external;

    function setNumSymbols(uint256 num) external;

    function setNumBTokens(uint256 num) external;

    function exists(address owner) external view returns (bool);

    function getMargin(address owner, uint256 bTokenId) external view returns (int256);

    function getMargins(address owner) external view returns (int256[] memory);

    function getPosition(address owner, uint256 symbolId) external view returns (Position memory);

    function getPositions(address owner) external view returns (Position[] memory);

    function mint(address owner, uint256 bTokenId, uint256 amount) external;

    function burn(address owner) external;

    function addMargin(address owner, uint256 bTokenId, int256 amount) external;

    function updateMargin(address owner, uint256 bTokenId, int256 amount) external;

    function updateMargins(address owner, int256[] memory margins) external;

    function updatePosition(address owner, uint256 symbolId, Position memory position) external;

}
