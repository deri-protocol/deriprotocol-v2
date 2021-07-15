// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IVolatilityOracle.sol';

contract VolatilityOracleOffChain is IVolatilityOracle {

    string  public symbol;
    address public signatory;
    uint256 public delayAllowance;

    uint256 public timestamp;
    uint256 public volatility;

    constructor (string memory symbol_, address signatory_, uint256 delayAllowance_) {
        symbol = symbol_;
        signatory = signatory_;
        delayAllowance = delayAllowance_;
    }

    function setDelayAllowance(uint256 delayAllowance_) external {
        require(msg.sender == signatory, 'only signatory');
        delayAllowance = delayAllowance_;
    }

    function getVolatility() external override view returns (uint256) {
        require(block.timestamp - timestamp < delayAllowance, 'volatility expired');
        return volatility;
    }

    // update oracle volatility using off chain signed volatility
    // the signature must be verified in order for the volatility to be updated
    function updateVolatility(uint256 timestamp_, uint256 volatility_, uint8 v_, bytes32 r_, bytes32 s_) external override {
        uint256 lastTimestamp = timestamp;
        if (timestamp_ > lastTimestamp) {
            if (v_ == 27 || v_ == 28) {
                bytes32 message = keccak256(abi.encodePacked(symbol, timestamp_, volatility_));
                bytes32 hash = keccak256(abi.encodePacked('\x19Ethereum Signed Message:\n32', message));
                address signer = ecrecover(hash, v_, r_, s_);
                if (signer == signatory) {
                    timestamp = timestamp_;
                    volatility = volatility_;
                }
            }
        }
    }

}
