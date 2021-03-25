// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

library MixedSafeMathWithUnit {

    uint256 constant UONE = 10**18;
    uint256 constant UMAX = 2**255 - 1;

    int256 constant IONE = 10**18;
    int256 constant IMIN = -2**255;


    function utoi(uint256 a) internal pure returns (int256) {
        require(a <= UMAX, 'MixedSafeMathWithUnit.utoi: overflow');
        return int256(a);
    }

    function itou(int256 a) internal pure returns (uint256) {
        require(a >= 0, 'MixedSafeMathWithUnit.itou: overflow');
        return uint256(a);
    }

    function abs(int256 a) internal pure returns (int256) {
        require(a != IMIN, 'MixedSafeMathWithUnit.abs: overflow');
        return a >= 0 ? a : -a;
    }

    function neg(int256 a) internal pure returns (int256) {
        require(a != IMIN, 'MixedSafeMathWithUnit.neg: overflow');
        return -a;
    }


    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function add(int256 a, int256 b) internal pure returns (int256) {
        return a + b;
    }

    function add(uint256 a, int256 b) internal pure returns (uint256) {
        return b >= 0 ? a + uint256(b) : a - uint256(-b);
    }

    function add(int256 a, uint256 b) internal pure returns (int256) {
        return a + utoi(b);
    }


    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    function sub(int256 a, int256 b) internal pure returns (int256) {
        return a - b;
    }

    function sub(uint256 a, int256 b) internal pure returns (uint256) {
        return b >= 0 ? a - uint256(b) : a + uint256(-b);
    }

    function sub(int256 a, uint256 b) internal pure returns (int256) {
        return a - utoi(b);
    }


    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b / UONE;
    }

    function mul(int256 a, int256 b) internal pure returns (int256) {
        return a * b / IONE;
    }

    function mul(uint256 a, int256 b) internal pure returns (uint256) {
        return a * itou(b) / UONE;
    }

    function mul(int256 a, uint256 b) internal pure returns (int256) {
        return a * utoi(b) / IONE;
    }


    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * UONE / b;
    }

    function div(int256 a, int256 b) internal pure returns (int256) {
        return a * IONE / b;
    }

    function div(uint256 a, int256 b) internal pure returns (uint256) {
        return a * UONE / itou(b);
    }

    function div(int256 a, uint256 b) internal pure returns (int256) {
        return a * IONE / utoi(b);
    }


    function rescale(uint256 a, uint256 decimals1, uint256 decimals2) internal pure returns (uint256) {
        return a * (10 ** decimals2) / (10 ** decimals1);
    }

    function rescale(int256 a, uint256 decimals1, uint256 decimals2) internal pure returns (int256) {
        return a * utoi(10 ** decimals2) / utoi(10 ** decimals1);
    }

    function reformat(uint256 a, uint256 decimals) internal pure returns (uint256) {
        return rescale(rescale(a, 18, decimals), decimals, 18);
    }

    function reformat(int256 a, uint256 decimals) internal pure returns (int256) {
        return rescale(rescale(a, 18, decimals), decimals, 18);
    }

}
