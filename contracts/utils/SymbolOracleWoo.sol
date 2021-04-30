// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IOracle.sol';

contract SymbolOracleWoo is IOracle {

    /*
    Contract address: 0x6e1BDdF0a6463BE035e5952cf9bd17427758eD95
    Token address in kovan:
        WOO :   0xaAaAcedf439e3d75C37b4E05A3024AfD8BFafEc4
        USDT :  0xEC516b0db35DB6d88CA6dA042e169cC0Ca8F83D1
        BTC :   0x41eFfaE6346D02aCE2Ea9226FA8D7ECbf97C2a92
        BNB :   0xDB0c79ecE9B4A0D8AF6D26A63e40C25A9cd24a2b
        ETH :   0x9d23DdB7c17222508EBFF303517E71b0Ccf60019
    */

    address public immutable oracle;
    address public immutable token;
    uint256 public immutable delayAllowance;

    constructor (address oracle_, address token_, uint256 delayAllowance_) {
        oracle = oracle_;
        token = token_;
        delayAllowance = delayAllowance_;
    }

    // get price using the WooTrade on-chain oracle
    function getPrice() public override view returns (uint256) {
        (, uint256 price, bool isValid, bool isStale, uint256 timestamp) = IWooOracle(oracle).getPrice(token);
        require(isValid && !isStale && block.timestamp - timestamp <= delayAllowance,
                'SymbolHandlerWoo.getPrice: invalid price');
        return price;
    }

}


interface IWooOracle {
    function getPrice(address base) external view returns (
        string memory symbol,
        uint256 price,
        bool isValid,
        bool isStale,
        uint256 timestamp
    );
}
