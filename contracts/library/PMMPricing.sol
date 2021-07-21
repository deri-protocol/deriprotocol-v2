// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;


import {DecimalMath} from "../library/DecimalMath.sol";
import {PMMCurve} from "../library/PMMCurve.sol";
import {SafeMath} from "../library/SafeMath.sol";
import "../interface/IEverlastingOption.sol";


/**
 * @title Pricing
 * @author Deri Protocol
 *
 * @notice Parapara Pricing model
 */
contract PMMPricing {
    using SafeMath for uint256;
    using SafeMath for int256;

    function getTvMidPrice(int256 timePrice, int256 deltaB, int256 equity, uint256 K) external pure returns (int256) {
        if (equity <=0) {
            return timePrice;
        }
        IEverlastingOption.Side side = deltaB == 0 ? IEverlastingOption.Side.FLAT : (deltaB > 0 ? IEverlastingOption.Side.SHORT : IEverlastingOption.Side.LONG);
        IEverlastingOption.VirtualBalance memory updateBalance = getExpectedTargetExt(
            side, equity.itou(), timePrice.itou(), deltaB.abs().itou(), K
        );
        uint256 midPrice = getMidPrice(updateBalance, timePrice.itou(), K);
        return midPrice.utoi();
    }

    function queryTradePMM(int256 timePrice, int256 deltaB, int256 volume, int256 equity, uint256 K) external pure returns (int256) {
        IEverlastingOption.Side side = deltaB == 0 ? IEverlastingOption.Side.FLAT : (deltaB > 0 ? IEverlastingOption.Side.SHORT : IEverlastingOption.Side.LONG);
        IEverlastingOption.VirtualBalance memory updateBalance = getExpectedTargetExt(
            side, equity.itou(), timePrice.itou(), deltaB.abs().itou(), K
        );
        uint256 deltaQuote;
        int256 tvCost;
        if (volume >= 0) {
            deltaQuote = _queryBuyBaseToken(
                updateBalance, timePrice.itou(), K, volume.itou()
            );
            tvCost = deltaQuote.utoi();
        } else {
            deltaQuote = _querySellBaseToken(
                updateBalance, timePrice.itou(), K, (-volume).itou()
            );
            tvCost = -(deltaQuote.utoi());
        }
        return tvCost;
    }


    // ============ Helper functions ============
    function _expectedTargetHelperWhenBiased(
        IEverlastingOption.Side side,
        uint256 quoteBalance,
        uint256 price,
        uint256 deltaB,
        uint256 _K_
    ) internal pure returns (
        IEverlastingOption.VirtualBalance memory updateBalance
    ) {
        if (side == IEverlastingOption.Side.SHORT) {
            (updateBalance.baseTarget, updateBalance.quoteTarget) = PMMCurve._RegressionTargetWhenShort(quoteBalance, price, deltaB, _K_);
            updateBalance.baseBalance = updateBalance.baseTarget - deltaB;
            updateBalance.quoteBalance = quoteBalance;
            updateBalance.newSide = IEverlastingOption.Side.SHORT;
        }
        else if (side == IEverlastingOption.Side.LONG) {
            (updateBalance.baseTarget, updateBalance.quoteTarget) = PMMCurve._RegressionTargetWhenLong(quoteBalance, price, deltaB, _K_);
            updateBalance.baseBalance = updateBalance.baseTarget + deltaB;
            updateBalance.quoteBalance = quoteBalance;
            updateBalance.newSide = IEverlastingOption.Side.LONG;
        }
    }

    function _expectedTargetHelperWhenBalanced(uint256 quoteBalance, uint256 price) internal pure returns (
        IEverlastingOption.VirtualBalance memory updateBalance
    ) {
        uint256 baseTarget = DecimalMath.divFloor(quoteBalance, price);
        updateBalance.baseTarget = baseTarget;
        updateBalance.baseBalance = baseTarget;
        updateBalance.quoteTarget = quoteBalance;
        updateBalance.quoteBalance = quoteBalance;
        updateBalance.newSide = IEverlastingOption.Side.FLAT;
    }


    function getExpectedTargetExt(
        IEverlastingOption.Side side,
        uint256 quoteBalance,
        uint256 price,
        uint256 deltaB,
        uint256 _K_
    )
    public
    pure
    returns (IEverlastingOption.VirtualBalance memory) {
        if (side == IEverlastingOption.Side.FLAT) {
            return _expectedTargetHelperWhenBalanced(quoteBalance, price);
        }
        else {
            return _expectedTargetHelperWhenBiased(
                side,
                quoteBalance,
                price,
                deltaB,
                _K_);
        }
    }


    function getMidPrice(IEverlastingOption.VirtualBalance memory updateBalance, uint256 oraclePrice, uint256 K) public pure returns (uint256) {
        if (updateBalance.newSide == IEverlastingOption.Side.LONG) {
            uint256 R =
            DecimalMath.divFloor(
                updateBalance.quoteTarget * updateBalance.quoteTarget / updateBalance.quoteBalance,
                updateBalance.quoteBalance
            );
            R = DecimalMath.ONE - K + (DecimalMath.mul(K, R));
            return DecimalMath.divFloor(oraclePrice, R);
        } else {
            uint256 R =
            DecimalMath.divFloor(
                updateBalance.baseTarget * updateBalance.baseTarget / updateBalance.baseBalance,
                updateBalance.baseBalance
            );
            R = DecimalMath.ONE - K + (DecimalMath.mul(K, R));
            return DecimalMath.mul(oraclePrice, R);
        }
    }


    function _sellHelperRAboveOne(
        uint256 sellBaseAmount,
        uint256 K,
        uint256 price,
        uint256 baseTarget,
        uint256 baseBalance,
        uint256 quoteTarget
    ) internal pure returns (
        uint256 receiveQuote,
        IEverlastingOption.Side newSide,
        uint256 newDeltaB)
    {
        uint256 backToOnePayBase = baseTarget - baseBalance;

        // case 2: R>1
        // complex case, R status depends on trading amount
        if (sellBaseAmount < backToOnePayBase) {
            // case 2.1: R status do not change
            receiveQuote = PMMCurve._RAboveSellBaseToken(
                price,
                K,
                sellBaseAmount,
                baseBalance,
                baseTarget
            );
            newSide = IEverlastingOption.Side.SHORT;
            newDeltaB = backToOnePayBase - sellBaseAmount;
            uint256 backToOneReceiveQuote = PMMCurve._RAboveSellBaseToken(price, K, backToOnePayBase, baseBalance, baseTarget);
            if (receiveQuote > backToOneReceiveQuote) {
                // [Important corner case!] may enter this branch when some precision problem happens. And consequently contribute to negative spare quote amount
                // to make sure spare quote>=0, mannually set receiveQuote=backToOneReceiveQuote
                receiveQuote = backToOneReceiveQuote;
            }
        }
        else if (sellBaseAmount == backToOnePayBase) {
            // case 2.2: R status changes to ONE
            receiveQuote = PMMCurve._RAboveSellBaseToken(price, K, backToOnePayBase, baseBalance, baseTarget);
            newSide = IEverlastingOption.Side.FLAT;
            newDeltaB = 0;
        }
        else {
            // case 2.3: R status changes to BELOW_ONE
            {
                receiveQuote = PMMCurve._RAboveSellBaseToken(price, K, backToOnePayBase, baseBalance, baseTarget) + (
                    PMMCurve._ROneSellBaseToken(
                        price,
                        K,
                        sellBaseAmount - backToOnePayBase,
                        quoteTarget
                    )
                );
            }
            newSide = IEverlastingOption.Side.LONG;
            newDeltaB = sellBaseAmount - backToOnePayBase;
            // newDeltaB = sellBaseAmount.sub(_POOL_MARGIN_ACCOUNT.SIZE)?
        }
    }

    function _querySellBaseToken(IEverlastingOption.VirtualBalance memory updateBalance, uint256 price, uint256 K, uint256 sellBaseAmount)
    public pure
    returns (uint256 receiveQuote)
    {
        uint256 newDeltaB;
        IEverlastingOption.Side newSide;
        if (updateBalance.newSide == IEverlastingOption.Side.FLAT) {
            // case 1: R=1
            // R falls below one
            receiveQuote = PMMCurve._ROneSellBaseToken(price, K, sellBaseAmount, updateBalance.quoteTarget);
            newSide = IEverlastingOption.Side.LONG;
            newDeltaB = sellBaseAmount;
        }
        else if (updateBalance.newSide == IEverlastingOption.Side.SHORT) {
            (receiveQuote, newSide, newDeltaB) = _sellHelperRAboveOne(sellBaseAmount, K, price, updateBalance.baseTarget, updateBalance.baseBalance, updateBalance.quoteTarget);
        } else {
            // ACCOUNT._R_STATUS_() == IEverlastingOption.Side.LONG
            // case 3: R<1
            receiveQuote = PMMCurve._RBelowSellBaseToken(
                price,
                K,
                sellBaseAmount,
                updateBalance.quoteBalance,
                updateBalance.quoteTarget
            );
            newSide = IEverlastingOption.Side.LONG;
            newDeltaB = updateBalance.baseBalance - updateBalance.baseTarget + sellBaseAmount;
        }

//        // count fees
//        if (newSide == IEverlastingOption.Side.FLAT) {
//            newUpdateBalance = _expectedTargetHelperWhenBalanced(updateBalance.quoteBalance, price);
//        } else {
//            newUpdateBalance = _expectedTargetHelperWhenBiased(newSide, updateBalance.quoteBalance, price, newDeltaB, K);
//        }

        return receiveQuote;
    }

    // to avoid stack too deep
    function _buyHelperRBelowOne(
        uint256 buyBaseAmount,
        uint256 K,
        uint256 price,
        uint256 backToOneReceiveBase,
        uint256 baseTarget,
        uint256 quoteTarget,
        uint256 quoteBalance
    ) internal pure returns (
        uint256 payQuote,
        IEverlastingOption.Side newSide,
        uint256 newDeltaB
    ) {
        // case 3: R<1
        // complex case, R status may change
        if (buyBaseAmount < backToOneReceiveBase) {
            // case 3.1: R status do not change
            // no need to check payQuote because spare base token must be greater than zero
            payQuote = PMMCurve._RBelowBuyBaseToken(
                price,
                K,
                buyBaseAmount,
                quoteBalance,
                quoteTarget
            );

            newSide = IEverlastingOption.Side.LONG;
            newDeltaB = backToOneReceiveBase - buyBaseAmount;

        } else if (buyBaseAmount == backToOneReceiveBase) {
            // case 3.2: R status changes to ONE
            payQuote = PMMCurve._RBelowBuyBaseToken(price, K, backToOneReceiveBase, quoteBalance, quoteTarget);
            newSide = IEverlastingOption.Side.FLAT;
            newDeltaB = 0;
        } else {
            // case 3.3: R status changes to ABOVE_ONE
            uint256 addQuote = PMMCurve._ROneBuyBaseToken(
                price,
                K,
                buyBaseAmount - backToOneReceiveBase,
                baseTarget);
            payQuote = PMMCurve._RBelowBuyBaseToken(price, K, backToOneReceiveBase, quoteBalance, quoteTarget) + addQuote;
            newSide = IEverlastingOption.Side.SHORT;
            newDeltaB = buyBaseAmount - backToOneReceiveBase;
        }
    }


    function _queryBuyBaseToken(IEverlastingOption.VirtualBalance memory updateBalance, uint256 price, uint256 K, uint256 buyBaseAmount)
    public pure
    returns (uint256 payQuote)
    {
        uint256 newDeltaB;
        IEverlastingOption.Side newSide;
        {
            if (updateBalance.newSide == IEverlastingOption.Side.FLAT) {
                // case 1: R=1
                payQuote = PMMCurve._ROneBuyBaseToken(price, K, buyBaseAmount, updateBalance.baseTarget);
                newSide = IEverlastingOption.Side.SHORT;
                newDeltaB = buyBaseAmount;
            } else if (updateBalance.newSide == IEverlastingOption.Side.SHORT) {
                // case 2: R>1
                payQuote = PMMCurve._RAboveBuyBaseToken(
                    price,
                    K,
                    buyBaseAmount,
                    updateBalance.baseBalance,
                    updateBalance.baseTarget
                );
                newSide = IEverlastingOption.Side.SHORT;
                newDeltaB = updateBalance.baseTarget - updateBalance.baseBalance + buyBaseAmount;
            } else if (updateBalance.newSide == IEverlastingOption.Side.LONG) {
                (payQuote, newSide, newDeltaB) = _buyHelperRBelowOne(buyBaseAmount, K, price, updateBalance.baseBalance - updateBalance.baseTarget, updateBalance.baseTarget, updateBalance.quoteTarget, updateBalance.quoteBalance);
            }
        }
//        if (newSide == IEverlastingOption.Side.FLAT) {
//            newUpdateBalance = _expectedTargetHelperWhenBalanced(updateBalance.quoteBalance, price);
//        } else {
//            newUpdateBalance = _expectedTargetHelperWhenBiased(newSide, updateBalance.quoteBalance, price, newDeltaB, K);
//        }
        return payQuote;
    }

}
