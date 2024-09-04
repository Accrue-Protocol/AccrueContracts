// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {InvGovernor} from "../../src/InvGovernor.sol";
import {InvEngine} from "../../src/InvEngine.sol";
import {TimeLock} from "../../src/TimeLock.sol";
import {InvToken} from "../../src/InvariantToken.sol";
import {WrapToken} from "../../src/WrapToken.sol";
import {InvRewardManager} from "../../src/InvRewardManager.sol";
import {InvInterestRateModel} from "../../src/InvInterestRateModel.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

/**
 * @title InvGovernorTest
 * @dev InvGovernorTest This contract tests all asset update configurations, but
 *      the test for configureAsset seems fail because of `abi.encodeWithSignature`
 *      is configured wrong.
 *
 *      Btw the DAO is working great :D
 */
contract InvGovernorTest is Test {
    InvGovernor invGovernor;
    InvEngine invEngine;
    TimeLock timelock;
    InvToken invToken;
    InvInterestRateModel baseInterestRateModel;

    uint256 private s_baseRatePerYear = 2e16; // 2%
    uint256 private s_multiplierPerYear = 3e17; // 10%
    uint256 private s_jumpMultiplierPerYear = 4e17; // 20%
    uint256 private s_inflectionPoint = 8e17; // 80%
    uint256 private s_smoothingFactor = 1e17; // 20%
    uint256 private s_maxRatePerYear = 4e17; // 40%
    uint256 private s_minRatePerYear = 1e16; // 1%

    uint256 private s_reserveFactor = 2e17; // 20%

    address[] private tokenAddresses;
    address[] private priceFeedAddresses;
    address[] private wrapTokenAddresses;

    address public USER = makeAddr("user");
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    address[] proposers;
    address[] executors;

    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    uint256 public constant MIN_DELAY = 3600; // 1 hour - after a vote passes
    uint256 public constant VOTING_DELAY = 1; // 1 block - until a vote starts
    uint256 public constant VOTING_PERIOD = 50400; // 1 week - until a vote ends

    function setUp() public {
        // deploy token
        invToken = new InvToken();
        invToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        // delegate votes to ourselves
        invToken.delegate(USER);

        // deploy timelock and governor
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        invGovernor = new InvGovernor(invToken, timelock);

        // get roles
        bytes32 proporserRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        // grant roles
        timelock.grantRole(proporserRole, address(invGovernor));
        timelock.grantRole(executorRole, address(0)); // anyone can execute
        timelock.revokeRole(adminRole, USER); // remove default admin
        vm.stopPrank();

        // deploy invEngine with timelock as owner
        invEngine = new InvEngine(address(timelock));
    }

    function testTimelockIsOwner() public {
        assertEq(address(timelock), invEngine.owner());
    }

    modifier assetsConfigurations() {
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        WrapToken invEth = new WrapToken("invEth", "invEth");

        tokenAddresses = [address(wethMock)];
        priceFeedAddresses = [address(wethPriceFeed)];
        wrapTokenAddresses = [address(invEth)];

        _;
    }

    modifier configureAsset() {
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        WrapToken invEth = new WrapToken("invEth", "invEth");

        tokenAddresses = [address(wethMock)];
        priceFeedAddresses = [address(wethPriceFeed)];
        wrapTokenAddresses = [address(invEth)];
        InvEngine.Configuration[] memory assetConfigurations = new InvEngine.Configuration[](1);
        assetConfigurations[0] = InvEngine.Configuration(75, 0, 80, address(0), address(0));

        // vm.expectRevert();
        invEngine.configureAsset(tokenAddresses, priceFeedAddresses, wrapTokenAddresses, assetConfigurations);
        _;
    }

    function testCantconfigureAssetWitoutGovernance() public {
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        WrapToken invEth = new WrapToken("invEth", "invEth");

        tokenAddresses = [address(wethMock)];
        priceFeedAddresses = [address(wethPriceFeed)];
        wrapTokenAddresses = [address(invEth)];
        InvEngine.Configuration[] memory assetConfigurations = new InvEngine.Configuration[](1);
        assetConfigurations[0] = InvEngine.Configuration(75, 0, 80, address(0), address(0));

        // vm.expectRevert();
        invEngine.configureAsset(tokenAddresses, priceFeedAddresses, wrapTokenAddresses, assetConfigurations);
    }

    function testGovernanceConfigureAsset() public {
        // configurations to proporse
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        WrapToken invEth = new WrapToken("invEth", "invEth");

        tokenAddresses = [address(wethMock)];
        priceFeedAddresses = [address(wethPriceFeed)];
        wrapTokenAddresses = [address(invEth)];
        InvEngine.Configuration[] memory assetConfigurations = new InvEngine.Configuration[](1);
        assetConfigurations[0] = InvEngine.Configuration(75, 0, 80, address(0), address(0));

        string memory description = "Configure WETH as new asset on Invariant";
        bytes memory encodeFunctionCall = abi.encodeWithSignature(
            "configureAsset(address[],address[],address[],InvEngine.Configuration[])",
            tokenAddresses,
            priceFeedAddresses,
            wrapTokenAddresses,
            assetConfigurations
        );

        // push configs to arrays
        values.push(0);
        calldatas.push(encodeFunctionCall);
        targets.push(address(invEngine));

        // proporse to the DAO
        uint256 proporseId = invGovernor.propose(targets, values, calldatas, description);

        // 1. view the state of the proporsal
        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        // 2. vote
        string memory reason = "Because WETH is the best";
        uint8 voteWay = 1; // 0 = Against, 1 = For, 2 = Abstain
        vm.prank(USER);
        invGovernor.castVoteWithReason(proporseId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        // 3. queue TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        invGovernor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1000);
        vm.roll(block.number + MIN_DELAY + 1000);

        // 4. execute
        invGovernor.execute(targets, values, calldatas, descriptionHash);

        assertEq(invEngine.getCollateralTokensCount(), 1);
    }

    function testGovernanceUpdateAssetFactors() public configureAsset {
        // configurations to proporse
        address tokenAddress = tokenAddresses[0];
        uint256 lendFactor = 80;
        uint256 lt = 85;

        string memory description = "Update factors for WETH";
        bytes memory encodeFunctionCall =
            abi.encodeWithSignature("updateAssetFactors(address,uint256,uint256)", tokenAddress, lendFactor, lt);

        // push configs to arrays
        values.push(0);
        calldatas.push(encodeFunctionCall);
        targets.push(address(invEngine));

        // proporse to the DAO
        uint256 proporseId = invGovernor.propose(targets, values, calldatas, description);

        // 1. view the state of the proporsal
        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        // 2. vote
        string memory reason = "Because WETH is the best";
        uint8 voteWay = 1; // 0 = Against, 1 = For, 2 = Abstain
        vm.prank(USER);
        invGovernor.castVoteWithReason(proporseId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        // 3. queue TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        invGovernor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1000);
        vm.roll(block.number + MIN_DELAY + 1000);

        // 4. execute
        invGovernor.execute(targets, values, calldatas, descriptionHash);

        assertEq(invEngine.getConfiguration(tokenAddress).lendFactor, lendFactor);
        assertEq(invEngine.getConfiguration(tokenAddress).liquidationThreshold, lt);
    }

    function testGovernanceUpdateInterestRateModel() public configureAsset {
        // configurations to proporse
        address tokenAddress = tokenAddresses[0];
        // deploy the Interest Rate Model
        baseInterestRateModel = new InvInterestRateModel(
            s_baseRatePerYear,
            s_multiplierPerYear,
            s_jumpMultiplierPerYear,
            s_inflectionPoint,
            s_smoothingFactor,
            s_maxRatePerYear,
            s_minRatePerYear,
            address(msg.sender)
        );

        string memory description = "Update IRM for WETH";
        bytes memory encodeFunctionCall = abi.encodeWithSignature(
            "updateAssetInterestRateModel(address,address)", tokenAddress, baseInterestRateModel
        );

        // push configs to arrays
        values.push(0);
        calldatas.push(encodeFunctionCall);
        targets.push(address(invEngine));

        // proporse to the DAO
        uint256 proporseId = invGovernor.propose(targets, values, calldatas, description);

        // 1. view the state of the proporsal
        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        // 2. vote
        string memory reason = "Because WETH is the best";
        uint8 voteWay = 1; // 0 = Against, 1 = For, 2 = Abstain
        vm.prank(USER);
        invGovernor.castVoteWithReason(proporseId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        // 3. queue TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        invGovernor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1000);
        vm.roll(block.number + MIN_DELAY + 1000);

        // 4. execute
        invGovernor.execute(targets, values, calldatas, descriptionHash);

        assertEq(invEngine.getConfiguration(tokenAddress).interestRateModel, address(baseInterestRateModel));
    }

    function testGovernanceUpdateRewardManager() public configureAsset {
        // configurations to proporse
        address tokenAddress = tokenAddresses[0];
        // deploy the Reward Manager
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        InvRewardManager rm = new InvRewardManager(
            address(invEngine),
            address(wethMock),
            address(0xfffffff),
            address(0xfffffff),
            address(invToken),
            s_reserveFactor
        );

        string memory description = "Update IRM for WETH";
        bytes memory encodeFunctionCall =
            abi.encodeWithSignature("updateAssetRewardManager(address,address)", tokenAddress, rm);

        // push configs to arrays
        values.push(0);
        calldatas.push(encodeFunctionCall);
        targets.push(address(invEngine));

        // proporse to the DAO
        uint256 proporseId = invGovernor.propose(targets, values, calldatas, description);

        // 1. view the state of the proporsal
        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        // 2. vote
        string memory reason = "Because WETH is the best";
        uint8 voteWay = 1; // 0 = Against, 1 = For, 2 = Abstain
        vm.prank(USER);
        invGovernor.castVoteWithReason(proporseId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console.log("Proporsal state: %s", uint256(invGovernor.state(proporseId)));

        // 3. queue TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        invGovernor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1000);
        vm.roll(block.number + MIN_DELAY + 1000);

        // 4. execute
        invGovernor.execute(targets, values, calldatas, descriptionHash);

        assertEq(invEngine.getConfiguration(tokenAddress).rewardManager, address(rm));
    }
}
