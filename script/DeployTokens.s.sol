// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {Faucet} from "../src/Faucet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {WrapToken} from "../src/WrapToken.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {InvRewardManager} from "../src/InvRewardManager.sol";
import {InvInterestRateModel} from "../src/InvInterestRateModel.sol";
import {InvFeeManager} from "../src/InvFeeManager.sol";
import {InvEngine} from "../src/InvEngine.sol";

contract DeployTokens is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 25000e8;
    uint256 public constant AMOUNT_TO_MINT = 100000e18;
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = // wallet private key here;
    address deployerAddress = // wallet address here;
    address public usdcPriceFeed = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address public linkPriceFeed = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    address public daiPriceFeed = 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19;

    address[] private tokenAddresses;
    address[] private priceFeedAddresses;
    address[] private wrapTokenAddresses;

    uint256 private s_reserveFactor = 2e17; // 20%

    InvRewardManager usdcRewardManager;
    InvRewardManager linkRewardManager;
    InvRewardManager daiRewardManager;
    InvInterestRateModel baseInterestRateModel;
    InvFeeManager feeManager;

    uint256 private s_baseRatePerYear = 0.06 ether; // 5%
    uint256 private s_multiplierPerYear = 0.25 ether; // 25%
    uint256 private s_jumpMultiplierPerYear = 0.5 ether; // 40%
    uint256 private s_inflectionPoint = 0.65 ether; // 80%
    uint256 private s_smoothingFactor = 0.01 ether; // 1%
    uint256 private s_maxRatePerYear = 0.25 ether; // 40%
    uint256 private s_minRatePerYear = 0.02 ether; // 1%
    // address private constant OWNER = "";

    struct Configuration {
        uint256 lendFactor;
        uint256 borrowFactor;
        uint256 liquidationThreshold;
        address interestRateModel;
        address rewardManager;
    }

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // invEngine address
        InvEngine invEngine = InvEngine(
            // 0xd13E27C299b7DE2F9e6dCd0366d60db0BF9e5956
            // add invengine address you deployed here
            );

        // @custom:todo maybe we need transfer ownership to invEngine (msg.sender) ??? I don't know 
        WrapToken usdcToken = new WrapToken("USDC", "USDC");
        WrapToken invUsdc = new WrapToken("invUsdc", "invUsdc");
        usdcToken.mint(deployerAddress, AMOUNT_TO_MINT);
        // usdcToken.transferOwnership(deployerAddress);
        // invUsdc.transferOwnership(deployerAddress);
        address usdc = address(usdcToken);

        // @custom:todo maybe we need transfer ownership to invEngine (msg.sender) ??? I don't know 
        WrapToken invLink = new WrapToken("invLink", "invLink");
        WrapToken linkToken = new WrapToken("Link", "Link");
        linkToken.mint(deployerAddress, AMOUNT_TO_MINT);
        // invLink.transferOwnership(deployerAddress);
        // linkToken.transferOwnership(deployerAddress);
        address link = address(linkToken);

        // WrapToken daiToken = new WrapToken("DAI", "DAI");
        // WrapToken invDai = new WrapToken("invDai", "invDai");
        // daiToken.mint(deployerAddress, AMOUNT_TO_MINT);
        // // daiToken.transferOwnership(deployerAddress);
        // // invDai.transferOwnership(deployerAddress);
        // address dai = address(daiToken);

        tokenAddresses = [usdc, link];
        priceFeedAddresses = [usdcPriceFeed, linkPriceFeed];
        wrapTokenAddresses = [address(invUsdc), address(invLink)];

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
        usdcRewardManager = new InvRewardManager(
            address(invEngine),
            usdc,
            address(invEngine),
            address(baseInterestRateModel),
            address(invUsdc),
            s_reserveFactor
        );
        linkRewardManager = new InvRewardManager(
            address(invEngine),
            link,
            address(invEngine),
            address(baseInterestRateModel),
            address(invLink),
            s_reserveFactor
        );
        // daiRewardManager = new InvRewardManager(
        //     address(invEngine), dai, address(invEngine), address(baseInterestRateModel), address(invDai)
        // );

        // configure assets
        configureAssets(invEngine);

        // transfer ownership
        WrapToken(invUsdc).transferOwnership(address(invEngine));
        WrapToken(invLink).transferOwnership(address(invEngine));
        // WrapToken(invDai).transferOwnership(address(invEngine));

        vm.stopBroadcast();
    }

    function configureAssets(InvEngine invEngine) internal {
        InvEngine.Configuration[] memory assetConfigurations = new InvEngine.Configuration[](2);
        assetConfigurations[0] =
            InvEngine.Configuration(85, 0, 90, address(baseInterestRateModel), address(usdcRewardManager));
        assetConfigurations[1] =
            InvEngine.Configuration(65, 0, 75, address(baseInterestRateModel), address(linkRewardManager));
        // assetConfigurations[1] =
        //     InvEngine.Configuration(85, 0, 90, address(baseInterestRateModel), address(daiRewardManager));

        invEngine.configureAsset(tokenAddresses, priceFeedAddresses, wrapTokenAddresses, assetConfigurations);
    }
}
