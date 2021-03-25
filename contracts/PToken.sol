// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import './MixedSafeMathWithUnit.sol';
import './ERC721.sol';

contract PToken is ERC721 {

    using MixedSafeMathWithUnit for uint256;
    using MixedSafeMathWithUnit for int256;

    event UpdateMargin(address indexed owner, uint256 indexed baseId, int256 amount);

    event UpdatePosition(address indexed owner, uint256 indexed symbolId, int256 volume, int256 cost, int256 lastCumuFundingRate);

    struct Position {
        int256 volume;
        int256 cost;
        int256 lastCumuFundingRate;
    }

    struct Portfolio {
        Position[] positions; // symbolId indexed
        int256[] margins;    // baseId indexed
        uint256 lastUpdateTimestamp;
    }

    address public pool;

    uint256 public totalMinted;

    uint256 public totalSupply;

    uint256 public numSymbols;

    uint256 public numBases;

    mapping (uint256 => Portfolio) private _tokenIdPortfolio;

    modifier _pool_() {
        require(msg.sender == pool, 'PToken: only pool');
        _;
    }

    function exists(address owner) public view returns (bool) {
        return _exists(owner);
    }

    function getPosition(address owner, uint256 symbolId) public view returns (int256, int256, int256) {
        Position storage p = _tokenIdPortfolio[_ownerTokenId[owner]].positions[symbolId];
        return (p.volume, p.cost, p.lastCumuFundingRate);
    }

    function getMargin(address owner, uint256 baseId) public view returns (int256) {
        return _tokenIdPortfolio[_ownerTokenId[owner]].margins[baseId];
    }

    function mint(address owner, uint256 baseId, uint256 amount) public _pool_ {
        require(owner != address(0), 'PToken: mint to 0 address');
        require(!_exists(owner), 'PToken: mint to existent owner');

        totalMinted += 1;
        totalSupply += 1;
        uint256 tokenId = totalMinted;
        require(!_exists(tokenId), 'PToken: mint to existent tokenId');

        _ownerTokenId[owner] = tokenId;
        _tokenIdOwner[tokenId] = owner;
        Portfolio storage p = _tokenIdPortfolio[tokenId];

        p.margins[baseId] = amount.utoi();
        p.lastUpdateTimestamp = block.timestamp;

        emit Transfer(address(0), owner, tokenId);
        emit UpdateMargin(owner, baseId, amount.utoi());
    }

    function burn(address owner) public _pool_ {
        require(_exists(owner), 'PToken: burn nonexistent owner');
        uint256 tokenId = _ownerTokenId[owner];
        Portfolio storage p = _tokenIdPortfolio[tokenId];

        for (uint256 i = 0; i < numSymbols; i++) {
            require(p.positions[i].volume == 0, 'PToken: burn non empty token');
        }

        totalSupply -= 1;

        for (uint256 i = 0; i < numBases; i++) {
            if (p.margins[i] != 0) {
                emit UpdateMargin(owner, i, 0);
            }
        }

        delete _ownerTokenId[owner];
        delete _tokenIdOwner[tokenId];
        delete _tokenIdOperator[tokenId];
        delete _tokenIdPortfolio[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    function updateMargin(address owner, uint256 baseId, int256 amount) public _pool_ {
        require(_exists(owner), 'PToken: update nonexistent token');
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];

        p.margins[baseId] = amount;
        p.lastUpdateTimestamp = block.timestamp;

        emit UpdateMargin(owner, baseId, amount);
    }

    function updatePosition(address owner, uint256 symbolId, int256 volume, int256 cost, int256 lastCumuFundingRate) public _pool_ {
        require(_exists(owner), 'PToken: update nonexistent token');
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];

        p.positions[symbolId].volume = volume;
        p.positions[symbolId].cost = cost;
        p.positions[symbolId].lastCumuFundingRate = lastCumuFundingRate;
        p.lastUpdateTimestamp = block.timestamp;

        emit UpdatePosition(owner, symbolId, volume, cost, lastCumuFundingRate);
    }

}
