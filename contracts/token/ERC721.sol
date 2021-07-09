// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC721Receiver.sol';
import '../interface/IERC721.sol';
import '../library/Address.sol';
import './ERC165.sol';

/**
 * @dev ERC721 Non-Fungible Token Implementation
 *
 * Exert uniqueness of owner: one owner can only have one token
 */
contract ERC721 is IERC721, ERC165 {

    using Address for address;

    /*
     * Equals to `bytes4(keccak256('onERC721Received(address,address,uint256,bytes)'))`
     * which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
     */
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x081812fc ^ 0xe985e9c5 ^
     *        0x095ea7b3 ^ 0xa22cb465 ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    // Mapping from owner address to tokenId
    // tokenId starts from 1, 0 is reserved for nonexistent token
    // One owner can only own one token in this contract
    mapping (address => uint256) _ownerTokenId;

    // Mapping from tokenId to owner
    mapping (uint256 => address) _tokenIdOwner;

    // Mapping from tokenId to approved operator
    mapping (uint256 => address) _tokenIdOperator;

    // Mapping from owner to operator for all approval
    mapping (address => mapping (address => bool)) _ownerOperator;

    modifier _existsTokenId_(uint256 tokenId) {
        require(_exists(tokenId), 'ERC721: nonexistent tokenId');
        _;
    }

    modifier _existsOwner_(address owner) {
        require(_exists(owner), 'ERC721: nonexistent owner');
        _;
    }

    constructor () {
        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721);
    }

    function balanceOf(address owner) public override view returns (uint256) {
        return _exists(owner) ? 1 : 0;
    }

    function ownerOf(uint256 tokenId) public override view _existsTokenId_(tokenId) returns (address) {
        return _tokenIdOwner[tokenId];
    }

    function getTokenId(address owner) public override view _existsOwner_(owner) returns (uint256) {
        return _ownerTokenId[owner];
    }

    function getApproved(uint256 tokenId) public override view _existsTokenId_(tokenId) returns (address) {
        return _tokenIdOperator[tokenId];
    }

    function isApprovedForAll(address owner, address operator) public override view _existsOwner_(owner) returns (bool) {
        return _ownerOperator[owner][operator];
    }

    function approve(address operator, uint256 tokenId) public override {
        require(msg.sender == ownerOf(tokenId), 'ERC721.approve: caller not owner');
        _tokenIdOperator[tokenId] = operator;
        emit Approval(msg.sender, operator, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public override {
        require(_exists(msg.sender), 'ERC721.setApprovalForAll: nonexistent owner');
        _ownerOperator[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        _validateTransfer(msg.sender, from, to, tokenId);
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        safeTransferFrom(from, to, tokenId, '');
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        _validateTransfer(msg.sender, from, to, tokenId);
        _safeTransfer(from, to, tokenId, data);
    }

    //================================================================================

    function _exists(address owner) internal view returns (bool) {
        return _ownerTokenId[owner] != 0;
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _tokenIdOwner[tokenId] != address(0);
    }

    function _validateTransfer(address operator, address from, address to, uint256 tokenId) internal view {
        require(from == ownerOf(tokenId), 'ERC721._validateTransfer: not owned token');
        require(to != address(0) && !_exists(to), 'ERC721._validateTransfer: to address exists or 0');
        require(
            operator == from || _tokenIdOperator[tokenId] == operator || _ownerOperator[from][operator],
            'ERC721._validateTransfer: not owner nor approved'
        );
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        // clear previous ownership and approvals
        delete _ownerTokenId[from];
        delete _tokenIdOperator[tokenId];

        // set up new owner
        _ownerTokenId[to] = tokenId;
        _tokenIdOwner[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract
     * recipients are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Validation check on parameters should be carried out before calling this function.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, data),
            'ERC721: transfer to non ERC721Receiver implementer'
        );
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     *      The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID.
     * @param to target address that will receive the tokens.
     * @param tokenId uint256 ID of the token to be transferred.
     * @param data bytes optional data to send along with the call.
     * @return bool whether the call correctly returned the expected magic value.
     */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data)
        internal returns (bool)
    {
        if (!to.isContract()) {
            return true;
        }
        bytes memory returndata = to.functionCall(abi.encodeWithSelector(
            IERC721Receiver(to).onERC721Received.selector,
            msg.sender,
            from,
            tokenId,
            data
        ), 'ERC721: transfer to non ERC721Receiver implementer');
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == _ERC721_RECEIVED);
    }

}
