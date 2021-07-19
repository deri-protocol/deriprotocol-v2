// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IEverlastingOptionPricing {

    function getEverlastingCallPrice(uint256 S, uint256 K, uint256 vol, uint256 t, uint256 iterations) external pure returns (int256);

    function getEverlastingPutPrice(uint256 S, uint256 K, uint256 vol, uint256 t, uint256 iterations) external pure returns (int256);

    /**
     * Everlasting option pricing with converge approximation
     *
     * convergePeriod: period to converge, option price expires at mid of this period will be used for
     * all components in this period
     *
     */
    function getEverlastingCallPriceConverge(uint256 S, uint256 K, uint256 vol, uint256 convergePeriod, uint256 iterations)
        external pure returns (int256);

    function getEverlastingPutPriceConverge(uint256 S, uint256 K, uint256 vol, uint256 convergePeriod, uint256 iterations)
        external pure returns (int256);

    /**
     * Everlasting option pricing with converge approximation, utilizing early stop
     */
    function getEverlastingCallPriceConvergeEarlyStop(uint256 S, uint256 K, uint256 vol, uint256 convergePeriod, uint256 accuracy)
        external pure returns (int256);

    function getEverlastingPutPriceConvergeEarlyStop(uint256 S, uint256 K, uint256 vol, uint256 convergePeriod, uint256 accuracy)
		external pure returns (int256);

}
