// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/ILToken.sol';
import './ERC721.sol';

contract LToken is ILToken, ERC721 {

    // LToken name
    string _name;
    // LToken symbol
    string _symbol;
    // associative pool address
    address _pool;
    // total LToken ever minted, this number will never decease
    uint256 _totalMinted;
    // total LTokens hold by LPs
    uint256 _totalSupply;
    // number of bTokens
    uint256 _numBTokens;

    // tokenId => (bTokenId => Asset)
    mapping (uint256 => mapping (uint256 => Asset)) _tokenIdAssets;

    modifier _pool_() {
        require(msg.sender == _pool, 'LToken: only pool');
        _;
    }

    constructor (string memory name_, string memory symbol_, uint256 numBTokens_) {
        _name = name_;
        _symbol = symbol_;
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

    function setPool(address newPool) public override {
        require(_pool == address(0) || _pool == msg.sender, 'LToken.setPool: not allowed');
        _pool = newPool;
    }

    function setNumBTokens(uint256 num) public override _pool_ {
        require(num > _numBTokens, 'LToken.setNumBTokens: can only increase');
        _numBTokens = num;
    }

    function exists(address owner) public override view returns (bool) {
        return _exists(owner);
    }

    function getAsset(address owner, uint256 bTokenId) public override view returns (Asset memory) {
        return _tokenIdAssets[_ownerTokenId[owner]][bTokenId];
    }

    function getAssets(address owner) public override view returns (Asset[] memory) {
        uint256 tokenId = _ownerTokenId[owner];
        uint256 length = _numBTokens;
        Asset[] memory assets = new Asset[](length);
        for (uint256 i = 0; i < length; i++) {
            assets[i] = _tokenIdAssets[tokenId][i];
        }
        return assets;
    }

    function updateAsset(address owner, uint256 bTokenId, Asset memory asset) public override _pool_ {
        _tokenIdAssets[_ownerTokenId[owner]][bTokenId] = asset;
        emit UpdateAsset(
            owner,
            bTokenId,
            asset.liquidity,
            asset.pnl,
            asset.lastCumulativePnl
        );
    }

    function mint(address owner) public override _pool_ {
        _totalSupply++;
        uint256 tokenId = ++_totalMinted;
        require(!_exists(tokenId), 'LToken.mint: existent tokenId');

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
            delete _tokenIdAssets[tokenId][i];
        }

        emit Transfer(owner, address(0), tokenId);
    }

}
