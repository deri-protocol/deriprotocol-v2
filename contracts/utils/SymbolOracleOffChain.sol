// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IOracleWithUpdate.sol';

contract SymbolOracleOffChain is IOracleWithUpdate {

    string  public symbol;
    address public immutable signatory;
    uint256 public immutable delayAllowance;

    uint256 public timestamp;
    uint256 public price;

    constructor (string memory symbol_, address signatory_, uint256 delayAllowance_) {
        symbol = symbol_;
        signatory = signatory_;
        delayAllowance = delayAllowance_;
    }

    function getPrice() public override view returns (uint256) {
        require(block.timestamp - timestamp <= delayAllowance, 'price expired');
        return price;
    }

    function updatePrice(uint256 timestamp_, uint256 price_, uint8 v_, bytes32 r_, bytes32 s_) public override {
        uint256 curTimestamp = timestamp;
        if (timestamp_ > curTimestamp) {
            if (v_ == 27 || v_ == 28) {
                bytes32 message = keccak256(abi.encodePacked(symbol, timestamp_, price_));
                bytes32 hash = keccak256(abi.encodePacked('\x19Ethereum Signed Message:\n32', message));
                address signer = ecrecover(hash, v_, r_, s_);
                if (signer == signatory) {
                    timestamp = timestamp_;
                    price = price_;
                }
            }
        }
    }

}
