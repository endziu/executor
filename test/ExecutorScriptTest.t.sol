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

    // `vm.setEnv` mutates process-global state and Foundry snapshots after the
    // single `setUp` run, so each test sets OWNER itself rather than relying on
    // a shared value that another test could have overwritten.

    function testRunDeploysOnBaseMainnet() public {
        vm.chainId(8453);
        vm.setEnv("OWNER", vm.toString(OWNER));

        deploymentScript.run();

        assertEq(deploymentScript.executor().OWNER(), OWNER);
    }

    function testRunDeploysOnBaseSepolia() public {
        vm.chainId(84532);
        vm.setEnv("OWNER", vm.toString(OWNER));

        deploymentScript.run();

        assertEq(deploymentScript.executor().OWNER(), OWNER);
    }

    function testRunRevertsOnUnsupportedChain() public {
        vm.chainId(1);
        vm.setEnv("OWNER", vm.toString(OWNER));
        vm.expectRevert(abi.encodeWithSignature("UnsupportedChain(uint256)", 1));

        deploymentScript.run();
    }

    function testRunRevertsOnZeroOwner() public {
        vm.chainId(8453);
        vm.setEnv("OWNER", vm.toString(address(0)));
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));

        deploymentScript.run();
    }
}
