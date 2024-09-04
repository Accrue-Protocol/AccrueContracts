// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {WrapToken} from "../src/WrapToken.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {InvToken} from "../src/InvariantToken.sol";
import {InvEngine} from "../src/InvEngine.sol";
import {InvInterestRateModel} from "../src/InvInterestRateModel.sol";
import {InvRewardManager} from "../src/InvRewardManager.sol";
import {InvFeeManager} from "../src/InvFeeManager.sol";

contract DeployInv is Script {
    address[] private tokenAddresses;
    address[] private priceFeedAddresses;
    address[] private wrapTokenAddresses;

    InvRewardManager wethRewardManager;
    InvRewardManager wbtcRewardManager;
    InvInterestRateModel baseInterestRateModel;
    InvFeeManager feeManager;

    uint256 private s_baseRatePerYear = 0.05 ether; // 5%
    uint256 private s_multiplierPerYear = 0.15 ether; // 15%
    uint256 private s_jumpMultiplierPerYear = 0.3 ether; // 40%
    uint256 private s_inflectionPoint = 0.6 ether; // 80%
    uint256 private s_smoothingFactor = 0.1 ether; // 2%
    uint256 private s_maxRatePerYear = 0.2 ether; // 40%
    uint256 private s_minRatePerYear = 0.02 ether; // 1%

    uint256 private s_reserveFactor = 2e17; // 20%
    // address private constant OWNER = "";

    struct Configuration {
        uint256 lendFactor;
        uint256 borrowFactor;
        uint256 liquidationThreshold;
        address interestRateModel;
        address rewardManager;
    }

    function run()
        external
        returns (InvToken, InvEngine, HelperConfig, InvInterestRateModel, InvRewardManager, InvRewardManager)
    {
        // deploy helper config
        HelperConfig config = new HelperConfig();

        // get pool data info from helper config
        (
            address weth,
            address wethPriceFeed,
            address invEth,
            address wbtc,
            address wbtcPriceFeed,
            address invBTC,
            uint256 deployerKey
        ) = config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethPriceFeed, wbtcPriceFeed];
        wrapTokenAddresses = [invEth, invBTC];

        // vm.startBroadcast(deployerKey);
        vm.startBroadcast(msg.sender);

        // deploy the base token and the INVEngine
        InvToken invariantToken = new InvToken();
        InvEngine invEngine = new InvEngine(msg.sender);

        // deploy feeManager and set it as the feeManager of the INVEngine
        feeManager = new InvFeeManager(msg.sender, address(invEngine));
        invEngine.setFeeManager(address(feeManager));

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

        // deploy the reward manager for tokens
        wethRewardManager = new InvRewardManager(
            address(invEngine),
            weth,
            address(invEngine),
            address(baseInterestRateModel),
            address(invEth),
            s_reserveFactor
        );
        wbtcRewardManager = new InvRewardManager(
            address(invEngine),
            wbtc,
            address(invEngine),
            address(baseInterestRateModel),
            address(invBTC),
            s_reserveFactor
        );

        // configure assets
        configureAssets(invEngine);

        // transfer ownership of the Invariant Token from msg.sender to INVEngine
        invariantToken.transferOwnership(address(invEngine));

        // WrapToken(invEth).transferOwnership(address(invEngine));
        // WrapToken(invBTC).transferOwnership(address(invEngine));

        vm.stopBroadcast();
        vm.startBroadcast(address(this));
        WrapToken(invEth).transferOwnership(address(invEngine));
        WrapToken(invBTC).transferOwnership(address(invEngine));
        vm.stopBroadcast();

        return (invariantToken, invEngine, config, baseInterestRateModel, wethRewardManager, wbtcRewardManager);
    }

    function configureAssets(InvEngine invEngine) internal {
        InvEngine.Configuration[] memory assetConfigurations = new InvEngine.Configuration[](2);
        assetConfigurations[0] =
            InvEngine.Configuration(75, 0, 80, address(baseInterestRateModel), address(wethRewardManager));
        assetConfigurations[1] =
            InvEngine.Configuration(75, 0, 80, address(baseInterestRateModel), address(wbtcRewardManager));

        invEngine.configureAsset(tokenAddresses, priceFeedAddresses, wrapTokenAddresses, assetConfigurations);
    }
}
