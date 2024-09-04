// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {InvEngine} from "./InvEngine.sol";
import {InvInterestRateModel} from "./InvInterestRateModel.sol";
// import {IInvRewardManager} from "./Interfaces/IInvRewardManager.sol";

contract InvRewardManager is ReentrancyGuard, Owned {
    using SafeTransferLib for ERC20;

    /*///////////////////////////////////////////////////////////////
                          ERRORS & WARNINGS
    //////////////////////////////////////////////////////////////*/
    error INVRewardManager__CannotDepositZero();
    error INVRewardManager__CannotWithdrawZero();
    error INVRewardManager__CannotNotifyZeroInterest();
    error INVRewardManager__NotSuficientReward();

    /*///////////////////////////////////////////////////////////////
                          STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    struct UserDeposit {
        uint256 totalAmount; // Total depositado pelo usuário
        uint256 lastUpdate; // Último timestamp de atualização
        uint256 frozenRewards;
    }

    uint256 private constant PRECISION = 1e18;
    uint256 private constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60; // 31,536,000 seconds

    ERC20 private s_collateralToken;
    ERC20 private s_representativeToken;
    InvEngine private s_invEngine;
    InvInterestRateModel private s_interestRateModel;

    uint256 private s_totalSupply;
    uint256 private s_totalReward = 0;
    uint256 private s_liquidityIndex = 1e18;
    uint256 private s_supplyRate;
    uint256 private s_reserveFactor;

    uint256 private s_totalRewardAlreadyPaid;
    uint256 private s_totalInterestAlreadyPaid;
    uint256 private s_totalVirtualInterestAccumulated;
    uint256 private s_totalVirtualSupplyRewardAccumulated;
    uint256 private s_currentInterestPerSecond;
    uint256 private s_lastUpdatedInterestTimestamp;

    mapping(address => uint256) private s_lastUpdateDebtTimestamp;
    mapping(address user => uint256 amount) private s_unpaidUserInterest;
    mapping(address user => uint256 interest) private s_interests;
    mapping(address user => uint256 rewardClaimed) private s_rewardsClaimed;

    mapping(address => uint256) private s_userRewardPerTokenPaid;
    mapping(address => uint256) private s_rewards;
    mapping(address => uint256) private s_cumulativeTimeWeightedShare;
    mapping(address => UserDeposit) private userDeposits;

    /*///////////////////////////////////////////////////////////////
                         EVENTS & CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    event NotifyDeposit(address indexed receiver, uint256 amount);
    event NotifyWithdraw(address indexed receiver, uint256 amount);
    event GetReward(address indexed receiver, uint256 amount);
    event NotifyNewInterest(uint256 amount);

    constructor(
        address owner,
        address collateralToken,
        address invEngine,
        address interestRateModel,
        address representativeToken,
        uint256 reserveFactor
    ) Owned(owner) {
        s_collateralToken = ERC20(collateralToken);
        s_invEngine = InvEngine(invEngine);
        s_interestRateModel = InvInterestRateModel(interestRateModel);
        s_representativeToken = ERC20(representativeToken);
        s_reserveFactor = reserveFactor;
    }

    /*///////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Notifies the contract that an user has deposited some collateral
     * @param user The address of the user to notify deposit
     * @param amount The amount to notify deposit
     */
    function notifyDeposit(address user, uint256 amount) external onlyOwner {
        accrueInterest();

        if (amount == 0) {
            revert INVRewardManager__CannotDepositZero();
        }

        // get reward before update deposit data
        getReward(user);
        _updateDeposit(user, amount, true);

        emit NotifyDeposit(user, amount);
    }

    /**
     * @notice Notifies the contract that an user has withdrawn some collateral
     * @param user The address of the user to notify withdraw
     * @param amount The amount to notify withdraw
     */
    function notifyWithdraw(address user, uint256 amount) external onlyOwner {
        accrueInterest();

        if (amount == 0) {
            revert INVRewardManager__CannotWithdrawZero();
        }

        // get reward before update withdraw data
        getReward(user);
        _updateDeposit(user, amount, false);

        emit NotifyWithdraw(user, amount);
    }

    function totalSupply() external view returns (uint256) {
        return s_totalSupply;
    }

    function updateUserTimestamp(address user) external onlyOwner {
        s_lastUpdateDebtTimestamp[user] = block.timestamp;
    }

    /*///////////////////////////////////////////////////////////////
                         PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @todo turn this into onlyOwner
    function accrueInterest() public {
        address token = address(s_collateralToken);
        uint256 totalDebt = s_invEngine.getTotalInternalDebt(token);

        // If there's no debt, there's no interest to accrue
        if (totalDebt == 0) {
            return;
        }

        // Get current block timestamp
        uint256 currentTime = block.timestamp;

        // Get Interest info
        (
            uint256 interestAccrued,
            uint256 interestRatePerSecond,
            uint256 supplyRewardAccrued,
            uint256 supplyRatePerSecond
        ) = getAccumulatedInterest(token);

        // Update states
        s_supplyRate = supplyRatePerSecond;

        s_currentInterestPerSecond = interestRatePerSecond;
        s_totalVirtualInterestAccumulated += interestAccrued;
        s_totalVirtualSupplyRewardAccumulated += supplyRewardAccrued;
        s_lastUpdatedInterestTimestamp = currentTime;
    }

    function updateUserInterest(address user, uint256 amountUnpaid, uint256 amountPaid) public nonReentrant onlyOwner {
        s_unpaidUserInterest[user] = amountUnpaid;
        s_interests[user] = 0;
        s_totalInterestAlreadyPaid += amountPaid;
    }

    function snapshotInterestDue(address user) external onlyOwner {
        s_interests[user] = calculateUserInterestDue(user);
    }

    /**
     * @notice Gets the reward of an user
     * @param user The address of the user to get reward
     */
    function getReward(address user) public nonReentrant onlyOwner returns (uint256 reward) {
        UserDeposit storage deposit = userDeposits[user];
        uint256 rewardAvailable = getRewardAvailable();
        reward = earnedWithAccrue(user);

        if (reward > rewardAvailable) {
            uint256 rewardToBeFrozen = reward - rewardAvailable;
            s_rewardsClaimed[user] += rewardAvailable;
            s_totalRewardAlreadyPaid += rewardAvailable;
            deposit.lastUpdate = block.timestamp;
            deposit.frozenRewards = rewardToBeFrozen;

            // todo maybe we need to check if rewardAvailable is zero
            s_collateralToken.safeTransfer(user, rewardAvailable);

            emit GetReward(user, rewardAvailable);
        } else {
            s_rewardsClaimed[user] += reward;
            s_totalRewardAlreadyPaid += reward;
            deposit.lastUpdate = block.timestamp;
            deposit.frozenRewards = 0;

            s_collateralToken.safeTransfer(user, reward);

            emit GetReward(user, reward);
        }

        return reward;
    }

    /**
     * @notice This function is used to calculate the user interest due
     *         for a given token.
     * @param user The address of the user to check.
     * @return The user interest due.
     */
    function calculateUserInterestDue(address user) public returns (uint256) {
        address token = address(s_collateralToken);
        accrueInterest();

        uint256 userDebt = s_invEngine.getUserInternalDebt(user, token);
        uint256 deltaTime = block.timestamp - s_lastUpdateDebtTimestamp[user];

        // Calculate user interest using s_currentInterestPerSecond.
        uint256 userInterest = s_currentInterestPerSecond * deltaTime * userDebt / PRECISION;
        uint256 interest = userInterest + s_unpaidUserInterest[user] + s_interests[user];

        return interest;
    }

    function earnedWithAccrue(address user) public returns (uint256) {
        accrueInterest();
        uint256 reward = earned(user);

        return reward;
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _updateDeposit(address user, uint256 amount, bool isDeposit) internal {
        UserDeposit storage deposit = userDeposits[user];

        if (isDeposit) {
            deposit.totalAmount += amount;
            s_totalSupply += amount;
        } else {
            require(deposit.totalAmount >= amount, "Withdraw amount exceeds balance");

            deposit.totalAmount -= amount;
            s_totalSupply -= amount;
        }

        deposit.lastUpdate = block.timestamp;
    }

    /*///////////////////////////////////////////////////////////////
                         VIEWS & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @todo turn this into onlyOwner
    function getAccumulatedInterest(address token) public view returns (uint256, uint256, uint256, uint256) {
        uint256 totalLiquidity = s_invEngine.getTotalInternalBalances(token);
        uint256 totalDebt = s_invEngine.getTotalInternalDebt(token);
        uint256 utilizationRate = s_invEngine.getUtilization(token);
        // Get current block timestamp
        uint256 currentTime = block.timestamp;
        // Get the time difference since the last update for the given token
        uint256 secondsSinceLastUpdate = currentTime - s_lastUpdatedInterestTimestamp;

        // Get current rate
        uint256 annualInterestRate = s_interestRateModel.getBorrowRate(totalLiquidity, totalDebt);

        // Convert annual interest rate to rate per second
        uint256 interestRatePerSecond = annualInterestRate / SECONDS_PER_YEAR;
        uint256 supplyRate = annualInterestRate * utilizationRate / PRECISION;
        uint256 supplyRateLessReserveFactor = supplyRate * (PRECISION - s_reserveFactor) / PRECISION;
        uint256 supplyRatePerSecond = supplyRateLessReserveFactor / SECONDS_PER_YEAR;

        // Calculate accumulated interest without changing the state
        uint256 interestAccrued = interestRatePerSecond * secondsSinceLastUpdate * totalDebt / PRECISION;
        uint256 supplyRewardAccrued = supplyRatePerSecond * secondsSinceLastUpdate * s_totalSupply / PRECISION;

        return (interestAccrued, interestRatePerSecond, supplyRewardAccrued, supplyRatePerSecond);
    }

    function earned(address user) public view returns (uint256) {
        UserDeposit storage deposit = userDeposits[user];
        uint256 userBalance = deposit.totalAmount;
        uint256 deltaTime = block.timestamp - deposit.lastUpdate;

        uint256 userSupplyRate = s_supplyRate * deltaTime * userBalance / PRECISION;
        uint256 reward = userSupplyRate + deposit.frozenRewards;

        return reward;
    }

    /**
     * @notice This function is used to simulate the user interest due
     *         for a given token.
     * @param user The address of the user to check.
     * @return The user interest due.
     */
    function simulateUserInterestDue(address user) public view returns (uint256) {
        address token = address(s_collateralToken);

        uint256 userDebt = s_invEngine.getUserInternalDebt(user, token);
        uint256 deltaTime = block.timestamp - s_lastUpdateDebtTimestamp[user];

        // Calculate user interest using s_currentInterestPerSecond.
        uint256 userInterest = s_currentInterestPerSecond * deltaTime * userDebt / PRECISION;
        uint256 interest = userInterest + s_unpaidUserInterest[user] + s_interests[user];

        return interest;
    }

    /**
     * @notice Returns the total interest accumulated.
     * @return The total interest accumulated.
     */
    function getVirtualAccumulatedInterest() public view returns (uint256) {
        return s_totalVirtualInterestAccumulated;
    }

    /**
     * @notice Returns the reward available.
     * @return The total reward avaialable at the moment.
     */
    function getRewardAvailable() public view returns (uint256) {
        return s_collateralToken.balanceOf(address(this));
    }

    /**
     * @notice Returns the total interest accumulated.
     * @return The total interest accumulated.
     */
    function getVirtualAccumulatedSupplyReward() public view returns (uint256) {
        return s_totalVirtualSupplyRewardAccumulated;
    }

    /**
     * @notice Returns the current interest per second.
     * @return The current interest per second.
     */
    function getCurrentInterestPerSecond() external view returns (uint256) {
        return s_currentInterestPerSecond;
    }

    /**
     * @notice Returns the last updated interest timestamp.
     * @return The last updated interest timestamp.
     */
    function getLastUpdatedInterestTimestamp() external view returns (uint256) {
        return s_lastUpdatedInterestTimestamp;
    }

    /**
     * @notice Returns the current supply rate.
     * @return The last current supply rate.
     */
    function getSupplyRate() public view returns (uint256) {
        return s_supplyRate;
    }

    /**
     * @notice Returns the current reserve factor.
     * @return The last current reserve factor.
     */
    function getReserveFactor() external view returns (uint256) {
        return s_reserveFactor;
    }

    /**
     * @notice Returns the reward already claimed by the user.
     * @return The last total reward claimed by the user.
     */
    function getRewardsAlreadyClaimed(address user) external view returns (uint256) {
        return s_rewardsClaimed[user];
    }

    /**
     * @notice Returns the interest already paid.
     * @return The last total interest already paid by all the users.
     */
    function getTotalInterestAlreadyPaid() external view returns (uint256) {
        return s_totalInterestAlreadyPaid;
    }

    /**
     * @notice Returns the reward already paid.
     * @return The last total reward already paid by all the users.
     */
    function getTotalRewardAlreadyPaid() external view returns (uint256) {
        return s_totalRewardAlreadyPaid;
    }

    /**
     * @notice Returns the user info.
     * @return The user rewards and deposits info.
     */
    function getUserInfo(address user) external view returns (UserDeposit memory) {
        return userDeposits[user];
    }
}
