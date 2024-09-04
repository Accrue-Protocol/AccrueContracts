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

contract InvEngineTest is Test {
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
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint8 public constant DECIMALS = 8;
    int256 private constant NEW_WETH_PRICE = 1500e8;
    uint256 constant MINIMUM_LIQUIDITY = 1000;

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
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndBorrow() {
        uint256 amountToBorrow = 0.05 ether;
        uint256 expectedBorrowValue = 25000e18 * 0.05;

        vm.startPrank(USER2);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, amountToBorrow);
        vm.stopPrank();

        _;
    }

    modifier depositedCollateralAndBorrowAfterSomePeriod() {
        uint256 amountToBorrow = 0.05 ether;
        uint256 amountToBorrow2 = 0.1 ether;
        uint256 expectedBorrowValue = 25000e18 * 0.05;

        vm.startPrank(USER2);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, amountToBorrow);
        vm.stopPrank();

        vm.startPrank(USER);
        uint256 startAt = block.timestamp;

        vm.warp(startAt + 20 days);
        invEngine.borrow(wbtc, amountToBorrow2);

        vm.warp(startAt + 140 days);
        invEngine.borrow(wbtc, amountToBorrow2);

        uint256 currentTimestamp = block.timestamp;
        vm.warp(currentTimestamp + 100 days);

        vm.stopPrank();

        _;
    }

    modifier depositedCollateralByUser2() {
        vm.startPrank(USER2);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedMoreThanOneCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);

        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                    ASSET CONFIG TESTS
    //////////////////////////////////////////////////////////////*/
    function testAssetConfigs() public {
        InvEngine.Configuration memory assetConfiguration =
            InvEngine.Configuration(75, 0, 80, address(baseInterestRateModel), address(wethRewardManager));

        vm.startPrank(USER);
        uint256 actualAssetConfig = invEngine.getConfiguration(weth).lendFactor;
        InvEngine.Configuration memory expectedAssetConfig = assetConfiguration;

        assertEq(actualAssetConfig, expectedAssetConfig.lendFactor);
    }

    /*///////////////////////////////////////////////////////////////
                        POOL TESTS
    //////////////////////////////////////////////////////////////*/
    function testCalculateUtilization() public depositedCollateralAndBorrow {
        uint256 poolUtilization = invEngine.getUtilization(wbtc);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function depositCollateral() public {
        vm.startPrank(USER);
        uint256 userDepositedAssetsBeforeSupply = invEngine.getInternalBalance(USER, wbtc);
        ERC20Mock(weth).approve(address(this), AMOUNT_COLLATERAL);
        invEngine.supply(weth, 1e18);
        uint256 userDepositedAssetsAfterSupply = invEngine.getInternalBalance(USER, wbtc);
        vm.stopPrank();

        // console.log(userDepositedAssetsBeforeSupplyf, userDepositedAssetsAfterSupply);
        assertEq(userDepositedAssetsBeforeSupply, 0);
        // assert(userDepositedAssetsAfterSupply > 0);
        // assertEq(userDepositedAssetsBeforeSupply, 1e18);
    }

    function supplyMust() public {
        vm.startPrank(USER);
        // uint256 userDepositedAssetsBeforeSupply = invEngine.getInternalBalance(USER, address(weth));
        ERC20Mock(weth).approve(address(this), AMOUNT_COLLATERAL);
        invEngine.supply(weth, 1e18);
        vm.stopPrank();
        // uint256 userDepositedAssetsAfterSupply = invEngine.getInternalBalance(USER, address(weth));

        // console.log(userDepositedAssetsBeforeSupplyf, userDepositedAssetsAfterSupply);
        // assertEq(userDepositedAssetsBeforeSupply, 0);
        // assert(userDepositedAssetsAfterSupply > 0);
        // assertEq(userDepositedAssetsBeforeSupply, 1e18);
    }

    function supplyMustBeOk() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(this), AMOUNT_COLLATERAL);
        invEngine.supply(weth, 1e18);
        vm.stopPrank();
        uint256 userDepositedAssetsAfterSupply = invEngine.getInternalBalance(USER, weth);
        assert(userDepositedAssetsAfterSupply > 0);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(this), AMOUNT_COLLATERAL);

        vm.expectRevert(InvEngine.INVEngine__NeedsMoreThanZero.selector);
        invEngine.supply(weth, 0);
        vm.stopPrank();
    }

    function testCheckIfuserGetsWrapTokenOnSupply() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);

        // Saldo inicial de wrapTokens do usuário
        uint256 initialWrapTokenBalance = ERC20(invEth).balanceOf(USER);

        // Fazer o depósito de colateral
        invEngine.supply(weth, AMOUNT_COLLATERAL);

        // Verificar se o usuário recebeu os wrapTokens corretos
        uint256 finalWrapTokenBalance = ERC20(invEth).balanceOf(USER);
        uint256 expectedWrapTokenBalance = initialWrapTokenBalance + AMOUNT_COLLATERAL;

        assertEq(finalWrapTokenBalance, expectedWrapTokenBalance - MINIMUM_LIQUIDITY);

        vm.stopPrank();
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);

        uint256 expectedUserAccountCollateralValue = 20000e18;

        // Fazer o depósito de colateral
        invEngine.supply(weth, AMOUNT_COLLATERAL);

        uint256 actualUserAccountCollateralValue = invEngine.getAccountCollateralValue(USER);
        assertEq(actualUserAccountCollateralValue, expectedUserAccountCollateralValue);

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                    WITHDRAW COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdraw() public {
        // Configurar o ambiente de teste
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        // Fazer um depósito inicial de colateral
        invEngine.supply(weth, AMOUNT_COLLATERAL);

        // Saldo inicial de colateral do usuário
        uint256 initialCollateralBalance = ERC20(weth).balanceOf(USER);

        // Saldo inicial de wrapTokens do usuário
        uint256 initialWrapTokenBalance = ERC20(invEth).balanceOf(USER);

        // Retirar parte da colateral
        uint256 amountToWithdraw = AMOUNT_COLLATERAL / 2;
        ERC20Mock(invEth).approve(address(invEngine), amountToWithdraw); // approve wrapToken
        invEngine.withdraw(weth, amountToWithdraw);

        // Verificar se o usuário recebeu a colateral de volta
        uint256 finalCollateralBalance = ERC20(weth).balanceOf(USER);
        uint256 expectedCollateralBalance = initialCollateralBalance + amountToWithdraw;
        uint256 finalCollateralBalanceOnEngine = invEngine.getInternalBalance(USER, address(weth));
        assertEq(finalCollateralBalance, expectedCollateralBalance);
        assertEq(finalCollateralBalanceOnEngine, expectedCollateralBalance);

        // Verificar se o usuário teve os wrapTokens queimados corretamente
        uint256 finalWrapTokenBalance = ERC20(invEth).balanceOf(USER);
        uint256 expectedWrapTokenBalance = initialWrapTokenBalance - amountToWithdraw;
        assertEq(finalWrapTokenBalance, expectedWrapTokenBalance);

        console.log(initialWrapTokenBalance, "initialWrapTokenBalance");
        console.log(finalWrapTokenBalance, "finalWrapTokenBalance");
        // console.log(amountToWithdraw, "amountToWithdraw");
        // console.log(expectedWrapTokenBalance, "expectedWrapTokenBalance");
        vm.stopPrank();
    }

    function testWrapTokenTotalSupplyBeforeAndAfterWithdraw() public {
        // Configurar o ambiente de teste
        vm.startPrank(USER);

        // Saldo total de wrap tokens antes de supply
        uint256 wrapTokenTotalSupplyBeforeSupply = invEngine.getWrapTokensTotalSuppply(address(weth), address(invEth));
        assertEq(wrapTokenTotalSupplyBeforeSupply, 0);

        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        // Fazer um depósito inicial de colateral
        invEngine.supply(weth, AMOUNT_COLLATERAL);

        // Saldo total de wrap tokens depois de supply
        uint256 wrapTokenTotalSupplyAfterSupply = invEngine.getWrapTokensTotalSuppply(address(weth), address(invEth));
        assertEq(wrapTokenTotalSupplyAfterSupply, AMOUNT_COLLATERAL);

        // Retirar parte da colateral
        uint256 amountToWithdraw = AMOUNT_COLLATERAL / 2;
        ERC20Mock(invEth).approve(address(invEngine), amountToWithdraw); // approve wrapToken
        invEngine.withdraw(weth, amountToWithdraw);

        // Saldo total de wrap tokens depois de withdraw
        uint256 wrapTokenTotalSupplyAfterWithdraw = invEngine.getWrapTokensTotalSuppply(address(weth), address(invEth));
        assertEq(wrapTokenTotalSupplyAfterWithdraw, amountToWithdraw);

        vm.stopPrank();
    }

    function testWrapTokenTotalSupplyWhenThereIsAnotherSupplier() public {
        // Configurar o ambiente de teste
        vm.startPrank(USER);

        // Saldo total de wrap tokens antes de supply
        uint256 wrapTokenTotalSupplyBeforeSupply = invEngine.getWrapTokensTotalSuppply(address(weth), address(invEth));
        assertEq(wrapTokenTotalSupplyBeforeSupply, 0);

        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        // Fazer um depósito inicial de colateral
        invEngine.supply(weth, AMOUNT_COLLATERAL);

        // Saldo total de wrap tokens depois de supply
        uint256 wrapTokenTotalSupplyAfterSupply = invEngine.getWrapTokensTotalSuppply(address(weth), address(invEth));
        assertEq(wrapTokenTotalSupplyAfterSupply, AMOUNT_COLLATERAL);

        // Retirar parte da colateral
        uint256 amountToWithdraw = AMOUNT_COLLATERAL / 2;
        ERC20Mock(invEth).approve(address(invEngine), amountToWithdraw); // approve wrapToken
        invEngine.withdraw(weth, amountToWithdraw);

        // Saldo total de wrap tokens depois de withdraw
        uint256 wrapTokenTotalSupplyAfterWithdraw = invEngine.getWrapTokensTotalSuppply(address(weth), address(invEth));
        assertEq(wrapTokenTotalSupplyAfterWithdraw, amountToWithdraw);
        vm.stopPrank();

        vm.startPrank(USER2);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        // Fazer um depósito inicial de colateral
        invEngine.supply(weth, AMOUNT_COLLATERAL - 2 ether);

        // Saldo total de wrap tokens depois de withdraw
        uint256 wrapTokenTotalSupplyOnUser2 = invEngine.getWrapTokensTotalSuppply(address(weth), address(invEth));
        assert(wrapTokenTotalSupplyOnUser2 > wrapTokenTotalSupplyAfterWithdraw);

        console.log(wrapTokenTotalSupplyOnUser2, wrapTokenTotalSupplyAfterWithdraw);
        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                          PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15ETH * $2000 = 30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = invEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    /*///////////////////////////////////////////////////////////////
                        HEALTH FACTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetHealthFactor() public depositedCollateralAndBorrow {
        uint256 expectedHealthFactor = 136e17;

        vm.startPrank(USER);
        uint256 healthFactorUser = invEngine.getUserHealthFactor(USER);
        console.log(healthFactorUser, expectedHealthFactor);

        vm.stopPrank();
    }

    // IT WILL PASS; SO WE DISABLED THE PARAM BORROW VALUE ON CALCULATE HEALTH FACTOR
    // AND THE FUNC `calculateHealthFactor`
    // function testCalculateHealthFactorIsWorkingByGivingBorrowValueBiggerThanCollateralValue()
    //     public
    //     depositedCollateralAndBorrow
    // {
    //     uint256 unrealBorrowValueInUsd = 18000e18;
    //     // 17000e18 is the collateralValueOfTheUser * LIQUIDATION_THRESHOLD
    //     uint256 expectedHealthFactor = (17000e18 * PRECISION) / unrealBorrowValueInUsd;

    //     vm.startPrank(USER);
    //     uint256 healthFactorUser = invEngine.calculateHealthFactor(USER, unrealBorrowValueInUsd);

    //     assertEq(healthFactorUser, expectedHealthFactor);
    //     assertEq(healthFactorUser, expectedHealthFactor);
    //     vm.stopPrank();
    // }

    // function testCalculateHealthFactor() public depositedCollateralAndBorrow {
    //     uint256 unrealBorrowValueInUsd = 4000e18;
    //     // 17000e18 is the collateralValueOfTheUser * LIQUIDATION_THRESHOLD
    //     uint256 expectedHealthFactor = (17000e18 * PRECISION) / unrealBorrowValueInUsd; // 3.75e18

    //     vm.startPrank(USER);
    //     uint256 healthFactorUser = invEngine.calculateHealthFactor(USER, unrealBorrowValueInUsd);
    //     assertEq(healthFactorUser, expectedHealthFactor);
    //     vm.stopPrank();
    // }

    /*///////////////////////////////////////////////////////////////
                        BORROW TESTS
    //////////////////////////////////////////////////////////////*/
    function testIfUserCanBorrowSpecificToken() public depositedCollateral {
        bool isTrue = invEngine.canBorrowSpecificToken(USER, wbtc, 0.1 ether);
        assertEq(isTrue, true);
    }

    function testIfUserCannotBorrowSpecificToken() public depositedCollateral {
        bool isTrue = invEngine.canBorrowSpecificToken(USER3, wbtc, 0.1 ether);
        assertEq(isTrue, false);
    }

    function testIfIsAvailableLiquidityToBorrowFuncIsWorking() public depositedCollateral {
        uint256 amountToBorrow = 1 ether;
        bool isAvailableWethLiquidity = invEngine.isAvailableLiquidityToBorrow(weth, amountToBorrow);
        bool isAvailableWbtcLiquidity = invEngine.isAvailableLiquidityToBorrow(wbtc, amountToBorrow);

        assertEq(isAvailableWethLiquidity, true);
        assertEq(isAvailableWbtcLiquidity, false);
    }

    function testIfAvailableLiquidityFuncIsWorking() public depositedCollateral {
        uint256 availableWethAmount = invEngine.getAvailableLiquidity(weth);
        uint256 availableWbtcAmount = invEngine.getAvailableLiquidity(wbtc);
        uint256 expectedWethAmount = AMOUNT_COLLATERAL;
        uint256 expectedWbtcAmount = 0;

        assertEq(availableWethAmount, expectedWethAmount);
        assertEq(availableWbtcAmount, expectedWbtcAmount);
    }

    function testRevertIfHasNoLiquidityAvailableToBorrow() public depositedCollateral {
        uint256 amountToBorrow = 0.1 ether;

        vm.startPrank(USER);
        vm.expectRevert(InvEngine.INVEngine__NoLiquidityAvailable.selector);
        invEngine.borrow(wbtc, amountToBorrow);

        vm.stopPrank();
    }

    function testRevertIfTheUserHasSufficientCollateralForBorrowing() public depositedCollateral {
        uint256 amountToBorrow = 1 ether;

        vm.startPrank(USER2);
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(invEth).approve(address(invEngine), AMOUNT_COLLATERAL); // approve wrapToken
        vm.expectRevert(InvEngine.INVEngine__UserCannotBorrow.selector);
        invEngine.borrow(wbtc, amountToBorrow);
        vm.stopPrank();
    }

    function testBorrow() public depositedCollateralByUser2 depositedMoreThanOneCollateral {
        uint256 amountToBorrow = 0.05 ether;
        uint256 expectedBorrowValue = 25000e18 * 0.05;

        vm.startPrank(USER2);
        (uint256 maximumBorrowable, uint256 borrowValueRemaining) = invEngine.maxBorrowable(USER2);
        console.log(borrowValueRemaining, maximumBorrowable);
        invEngine.borrow(wbtc, amountToBorrow);

        (uint256 maximumBorrowableafter, uint256 borrowValueRemainingafter) = invEngine.maxBorrowable(USER2);
        console.log(borrowValueRemainingafter, maximumBorrowableafter);

        uint256 actualBorrowValue = invEngine.getAccountBorrowValue(USER2);
        uint256 userInternalDebt = invEngine.getUserInternalDebt(USER2, wbtc);
        uint256 totalInternalDebt = invEngine.getTotalInternalDebt(wbtc);
        uint256 userWbtcBalance = ERC20(wbtc).balanceOf(USER2);

        assertEq(actualBorrowValue, expectedBorrowValue);
        assertEq(userInternalDebt, amountToBorrow);
        assertEq(totalInternalDebt, amountToBorrow);
        assertEq(userWbtcBalance, amountToBorrow + AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                        REPAY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRepayWithoutBorrowingShouldFail() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(abi.encodeWithSelector(InvEngine.INVEngine__NotBorrowed.selector, weth));
        invEngine.repay(weth, 1 ether);
        vm.stopPrank();
    }

    function testRepayMoreThanBorrowed() public depositedCollateralAndBorrow {
        vm.startPrank(USER);

        vm.expectRevert(InvEngine.INVEngine__CannotRepayMoreThanBorrowed.selector);
        invEngine.repay(wbtc, 0.1 ether);
        vm.stopPrank();
    }

    function testSuccessfulRepay() public depositedCollateralAndBorrow {
        uint256 amountToRepay = 0.05 ether;
        uint256 initialDebt = invEngine.getUserInternalDebt(USER, wbtc);
        uint256 initialINVEngineWbtcBalance = ERC20(wbtc).balanceOf(address(invEngine));

        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), amountToRepay);
        invEngine.repay(wbtc, amountToRepay);
        vm.stopPrank();

        uint256 finalDebt = invEngine.getUserInternalDebt(USER, wbtc);
        uint256 finalINVEngineWbtcBalance = ERC20(wbtc).balanceOf(address(invEngine));

        assertEq(initialDebt - amountToRepay, finalDebt);
        assertEq(finalINVEngineWbtcBalance, initialINVEngineWbtcBalance + amountToRepay);
    }

    function testSuccessfulRepayAfterSomePeriod() public depositedCollateralAndBorrowAfterSomePeriod {
        uint256 amountToRepay = 0.05 ether;
        uint256 initialDebt = invEngine.getUserInternalDebt(USER, wbtc);
        uint256 initialINVEngineWbtcBalance = ERC20(wbtc).balanceOf(address(invEngine));

        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), amountToRepay);
        uint256 interestDue = invEngine.getUserInterestDue(USER, wbtc);
        uint256 interest = invEngine.repay(wbtc, amountToRepay);
        vm.stopPrank();

        uint256 finalDebt = invEngine.getUserInternalDebt(USER, wbtc);

        uint256 finalINVEngineWbtcBalance = ERC20(wbtc).balanceOf(address(invEngine));

        console.log((initialDebt - amountToRepay) + interestDue, finalDebt);
        console.log(interest, "interest");
        assertEq((initialDebt - amountToRepay) + interestDue, finalDebt);
        assertEq(finalINVEngineWbtcBalance, initialINVEngineWbtcBalance + amountToRepay - interestDue);
    }

    function testSuccessfulRepayAllDebtAfterSomePeriod() public depositedCollateralAndBorrowAfterSomePeriod {
        uint256 amountToRepay = 0.15 ether;
        uint256 initialDebt = invEngine.getUserInternalDebt(USER, wbtc);
        uint256 initialINVEngineWbtcBalance = ERC20(wbtc).balanceOf(address(invEngine));

        vm.startPrank(USER);

        uint256 totalLiquidity = invEngine.getTotalInternalBalances(wbtc);
        uint256 totalBorrowed = invEngine.getTotalInternalDebt(wbtc);
        uint256 annualInterestRate =
            InvInterestRateModel(interestRateModel).getBorrowRate(totalLiquidity, totalBorrowed);
        uint256 interestDue = invEngine.getUserInterestDue(USER, wbtc);
        ERC20Mock(wbtc).approve(address(invEngine), initialDebt);
        invEngine.repay(wbtc, initialDebt);
        vm.stopPrank();

        uint256 finalDebt = invEngine.getUserInternalDebt(USER, wbtc);

        uint256 finalINVEngineWbtcBalance = ERC20(wbtc).balanceOf(address(invEngine));
        console.log((initialDebt - initialDebt) + interestDue, finalDebt);
        assertEq((initialDebt - initialDebt) + interestDue, finalDebt);
        assertEq(finalINVEngineWbtcBalance, initialINVEngineWbtcBalance + initialDebt - interestDue);
    }

    function testSuccessfulRepayLessThanTheDebt() public depositedCollateralAndBorrow {
        uint256 amountToRepay = 0.02 ether;
        uint256 initialDebt = invEngine.getUserInternalDebt(USER, wbtc);
        uint256 initialINVEngineWbtcBalance = ERC20(wbtc).balanceOf(address(invEngine));

        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(invEngine), amountToRepay);
        invEngine.repay(wbtc, amountToRepay);
        vm.stopPrank();

        uint256 finalDebt = invEngine.getUserInternalDebt(USER, wbtc);
        uint256 finalINVEngineWbtcBalance = ERC20(wbtc).balanceOf(address(invEngine));

        assertEq(initialDebt - amountToRepay, finalDebt);
        assertEq(finalINVEngineWbtcBalance, initialINVEngineWbtcBalance + amountToRepay);
    }

    function testNonEligibleUserCannotRepay() public depositedCollateralByUser2 {
        uint256 amountToRepay = 0.01 ether; // Some arbitrary amount
        address tokenBorrowedAddress = wbtc; // You can choose any supported token

        vm.startPrank(USER2);
        ERC20Mock(tokenBorrowedAddress).approve(address(invEngine), amountToRepay);
        vm.expectRevert(
            abi.encodeWithSelector(InvEngine.INVEngine__NotBorrowed.selector, address(tokenBorrowedAddress))
        );
        invEngine.repay(tokenBorrowedAddress, amountToRepay); // Attempt to repay
        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                        LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    function testCalculateSeizeAmount() public {
        uint256 expectedTotalAmountToRepayAfterDiscount = 0.27 ether;
        uint256 expectedtotalAmountToSeizeInSeizeAsset = 3.75 ether;

        (uint256 totalAmountToRepayAfterDiscount, uint256 totalAmountToSeizeInSeizeAsset) =
            invEngine.calculateRepayAmountOnLiquidation(weth, wbtc, 0.3 ether);

        assertEq(totalAmountToRepayAfterDiscount, expectedTotalAmountToRepayAfterDiscount);
        assertEq(totalAmountToSeizeInSeizeAsset, expectedtotalAmountToSeizeInSeizeAsset);
    }

    function testRepayUserDebt() public {
        uint256 amountCollateral = 9 ether;
        uint256 amountToBorrow = 0.6 ether;

        vm.startPrank(USER2);
        // approve 10e18 wbtc
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        // supply only 9e18 wbtc
        invEngine.supply(wbtc, amountCollateral);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, amountToBorrow);

        // (uint256 internalDebt, uint256 amountToRepay, uint256 resultOfTheSub) =
        //     invEngine._repayUserDebt(wbtc, USER, 3e16);

        // console.log(internalDebt, amountToRepay, resultOfTheSub, "result");
        vm.stopPrank();
    }

    function testRevertIfTryLiquidateHealthyUser() public {
        MockV3Aggregator newWethPriceFeed = new MockV3Aggregator(DECIMALS, NEW_WETH_PRICE);
        uint256 amountCollateral = 9 ether;
        uint256 amountToBorrow = 0.6 ether;

        vm.startPrank(USER2);
        // approve 10e18 wbtc
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        // supply only 9e18 wbtc
        invEngine.supply(wbtc, amountCollateral);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, amountToBorrow);

        vm.stopPrank();

        vm.startPrank(USER2);
        vm.expectRevert(InvEngine.INVEngine__CannotLiquidateHealthyUser.selector);
        invEngine.liquidate(USER, wbtc, weth, 3e17);

        vm.stopPrank();
    }

    function testLiquidateAllUserDebts() public {
        InvEngine.Configuration memory assetConfiguration =
            InvEngine.Configuration(75, 0, 80, address(baseInterestRateModel), address(wethRewardManager));
        MockV3Aggregator newWethPriceFeed = new MockV3Aggregator(DECIMALS, NEW_WETH_PRICE);
        uint256 amountCollateral = 9 ether;
        uint256 amountToBorrow = 0.6 ether;

        vm.startPrank(USER2);
        // approve 10e18 wbtc
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        // supply only 9e18 wbtc
        invEngine.supply(wbtc, amountCollateral);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, amountToBorrow);

        vm.startPrank(USER);
        // Update price info for testing purpose
        invEngine.updateAsset(weth, address(newWethPriceFeed), assetConfiguration);

        vm.stopPrank();

        vm.startPrank(USER2);

        uint256 userInternalDebt = invEngine.getUserInternalDebt(USER, wbtc);

        (uint256 starting, uint256 ending) = invEngine.liquidate(USER, wbtc, weth, userInternalDebt);
        uint256 newUserInternalDebt = invEngine.getUserInternalDebt(USER, wbtc);
        console.log(starting, ending, "starting & ending");
        assertEq(newUserInternalDebt, 0);

        vm.stopPrank();
    }

    function testLiquidateUserDebtsPartially() public {
        InvEngine.Configuration memory assetConfiguration =
            InvEngine.Configuration(75, 0, 80, address(baseInterestRateModel), address(wethRewardManager));
        MockV3Aggregator newWethPriceFeed = new MockV3Aggregator(DECIMALS, NEW_WETH_PRICE);
        uint256 amountCollateral = 9 ether;
        uint256 amountToBorrow = 0.6 ether;
        uint256 liquidateAmount = 0.5 ether;

        vm.startPrank(USER2);
        // approve 10e18 wbtc
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        // supply only 9e18 wbtc
        invEngine.supply(wbtc, amountCollateral);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, amountToBorrow);

        vm.startPrank(USER);
        // Update price info for testing purpose
        invEngine.updateAsset(weth, address(newWethPriceFeed), assetConfiguration);

        vm.stopPrank();

        vm.startPrank(USER2);

        (uint256 starting, uint256 ending) = invEngine.liquidate(USER, wbtc, weth, liquidateAmount);
        uint256 newUserInternalDebt = invEngine.getUserInternalDebt(USER, wbtc);
        console.log(starting, ending, "starting & ending");

        assertEq(newUserInternalDebt, amountToBorrow - liquidateAmount);
        // assert(starting <= ending);

        vm.stopPrank();
    }

    function testLiquidateUserDebtsPartiallyAndCheckBalances() public {
        InvEngine.Configuration memory assetConfiguration =
            InvEngine.Configuration(75, 0, 80, address(baseInterestRateModel), address(wethRewardManager));

        MockV3Aggregator newWethPriceFeed = new MockV3Aggregator(DECIMALS, NEW_WETH_PRICE);
        uint256 amountCollateral = 9 ether;
        uint256 amountToBorrow = 0.6 ether;
        uint256 liquidateAmount = 0.3 ether;

        vm.startPrank(USER2);
        // approve 10e18 wbtc
        ERC20Mock(wbtc).approve(address(invEngine), AMOUNT_COLLATERAL);
        // supply only 9e18 wbtc
        invEngine.supply(wbtc, amountCollateral);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(invEngine), AMOUNT_COLLATERAL);
        invEngine.supply(weth, AMOUNT_COLLATERAL);
        invEngine.borrow(wbtc, amountToBorrow);

        vm.startPrank(USER);
        // Update price info for testing purpose
        invEngine.updateAsset(weth, address(newWethPriceFeed), assetConfiguration);

        vm.stopPrank();

        vm.startPrank(USER2);
        uint256 startingInvEngineWethBalance = ERC20(weth).balanceOf(address(invEngine));
        uint256 startingUser2WethBalance = ERC20(weth).balanceOf(USER2);

        (uint256 totalAmountToRepayAfterDiscount, uint256 totalAmountToSeizeInSeizeAsset) =
            invEngine.calculateRepayAmountOnLiquidation(weth, wbtc, liquidateAmount);

        // expected results
        uint256 expectedInvEngineWethBalance = startingInvEngineWethBalance - totalAmountToSeizeInSeizeAsset;
        uint256 expectedUser2WethBalance = startingUser2WethBalance + totalAmountToSeizeInSeizeAsset;
        uint256 expectedUser2WbtcBalance = (AMOUNT_COLLATERAL - totalAmountToRepayAfterDiscount) - amountCollateral;

        (uint256 starting, uint256 ending) = invEngine.liquidate(USER, wbtc, weth, liquidateAmount);
        uint256 newUserInternalDebt = invEngine.getUserInternalDebt(USER, wbtc);

        uint256 actualInvEngineWethBalance = ERC20(weth).balanceOf(address(invEngine));
        uint256 actualUser2WethBalance = ERC20(weth).balanceOf(USER2);
        uint256 actualUser2WbtcBalance = ERC20(wbtc).balanceOf(USER2);

        console.log(starting, ending);
        assertEq(expectedUser2WethBalance, actualUser2WethBalance);
        assertEq(expectedInvEngineWethBalance, actualInvEngineWethBalance);
        assertEq(expectedUser2WbtcBalance, actualUser2WbtcBalance);
        // assertEq(newUserInternalDebt, amountToBorrow - liquidateAmount);

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                            IRM
    //////////////////////////////////////////////////////////////*/

    function testGetBorrowRate() public depositedCollateralAndBorrow {
        vm.startPrank(USER);
        uint256 totalLiquidity = invEngine.getTotalInternalBalances(weth);
        uint256 totalBorrowed = invEngine.getTotalInternalDebt(weth);

        // Get current rate
        uint256 annualInterestRate =
            InvInterestRateModel(interestRateModel).getBorrowRate(totalLiquidity, totalBorrowed);
        assertEq(annualInterestRate, 5e16);
        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                    USER INTEREST DUE
    //////////////////////////////////////////////////////////////*/

    // function testGetUserInterestDue() public depositedCollateralAndBorrow {
    //     uint256 amountToBorrow = 0.1 ether;

    //     vm.startPrank(USER);
    //     uint256 startAt = block.timestamp;

    //     vm.warp(startAt + 20 days);
    //     uint256 interestDue = invEngine.getUserInterestDue(USER, wbtc);
    //     invEngine.borrow(wbtc, amountToBorrow);

    //     vm.warp(startAt + 140 days);
    //     uint256 interestDue2 = invEngine.getUserInterestDue(USER, wbtc);
    //     invEngine.borrow(wbtc, amountToBorrow);

    //     uint256 currentTimestamp = block.timestamp;
    //     vm.warp(currentTimestamp + 100 days);
    //     uint256 interestDueAfter140days = invEngine.getUserInterestDue(USER, wbtc);
    //     (uint256 interestAccrued, uint256 interestRatePerSecond,,) = invEngine.getAccumulatedInterest(wbtc);

    //     console.log(interestRatePerSecond, interestAccrued);
    //     console.log(interestDue, interestDue2, interestDueAfter140days);
    //     console.log(startAt);
    //     console.log(block.timestamp);
    //     vm.stopPrank();
    // }
}
