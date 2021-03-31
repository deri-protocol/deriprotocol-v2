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
        require(msg.sender == pool, 'PToken: only pool');
        _;
    }

    modifier _existsOwner_(address owner) {
        require(_exists(owner), 'PToken: nonexistent owner');
        _;
    }

    modifier _validSymbolId_(uint256 symbolId) {
        require(symbolId < numSymbols, 'PToken: invalid symbolId');
        _;
    }

    modifier _validBTokenId_(uint256 bTokenId) {
        require(bTokenId < numBTokens, 'PToken: invalid bTokenId');
        _;
    }

    constructor () {
        pool = msg.sender;
    }

    function initialize(string memory _name, string memory _symbol, uint256 _numSymbols, uint256 _numBTokens, address _pool) public {
        require(bytes(name).length == 0 && bytes(symbol).length == 0 && pool == address(0), 'PToken.initialize: already intialized');
        name = _name;
        symbol = _symbol;
        numSymbols = _numSymbols;
        numBTokens = _numBTokens;
        pool = _pool;
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

    function getMargin(address owner, uint256 bTokenId) public view _existsOwner_(owner) _validBTokenId_(bTokenId) returns (int256) {
        return _tokenIdPortfolio[_ownerTokenId[owner]].margins[bTokenId];
    }

    function getMargins(address owner) public view _existsOwner_(owner) returns (int256[] memory) {
        mapping (uint256 => int256) storage margins = _tokenIdPortfolio[_ownerTokenId[owner]].margins;
        int256[] memory res = new int256[](numBTokens);
        for (uint256 i = 0; i < numBTokens; i++) {
            res[i] = margins[i];
        }
        return res;
    }

    function getPosition(address owner, uint256 symbolId) public view _existsOwner_(owner) _validSymbolId_(symbolId) returns (Position memory) {
        return _tokenIdPortfolio[_ownerTokenId[owner]].positions[symbolId];
    }

    function getPositions(address owner) public view _existsOwner_(owner) returns (Position[] memory) {
        mapping (uint256 => Position) storage positions = _tokenIdPortfolio[_ownerTokenId[owner]].positions;
        Position[] memory res = new Position[](numSymbols);
        for (uint256 i = 0; i < numSymbols; i++) {
            res[i] = positions[i];
        }
        return res;
    }

    function mint(address owner, uint256 bTokenId, uint256 amount) public _pool_ _validBTokenId_(bTokenId) {
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

    function burn(address owner) public _pool_ _existsOwner_(owner) {
        uint256 tokenId = _ownerTokenId[owner];

        totalSupply -= 1;
        delete _ownerTokenId[owner];
        delete _tokenIdOwner[tokenId];
        delete _tokenIdPortfolio[tokenId];
        delete _tokenIdOperator[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    function addMargin(address owner, uint256 bTokenId, int256 amount) public _pool_ _existsOwner_(owner) _validBTokenId_(bTokenId) {
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.margins[bTokenId] += amount;
        emit UpdateMargin(owner, bTokenId, p.margins[bTokenId]);
    }

    function updateMargin(address owner, uint256 bTokenId, int256 amount) public _pool_ _existsOwner_(owner) _validBTokenId_(bTokenId) {
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.margins[bTokenId] = amount;
        emit UpdateMargin(owner, bTokenId, amount);
    }

    function updateMargins(address owner, int256[] memory margins) public _pool_ _existsOwner_(owner) {
        require(margins.length == numBTokens, 'PToken.updateMargins: invalid margins length');
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        for (uint256 i = 0; i < numBTokens; i++) {
            if (p.margins[i] != margins[i]) {
                p.margins[i] = margins[i];
                emit UpdateMargin(owner, i, margins[i]);
            }
        }
    }

    function updatePosition(address owner, uint256 symbolId, Position memory position) public _pool_ _existsOwner_(owner) _validSymbolId_(symbolId) {
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.positions[symbolId] = position;
        emit UpdatePosition(owner, symbolId, position.volume, position.cost, position.lastCumuFundingRate);
    }


    function _utoi(uint256 a) internal pure returns (int256) {
        require(a < 2**255, 'PToken.utoi: overflow');
        return int256(a);
    }

}
