// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExecutorTest, FailingTarget, ReentrantAttacker} from "./BaseExecutorTest.t.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorExecuteTest is BaseExecutorTest {
    function testExecuteAsOwner() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        vm.prank(OWNER);
        executor.execute(address(target1), data);
        assertEq(target1.number(), 42);
    }

    function testExecuteWithEther() public {
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSelector(target1.receiveEther.selector);
        vm.prank(OWNER);
        vm.deal(OWNER, amount);
        executor.execute{value: amount}(address(target1), data);
        assertEq(address(target1).balance, amount);
    }

    function testCannotExecuteAsNonOwner() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        vm.prank(ALICE);
        vm.expectRevert(Executor.NotOwner.selector);
        executor.execute(address(target1), data);
    }

    function testCannotExecuteToZeroAddress() public {
        vm.prank(OWNER);
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        vm.expectRevert(Executor.InvalidTarget.selector);
        executor.execute(address(0), data);
    }

    function testCannotExecuteEmptyCallWithNoValue() public {
        vm.prank(OWNER);
        vm.expectRevert(Executor.NoTransactionData.selector);
        executor.execute(address(target1), "");
    }

    function testExecuteGas() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        uint256 gasBefore = gasleft();
        vm.prank(OWNER);
        executor.execute(address(target1), data);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Execute Gas Used", gasUsed);
    }

    function testExecuteEmitsEvent() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        bytes memory expectedResult = abi.encode(); // Empty because setNumber doesn't return anything

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit Executed(address(target1), data, expectedResult);
        executor.execute(address(target1), data);
    }

    function testExecuteReverts() public {
        FailingTarget failingTarget = new FailingTarget();
        bytes memory data = abi.encodeWithSelector(failingTarget.alwaysRevert.selector);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.ExecutionFailed.selector, 0));
        executor.execute(address(failingTarget), data);
    }

    function testCannotReenterExecute() public {
        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(executor)));

        bytes memory data = abi.encodeWithSignature("doNothing()");
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.ExecutionFailed.selector, 0));
        executor.execute(address(attacker), data);
    }
}
