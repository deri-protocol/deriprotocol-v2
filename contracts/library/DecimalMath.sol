// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import {SafeMath} from "./SafeMath.sol";

/**
 * @title DecimalMath
 * @author Deri Protocol
 *
 * @notice Functions for fixed point number with 18 decimals
 */
library DecimalMath {
    using SafeMath for uint256;

    uint256 constant ONE = 10**18;

    function mul(uint256 target, uint256 d) internal pure returns (uint256) {
        return target * d / ONE;
    }

    function mulCeil(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return (target * d).divCeil(ONE);
    }

    function divFloor(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return target * ONE / d;
    }

    function divCeil(uint256 target, uint256 d)
        internal
        pure
        returns (uint256)
    {
        return (target * ONE).divCeil(d);
    }
}
