// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IPToken.sol';
import './ERC721.sol';

contract PToken is IPToken, ERC721 {

    // PToken name
    string _name;
    // PToken symbol
    string _symbol;
    // associative pool address
    address _pool;
    // total number of PToken ever minted, this number will never decease
    uint256 _totalMinted;
    // total PTokens hold by all traders
    uint256 _totalSupply;
    // number of symbols
    uint256 _numSymbols;
    // number of bTokens
    uint256 _numBTokens;

    // tokenId => (bTokenId => Margin)
    mapping (uint256 => mapping (uint256 => int256)) _tokenIdMargins;
    // tokenId => (symbolId => Position)
    mapping (uint256 => mapping (uint256 => Position)) _tokenIdPositions;

    modifier _pool_() {
        require(msg.sender == _pool, 'PToken: only pool');
        _;
    }

    constructor (string memory name_, string memory symbol_, uint256 numSymbols_, uint256 numBTokens_) {
        _name = name_;
        _symbol = symbol_;
        _numSymbols = numSymbols_;
        _numBTokens = numBTokens_;
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

    function numBTokens() public override view returns (uint256) {
        return _numBTokens;
    }

    function numSymbols() public override view returns (uint256) {
        return _numSymbols;
    }

    function setPool(address newPool) public override {
        require(_pool == address(0) || _pool == msg.sender, 'PToken.setPool: not allowed');
        _pool = newPool;
    }

    function setNumBTokens(uint256 num) public override _pool_ {
        require(num > _numBTokens, 'PToken.setNumBTokens: can only increase');
        _numBTokens = num;
    }

    function setNumSymbols(uint256 num) public override _pool_ {
        require(num > _numSymbols, 'PToken.setNumSymbols: can only increase');
        _numSymbols = num;
    }

    function exists(address owner) public override view returns (bool) {
        return _exists(owner);
    }

    function getMargin(address owner, uint256 bTokenId) public override view returns (int256) {
        return _tokenIdMargins[_ownerTokenId[owner]][bTokenId];
    }

    function getMargins(address owner) public override view returns (int256[] memory) {
        uint256 tokenId = _ownerTokenId[owner];
        uint256 length = _numBTokens;
        int256[] memory margins = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
            margins[i] = _tokenIdMargins[tokenId][i];
        }
        return margins;
    }

    function getPosition(address owner, uint256 symbolId) public override view returns (Position memory) {
        return _tokenIdPositions[_ownerTokenId[owner]][symbolId];
    }

    function getPositions(address owner) public override view returns (Position[] memory) {
        uint256 tokenId = _ownerTokenId[owner];
        uint256 length = _numSymbols;
        Position[] memory positions = new Position[](length);
        for (uint256 i = 0; i < length; i++) {
            positions[i] = _tokenIdPositions[tokenId][i];
        }
        return positions;
    }

    function updateMargin(address owner, uint256 bTokenId, int256 amount) public override _pool_ {
        _tokenIdMargins[_ownerTokenId[owner]][bTokenId] = amount;
        emit UpdateMargin(owner, bTokenId, amount);
    }

    function updateMargins(address owner, int256[] memory margins) public override _pool_ {
        uint256 tokenId = _ownerTokenId[owner];
        uint256 length = _numBTokens;
        for (uint256 i = 0; i < length; i++) {
            _tokenIdMargins[tokenId][i] = margins[i];
            emit UpdateMargin(owner, i, margins[i]);
        }
    }

    function updatePosition(address owner, uint256 symbolId, Position memory position) public override _pool_ {
        _tokenIdPositions[_ownerTokenId[owner]][symbolId] = position;
        emit UpdatePosition(owner, symbolId, position.volume, position.cost, position.lastCumulativeFundingRate);
    }

    function mint(address owner) public override _pool_ {
        _totalSupply++;
        uint256 tokenId = ++_totalMinted;
        require(!_exists(tokenId), 'PToken.mint: existent tokenId');

        _ownerTokenId[owner] = tokenId;
        _tokenIdOwner[tokenId] = owner;

        emit Transfer(address(0), owner, tokenId);
    }

    function burn(address owner) public override _pool_ {
        uint256 tokenId = _ownerTokenId[owner];

        _totalSupply--;
        delete _ownerTokenId[owner];
        delete _tokenIdOwner[tokenId];
        delete _tokenIdOperator[tokenId];

        uint256 length = _numBTokens;
        for (uint256 i = 0; i < length; i++) {
            delete _tokenIdMargins[tokenId][i];
        }

        length = _numSymbols;
        for (uint256 i = 0; i < length; i++) {
            delete _tokenIdPositions[tokenId][i];
        }

        emit Transfer(owner, address(0), tokenId);
    }

}
