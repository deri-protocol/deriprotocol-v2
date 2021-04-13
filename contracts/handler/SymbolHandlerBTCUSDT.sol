// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

contract SymbolHandlerBTCUSDT {

    // WooOracle BTCUSDT on Kovan
    address public constant pool = 0xBB51dC3843a371bc0B434EbD3255CFa894AC2506;
    address public constant base = 0x41eFfaE6346D02aCE2Ea9226FA8D7ECbf97C2a92;
    address public constant quote = 0xEC516b0db35DB6d88CA6dA042e169cC0Ca8F83D1;
    uint256 public constant delayAllowance = 100;

    function getPrice() public view returns (uint256) {
        (, , uint256 price, bool isValid, , uint256 timestamp) = IWooOracle(pool).getPrice(base, quote);
        require(isValid && block.timestamp - timestamp <= delayAllowance,
                'SymbolHandlerBTCUSDT.getPrice: invalid price');
        return price;
    }

}


interface IWooOracle {
    function getPrice(address base, address quote) external view returns (
        string memory baseSymbol,
        string memory quoteSymbol,
        uint256 lastestPrice,
        bool isValid,
        bool isStale,
        uint256 timestamp
    );
}
