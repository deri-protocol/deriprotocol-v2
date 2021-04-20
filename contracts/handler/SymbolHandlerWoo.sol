// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

contract SymbolHandlerWoo {

    address public immutable pair;
    address public immutable quote;
    address public immutable base;
    uint256 public immutable delayAllowance;

    constructor (
        address pair_,
        address quote_,
        address base_,
        uint256 delayAllowance_
    ) {
        pair = pair_;
        quote = quote_;
        base = base_;
        delayAllowance = delayAllowance_;
    }

    function getPrice() public view returns (uint256) {
        (, , uint256 price, bool isValid, , uint256 timestamp) = IWooOracle(pair).getPrice(base, quote);
        require(isValid && (delayAllowance == 0 || block.timestamp - timestamp <= delayAllowance),
                'SymbolHandlerWoo: invalid price');
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
