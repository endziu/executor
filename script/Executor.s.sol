// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import {Script} from "forge-std/Script.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorScript is Script {
    Executor public executor;

    function run() public {
        address owner = vm.envAddress("OWNER");

        vm.startBroadcast();
        executor = new Executor(owner);
        vm.stopBroadcast();

        require(executor.OWNER() == owner, "Executor owner mismatch");
    }
}
