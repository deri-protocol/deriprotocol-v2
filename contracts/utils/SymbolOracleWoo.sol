// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IOracle.sol';

contract SymbolOracleWoo is IOracle {

    /*
    Network: Kovan
    Contract address: 0xc995bD8a17f7582122FF1eBd1134142a573894a7
    Token address in Kovan:
    WOO : 0xaAaAcedf439e3d75C37b4E05A3024AfD8BFafEc4
    USDT : 0xEC516b0db35DB6d88CA6dA042e169cC0Ca8F83D1
    BTC : 0x41eFfaE6346D02aCE2Ea9226FA8D7ECbf97C2a92
    BNB : 0xDB0c79ecE9B4A0D8AF6D26A63e40C25A9cd24a2b
    ETH : 0x9d23DdB7c17222508EBFF303517E71b0Ccf60019

    Network: BSC testnet
    Contract address: 0x33Bc155b5d3d8eb8e0852F5E4d2D479684cbDBBB
    Token address in BSC testnet:
    WOO : 0x7C33c7330432874f3f2ed7A7014cB487e6023Ab1
    USDT : 0x3560816A4742F5649A023F57310cDa25FC83744a
    BTC : 0x8c75288F441d81E3Fb426F8a727B924d9f7d7845
    BNB : 0x5cb76e31aC5607f6A2e067189f1D7692D0414291
    ETH : 0x0e3B7545C0bec8FBfc649ed877906750Ff93ece6
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
    function getPrice() external override view returns (uint256) {
        (uint256 price, bool isValid, bool isStale, uint256 timestamp) = IWooOracle(oracle).getPrice(token);
        require(isValid && !isStale && block.timestamp - timestamp <= delayAllowance,
                'SymbolHandlerWoo.getPrice: invalid price');
        return price;
    }

}


interface IWooOracle {
    function getPrice(address base) external view returns (
        uint256 price,
        bool isValid,
        bool isStale,
        uint256 timestamp
    );
}
