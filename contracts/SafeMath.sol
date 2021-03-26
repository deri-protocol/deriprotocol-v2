// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

library SafeMath {

    uint256 constant UMAX = 2**255 - 1;
    int256  constant IMIN = -2**255;

    function utoi(uint256 a) internal pure returns (int256) {
        require(a <= UMAX, 'SafeMath.utoi: overflow');
        return int256(a);
    }

    function itou(int256 a) internal pure returns (uint256) {
        require(a >= 0, 'SafeMath.itou: overflow');
        return uint256(a);
    }

    function abs(int256 a) internal pure returns (int256) {
        require(a != IMIN, 'SafeMath.abs: overflow');
        return a >= 0 ? a : -a;
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
