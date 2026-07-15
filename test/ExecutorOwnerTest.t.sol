// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExecutorTest} from "./BaseExecutorTest.t.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorOwnerTest is BaseExecutorTest {
    function testCorrectOwnerAtDeployment() public view {
        assertEq(executor.OWNER(), OWNER);
    }

    function testGetOwnerMatchesOwner() public view {
        assertEq(executor.getOwner(), executor.OWNER());
    }

    function testCannotDeployWithZeroAddress() public {
        vm.expectRevert();
        new Executor(address(0));
    }
}
