// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/ICloneFactory.sol';
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
        address cloneFactory;
        address perpetualPoolTemplate;
        address pTokenTemplate;
        address lTokenTemplate;
        address liquidatorQualifier;
        address dao;
        address poolController;
    }

    event CreatePerpetualPool(address perpetualPoolAddress);

    address public controller;

    address public createdPerpetualPool;

    modifier _controller_() {
        require(msg.sender == controller, 'PoolFactory: only controller');
        _;
    }

    constructor () {
        controller = msg.sender;
    }

    function setController(address newController) public _controller_ {
        controller = newController;
    }

    function createPerpetualPool(
        Addresses memory addresses,
        Symbol[] memory symbols,
        BToken[] memory bTokens,
        int256[] memory parameters
    ) public _controller_ {
        address perpetualPool = ICloneFactory(addresses.cloneFactory).clone(addresses.perpetualPoolTemplate);

        address pToken = ICloneFactory(addresses.cloneFactory).clone(addresses.pTokenTemplate);
        IPToken(pToken).initialize('DeriV2 Position Token', 'DPT', 0, 0, perpetualPool);

        address[] memory _addresses = new address[](4);
        _addresses[0] = pToken;
        _addresses[1] = addresses.liquidatorQualifier;
        _addresses[2] = addresses.dao;
        _addresses[3] = addresses.poolController;

        address poolController = addresses.poolController;
        addresses.poolController = address(this);
        IPerpetualPool(perpetualPool).initialize(parameters, _addresses);

        for (uint256 i = 0; i < bTokens.length; i++) {
            IPerpetualPool.BTokenInfo memory b;

            address lToken = ICloneFactory(addresses.cloneFactory).clone(addresses.lTokenTemplate);
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

        IPerpetualPool(perpetualPool).setNewController(poolController);

        createdPerpetualPool = perpetualPool;
        emit CreatePerpetualPool(perpetualPool);
    }

}
