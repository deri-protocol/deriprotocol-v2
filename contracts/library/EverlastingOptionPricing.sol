// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

library EverlastingOptionPricing {

    // 2^127
    uint128 private constant TWO127 = 0x80000000000000000000000000000000;
    // 2^128 - 1
    uint128 private constant TWO128_1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    // ln(2) * 2^128
    uint128 private constant LN2 = 0xb17217f7d1cf79abc9e3b39803f2f6af;

    int256 private constant ONE = 10**18;
    uint256 private constant UONE = 10**18;

    /*
     * Return index of most significant non-zero bit in given non-zero 256-bit
     * unsigned integer value.
     *
     * @param x value to get index of most significant non-zero bit in
     * @return index of most significant non-zero bit in given number
     */
    function mostSignificantBit (uint256 x) pure internal returns (uint8 r) {
        require (x > 0);

        if (x >= 0x100000000000000000000000000000000) {x >>= 128; r += 128;}
        if (x >= 0x10000000000000000) {x >>= 64; r += 64;}
        if (x >= 0x100000000) {x >>= 32; r += 32;}
        if (x >= 0x10000) {x >>= 16; r += 16;}
        if (x >= 0x100) {x >>= 8; r += 8;}
        if (x >= 0x10) {x >>= 4; r += 4;}
        if (x >= 0x4) {x >>= 2; r += 2;}
        if (x >= 0x2) r += 1; // No need to shift x anymore
    }

    /*
     * Calculate log_2 (x / 2^128) * 2^128.
     *
     * @param x parameter value
     * @return log_2 (x / 2^128) * 2^128
     */
    function _log_2 (uint256 x) pure internal returns (int256) {
        require (x > 0);

        uint8 msb = mostSignificantBit (x);

        if (msb > 128) x >>= msb - 128;
        else if (msb < 128) x <<= 128 - msb;

        x &= TWO128_1;

        int256 result = (int256 (uint256(msb)) - 128) << 128; // Integer part of log_2

        int256 bit = int256(uint256(TWO127));
        for (uint8 i = 0; i < 128 && x > 0; i++) {
            x = (x << 1) + ((x * x + TWO127) >> 128);
            if (x > TWO128_1) {
                result |= bit;
                x = (x >> 1) - TWO127;
            }
            bit >>= 1;
        }

        return result;
    }

    /*
     * Calculate ln (x / 2^128) * 2^128.
     *
     * @param x parameter value
     * @return ln (x / 2^128) * 2^128
     */
    function _ln (uint256 x) pure internal returns (int256) {
        require (x > 0);

        int256 l2 = _log_2 (x);
        if (l2 == 0) return 0;
        else {
            uint256 al2 = uint256 (l2 > 0 ? l2 : -l2);
            uint8 msb = mostSignificantBit (al2);
            if (msb > 127) al2 >>= msb - 127;
            al2 = (al2 * LN2 + TWO127) >> 128;
            if (msb > 127) al2 <<= msb - 127;

            return l2 >= 0 ? int256(al2) : -int256(al2);
        }
    }

    // x in 18 decimals, return in 18 decimals
    function log_2(uint256 x) internal pure returns (int256) {
        int256 res = _log_2((x << 128) / 10**18);
        return (res * 10**18) >> 128;
    }

    // x in 18 decimals, return in 18 decimals
    function ln(uint256 x) internal pure returns (int256) {
        int256 res = _ln((x << 128) / 10**18);
        return (res * 10**18) >> 128;
    }

    // x in 18 decimals, y in 18 decimals
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = x / 2 + 1;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        y *= 10**9;
    }

    // x in 18 decimals, return in 18 decimals
    function ndf(int256 x) internal pure returns (int256) {
        // 1 / sqrt(2 * pi)
        int256 c = 398942280401432700;

        // x1 is 1/x, x3 is 1/x^3 ...
        int256 x1 = ONE * ONE / x;
        int256 x2 = x1 * ONE / x;
        int256 x3 = x1 * x2 / ONE;
        int256 x5 = x3 * x2 / ONE;
        int256 x7 = x5 * x2 / ONE;
        int256 x9 = x7 * x2 / ONE;

        int256 res = (x1 - x3 + x5 * 3 - x7 * 15 + x9 * 105) * c / ONE;
        return res;
    }

    function utoi(uint256 a) internal pure returns (int256) {
        require(a <= 2**255 - 1);
        return int256(a);
    }

    function itou(int256 a) internal pure returns (uint256) {
        require(a >= 0);
        return uint256(a);
    }

    // S: spot, in 18 decimals
    // K: strike, in 18 decimals
    // sigma: volatility, in 18 decimals
    // t: expiring period, in 18 decimals
    // iterations: divide iterations, P = P1 / 2 + P2 / 4 + P3 / 8 ...
    // return in 18 decimals
    function pricingCall(uint256 S, uint256 K, uint256 sigma, uint256 t, uint256 iterations) external pure returns (int256) {
        // ln(S/K)
        int256 lnSK = ln(S * UONE / K);

        int256 price;
        for (uint256 i = 1; i < iterations + 1; i++) {
            // sigma * sqrt(t * i)
            int256 sigmaT = utoi(sigma * sqrt(t * i) / UONE);
            int256 x1 = lnSK * ONE / sigmaT + sigmaT / 2;
            int256 x2 = lnSK * ONE / sigmaT - sigmaT / 2;

            price += (ndf(x1) * utoi(S) / ONE - ndf(x2) * utoi(K) / ONE) / utoi(2**i);
        }

        return price;
    }

    // S: spot, in 18 decimals
    // K: strike, in 18 decimals
    // sigma: volatility, in 18 decimals
    // t: expiring period, in 18 decimals
    // iterations: divide iterations, P = P1 / 2 + P2 / 4 + P3 / 8 ...
    // return in 18 decimals
    function pricingPut(uint256 S, uint256 K, uint256 sigma, uint256 t, uint256 iterations) external pure returns (int256) {
        // ln(S/K)
        int256 lnSK = ln(S * UONE / K);

        int256 price;
        for (uint256 i = 1; i < iterations + 1; i++) {
            // sigma * sqrt(t * i)
            int256 sigmaT = utoi(sigma * sqrt(t * i) / UONE);
            int256 x1 = -lnSK * ONE / sigmaT + sigmaT / 2;
            int256 x2 = -lnSK * ONE / sigmaT - sigmaT / 2;

            price += (ndf(x1) * utoi(K) / ONE - ndf(x2) * utoi(S) / ONE) / utoi(2**i);
        }

        return price;
    }

}
