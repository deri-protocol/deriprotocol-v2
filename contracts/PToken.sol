// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './ERC721.sol';

contract PToken is ERC721 {

    event UpdateMargin(address indexed owner, uint256 indexed bTokenId, int256 amount);

    event UpdatePosition(address indexed owner, uint256 indexed symbolId, int256 volume, int256 cost, int256 lastCumuFundingRate);

    struct Position {
        int256 volume;
        int256 cost;
        int256 lastCumuFundingRate;
    }

    struct Portfolio {
        mapping (uint256 => Position) positions;    // symbolId indexed
        mapping (uint256 => int256) margins;        // bTokenId indexed
        uint256 lastUpdateTimestamp;
    }

    string public name;

    string public symbol;

    address public pool;

    uint256 public totalMinted;

    uint256 public totalSupply;

    uint256 public numSymbols;

    uint256 public numBTokens;

    mapping (uint256 => Portfolio) private _tokenIdPortfolio;

    modifier _pool_() {
        require(msg.sender == pool, 'PToken._pool_: only pool');
        _;
    }

    constructor (string memory _name, string memory _symbol, address _pool, uint256 _numSymbols, uint256 _numBTokens) {
        require(_pool != address(0), 'PToken.constructor: 0 pool address');
        name = _name;
        symbol = _symbol;
        pool = _pool;
        numSymbols = _numSymbols;
        numBTokens = _numBTokens;
    }

    function setPool(address newPool) public _pool_ {
        require(newPool != address(0), 'PToken.setPool: to 0 address');
        pool = newPool;
    }

    function setNumSymbols(uint256 num) public _pool_ {
        require(num > numSymbols, 'PToken.setNumSymbols: cannot reduce numSymbols');
        numSymbols = num;
    }

    function setNumBTokens(uint256 num) public _pool_ {
        require(num > numBTokens, 'PToken.setNumBTokens: cannot reduce numBTokens');
        numBTokens = num;
    }

    function exists(address owner) public view returns (bool) {
        return _exists(owner);
    }

    function getMargin(address owner, uint256 bTokenId) public view returns (int256) {
        return _tokenIdPortfolio[_ownerTokenId[owner]].margins[bTokenId];
    }

    function getMargins(address owner) public view returns (int256[] memory) {
        mapping (uint256 => int256) storage margins = _tokenIdPortfolio[_ownerTokenId[owner]].margins;
        int256[] memory res = new int256[](numBTokens);
        for (uint256 i = 0; i < numBTokens; i++) {
            res[i] = margins[i];
        }
        return res;
    }

    function getPosition(address owner, uint256 symbolId) public view returns (Position memory) {
        return _tokenIdPortfolio[_ownerTokenId[owner]].positions[symbolId];
    }

    function getPositions(address owner) public view returns (Position[] memory) {
        mapping (uint256 => Position) storage positions = _tokenIdPortfolio[_ownerTokenId[owner]].positions;
        Position[] memory res = new Position[](numSymbols);
        for (uint256 i = 0; i < numSymbols; i++) {
            res[i] = positions[i];
        }
        return res;
    }

    function mint(address owner, uint256 bTokenId, uint256 amount) public _pool_ {
        require(owner != address(0), 'PToken.mint: to 0 address');
        require(!_exists(owner), 'PToken.mint: to existent owner');

        totalMinted += 1;
        totalSupply += 1;
        uint256 tokenId = totalMinted;
        require(!_exists(tokenId), 'PToken.mint: to existent tokenId');

        _ownerTokenId[owner] = tokenId;
        _tokenIdOwner[tokenId] = owner;
        Portfolio storage p = _tokenIdPortfolio[tokenId];
        p.margins[bTokenId] = _utoi(amount);

        emit UpdateMargin(owner, bTokenId, p.margins[bTokenId]);
        emit Transfer(address(0), owner, tokenId);
    }

    function addMargin(address owner, uint256 bTokenId, int256 amount) public _pool_ {
        require(_exists(owner), 'PToken.addMargin: nonexistent owner');
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.margins[bTokenId] += amount;
        emit UpdateMargin(owner, bTokenId, p.margins[bTokenId]);
    }

    function updateMargin(address owner, uint256 bTokenId, int256 amount) public _pool_ {
        require(_exists(owner), 'PToken.updateMargin: nonexistent owner');
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.margins[bTokenId] = amount;
        emit UpdateMargin(owner, bTokenId, amount);
    }

    function updateMargins(address owner, int256[] memory margins) public _pool_ {
        require(_exists(owner), 'PToken.updateMargins: nonexistent owner');
        require(margins.length == numBTokens, 'PToken.updateMargins: invalid margins length');
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        for (uint256 i = 0; i < numBTokens; i++) {
            if (p.margins[i] != margins[i]) {
                p.margins[i] = margins[i];
                emit UpdateMargin(owner, i, margins[i]);
            }
        }
    }

    function updatePosition(address owner, uint256 symbolId, Position memory position) public _pool_ {
        require(_exists(owner), 'PToken.updatePosition: nonexistent owner');
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.positions[symbolId] = position;
        emit UpdatePosition(owner, symbolId, position.volume, position.cost, position.lastCumuFundingRate);
    }


    function _utoi(uint256 a) internal pure returns (int256) {
        require(a < 2**255, 'PToken.utoi: overflow');
        return int256(a);
    }

}
