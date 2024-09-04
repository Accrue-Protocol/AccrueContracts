// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {DeployInv} from "../../script/DeployInv.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {InvToken} from "../../src/InvariantToken.sol";
import {InvEngine} from "../../src/InvEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {InvInterestRateModel} from "../../src/InvInterestRateModel.sol";
import {InvRewardManager} from "../../src/InvRewardManager.sol";

contract InvRewardManagerTest is Test {
    DeployInv deployer;
    InvToken invariantToken;
    InvEngine invEngine;
    HelperConfig config;

    // Configuration[] assetConfigurations;

    InvRewardManager wethRewardManager;
    InvRewardManager wbtcRewardManager;
    InvInterestRateModel baseInterestRateModel;

    address weth;
    address wethPriceFeed;
    address invEth;
    address wbtc;
    address wbtcPriceFeed;
    address invBtc;
    address interestRateModel;

    address public USER = makeAddr("user");
    address public USER2 = makeAddr("user2");
    address public USER3 = makeAddr("user3");
    address public USER4 = makeAddr("user4");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 20 ether;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint8 public constant DECIMALS = 8;
    int256 private constant NEW_WETH_PRICE = 1500e8;

    uint256 private s_reserveFactor = 2e17; // 20%

    struct Configuration {
        uint256 lendFactor;
        uint256 borrowFactor;
        uint256 liquidationThreshold;
        address interestRateModel;
        address rewardManager;
    }

    function setUp() public {
        deployer = new DeployInv();
        (invariantToken, invEngine, config, baseInterestRateModel, wethRewardManager, wbtcRewardManager) =
            deployer.run();
        (weth, wethPriceFeed, invEth, wbtc, wbtcPriceFeed, invBtc,) = config.activeNetworkConfig();

        // assetConfigurations = new Configuration[](2);
        // assetConfigurations[0] = Configuration(75, 0, 80, address(baseInterestRateModel), address(wethRewardManager));
        // assetConfigurations[1] = Configuration(75, 0, 80, address(baseInterestRateModel), address(wbtcRewardManager));

        // get interest rate model
        interestRateModel = invEngine.getConfiguration(weth).interestRateModel;

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(USER2, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER2, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(USER3, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER3, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(USER4, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER4, STARTING_USER_BALANCE);
    }

    /*///////////////////////////////////////////////////////////////
                          MODIFIERS 
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateralAndBorrowAfterSomePeriod() {
        uint256 amountToBorrow = 0.2 ether;
        uint256 expectedBorrowValue = 25000e18 * 0.05;

        vm.startPrank(USER2);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL - 1e18);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, amountToBorrow);
        vm.stopPrank();

        vm.startPrank(USER);

        vm.stopPrank();

        _;
    }

    /*///////////////////////////////////////////////////////////////
                        YIELD TESTS
    //////////////////////////////////////////////////////////////*/
    function testNotifyNewInterest() public {
        uint256 deposit = 1000e18;
        uint256 borrow = 1e18;
        InvRewardManager wbtcRewardManagerMock = new InvRewardManager(
            address(this), wbtc, address(invEngine), address(baseInterestRateModel), address(invBtc), s_reserveFactor
        );

        // wbtcRewardManagerMock.notifyNewInterest(deposit);

        // user supply wbtc
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL - 1e18);
        vm.stopPrank();
        wbtcRewardManagerMock.notifyDeposit(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER2);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL - 5e18);
        invEngine.borrow(wbtc, borrow);
        vm.stopPrank();
        wbtcRewardManagerMock.notifyDeposit(USER2, AMOUNT_COLLATERAL);

        wbtcRewardManagerMock.accrueInterest();

        uint256 currentTimestamp = block.timestamp;
        vm.warp(currentTimestamp + 182 days);

        vm.startPrank(USER);

        (uint256 earned) = wbtcRewardManagerMock.earned(USER);
        vm.stopPrank();
        // wbtcRewardManagerMock.notiffyNewInterest(deposit);
        vm.startPrank(USER);
        uint256 currentTimestamp2 = block.timestamp;
        vm.warp(currentTimestamp2 + 185 days);
        (uint256 earned2) = wbtcRewardManagerMock.earned(USER);
        console.log(earned2, "earned2earned2earned2");

        console.log(earned, earned2, "earned", earned2);
        // assert(rewardRate > 0);
        // assert(earned2 > 0);
        // assertEq(userBalance, deposit);
        // vm.warp(currentTimestamp + 100 days);
        vm.stopPrank();
    }

    function testNotifyDeposit() public {
        uint256 deposit = 1000e8;
        InvRewardManager wbtcRewardManagerMock = new InvRewardManager(
            address(this), wbtc, address(invEngine), address(baseInterestRateModel), address(invBtc), s_reserveFactor
        );

        wbtcRewardManagerMock.notifyDeposit(USER, deposit);
        uint256 currentTimestamp2 = block.timestamp;
        vm.warp(currentTimestamp2 + 185 days);
        (uint256 userEarn) = wbtcRewardManagerMock.earned(USER);
        wbtcRewardManagerMock.notifyDeposit(USER2, deposit);

        // wbtcRewardManagerMock.notifyNewInterest(deposit);
        (uint256 userEarnAfter) = wbtcRewardManagerMock.earned(USER);
        (uint256 user2Earn) = wbtcRewardManagerMock.earned(USER2);
        (uint256 totalSupply) = wbtcRewardManagerMock.totalSupply();

        console.log(userEarn, userEarnAfter, user2Earn, "userBalance");

        // assertEq(totalSupply, depfosit);
        // vm.warp(currentTimestamp + 100 days);f
    }

    function testInterestDueAfterRapeyLessThanDebt() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        uint256 currentTimestamp = block.timestamp;

        vm.startPrank(USER);

        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);

        // 1 day after
        vm.warp(currentTimestamp + 1 days);
        uint256 User2EarnedValue1DayAfter = wbtcRewardManager.earned(USER2);
        uint256 userInitialInterest = invEngine.getUserInterestDue(USER, wbtc);

        invEngine.borrow(wbtc, 0.2 ether);
        // invEngine.repay(wbtc, amountToPayToPayLessThanDebt);
        uint256 userFinalInterest = invEngine.getUserInterestDue(USER, wbtc);
        vm.warp(currentTimestamp + 2 days);
        uint256 userFinalInterestAtDayTwo = invEngine.getUserInterestDue(USER, wbtc);

        invEngine.supply(wbtc, 0.1 ether);
        uint256 userFinalInterestAtDayTwoAfterSupply = invEngine.getUserInterestDue(USER, wbtc);
        vm.warp(currentTimestamp + 3 days);
        uint256 userFinalInterestAtDayTwoAfterSupplyAfter1Day = invEngine.getUserInterestDue(USER, wbtc);
        uint256 amountToPayToPayLessThanDebt =
            userFinalInterestAtDayTwoAfterSupplyAfter1Day - userFinalInterestAtDayTwoAfterSupply;
        invEngine.repay(wbtc, amountToPayToPayLessThanDebt);
        uint256 userFinalInterestAtDayTwoAfterSupplyAfterRepay = invEngine.getUserInterestDue(USER, wbtc);

        assert(userFinalInterest < userFinalInterestAtDayTwo);
        assertEq(userInitialInterest, userFinalInterest);
        assertEq(
            userFinalInterestAtDayTwoAfterSupplyAfterRepay,
            userFinalInterestAtDayTwoAfterSupplyAfter1Day - amountToPayToPayLessThanDebt
        );
        assert(userFinalInterestAtDayTwoAfterSupplyAfterRepay < userFinalInterestAtDayTwoAfterSupplyAfter1Day);
        console.log(userInitialInterest, userFinalInterest, userFinalInterestAtDayTwo);
        console.log(
            userFinalInterestAtDayTwoAfterSupply,
            userFinalInterestAtDayTwoAfterSupplyAfter1Day,
            userFinalInterestAtDayTwoAfterSupplyAfterRepay
        );
        vm.stopPrank();
        // invEngine.borrow(wbtc, 1e16);
    }

    function testYield() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        uint256 currentTimestamp = block.timestamp;

        vm.startPrank(USER);
        // ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);

        // 1 day after
        vm.warp(currentTimestamp + 1 days);
        uint256 User2EarnedValue1DayAfter = wbtcRewardManager.earned(USER2);
        uint256 UserInterestToPay1DayAfter = invEngine.getUserInterestDue(USER, wbtc);
        vm.stopPrank();
        // invEngine.borrow(wbtc, 1e16);

        vm.startPrank(USER2);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, 1e17);
        uint256 User2EarnedValueAfterBorrow = wbtcRewardManager.earned(USER2);
        uint256 UserInterestToPay1DayAfterOtherUserBorrow = invEngine.getUserInterestDue(USER, wbtc);
        vm.warp(currentTimestamp + 2 days);
        // uint256 afterOtherUserGetBorrow = invEngine.getUserInterestDue(USER, wbtc);
        vm.stopPrank();

        vm.startPrank(USER);
        uint256 afterOtherUserGetBorrow2 = invEngine.getUserInterestDue(USER, wbtc);

        uint256 user2Interest = invEngine.getUserInterestDue(USER2, wbtc);

        // uint256 userInterest = invEngine.getUserInterestgetUserInterestDue(USER, wbtc);

        vm.warp(currentTimestamp + 366 days);
        uint256 userInterest1 = invEngine.getUserInterestDue(USER, wbtc);
        uint256 user2Interest2 = invEngine.getUserInterestDue(USER2, wbtc);

        // invEngine.claimYield(USER2, wbtc);
        (uint256 earned) = wbtcRewardManager.earned(USER2);
        (uint256 earnedUser1) = wbtcRewardManager.earned(USER);

        uint256 wbtcBalanceOfUser2 = ERC20(wbtc).balanceOf(address(USER2));
        // uint256 user2Yield = invEngine.getUserYield(USER2, wbtc);
        // uint256 userYield = invEngine.getUserYield(USER, wbtc);
        // console.log(beforeOtherUserGetBorrow, afterOtherUserGetBorrow, afterOtherUserGetBorrow2, userInterest1);
        console.log(
            User2EarnedValue1DayAfter,
            UserInterestToPay1DayAfter,
            "User2EarnedValue1DayAfter, UserInterestToPay1DayAfter"
        );
        console.log(
            User2EarnedValueAfterBorrow,
            UserInterestToPay1DayAfterOtherUserBorrow,
            "User2EarnedValueAfterBorrow, UserInterestToPay1DayAfterOtherUserBorrow"
        );
        console.log(earned, "user2eaner");
        vm.stopPrank();
    }

    function testEarn() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        uint256 currentTimestamp = block.timestamp;
        console.log(wbtcRewardManager.getVirtualAccumulatedInterest(), "accumulated interest before");

        // 1 day after
        vm.warp(currentTimestamp + 1 days);
        uint256 User2EarnedValue1DayAfter = wbtcRewardManager.earned(USER2);
        uint256 UserInterestToPay1DayAfter = invEngine.getUserInterestDue(USER, wbtc);
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), 0.1 ether);
        invEngine.repay(address(wbtc), 0.1 ether);
        uint256 interestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        uint256 User2EarnedValue1DayAfterAfterUser2Repay = wbtcRewardManager.earned(USER2);

        console.log(wbtcRewardManager.getVirtualAccumulatedInterest(), "accumulated interest");
        vm.stopPrank();

        // 3 days after
        vm.warp(currentTimestamp + 3 days);
        vm.startPrank(USER2);
        uint256 reward = invEngine.claimYield(USER2, address(wbtc));
        uint256 User2EarnedValue3DayAfter = wbtcRewardManager.earned(USER2);
        vm.stopPrank();

        uint256 UserInterestToPay3DayAfter = invEngine.getUserInterestDue(USER, wbtc);
        console.log(wbtcRewardManager.getVirtualAccumulatedInterest(), "accumulated interest after all");

        // invEngine.borrow(wbtc, 1e16);
        console.log(reward, "reward");
        console.log(User2EarnedValue1DayAfter, "User2EarnedValue1DayAfter");
        console.log(UserInterestToPay1DayAfter, "UserInterestToPay1DayAfter");
        console.log(User2EarnedValue1DayAfterAfterUser2Repay, "User2EarnedValue1DayAfterAfterUser2Repay");

        console.log(User2EarnedValue3DayAfter, "User2EarnedValue3DayAfterf");
        console.log(UserInterestToPay3DayAfter, "UserInterestToPay3DayAfter");
        console.log(interestDueAfterRepay, "interestDueAfterRepay");

        assertEq(User2EarnedValue1DayAfter, 0);
        assertEq(interestDueAfterRepay, 0);
    }

    /*///////////////////////////////////////////////////////////////
                        Interest Due TESTS
    //////////////////////////////////////////////////////////////*/
    function testInterestRemainsTheSameAfterSupply() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards

        vm.warp(block.timestamp + 1 days);
        uint256 userInterestToPayAfter1Day = invEngine.getUserInterestDue(USER, wbtc);

        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(address(wbtc), 1e18);
        uint256 userInterestToPayAfterSupply = invEngine.getUserInterestDue(USER, wbtc);
        vm.stopPrank();

        assertEq(userInterestToPayAfter1Day, userInterestToPayAfterSupply);

        vm.warp(block.timestamp + 1 days);
        uint256 userInterestToPay1DayAfterSupply = invEngine.getUserInterestDue(USER, wbtc);
        assert(userInterestToPay1DayAfterSupply > userInterestToPayAfterSupply);
        console.log(userInterestToPay1DayAfterSupply > userInterestToPayAfterSupply);
    }

    function testInterestDecreaseCorrectlyOnRepayAllInterestDue() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards

        vm.warp(block.timestamp + 1 days);
        // Interest to be paid by the user should increase as the days pass
        uint256 userInterestToPayAfter1Day = invEngine.getUserInterestDue(USER, wbtc);
        vm.warp(block.timestamp + 2 days);
        uint256 userInterestToPayAfter2Days = invEngine.getUserInterestDue(USER, wbtc);

        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), userInterestToPayAfter2Days);
        invEngine.repay(address(wbtc), userInterestToPayAfter2Days);
        vm.stopPrank();

        uint256 userInterestAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        assertEq(userInterestAfterRepay, 0);

        assert(userInterestToPayAfter1Day > 0);
        assert(userInterestToPayAfter2Days > userInterestToPayAfter1Day);
    }

    function testInterestDecreaseCorrectlyOnRepayPartialInterestDue()
        public
        depositedCollateralAndBorrowAfterSomePeriod
    {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards

        vm.warp(block.timestamp + 1 days);
        // Interest to be paid by the user should increase as the days pass
        uint256 userInterestToPayAfter1Day = invEngine.getUserInterestDue(USER, wbtc);
        console.log(userInterestToPayAfter1Day, "userInterestToPayAfter1Day");
        vm.warp(block.timestamp + 2 days);
        uint256 userInterestToPayAfter2Days = invEngine.getUserInterestDue(USER, wbtc);

        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), userInterestToPayAfter2Days);
        invEngine.repay(address(wbtc), userInterestToPayAfter2Days / 2);
        vm.stopPrank();

        uint256 userInterestAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        assertEq(userInterestAfterRepay, userInterestToPayAfter2Days / 2);

        assert(userInterestToPayAfter1Day > 0);
        assert(userInterestToPayAfter2Days > userInterestToPayAfter1Day);
        console.log(userInterestToPayAfter2Days, userInterestAfterRepay, "userInterestAfterRepay");
        vm.warp(block.timestamp + 5 minutes);
        // user interest here - 28987633138455
        uint256 userInterestToPayAfter5minutes = invEngine.getUserInterestDue(USER, wbtc);
        console.log(userInterestToPayAfter5minutes, "userInterestToPayAfter5minutes");
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), userInterestToPayAfter5minutes);
        invEngine.repay(address(wbtc), userInterestToPayAfter5minutes / 4);
        vm.stopPrank();

        uint256 userInterestAfterRepay5min = invEngine.getUserInterestDue(USER, wbtc);
        assertEq(userInterestAfterRepay5min, userInterestToPayAfter5minutes - (userInterestToPayAfter5minutes / 4));
    }

    function testInterestIncreaseOverTime() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards
        uint256 currentTimestamp = block.timestamp;

        vm.warp(currentTimestamp + 1 days);
        // Interest to be paid by the user should increase as the days pass
        uint256 userInterestToPayAfter1Day = invEngine.getUserInterestDue(USER, wbtc);
        vm.warp(currentTimestamp + 2 days);
        uint256 userInterestToPayAfter2Days = invEngine.getUserInterestDue(USER, wbtc);

        assert(userInterestToPayAfter1Day > 0);
        assert(userInterestToPayAfter2Days > userInterestToPayAfter1Day);
    }

    function testIsNoInterestDueAfterRepayment() public depositedCollateralAndBorrowAfterSomePeriod {
        // A user cannot have interest to pay if they have just made a repayment
        // and covered all outstanding debts or a sufficient amount
        // to settle the owed interest.
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(USER);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtBeforePayment = invEngine.getUserInternalDebt(USER, address(wbtc));
        ERC20Mock(wbtc).approve(address(invEngine), userInterestDue);

        invEngine.repay(address(wbtc), userInterestDue);

        uint256 userInterestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtAfterPayment = invEngine.getUserInternalDebt(USER, address(wbtc));

        assertEq(userInterestDueAfterRepay, 0);
        assertEq(userInternalDebtBeforePayment, userInternalDebtAfterPayment);

        vm.stopPrank();
    }

    function testIsInterestDueAfterInsufficientInterestRepayment() public depositedCollateralAndBorrowAfterSomePeriod {
        // A user cannot have interest to pay if they have just made a repayment
        // and covered all outstanding debts or a sufficient amount
        // to settle the owed interest.
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(USER);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtBeforePayment = invEngine.getUserInternalDebt(USER, address(wbtc));

        uint256 payLessThanInterest = userInterestDue / 2;
        ERC20Mock(wbtc).approve(address(invEngine), payLessThanInterest);

        invEngine.repay(address(wbtc), payLessThanInterest);

        uint256 userInterestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtAfterPayment = invEngine.getUserInternalDebt(USER, address(wbtc));

        assert(userInterestDue > userInterestDueAfterRepay);
        assertEq(userInterestDueAfterRepay, payLessThanInterest);
        assertEq(userInternalDebtBeforePayment, userInternalDebtAfterPayment);

        vm.stopPrank();
    }

    function testIsInterestDueAfterRepayAllDebtAndDoNewBorrow() public depositedCollateralAndBorrowAfterSomePeriod {
        // A user cannot have interest to pay if they have just made a repayment
        // and covered all outstanding debts or a sufficient amount
        // to settle the owed interest.
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(USER);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtBeforePayment = invEngine.getUserInternalDebt(USER, address(wbtc));
        uint256 quitLoanValue = userInternalDebtBeforePayment + userInterestDue;
        ERC20Mock(wbtc).approve(address(invEngine), quitLoanValue);

        invEngine.repay(address(wbtc), quitLoanValue);

        uint256 userInterestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtAfterPayment = invEngine.getUserInternalDebt(USER, address(wbtc));

        assertEq(userInterestDueAfterRepay, 0);
        assertEq(userInternalDebtAfterPayment, 0);

        invEngine.borrow(wbtc, quitLoanValue);
        vm.warp(block.timestamp + 1 days);
        uint256 newUserInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        console.log(newUserInterestDue);
        assert(newUserInterestDue > 0);

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                        Earn TESTS
    //////////////////////////////////////////////////////////////*/

    function testIfInterestDueIsAddedToBorrowAmount() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards

        // get paid interest at the moment
        vm.warp(block.timestamp + 1 days);
        uint256 paidInterestAfter1Day = wbtcRewardManager.getTotalInterestAlreadyPaid();
        assertEq(paidInterestAfter1Day, 0);

        // repay to get some paid interest
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, address(wbtc));
        invEngine.repay(address(wbtc), userInterestDue);
        vm.stopPrank();

        // get reward from claim
        uint256 rewardAvailableBeforeClaim = wbtcRewardManager.getRewardAvailable();
        uint256 earnedByUserBeforeClaim = wbtcRewardManager.earnedWithAccrue(USER2);
        invEngine.claimYield(USER2, address(wbtc));
        uint256 rewardAvailableAfterClaim = wbtcRewardManager.getRewardAvailable();
        uint256 earnedByUserAfterClaim = wbtcRewardManager.earnedWithAccrue(USER2);
        // reward available before claim should be equal to alread paid interest
        // assertEq(rewardAvailableBeforeClaim, paidInterestAfterRepay);
        // reward available after claim should be equal the rewardAvailableBeforeClaim less earnedByUserBeforeClaim
        assertEq(rewardAvailableBeforeClaim - earnedByUserBeforeClaim, rewardAvailableAfterClaim);
        assertEq(earnedByUserAfterClaim, 0);

        // console.log(paidInterestAfter1Day, "paidInterestAfter1Day");
        // console.log(paidInterestAfterRepay, "paidInterestAfterRepay");
        // console.log(rewardAvailableBeforeClaim, "rewardAvailableBeforeClaim");
        // console.log(rewardAvailableAfterClaim, "rewardAvailableAfterClaim");
        // console.log(earnedByUserBeforeClaim, "earnedByUserBeforeClaim");
        // console.log(earnedByUserAfterClaim, "earnedByUserAfterClaim");
    }

    function testIfUserFrozenRewardIsZeroAfterGetReward() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards

        // get paid interest at the moment
        vm.warp(block.timestamp + 1 days);
        uint256 paidInterestAfter1Day = wbtcRewardManager.getTotalInterestAlreadyPaid();
        assertEq(paidInterestAfter1Day, 0);

        // repay to get some paid interest
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, address(wbtc));
        invEngine.repay(address(wbtc), userInterestDue);
        vm.stopPrank();

        // check if it works
        uint256 paidInterestAfterRepay = wbtcRewardManager.getTotalInterestAlreadyPaid();
        assertEq(paidInterestAfterRepay, userInterestDue);

        // get reward from claim
        uint256 rewardAvailableBeforeClaim = wbtcRewardManager.getRewardAvailable();
        uint256 earnedByUserBeforeClaim = wbtcRewardManager.earnedWithAccrue(USER2);
        invEngine.claimYield(USER2, address(wbtc));
        uint256 rewardAvailableAfterClaim = wbtcRewardManager.getRewardAvailable();
        uint256 earnedByUserAfterClaim = wbtcRewardManager.earnedWithAccrue(USER2);
        // reward available before claim should be equal to alread paid interest
        assertEq(rewardAvailableBeforeClaim, paidInterestAfterRepay);
        // reward available after claim should be equal the rewardAvailableBeforeClaim less earnedByUserBeforeClaim
        assertEq(rewardAvailableBeforeClaim - earnedByUserBeforeClaim, rewardAvailableAfterClaim);
        assertEq(earnedByUserAfterClaim, 0);

        // console.log(paidInterestAfter1Day, "paidInterestAfter1Day");
        // console.log(paidInterestAfterRepay, "paidInterestAfterRepay");
        // console.log(rewardAvailableBeforeClaim, "rewardAvailableBeforeClaim");
        // console.log(rewardAvailableAfterClaim, "rewardAvailableAfterClaim");
        // console.log(earnedByUserBeforeClaim, "earnedByUserBeforeClaim");
        // console.log(earnedByUserAfterClaim, "earnedByUserAfterClaim");
    }

    function testIfUserFrozenRewardIsNotZeroAfterGetPartialReward()
        public
        depositedCollateralAndBorrowAfterSomePeriod
    {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards

        // get paid interest at the moment
        vm.warp(block.timestamp + 1 days);
        uint256 paidInterestAfter1Day = wbtcRewardManager.getTotalInterestAlreadyPaid();
        assertEq(paidInterestAfter1Day, 0);

        // repay to get some paid interest
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        uint256 earnedByUserBeforeClaim = wbtcRewardManager.earnedWithAccrue(USER2);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, address(wbtc));
        invEngine.repay(address(wbtc), earnedByUserBeforeClaim / 2);
        vm.stopPrank();

        // check if it works
        uint256 paidInterestAfterRepay = wbtcRewardManager.getTotalInterestAlreadyPaid();
        assertEq(paidInterestAfterRepay, earnedByUserBeforeClaim / 2);

        // get reward from claim
        invEngine.claimYield(USER2, address(wbtc));
        uint256 earnedByUserAfterClaim = wbtcRewardManager.earnedWithAccrue(USER2);
        assertEq(earnedByUserAfterClaim, earnedByUserBeforeClaim / 2);

        uint256 rewardAvailableAfterClaim = wbtcRewardManager.getRewardAvailable();
        assertEq(rewardAvailableAfterClaim, 0);
    }

    function testEarns() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards
        uint256 currentTimestamp = block.timestamp;

        (, uint256 interestRatePerSecond,, uint256 supplyRatePerSecond) =
            wbtcRewardManager.getAccumulatedInterest(address(wbtc));

        uint256 totalDebt = invEngine.getTotalInternalDebt(address(wbtc));
        uint256 totalLiquidity = invEngine.getTotalInternalBalances(address(wbtc));

        uint256 borrowRate = baseInterestRateModel.getBorrowRate(totalLiquidity, totalDebt);

        uint256 user2Earns = wbtcRewardManager.earned(USER2);
        vm.warp(currentTimestamp + 365 days);
        vm.startPrank(USER3);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 totalInterestAccumulated = wbtcRewardManager.getVirtualAccumulatedInterest();
        uint256 totalSupplyRateAccumulated = wbtcRewardManager.getVirtualAccumulatedSupplyReward();

        uint256 user2EarnsAfter100days = wbtcRewardManager.earned(USER2);
        uint256 user3Earns = wbtcRewardManager.earned(USER3);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, address(wbtc));
        console.log(totalInterestAccumulated, totalSupplyRateAccumulated, interestRatePerSecond, supplyRatePerSecond);
        console.log(user2Earns, user2EarnsAfter100days, user3Earns, userInterestDue);

        // assertEq(user2EarnsBeforeRepays, 0);
    }

    function testUserGainsWithNoInterestCollected() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards
        uint256 currentTimestamp = block.timestamp;

        vm.warp(currentTimestamp + 1 days);
        uint256 user2EarnsBeforeRepays = wbtcRewardManager.earned(USER2);

        assertEq(user2EarnsBeforeRepays, 0);
    }

    function testValidateEarningsNotExceedingAccumulatedInterest() public depositedCollateralAndBorrowAfterSomePeriod {
        // 1. TEST
        // The user's gains should be zero if no interest has been collected yet.
        vm.warp(block.timestamp + 1 days);
        uint256 user2EarnsBeforeRepays = wbtcRewardManager.earned(USER2);
        uint256 initialAccumulatedInterest = wbtcRewardManager.getVirtualAccumulatedInterest();

        assertEq(user2EarnsBeforeRepays, 0);
        assertEq(initialAccumulatedInterest, 0);

        // Another TEST
        // Earnings cannot exceed the total accumulated interest
        vm.startPrank(USER);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtBeforePayment = invEngine.getUserInternalDebt(USER, address(wbtc));
        ERC20Mock(wbtc).approve(address(invEngine), userInterestDue);

        invEngine.repay(address(wbtc), userInterestDue);

        uint256 userInterestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtAfterPayment = invEngine.getUserInternalDebt(USER, address(wbtc));

        assertEq(userInterestDueAfterRepay, 0);
        assertEq(userInternalDebtBeforePayment, userInternalDebtAfterPayment);

        vm.stopPrank();

        uint256 accumulatedInterest = wbtcRewardManager.getVirtualAccumulatedInterest();
        uint256 user2EarnsAfterRepays = wbtcRewardManager.earned(USER2);
        console.log(user2EarnsAfterRepays, "user2EarnsAfterRepays");
        // assert(user2EarnsAfterRepays > 0);
        assertEq(user2EarnsAfterRepays, accumulatedInterest);
    }

    function testEarningsAfterClaimingRewardsIsEqualZero() public depositedCollateralAndBorrowAfterSomePeriod {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(USER);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        ERC20Mock(wbtc).approve(address(invEngine), userInterestDue);
        invEngine.repay(address(wbtc), userInterestDue);
        vm.stopPrank();

        uint256 accumulatedInterest = wbtcRewardManager.getVirtualAccumulatedInterest();
        uint256 user2Earned = wbtcRewardManager.earned(USER2);
        uint256 balanceRemaining = ERC20(wbtc).balanceOf(address(wbtcRewardManager));

        assert(user2Earned > 0);

        uint256 reward = invEngine.claimYield(USER2, address(wbtc));
        uint256 user2EarnsAfterClaim = wbtcRewardManager.earned(USER2);

        assert(reward > user2EarnsAfterClaim);
    }

    function testProfitsNotExceedBalance() public depositedCollateralAndBorrowAfterSomePeriod {
        // 1. TEST
        // The user's gains should be zero if no interest has been collected yet.
        vm.warp(block.timestamp + 1 days);
        uint256 user2EarnsBeforeRepays = wbtcRewardManager.earned(USER2);
        uint256 initialAccumulatedInterest = wbtcRewardManager.getVirtualAccumulatedInterest();
        // uint256 apyBeforeRepay = wbtcRewardManager.calculateSupplyAPY();

        assertEq(user2EarnsBeforeRepays, 0); // Ensure user's gains are zero initially
        assertEq(initialAccumulatedInterest, 0); // Ensure initial accumulated interest is zero

        // Another TEST
        // Profits cannot exceed the total interest already available.
        vm.startPrank(USER);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtBeforePayment = invEngine.getUserInternalDebt(USER, address(wbtc));
        ERC20Mock(wbtc).approve(address(invEngine), userInterestDue);
        invEngine.repay(address(wbtc), userInterestDue);

        // uint256 apyAfterRepay = wbtcRewardManager.calculateSupplyAPY();
        // console.log(apyBeforeRepay, apyAfterRepay, "before & after APY");

        uint256 userInterestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtAfterPayment = invEngine.getUserInternalDebt(USER, address(wbtc));

        assertEq(userInterestDueAfterRepay, 0); // Ensure user's interest due is zero after repayment
        assertEq(userInternalDebtBeforePayment, userInternalDebtAfterPayment); // Ensure internal debt remains the same

        vm.stopPrank();

        uint256 accumulatedInterest = wbtcRewardManager.getVirtualAccumulatedInterest();
        uint256 user2EarnsAfterRepays = wbtcRewardManager.earned(USER2);

        assert(user2EarnsAfterRepays > 0); // Ensure user2 earns some interest
        assertEq(user2EarnsAfterRepays, accumulatedInterest); // Ensure user2's earnings match the accumulated interest

        vm.startPrank(USER);
        invEngine.borrow(wbtc, 0.1 ether);
        vm.warp(block.timestamp + 1 days);
        uint256 userNewInterestDue = invEngine.getUserInterestDue(USER, wbtc);

        assert(userNewInterestDue > 0); // Ensure new interest due is greater than zero

        uint256 user2NewEarns = wbtcRewardManager.earned(USER2);
        uint256 balanceRM = ERC20(wbtc).balanceOf(address(wbtcRewardManager));

        assertEq(balanceRM, user2NewEarns); // Ensure balance in the reward manager matches user2's earnings

        vm.warp(block.timestamp + 1 days);

        uint256 newUserInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        ERC20Mock(wbtc).approve(address(invEngine), newUserInterestDue);
        invEngine.repay(address(wbtc), newUserInterestDue);

        uint256 user2NewEarnsAfterAll = wbtcRewardManager.earned(USER2);
        uint256 balanceRMAfterAll = ERC20(wbtc).balanceOf(address(wbtcRewardManager));

        assertEq(user2NewEarnsAfterAll, balanceRMAfterAll); // Ensure user2's earnings match the balance in the reward manager

        uint256 reward = invEngine.claimYield(USER2, address(wbtc));
        uint256 user2EarnsAfterAll = wbtcRewardManager.earned(USER2);
        uint256 balanceRMFinal = ERC20(wbtc).balanceOf(address(wbtcRewardManager));

        assertEq(user2EarnsAfterAll, 0); // Ensure user2's earnings are zero after claiming
        assertEq(balanceRMFinal, 0); // Ensure balance in the reward manager is zero after claiming

        vm.stopPrank();
    }

    function testEarnedFunctionWhenAnotherUserEntersThePool() public depositedCollateralAndBorrowAfterSomePeriod {
        // at this point
        // USER2 is supplying 9 BTC and borrowing nothing
        // USER is supplying 10 WETH and borrowing 0.2 BTC
        // So just USER2 should receive rewards
        uint256 currentTimestamp = block.timestamp;
        // console.log(wbtcRewardManager.getAccumulatedInterest(), "accumulated interest before");

        // 1. TEST
        // The user's gains should be zero if no interest has been collected yet.
        vm.warp(currentTimestamp + 1 days);
        uint256 user2EarnsBeforeRepays = wbtcRewardManager.earned(USER2);
        uint256 initialAccumulatedInterest = wbtcRewardManager.getVirtualAccumulatedInterest();

        assertEq(user2EarnsBeforeRepays, 0);
        assertEq(initialAccumulatedInterest, 0);

        // Another TEST
        // Profits cannot exceed the total interest already available.
        vm.startPrank(USER);
        uint256 userInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtBeforePayment = invEngine.getUserInternalDebt(USER, address(wbtc));
        ERC20Mock(wbtc).approve(address(invEngine), userInterestDue);
        invEngine.repay(address(wbtc), userInterestDue);
        uint256 userInterestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        uint256 userInternalDebtAfterPayment = invEngine.getUserInternalDebt(USER, address(wbtc));

        assertEq(userInterestDueAfterRepay, 0);
        assertEq(userInternalDebtBeforePayment, userInternalDebtAfterPayment);

        vm.stopPrank();

        // check user2 new earnings
        uint256 accumulatedInterest = wbtcRewardManager.getVirtualAccumulatedInterest();
        uint256 user2EarnsAfterRepays = wbtcRewardManager.earned(USER2);

        console.log(user2EarnsAfterRepays, accumulatedInterest);
        assert(user2EarnsAfterRepays > 0);
        assertEq(user2EarnsAfterRepays, accumulatedInterest);

        // check user2 earnings after another user enter the pool
        // 1. user3 enter the pool
        vm.startPrank(USER3);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();
        // check if earnings from user2 were affected
        uint256 accumulatedInterestAfterOtherUserEnterPool = wbtcRewardManager.getVirtualAccumulatedInterest();
        // uint256 user2EarnsAfterOtherUserEnterPool = wbtcRewardManager.earned(USER2);
        uint256 user2EarnsBefore5min = wbtcRewardManager.earned(USER2);
        uint256 user3Earns = wbtcRewardManager.earned(USER3);

        //
        assertEq(user2EarnsAfterRepays, accumulatedInterestAfterOtherUserEnterPool);
        // this is not possible at the moment with the current design
        // assertEq(user2EarnsAfterOtherUserEnterPool, user2EarnsAfterRepays);
        // assertEq(user2EarnsBefore5min, user2EarnsAfterRepays);

        console.log(user2EarnsBefore5min, user2EarnsAfterRepays, "user2EarnsBefore5min, user2EarnsAfterRepays");
        console.log(user2EarnsAfterRepays, accumulatedInterestAfterOtherUserEnterPool);
        console.log(user3Earns, "user3Earns");

        vm.warp(block.timestamp + 5 minutes);
        uint256 user2EarnsAfter5min = wbtcRewardManager.earned(USER2);
        uint256 user3EarnsAfter5min = wbtcRewardManager.earned(USER3);
        console.log(user2EarnsAfter5min, user3EarnsAfter5min, "user3EarnsAfter5min");

        vm.warp(block.timestamp + 360 days);
        uint256 user2EarnsAfter10min = wbtcRewardManager.earned(USER2);
        uint256 user3EarnsAfter10min = wbtcRewardManager.earned(USER3);
        console.log(
            user2EarnsAfter10min,
            user3EarnsAfter10min,
            accumulatedInterestAfterOtherUserEnterPool,
            "ususer3EarnsAfter10miner3EarnsAfter5min"
        );
        console.log(
            user2EarnsAfter10min + user3EarnsAfter10min < accumulatedInterestAfterOtherUserEnterPool,
            "ususer3EarnsAfter10miner3EarnsAfter5min"
        );
        assert(user2EarnsAfter10min + user3EarnsAfter10min <= accumulatedInterestAfterOtherUserEnterPool);

        vm.startPrank(USER4);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        uint256 user2EarnsAfter1year = wbtcRewardManager.earned(USER2);
        uint256 user3EarnsAfter1year = wbtcRewardManager.earned(USER3);
        uint256 user4EarnsAfter1year = wbtcRewardManager.earned(USER4);
        console.log(
            user2EarnsAfter1year, user3EarnsAfter1year, user4EarnsAfter1year, "after 1 year and another user supply"
        );

        vm.startPrank(USER2);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 user2EarnsAfter1yearAndDoSupply = wbtcRewardManager.earned(USER2);
        uint256 user3EarnsAfter1yearAndDoSupply = wbtcRewardManager.earned(USER3);
        uint256 user4EarnsAfter1yearAndDoSupply = wbtcRewardManager.earned(USER4);
        console.log(
            user2EarnsAfter1yearAndDoSupply,
            user3EarnsAfter1yearAndDoSupply,
            user4EarnsAfter1yearAndDoSupply,
            "after 1 year and another user supply"
        );
        assertEq(user2EarnsAfter1yearAndDoSupply, 0);
        vm.warp(block.timestamp + 1 days);
        uint256 userInterestDueAfterRepay1year = invEngine.getUserInterestDue(USER, wbtc);
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), userInterestDueAfterRepay1year);
        invEngine.repay(address(wbtc), userInterestDueAfterRepay1year);
        vm.stopPrank();
        console.log(userInterestDueAfterRepay1year, "interest due after 1 year");
        uint256 user2EarnsAfter1yearAndDoSupplyAfterRepay = wbtcRewardManager.earned(USER2);
        uint256 user3EarnsAfter1yearAndDoSupplyAfterRepay = wbtcRewardManager.earned(USER3);
        uint256 user4EarnsAfter1yearAndDoSupplyAfterRepay = wbtcRewardManager.earned(USER4);

        uint256 newAccumulatedInterest = wbtcRewardManager.getVirtualAccumulatedInterest();
        assert(
            user2EarnsAfter1yearAndDoSupplyAfterRepay + user3EarnsAfter1yearAndDoSupplyAfterRepay
                + user4EarnsAfter1yearAndDoSupplyAfterRepay <= newAccumulatedInterest
        );
        console.log(
            user2EarnsAfter1yearAndDoSupplyAfterRepay + user3EarnsAfter1yearAndDoSupplyAfterRepay
                + user4EarnsAfter1yearAndDoSupplyAfterRepay <= newAccumulatedInterest
        );
        console.log(
            user2EarnsAfter1yearAndDoSupplyAfterRepay + user3EarnsAfter1yearAndDoSupplyAfterRepay
                + user4EarnsAfter1yearAndDoSupplyAfterRepay
        );
        console.log(
            user2EarnsAfter1yearAndDoSupplyAfterRepay,
            user3EarnsAfter1yearAndDoSupplyAfterRepay,
            user4EarnsAfter1yearAndDoSupplyAfterRepay,
            "after 1 year and another user supply"
        );
        // 3. TEST
        // A user cannot have interest to pay if they have just made a repayment
        // and covered all outstanding debts or a sufficient amount
        // to settle the owed interest.
        // vm.startPrank(USER);
        // uint256 userInterestDue = invEngine.getUserInterestDue(USER, wbtc);
        // uint256 userInternalDebtBeforePayment = invEngine.getUserInternalDebt(USER, address(wbtc));
        // ERC20Mock(wbtc).approve(address(invEngine), userInterestDue);

        // invEngine.repay(address(wbtc), userInterestDue);

        // uint256 userInterestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        // uint256 userInternalDebtAfterPayment = invEngine.getUserInternalDebt(USER, address(wbtc));

        // assertEq(userInterestDueAfterRepay, 0);
        // assertEq(userInternalDebtBeforePayment, userInternalDebtAfterPayment);

        // vm.stopPrank();

        // vm.stopPrank();

        // vm.warp(currentTimestamp + 1 days);
        // uint256 User2EarnedValue1DayAfter = wbtcRewardManager.earned(USER2);

        // vm.startPrank(USER);
        // ERC20Mock(wbtc).approve(address(invEngine), 0.1 ether);
        // invEngine.repay(address(wbtc), 0.1 ether);
        // uint256 interestDueAfterRepay = invEngine.getUserInterestDue(USER, wbtc);
        // uint256 User2EarnedValue1DayAfterAfterUser2Repay = wbtcRewardManager.earned(USER2);
    }

    // function testYield() public depositedCollateralAndBorrowAfterSomePeriod {
    //     vm.startPrank(USER);
    //     uint256 balance = ERC20(wbtc).balanceOf(address(wbtcRewardManager));
    //     ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
    //     uint256 currentTimestamp2 = block.timestamp;
    //     vm.warp(currentTimestamp2 + 180 days);
    //     vm.stopPrank();

    //     vm.startPrank(USER2);
    //     ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
    //     uint256 beforeBorrow = invEngine.getUserInterestDue(USER, wbtc);
    //     // uint256 beforeOtherUserGetBorrow = invEngine.due(USER, wbtc);
    //     (uint256 earnedBefore) = wbtcRewardManager.earned(USER2);
    //     invEngine.borrow(wbtc, 1e17);
    //     (uint256 earnedAfter) = wbtcRewardManager.earned(USER2);

    //     uint256 afterBorrow = invEngine.getUserInterestDue(USER, wbtc);
    //     vm.warp(currentTimestamp2 + 181 days);
    //     // uint256 afterOtherUserGetBorrow = invEngine.getUserInterestDue(USER, wbtc);
    //     vm.stopPrank();

    //     vm.startPrank(USER);
    //     uint256 afterOtherUserGetBorrow2 = invEngine.getUserInterestDue(USER, wbtc);

    //     uint256 user2Interest = invEngine.getUserInterestDue(USER2, wbtc);

    //     // uint256 userInterest = invEngine.getUserInterestgetUserInterestDue(USER, wbtc);

    //     vm.warp(currentTimestamp2 + 366 days);
    //     uint256 userInterest1 = invEngine.getUserInterestDue(USER, wbtc);
    //     uint256 user2Interest2 = invEngine.getUserInterestDue(USER2, wbtc);

    //     // invEngine.claimYield(USER2, wbtc);
    //     (uint256 earned) = wbtcRewardManager.earned(USER2);
    //     (uint256 earnedUser1) = wbtcRewardManager.earned(USER);

    //     uint256 wbtcBalanceOfUser2 = ERC20(wbtc).balanceOf(address(USER2));
    //     // uint256 user2Yield = invEngine.getUserYield(USER2, wbtc);
    //     // uint256 userYield = invEngine.getUserYield(USER, wbtc);
    //     // console.log(beforeOtherUserGetBorrow, afterOtherUserGetBorrow, afterOtherUserGetBorrow2, userInterest1);
    //     console.log(earnedBefore, earnedAfter, user2Interest);
    //     console.log(userInterest1, user2Interest, userInterest1, user2Interest2);
    //     console.log(userInterest1, earned, balance, "userInterest,earned,balance");
    //     console.log(earnedUser1, earnedUser1 + earned, "earnedUser1,earnedUser1 + earned");

    //     vm.stopPrank();
    // }
}
