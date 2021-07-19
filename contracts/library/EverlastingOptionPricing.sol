// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

contract EverlastingOptionPricing {

    // 2^127
    uint128 private constant TWO127 = 0x80000000000000000000000000000000;
    // 2^128 - 1
    uint128 private constant TWO128_1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    // ln(2) * 2^128
    uint128 private constant LN2 = 0xb17217f7d1cf79abc9e3b39803f2f6af;

    int128 private constant MAX_64x64 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    int256 private constant ONE = 10**18;
    uint256 private constant UONE = 10**18;
    int256 private constant E = 2718281828459045000;

    function utoi(uint256 a) internal pure returns (int256) {
        require(a <= 2**255 - 1);
        return int256(a);
    }

    function itou(int256 a) internal pure returns (uint256) {
        require(a >= 0);
        return uint256(a);
    }

    function abs(int256 a) internal pure returns (int256) {
        require(a >= -2**255);
        return a >= 0 ? a : -a;
    }

    function int256To128(int256 a) internal pure returns (int128) {
        require(a >= -2**127);
        require(a <= 2**127 - 1);
        return int128(a);
    }

    /*
     * Return index of most significant non-zero bit in given non-zero 256-bit
     * unsigned integer value.
     *
     * @param x value to get index of most significant non-zero bit in
     * @return index of most significant non-zero bit in given number
     */
    function mostSignificantBit (uint256 x) internal pure returns (uint8 r) {
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
    function _log_2 (uint256 x) internal pure returns (int256) {
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
    function _ln (uint256 x) internal pure returns (int256) {
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

    /**
     * Calculate binary exponent of x.  Revert on overflow.
     *
     * @param x signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function exp_2 (int128 x) internal pure returns (int128) {
        unchecked {
            require (x < 0x400000000000000000); // Overflow

            if (x < -0x400000000000000000) return 0; // Underflow

            uint256 result = 0x80000000000000000000000000000000;

            if (x & 0x8000000000000000 > 0)
                result = result * 0x16A09E667F3BCC908B2FB1366EA957D3E >> 128;
            if (x & 0x4000000000000000 > 0)
                result = result * 0x1306FE0A31B7152DE8D5A46305C85EDEC >> 128;
            if (x & 0x2000000000000000 > 0)
                result = result * 0x1172B83C7D517ADCDF7C8C50EB14A791F >> 128;
            if (x & 0x1000000000000000 > 0)
                result = result * 0x10B5586CF9890F6298B92B71842A98363 >> 128;
            if (x & 0x800000000000000 > 0)
                result = result * 0x1059B0D31585743AE7C548EB68CA417FD >> 128;
            if (x & 0x400000000000000 > 0)
                result = result * 0x102C9A3E778060EE6F7CACA4F7A29BDE8 >> 128;
            if (x & 0x200000000000000 > 0)
                result = result * 0x10163DA9FB33356D84A66AE336DCDFA3F >> 128;
            if (x & 0x100000000000000 > 0)
                result = result * 0x100B1AFA5ABCBED6129AB13EC11DC9543 >> 128;
            if (x & 0x80000000000000 > 0)
                result = result * 0x10058C86DA1C09EA1FF19D294CF2F679B >> 128;
            if (x & 0x40000000000000 > 0)
                result = result * 0x1002C605E2E8CEC506D21BFC89A23A00F >> 128;
            if (x & 0x20000000000000 > 0)
                result = result * 0x100162F3904051FA128BCA9C55C31E5DF >> 128;
            if (x & 0x10000000000000 > 0)
                result = result * 0x1000B175EFFDC76BA38E31671CA939725 >> 128;
            if (x & 0x8000000000000 > 0)
                result = result * 0x100058BA01FB9F96D6CACD4B180917C3D >> 128;
            if (x & 0x4000000000000 > 0)
                result = result * 0x10002C5CC37DA9491D0985C348C68E7B3 >> 128;
            if (x & 0x2000000000000 > 0)
                result = result * 0x1000162E525EE054754457D5995292026 >> 128;
            if (x & 0x1000000000000 > 0)
                result = result * 0x10000B17255775C040618BF4A4ADE83FC >> 128;
            if (x & 0x800000000000 > 0)
                result = result * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB >> 128;
            if (x & 0x400000000000 > 0)
                result = result * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9 >> 128;
            if (x & 0x200000000000 > 0)
                result = result * 0x10000162E43F4F831060E02D839A9D16D >> 128;
            if (x & 0x100000000000 > 0)
                result = result * 0x100000B1721BCFC99D9F890EA06911763 >> 128;
            if (x & 0x80000000000 > 0)
                result = result * 0x10000058B90CF1E6D97F9CA14DBCC1628 >> 128;
            if (x & 0x40000000000 > 0)
                result = result * 0x1000002C5C863B73F016468F6BAC5CA2B >> 128;
            if (x & 0x20000000000 > 0)
                result = result * 0x100000162E430E5A18F6119E3C02282A5 >> 128;
            if (x & 0x10000000000 > 0)
                result = result * 0x1000000B1721835514B86E6D96EFD1BFE >> 128;
            if (x & 0x8000000000 > 0)
                result = result * 0x100000058B90C0B48C6BE5DF846C5B2EF >> 128;
            if (x & 0x4000000000 > 0)
                result = result * 0x10000002C5C8601CC6B9E94213C72737A >> 128;
            if (x & 0x2000000000 > 0)
                result = result * 0x1000000162E42FFF037DF38AA2B219F06 >> 128;
            if (x & 0x1000000000 > 0)
                result = result * 0x10000000B17217FBA9C739AA5819F44F9 >> 128;
            if (x & 0x800000000 > 0)
                result = result * 0x1000000058B90BFCDEE5ACD3C1CEDC823 >> 128;
            if (x & 0x400000000 > 0)
                result = result * 0x100000002C5C85FE31F35A6A30DA1BE50 >> 128;
            if (x & 0x200000000 > 0)
                result = result * 0x10000000162E42FF0999CE3541B9FFFCF >> 128;
            if (x & 0x100000000 > 0)
                result = result * 0x100000000B17217F80F4EF5AADDA45554 >> 128;
            if (x & 0x80000000 > 0)
                result = result * 0x10000000058B90BFBF8479BD5A81B51AD >> 128;
            if (x & 0x40000000 > 0)
                result = result * 0x1000000002C5C85FDF84BD62AE30A74CC >> 128;
            if (x & 0x20000000 > 0)
                result = result * 0x100000000162E42FEFB2FED257559BDAA >> 128;
            if (x & 0x10000000 > 0)
                result = result * 0x1000000000B17217F7D5A7716BBA4A9AE >> 128;
            if (x & 0x8000000 > 0)
                result = result * 0x100000000058B90BFBE9DDBAC5E109CCE >> 128;
            if (x & 0x4000000 > 0)
                result = result * 0x10000000002C5C85FDF4B15DE6F17EB0D >> 128;
            if (x & 0x2000000 > 0)
                result = result * 0x1000000000162E42FEFA494F1478FDE05 >> 128;
            if (x & 0x1000000 > 0)
                result = result * 0x10000000000B17217F7D20CF927C8E94C >> 128;
            if (x & 0x800000 > 0)
                result = result * 0x1000000000058B90BFBE8F71CB4E4B33D >> 128;
            if (x & 0x400000 > 0)
                result = result * 0x100000000002C5C85FDF477B662B26945 >> 128;
            if (x & 0x200000 > 0)
                result = result * 0x10000000000162E42FEFA3AE53369388C >> 128;
            if (x & 0x100000 > 0)
                result = result * 0x100000000000B17217F7D1D351A389D40 >> 128;
            if (x & 0x80000 > 0)
                result = result * 0x10000000000058B90BFBE8E8B2D3D4EDE >> 128;
            if (x & 0x40000 > 0)
                result = result * 0x1000000000002C5C85FDF4741BEA6E77E >> 128;
            if (x & 0x20000 > 0)
                result = result * 0x100000000000162E42FEFA39FE95583C2 >> 128;
            if (x & 0x10000 > 0)
                result = result * 0x1000000000000B17217F7D1CFB72B45E1 >> 128;
            if (x & 0x8000 > 0)
                result = result * 0x100000000000058B90BFBE8E7CC35C3F0 >> 128;
            if (x & 0x4000 > 0)
                result = result * 0x10000000000002C5C85FDF473E242EA38 >> 128;
            if (x & 0x2000 > 0)
                result = result * 0x1000000000000162E42FEFA39F02B772C >> 128;
            if (x & 0x1000 > 0)
                result = result * 0x10000000000000B17217F7D1CF7D83C1A >> 128;
            if (x & 0x800 > 0)
                result = result * 0x1000000000000058B90BFBE8E7BDCBE2E >> 128;
            if (x & 0x400 > 0)
                result = result * 0x100000000000002C5C85FDF473DEA871F >> 128;
            if (x & 0x200 > 0)
                result = result * 0x10000000000000162E42FEFA39EF44D91 >> 128;
            if (x & 0x100 > 0)
                result = result * 0x100000000000000B17217F7D1CF79E949 >> 128;
            if (x & 0x80 > 0)
                result = result * 0x10000000000000058B90BFBE8E7BCE544 >> 128;
            if (x & 0x40 > 0)
                result = result * 0x1000000000000002C5C85FDF473DE6ECA >> 128;
            if (x & 0x20 > 0)
                result = result * 0x100000000000000162E42FEFA39EF366F >> 128;
            if (x & 0x10 > 0)
                result = result * 0x1000000000000000B17217F7D1CF79AFA >> 128;
            if (x & 0x8 > 0)
                result = result * 0x100000000000000058B90BFBE8E7BCD6D >> 128;
            if (x & 0x4 > 0)
                result = result * 0x10000000000000002C5C85FDF473DE6B2 >> 128;
            if (x & 0x2 > 0)
                result = result * 0x1000000000000000162E42FEFA39EF358 >> 128;
            if (x & 0x1 > 0)
                result = result * 0x10000000000000000B17217F7D1CF79AB >> 128;

            result >>= uint256 (int256 (63 - (x >> 64)));
            require (result <= uint256 (int256 (MAX_64x64)));

            return int128 (int256 (result));
        }
    }

    /**
     * Calculate natural exponent of x.  Revert on overflow.
     *
     * @param x signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function _exp (int128 x) internal pure returns (int128) {
        unchecked {
            require (x < 0x400000000000000000); // Overflow

            if (x < -0x400000000000000000) return 0; // Underflow

            return exp_2 (int128 (int256 (x) * 0x171547652B82FE1777D0FFDA0D23A7D12 >> 128));
        }
    }

    // x in 18 decimals, return in 18 decimals
    function exp(int256 x) internal pure returns (int256) {
        int128 res = _exp(int256To128((x << 64) / ONE));
        return (res * ONE) >> 64;
    }

    function integrateAB(int256 a, int256 b, int256 dx, int256 accuracy) internal pure returns (int256 A, int256 B) {
        int256 x = dx / 2;
        while (true) {
            int256 v1 = a * ONE / x;
            int256 v2 = b * x / ONE;
            int256 v3 = x * x / ONE;
            int256 v4 = -a * ONE / x * ONE / x;

            int256 fA = exp(-(v1 + v2) * (v1 + v2) / ONE / 2 - v3) * (v4 + b) / ONE;
            int256 fB = exp(-(v1 - v2) * (v1 - v2) / ONE / 2 - v3) * (v4 - b) / ONE;
            int256 deltaA = fA * dx / ONE;
            int256 deltaB = fB * dx / ONE;
            A += deltaA;
            B += deltaB;

            if (A != 0 && abs(deltaA * ONE / A) < accuracy && B != 0 && abs(deltaB * ONE / B) < accuracy) {
                break;
            }

            x += dx;
        }
    }

    function getEverlastingTimeValue(int256 S, int256 K, int256 V, int256 T) internal pure returns (int256) {
        int256 lnSK = ln(itou(S * ONE / K));
        int256 sqrtT = utoi(sqrt(itou(T)));
        int256 a = lnSK * ONE / V * ONE / sqrtT;
        int256 b = V * sqrtT / ONE / 2;

        int256 dx = ONE / 5;            // dx = 0.2
        int256 accuracy = ONE / 100;    // accuracy = 0.01
        (int256 A, int256 B) = integrateAB(a, b, dx, accuracy);

        return (S * A - K * B) / 2506628274631000064;   // sqrt(2 * pi)
    }

    function getEverlastingCallPrice(int256 S, int256 K, int256 V, int256 T) internal pure returns (int256) {
        int256 timeValue = getEverlastingTimeValue(S, K, V, T);
        return S > K ? S - K + timeValue : timeValue;
    }

    function getEverlastingPutPrice(int256 S, int256 K, int256 V, int256 T) internal pure returns (int256) {
        int256 timeValue = getEverlastingTimeValue(S, K, V, T);
        return K > S ? K - S + timeValue : timeValue;
    }

}
