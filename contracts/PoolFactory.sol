// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './interface/IERC20.sol';
import './interface/ICloneFactory.sol';
import './interface/IPerpetualPool.sol';
import './interface/IPToken.sol';
import './interface/ILToken.sol';

contract PoolFactory {

    event CreatePerpetualPool(address perpetualPoolAddress);

    struct SymbolParams {
        string  symbol;
        address handlerAddress;
        int256  multiplier;
        int256  feeRatio;
        int256  fundingRateCoefficient;
    }

    struct BTokenParams {
        address bTokenAddress;
        address handlerAddress;
        int256  discount;
    }

    address public controller;

    address public cloneFactory;

    address public perpetualPoolTemplate;

    address public pTokenTemplate;

    address public lTokenTemplate;

    address public createdPerpetualPoolAddress;

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

    function setAddresses(address[4] calldata addresses) public _controller_ {
        cloneFactory = addresses[0];
        perpetualPoolTemplate = addresses[1];
        pTokenTemplate = addresses[2];
        lTokenTemplate = addresses[3];
    }

    function createPerpetualPool(
        SymbolParams[] calldata _symbols,
        BTokenParams[] calldata _bTokens,
        int256[] calldata _parameters,
        address _controller
    ) public _controller_ {
        address perpetualPool = ICloneFactory(cloneFactory).clone(perpetualPoolTemplate);

        address pToken = ICloneFactory(cloneFactory).clone(pTokenTemplate);
        IPToken(pToken).initialize('DeriV2 Position Token', 'DPT', _symbols.length, _bTokens.length, perpetualPool);

        address[] memory lTokens = new address[](_bTokens.length);
        for (uint256 i = 0; i < _bTokens.length; i++) {
            address lToken = ICloneFactory(cloneFactory).clone(lTokenTemplate);
            ILToken(lToken).initialize('DeriV2 Liquidity Token', 'DLT', perpetualPool);
            lTokens[i] = lToken;
        }

        IPerpetualPool.SymbolInfo[] memory symbols = new IPerpetualPool.SymbolInfo[](_symbols.length);
        for (uint256 i = 0; i < _symbols.length; i++) {
            symbols[i].symbol = _symbols[i].symbol;
            symbols[i].handlerAddress = _symbols[i].handlerAddress;
            symbols[i].multiplier = _symbols[i].multiplier;
            symbols[i].feeRatio = _symbols[i].feeRatio;
            symbols[i].fundingRateCoefficient = _symbols[i].fundingRateCoefficient;
            symbols[i].price = 0;
            symbols[i].cumuFundingRate = 0;
            symbols[i].tradersNetVolume = 0;
            symbols[i].tradersNetCost = 0;
        }

        IPerpetualPool.BTokenInfo[] memory bTokens = new IPerpetualPool.BTokenInfo[](_bTokens.length);
        for (uint256 i = 0; i < _bTokens.length; i++) {
            bTokens[i].bTokenAddress = _bTokens[i].bTokenAddress;
            bTokens[i].lTokenAddress = lTokens[i];
            bTokens[i].handlerAddress = _bTokens[i].handlerAddress;
            bTokens[i].decimals = IERC20(_bTokens[i].bTokenAddress).decimals();
            bTokens[i].discount = _bTokens[i].discount;
            bTokens[i].price = 0;
            bTokens[i].liquidity = 0;
            bTokens[i].pnl = 0;
        }

        IPerpetualPool(perpetualPool).initialize(symbols, bTokens, _parameters, pToken, _controller);

        createdPerpetualPoolAddress = perpetualPool;
        emit CreatePerpetualPool(createdPerpetualPoolAddress);
    }

}
