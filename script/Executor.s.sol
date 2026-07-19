// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import {Script} from "forge-std/Script.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorScript is Script {
    uint256 private constant BASE_CHAIN_ID = 8453;
    uint256 private constant BASE_SEPOLIA_CHAIN_ID = 84532;

    Executor public executor;

    error UnsupportedChain(uint256 chainId);

    function run() public {
        if (block.chainid != BASE_CHAIN_ID && block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert UnsupportedChain(block.chainid);
        }

        address owner = vm.envAddress("OWNER");

        vm.startBroadcast();
        executor = new Executor(owner);
        vm.stopBroadcast();

        require(executor.OWNER() == owner, "Executor owner mismatch");
    }
}
