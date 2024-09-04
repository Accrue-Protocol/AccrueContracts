// SPDX:Lincense-Identifier: MIT

pragma solidity ^0.8.18;

import {Owned} from "solmate/auth/Owned.sol";

/**
 * @title InvInterestRateModel
 * @author Victor
 * @notice This contract is used to calculate the interest rate per block
 */
contract InvInterestRateModel is Owned {
    /*///////////////////////////////////////////////////////////////
                          STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private s_baseRatePerYear;
    uint256 private s_multiplierPerYear;
    uint256 private s_jumpMultiplierPerYear;
    uint256 private s_inflectionPoint;
    uint256 private s_smoothingFactor;
    uint256 private s_maxRatePerYear;
    uint256 private s_minRatePerYear;
    uint256 private immutable PRECISION = 1e18;

    /*///////////////////////////////////////////////////////////////
                          EVENTS
    //////////////////////////////////////////////////////////////*/

    event SetParams(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 inflectionPoint,
        uint256 smoothingFactor,
        uint256 maxRatePerYear,
        uint256 minRatePerYear
    );

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 inflectionPoint,
        uint256 smoothingFactor,
        uint256 maxRatePerYear,
        uint256 minRatePerYear,
        address owner
    ) Owned(owner) {
        s_baseRatePerYear = baseRatePerYear;
        s_multiplierPerYear = multiplierPerYear;
        s_jumpMultiplierPerYear = jumpMultiplierPerYear;
        s_inflectionPoint = inflectionPoint;
        s_smoothingFactor = smoothingFactor;
        s_maxRatePerYear = maxRatePerYear;
        s_minRatePerYear = minRatePerYear;
    }

    /*///////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the current borrow rate per block
     * @param totalLiquidity The total amount of liquidity in the market
     * @param totalBorrow The total amount of borrows in the market
     * @return The borrow rate percentage per block (in wei - 1e18)
     */
    function getBorrowRate(uint256 totalLiquidity, uint256 totalBorrow) external view returns (uint256) {
        // Get the utilization rate
        uint256 utilizationRate = _getUtilizationRate(totalLiquidity, totalBorrow);

        // Get the borrow rate per year
        uint256 preliminaryRate = s_baseRatePerYear;

        // Apply jump multiplier if utilization is above the inflection point
        if (utilizationRate < s_inflectionPoint) {
            preliminaryRate = preliminaryRate + (utilizationRate * s_multiplierPerYear) / PRECISION;
        } else {
            // Get the utilization rate above the inflection point
            uint256 excessUtilizationRate = utilizationRate - s_inflectionPoint;

            // Apply the jump multiplier
            preliminaryRate = preliminaryRate
                + ((s_inflectionPoint * s_multiplierPerYear + excessUtilizationRate * s_jumpMultiplierPerYear) / PRECISION);
        }

        // If preliminaryRate is below the minimum rate, set it to the minimum rate
        // If preliminaryRate is above the maximum rate, set it to the maximum rate
        // If preliminaryRate is between the minimum and maximum rate, set it to the preliminary rate
        uint256 rate = (preliminaryRate < s_minRatePerYear)
            ? s_minRatePerYear
            : (preliminaryRate > s_maxRatePerYear ? s_maxRatePerYear : preliminaryRate);

        // Computes a weighted average between `rate` and `baseRatePerYear`
        // using the `smoothingFactor` as the weight.
        // This smooths the transition between the rates so that large variations
        // in `rate` don't lead to abrupt changes in the final rate.
        return (rate * s_smoothingFactor + s_baseRatePerYear * (PRECISION - s_smoothingFactor)) / PRECISION;
    }

    function getBaseRatePerYear() external view returns (uint256) {
        return s_baseRatePerYear;
    }

    function getMultiplierPerYear() external view returns (uint256) {
        return s_multiplierPerYear;
    }

    function getJumpMultiplierPerYear() external view returns (uint256) {
        return s_jumpMultiplierPerYear;
    }

    function getInflectionPoint() external view returns (uint256) {
        return s_inflectionPoint;
    }

    function getSmoothingFactor() external view returns (uint256) {
        return s_smoothingFactor;
    }

    function getMaxRatePerYear() external view returns (uint256) {
        return s_maxRatePerYear;
    }

    function getMinRatePerYear() external view returns (uint256) {
        return s_minRatePerYear;
    }

    function getPrecision() external view returns (uint256) {
        return PRECISION;
    }

    /*///////////////////////////////////////////////////////////////
                          PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Calculates the utilization rate
     * @param totalLiquidity The total amount of liquidity in the market
     * @param totalBorrow The total amount of borrows in the market
     * @return The utilization rate (in wei - 1e18)
     */
    function _getUtilizationRate(uint256 totalLiquidity, uint256 totalBorrow) private pure returns (uint256) {
        if (totalLiquidity == 0) {
            return 0;
        }
        return (totalBorrow * PRECISION) / totalLiquidity;
    }

    /*///////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the parameters of the interest rate model
     * @param baseRatePerYear The base rate per year (in wei - 1e18)
     * @param multiplierPerYear The multiplier per year (in wei - 1e18)
     * @param jumpMultiplierPerYear The jump multiplier per year (in wei - 1e18)
     * @param inflectionPoint The inflection point (in wei - 1e18)
     * @param smoothingFactor The smoothing factor (in wei - 1e18)
     * @param maxRatePerYear The maximum rate per year (in wei - 1e18)
     * @param minRatePerYear The minimum rate per year (in wei - 1e18)
     * @dev Only callable by the owner
     */
    function setParams(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 inflectionPoint,
        uint256 smoothingFactor,
        uint256 maxRatePerYear,
        uint256 minRatePerYear
    ) external onlyOwner {
        s_baseRatePerYear = baseRatePerYear;
        s_multiplierPerYear = multiplierPerYear;
        s_jumpMultiplierPerYear = jumpMultiplierPerYear;
        s_inflectionPoint = inflectionPoint;
        s_smoothingFactor = smoothingFactor;
        s_maxRatePerYear = maxRatePerYear;
        s_minRatePerYear = minRatePerYear;

        emit SetParams(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            inflectionPoint,
            smoothingFactor,
            maxRatePerYear,
            minRatePerYear
        );
    }
}
