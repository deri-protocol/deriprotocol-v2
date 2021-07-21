// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IPTokenOption.sol';
import './ERC721.sol';

contract PTokenOption is IPTokenOption, ERC721 {

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

    // tokenId => margin
    mapping (uint256 => int256) _tokenIdMargins;
    // tokenId => (symbolId => Position)
    mapping (uint256 => mapping (uint256 => Position)) _tokenIdPositions;

    // active symbolIds
    uint256[] _activeSymbolIds;
    // symbolId => bool
    mapping (uint256 => bool) _isActiveSymbolId;
    // symbolId => bool
    mapping (uint256 => bool) _isCloseOnly;
    // symbolId => number of position holders
    mapping (uint256 => uint256) _numPositionHolders;

    modifier _pool_() {
        require(msg.sender == _pool, 'PToken: only pool');
        _;
    }

    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
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

    function setPool(address newPool) public override {
        require(newPool != address(0), 'PToken: setPool to 0 address');
        require(_pool == address(0) || _pool == msg.sender, 'PToken.setPool: not allowed');
        _pool = newPool;
    }

    function getActiveSymbolIds() public override view returns (uint256[] memory) {
        return _activeSymbolIds;
    }

    function isActiveSymbolId(uint256 symbolId) public override view returns (bool) {
        return _isActiveSymbolId[symbolId];
    }

    function getNumPositionHolders(uint256 symbolId) public override view returns (uint256) {
        return _numPositionHolders[symbolId];
    }

    function addSymbolId(uint256 symbolId) public override _pool_ {
        require(!isActiveSymbolId(symbolId), 'PToken: symbolId already active');
        _activeSymbolIds.push(symbolId);
        _isActiveSymbolId[symbolId] = true;
    }

    function removeSymbolId(uint256 symbolId) public override _pool_ {
        require(isActiveSymbolId(symbolId), 'PToken: non-active symbolId');
        require(_numPositionHolders[symbolId] == 0, 'PToken: exists position holders');

        uint256 index;
        uint256 length = _activeSymbolIds.length;

        for (uint256 i = 0; i < length; i++) {
            if (_activeSymbolIds[i] == symbolId) {
                index = i;
                break;
            }
        }

        for (uint256 i = index; i < length - 1; i++) {
            _activeSymbolIds[i] = _activeSymbolIds[i+1];
        }

        _activeSymbolIds.pop();
        _isActiveSymbolId[symbolId] = false;
    }

    function toggleCloseOnly(uint256 symbolId) public override _pool_ {
        require(isActiveSymbolId(symbolId), 'PToken: inactive symbolId');
        _isCloseOnly[symbolId] = !_isCloseOnly[symbolId];
    }

    function exists(address owner) public override view returns (bool) {
        return _exists(owner);
    }

    function getMargin(address owner) public override view returns (int256) {
        return _tokenIdMargins[_ownerTokenId[owner]];
    }

    function updateMargin(address owner, int256 margin) public override _pool_ {
        _tokenIdMargins[_ownerTokenId[owner]] = margin;
        emit UpdateMargin(owner, margin);
    }

    function addMargin(address owner, int256 delta) public override _pool_ {
        int256 margin = _tokenIdMargins[_ownerTokenId[owner]] + delta;
        _tokenIdMargins[_ownerTokenId[owner]] = margin;
        emit UpdateMargin(owner, margin);
    }

    function getPosition(address owner, uint256 symbolId) public override view returns (Position memory) {
        return _tokenIdPositions[_ownerTokenId[owner]][symbolId];
    }

    function updatePosition(address owner, uint256 symbolId, Position memory position) public override _pool_ {
        int256 preVolume = _tokenIdPositions[_ownerTokenId[owner]][symbolId].volume;
        int256 curVolume = position.volume;

        if (preVolume == 0 && curVolume != 0) {
            _numPositionHolders[symbolId]++;
        } else if (preVolume != 0 && curVolume == 0) {
            _numPositionHolders[symbolId]--;
        }

        if (_isCloseOnly[symbolId]) {
            require(
                (preVolume >= 0 && curVolume >= 0 && preVolume >= curVolume) ||
                (preVolume <= 0 && curVolume <= 0 && preVolume <= curVolume),
                'PToken: close only'
            );
        }

        _tokenIdPositions[_ownerTokenId[owner]][symbolId] = position;
        emit UpdatePosition(owner, symbolId, position.volume, position.cost, position.lastCumulativeDeltaFundingRate, position.lastCumulativePremiumFundingRate);
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

        delete _tokenIdMargins[tokenId];

        uint256[] memory symbolIds = getActiveSymbolIds();
        for (uint256 i = 0; i < symbolIds.length; i++) {
            if (_tokenIdPositions[tokenId][symbolIds[i]].volume != 0) {
                _numPositionHolders[symbolIds[i]]--;
            }
            delete _tokenIdPositions[tokenId][symbolIds[i]];
        }

        emit Transfer(owner, address(0), tokenId);
    }

}
