// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/IPerpetualPool.sol';
import '../interface/IPToken.sol';
import '../interface/ILToken.sol';

contract PoolFactory {

    struct Symbol {
        string  symbol;
        address handlerAddress;
        int256  multiplier;
        int256  feeRatio;
        int256  fundingRateCoefficient;
    }

    struct BToken {
        address bTokenAddress;
        address handlerAddress;
        int256  discount;
    }

    struct Addresses {
        address perpetualPoolTemplate;
        address pTokenTemplate;
        address lTokenTemplate;
        address liquidatorQualifier;
        address dao;
        address poolController;
    }

    event Clone(address source, address target);

    event CreatePerpetualPool(address perpetualPool);

    address _controller;

    constructor () {
        _controller = msg.sender;
    }

    function controller() public view returns (address) {
        return _controller;
    }

    function setController(address newController) public {
        require(msg.sender == _controller, 'PoolFactory.setController: only controller');
        _controller = newController;
    }

    function clone(address source) public returns (address target) {
        require(msg.sender == _controller, 'PoolFactory.clone: only controller');
        bytes20 sourceBytes = bytes20(source);
        assembly {
            let c := mload(0x40)
            mstore(c, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(c, 0x14), sourceBytes)
            mstore(add(c, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            target := create(0, c, 0x37)
        }
        emit Clone(source, target);
    }

    function createPerpetualPool(
        Addresses memory addresses,
        Symbol[] memory symbols,
        BToken[] memory bTokens,
        int256[7] memory parameters
    ) public {
        require(msg.sender == _controller, 'PoolFactory.createPerpetualPool: only controller');

        // clone perpetualPool
        address perpetualPool = clone(addresses.perpetualPoolTemplate);

        // clone pToken and initialize
        address pToken = clone(addresses.pTokenTemplate);
        IPToken(pToken).initialize('DeriV2 Position Token', 'DPT', 0, 0, perpetualPool);

        // initialize perpetualPool
        address[4] memory poolAddresses = [
            pToken,
            addresses.liquidatorQualifier,
            addresses.dao,
            address(this)
        ];
        IPerpetualPool(perpetualPool).initialize(parameters, poolAddresses);

        // add bTokens
        for (uint256 i = 0; i < bTokens.length; i++) {
            IPerpetualPool.BTokenInfo memory b;

            address lToken = clone(addresses.lTokenTemplate);
            ILToken(lToken).initialize('DeriV2 Liquidity Token', 'DLT', perpetualPool);

            b.bTokenAddress = bTokens[i].bTokenAddress;
            b.lTokenAddress = lToken;
            b.handlerAddress = bTokens[i].handlerAddress;
            b.decimals = IERC20(bTokens[i].bTokenAddress).decimals();
            b.discount = bTokens[i].discount;
            b.price = 0;
            b.liquidity = 0;
            b.pnl = 0;

            IPerpetualPool(perpetualPool).addBToken(b);
        }

        // add symbols
        for (uint256 i = 0; i < symbols.length; i++) {
            IPerpetualPool.SymbolInfo memory s;

            s.symbol = symbols[i].symbol;
            s.handlerAddress = symbols[i].handlerAddress;
            s.multiplier = symbols[i].multiplier;
            s.feeRatio = symbols[i].feeRatio;
            s.fundingRateCoefficient = symbols[i].fundingRateCoefficient;
            s.price = 0;
            s.cumuFundingRate = 0;
            s.tradersNetVolume = 0;
            s.tradersNetCost = 0;

            IPerpetualPool(perpetualPool).addSymbol(s);
        }

        IPerpetualPool(perpetualPool).setNewController(addresses.poolController);

        emit CreatePerpetualPool(perpetualPool);
    }

}
