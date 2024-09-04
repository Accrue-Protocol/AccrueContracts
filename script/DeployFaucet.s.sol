// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {Faucet} from "../src/Faucet.sol";

contract DeployFaucet is Script {
    function run() external returns (Faucet) {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // deploy the faucet
        Faucet faucet = new Faucet();

        vm.stopBroadcast();

        return (faucet);
    }
}
