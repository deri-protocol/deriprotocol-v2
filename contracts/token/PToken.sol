// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IPToken.sol';
import './ERC721.sol';

contract PToken is IPToken, ERC721 {

    string _name;

    string _symbol;

    address _pool;

    uint256 _totalMinted;

    uint256 _totalSupply;

    uint256 _numSymbols;

    uint256 _numBTokens;

    mapping (uint256 => Portfolio) private _tokenIdPortfolio;

    modifier _pool_() {
        require(msg.sender == _pool, 'PToken: only pool');
        _;
    }

    modifier _existsOwner_(address owner) {
        require(_exists(owner), 'PToken: nonexistent owner');
        _;
    }

    modifier _validSymbolId_(uint256 symbolId) {
        require(symbolId < _numSymbols, 'PToken: invalid symbolId');
        _;
    }

    modifier _validBTokenId_(uint256 bTokenId) {
        require(bTokenId < _numBTokens, 'PToken: invalid bTokenId');
        _;
    }

    constructor () {
        _pool = msg.sender;
    }

    function initialize(string memory name_, string memory symbol_, uint256 numSymbols_, uint256 numBTokens_, address pool_) public override {
        require(bytes(_name).length == 0 && bytes(_symbol).length == 0 && _pool == address(0), 'PToken.initialize: already intialized');
        _name = name_;
        _symbol = symbol_;
        _numSymbols = numSymbols_;
        _numBTokens = numBTokens_;
        _pool = pool_;
    }

    function name() public override view returns (string memory) {
        return _name;
    }

    function symbol() public override view returns (string memory) {
        return _symbol;
    }

    function pool() public override view returns (address) {
        return _pool;
    }

    function totalMinted() public override view returns (uint256) {
        return _totalMinted;
    }

    function totalSupply() public override view returns (uint256) {
        return _totalSupply;
    }

    function numSymbols() public override view returns (uint256) {
        return _numSymbols;
    }

    function numBTokens() public override view returns (uint256) {
        return _numBTokens;
    }

    function setPool(address newPool) public override _pool_ {
        require(newPool != address(0), 'PToken.setPool: to 0 address');
        _pool = newPool;
    }

    function setNumSymbols(uint256 num) public override _pool_ {
        require(num > _numSymbols, 'PToken.setNumSymbols: only allow increase');
        _numSymbols = num;
    }

    function setNumBTokens(uint256 num) public override _pool_ {
        require(num > _numBTokens, 'PToken.setNumBTokens: only allow increase');
        _numBTokens = num;
    }

    function exists(address owner) public override view returns (bool) {
        return _exists(owner);
    }

    function getMargin(address owner, uint256 bTokenId) public override view _existsOwner_(owner) _validBTokenId_(bTokenId) returns (int256) {
        return _tokenIdPortfolio[_ownerTokenId[owner]].margins[bTokenId];
    }

    function getMargins(address owner) public override view _existsOwner_(owner) returns (int256[] memory) {
        mapping (uint256 => int256) storage margins = _tokenIdPortfolio[_ownerTokenId[owner]].margins;
        int256[] memory res = new int256[](_numBTokens);
        for (uint256 i = 0; i < _numBTokens; i++) {
            res[i] = margins[i];
        }
        return res;
    }

    function getPosition(address owner, uint256 symbolId) public override view _existsOwner_(owner) _validSymbolId_(symbolId) returns (Position memory) {
        return _tokenIdPortfolio[_ownerTokenId[owner]].positions[symbolId];
    }

    function getPositions(address owner) public override view _existsOwner_(owner) returns (Position[] memory) {
        mapping (uint256 => Position) storage positions = _tokenIdPortfolio[_ownerTokenId[owner]].positions;
        Position[] memory res = new Position[](_numSymbols);
        for (uint256 i = 0; i < _numSymbols; i++) {
            res[i] = positions[i];
        }
        return res;
    }

    function mint(address owner, uint256 bTokenId, uint256 amount) public override _pool_ _validBTokenId_(bTokenId) {
        require(owner != address(0), 'PToken.mint: to 0 address');
        require(!_exists(owner), 'PToken.mint: to existent owner');

        _totalMinted += 1;
        _totalSupply += 1;
        uint256 tokenId = _totalMinted;
        require(!_exists(tokenId), 'PToken.mint: to existent tokenId');

        _ownerTokenId[owner] = tokenId;
        _tokenIdOwner[tokenId] = owner;
        Portfolio storage p = _tokenIdPortfolio[tokenId];
        p.margins[bTokenId] = _utoi(amount);

        emit UpdateMargin(owner, bTokenId, p.margins[bTokenId]);
        emit Transfer(address(0), owner, tokenId);
    }

    function burn(address owner) public override _pool_ _existsOwner_(owner) {
        uint256 tokenId = _ownerTokenId[owner];

        _totalSupply -= 1;
        delete _ownerTokenId[owner];
        delete _tokenIdOwner[tokenId];
        delete _tokenIdPortfolio[tokenId];
        delete _tokenIdOperator[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    function addMargin(address owner, uint256 bTokenId, int256 amount) public override _pool_ _existsOwner_(owner) _validBTokenId_(bTokenId) {
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.margins[bTokenId] += amount;
        emit UpdateMargin(owner, bTokenId, p.margins[bTokenId]);
    }

    function updateMargin(address owner, uint256 bTokenId, int256 amount) public override _pool_ _existsOwner_(owner) _validBTokenId_(bTokenId) {
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.margins[bTokenId] = amount;
        emit UpdateMargin(owner, bTokenId, amount);
    }

    function updateMargins(address owner, int256[] memory margins) public override _pool_ _existsOwner_(owner) {
        require(margins.length == _numBTokens, 'PToken.updateMargins: invalid margins length');
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        for (uint256 i = 0; i < _numBTokens; i++) {
            if (p.margins[i] != margins[i]) {
                p.margins[i] = margins[i];
                emit UpdateMargin(owner, i, margins[i]);
            }
        }
    }

    function updatePosition(address owner, uint256 symbolId, Position memory position) public override _pool_ _existsOwner_(owner) _validSymbolId_(symbolId) {
        Portfolio storage p = _tokenIdPortfolio[_ownerTokenId[owner]];
        p.positions[symbolId] = position;
        emit UpdatePosition(owner, symbolId, position.volume, position.cost, position.lastCumuFundingRate);
    }


    function _utoi(uint256 a) internal pure returns (int256) {
        require(a < 2**255, 'PToken.utoi: overflow');
        return int256(a);
    }

}
