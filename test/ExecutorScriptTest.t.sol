// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {ExecutorScript} from "../script/Executor.s.sol";

contract ExecutorScriptTest is Test {
    address private constant OWNER = address(0xabc);

    ExecutorScript private deploymentScript;

    function setUp() public {
        deploymentScript = new ExecutorScript();
    }

    // Tests drive the owner-parameterized `run(address)` overload directly. The
    // env-reading `run()` wrapper is a one-line delegate; passing the owner here
    // avoids racing on the process-global `OWNER` env var, since Foundry runs
    // test functions concurrently.

    function testRunDeploysOnBaseMainnet() public {
        vm.chainId(8453);

        deploymentScript.run(OWNER);

        assertEq(deploymentScript.executor().OWNER(), OWNER);
    }

    function testRunDeploysOnBaseSepolia() public {
        vm.chainId(84532);

        deploymentScript.run(OWNER);

        assertEq(deploymentScript.executor().OWNER(), OWNER);
    }

    function testRunRevertsOnUnsupportedChain() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSignature("UnsupportedChain(uint256)", 1));

        deploymentScript.run(OWNER);
    }

    function testRunRevertsOnZeroOwner() public {
        vm.chainId(8453);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));

        deploymentScript.run(address(0));
    }
}
