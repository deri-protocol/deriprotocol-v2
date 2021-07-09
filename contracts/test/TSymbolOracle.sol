// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

contract TSymbolOracle {

    string  public symbol;
    address public signatory;
    uint256 public timestamp;
    uint256 public price;

    constructor (string memory symbol_, address signatory_) {
        symbol = symbol_;
        signatory = signatory_;
    }

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function updatePrice(uint256 timestamp_, uint256 price_, uint8 v, bytes32 r, bytes32 s) external {
        if (timestamp_ > timestamp) {
            bytes32 message = keccak256(abi.encodePacked(symbol, timestamp_, price_));
            bytes32 hash = keccak256(abi.encodePacked('\x19Ethereum Signed Message:\n32', message));
            address signer = ecrecover(hash, v, r, s);
            require(signer == signatory, 'TSymbolOracle: invalid price signature');
            timestamp = timestamp_;
            price = price_;
        }
    }

    function getPrice() external view returns (uint256) {
        return price;
    }

}
