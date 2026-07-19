// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {ExecutorScript} from "../script/Executor.s.sol";

contract ExecutorScriptTest is Test {
    address private constant OWNER = address(0xabc);

    ExecutorScript private deploymentScript;

    function setUp() public {
        deploymentScript = new ExecutorScript();
        vm.setEnv("OWNER", vm.toString(OWNER));
    }

    function testRunDeploysOnBaseMainnet() public {
        vm.chainId(8453);

        deploymentScript.run();

        assertEq(deploymentScript.executor().OWNER(), OWNER);
    }

    function testRunDeploysOnBaseSepolia() public {
        vm.chainId(84532);

        deploymentScript.run();

        assertEq(deploymentScript.executor().OWNER(), OWNER);
    }

    function testRunRevertsOnUnsupportedChain() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSignature("UnsupportedChain(uint256)", 1));

        deploymentScript.run();
    }
}
