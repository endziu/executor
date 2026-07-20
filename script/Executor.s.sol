// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import {Script, console2} from "forge-std/Script.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorScript is Script {
    uint256 private constant BASE_CHAIN_ID = 8453;
    uint256 private constant BASE_SEPOLIA_CHAIN_ID = 84532;

    Executor public executor;

    error UnsupportedChain(uint256 chainId);

    /// @notice Entry point for `forge script`; reads the owner from the `OWNER` env var.
    function run() public {
        run(vm.envAddress("OWNER"));
    }

    /// @dev Owner-parameterized deploy. Kept as an explicit overload so tests can
    ///      pass the owner directly and avoid racing on the process-global `OWNER`
    ///      env var (Foundry runs test functions concurrently).
    function run(address owner) public {
        if (block.chainid != BASE_CHAIN_ID && block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert UnsupportedChain(block.chainid);
        }

        vm.startBroadcast();
        executor = new Executor(owner);
        vm.stopBroadcast();

        // Confirms the constructor stored the supplied value. This cannot verify
        // the owner is the *intended* one — a wrong-but-valid address (typo, or
        // the raw form where an L1->L2-aliased address is required) is immutable
        // and unrecoverable. Verify the logged owner on a block explorer before
        // funding; see the owner-verification runbook in CLAUDE.md.
        require(executor.OWNER() == owner, "Executor owner mismatch");

        console2.log("Executor deployed at:", address(executor));
        console2.log("Resolved OWNER (verify before funding):", owner);
    }
}
