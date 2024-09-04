// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {WrapToken} from "../src/WrapToken.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 25000e8;
    uint256 public constant AMOUNT_TO_MINT = 100000e18;
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = // wallet private key here;
    address deployerAddress = // wallet address here;

    struct NetworkConfig {
        address weth;
        address wethPriceFeed;
        address invEth;
        address wbtc;
        address wbtcPriceFeed;
        address invBtc;
        uint256 deployerKey;
    }

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public returns (NetworkConfig memory sepoliaNetworkConfig) {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // @custom:todo maybe we need transfer ownership to invEngine (msg.sender) ??? I don't know yet
        WrapToken wethToken = new WrapToken("WETH", "WETH");
        WrapToken invEth = new WrapToken("invEth", "invEth");
        wethToken.mint(deployerAddress, AMOUNT_TO_MINT);
        wethToken.transferOwnership(deployerAddress);
        invEth.transferOwnership(deployerAddress);
        address weth = address(wethToken);
        address wethPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

        // @custom:todo maybe we need transfer ownership to invEngine (msg.sender) ??? I don't know yet
        WrapToken invBtc = new WrapToken("invBtc", "invBtc");
        WrapToken wbtc = new WrapToken("WBTC", "WBTC");
        wbtc.mint(deployerAddress, AMOUNT_TO_MINT);
        invBtc.transferOwnership(deployerAddress);
        wbtc.transferOwnership(deployerAddress);
        address wbtcPriceFeed = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

        vm.envUint("PRIVATE_KEY");

        sepoliaNetworkConfig = NetworkConfig({
            weth: weth,
            wethPriceFeed: wethPriceFeed,
            invEth: address(invEth),
            wbtc: address(wbtc),
            wbtcPriceFeed: wbtcPriceFeed,
            invBtc: address(invBtc),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        vm.stopBroadcast();
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        WrapToken invEth = new WrapToken("invEth", "invEth");
        invEth.transferOwnership(msg.sender);

        // @custom:todo maybe we need transfer ownership to invEngine (msg.sender) ??? I don't know yet
        MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        WrapToken invBtc = new WrapToken("invBtc", "invBtc");
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        invBtc.transferOwnership(msg.sender);

        anvilNetworkConfig = NetworkConfig({
            weth: address(wethMock),
            wethPriceFeed: address(wethPriceFeed),
            invEth: address(invEth),
            wbtc: address(wbtcMock),
            wbtcPriceFeed: address(wbtcPriceFeed),
            invBtc: address(invBtc),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });

        vm.stopBroadcast();
    }
}
