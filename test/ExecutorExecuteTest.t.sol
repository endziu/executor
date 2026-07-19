// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExecutorTest, FailingTarget, ReentrantAttacker} from "./BaseExecutorTest.t.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorExecuteTest is BaseExecutorTest {
    function testExecuteSpendsStoredEther() public {
        vm.deal(address(executor), 2 ether);

        bytes memory data = abi.encodeWithSelector(target1.receiveEther.selector);
        vm.prank(OWNER);
        executor.execute(address(target1), data, 1 ether);

        assertEq(address(target1).balance, 1 ether);
        assertEq(address(executor).balance, 1 ether);
    }

    function testExecuteCombinesStoredAndFreshEther() public {
        vm.deal(address(executor), 1 ether);

        bytes memory data = abi.encodeWithSelector(target1.receiveEther.selector);
        vm.prank(OWNER);
        executor.execute{value: 1 ether}(address(target1), data, 1.5 ether);

        assertEq(address(target1).balance, 1.5 ether);
        assertEq(address(executor).balance, 0.5 ether);
    }

    function testExecuteRetainsExcessFreshEther() public {
        bytes memory data = abi.encodeWithSelector(target1.receiveEther.selector);
        vm.prank(OWNER);
        executor.execute{value: 1 ether}(address(target1), data, 0.5 ether);

        assertEq(address(target1).balance, 0.5 ether);
        assertEq(address(executor).balance, 0.5 ether);
    }

    function testExecuteDoesNotAutomaticallyForwardMsgValue() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        vm.prank(OWNER);
        executor.execute{value: 1 ether}(address(target1), data, 0);

        assertEq(target1.number(), 42);
        assertEq(address(target1).balance, 0);
        assertEq(address(executor).balance, 1 ether);
    }

    function testCannotExecuteAboveAvailableBalance() public {
        vm.deal(address(executor), 1 ether);

        bytes memory data = abi.encodeWithSelector(target1.receiveEther.selector);
        vm.prank(OWNER);
        vm.expectRevert(Executor.InsufficientBalance.selector);
        executor.execute(address(target1), data, 2 ether);
    }

    function testExecuteStoredEtherTransferToEOA() public {
        vm.deal(address(executor), 1 ether);
        uint256 balanceBefore = ALICE.balance;

        vm.prank(OWNER);
        executor.execute(ALICE, "", 1 ether);

        assertEq(ALICE.balance, balanceBefore + 1 ether);
        assertEq(address(executor).balance, 0);
    }

    function testExecuteFailureRollsBackStoredAndFreshEther() public {
        FailingTarget failingTarget = new FailingTarget();
        vm.deal(address(executor), 2 ether);
        uint256 ownerBalanceBefore = OWNER.balance;

        bytes memory data = abi.encodeWithSelector(failingTarget.alwaysRevert.selector);
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.ExecutionFailed.selector, 0));
        executor.execute{value: 1 ether}(address(failingTarget), data, 2.5 ether);

        assertEq(address(executor).balance, 2 ether);
        assertEq(address(failingTarget).balance, 0);
        assertEq(OWNER.balance, ownerBalanceBefore);
    }

    function testExecuteAsOwner() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        vm.prank(OWNER);
        executor.execute(address(target1), data, 0);
        assertEq(target1.number(), 42);
    }

    function testExecuteWithEther() public {
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSelector(target1.receiveEther.selector);
        vm.prank(OWNER);
        vm.deal(OWNER, amount);
        executor.execute{value: amount}(address(target1), data, amount);
        assertEq(address(target1).balance, amount);
    }

    function testCannotExecuteAsNonOwner() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        vm.prank(ALICE);
        vm.expectRevert(Executor.NotOwner.selector);
        executor.execute(address(target1), data, 0);
    }

    function testCannotExecuteToZeroAddress() public {
        vm.prank(OWNER);
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        vm.expectRevert(Executor.InvalidTarget.selector);
        executor.execute(address(0), data, 0);
    }

    function testCannotExecuteEmptyCallWithNoValue() public {
        vm.prank(OWNER);
        vm.expectRevert(Executor.NoTransactionData.selector);
        executor.execute(address(target1), "", 0);
    }

    function testExecuteGas() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        uint256 gasBefore = gasleft();
        vm.prank(OWNER);
        executor.execute(address(target1), data, 0);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Execute Gas Used", gasUsed);
    }

    function testExecuteEmitsEvent() public {
        bytes memory data = abi.encodeWithSelector(target1.receiveEther.selector);
        vm.deal(address(executor), 1 ether);
        bytes32 expectedResultHash = keccak256("");

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit Executed(address(target1), 1 ether, data, expectedResultHash);
        executor.execute(address(target1), data, 1 ether);
    }

    // L-2: a call carrying calldata to a codeless address (EOA) would report
    // success without executing anything; it must revert instead.
    function testCannotExecuteWithDataToCodelessTarget() public {
        bytes memory data = abi.encodeWithSelector(target1.setNumber.selector, 42);
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.TargetNotContract.selector, 0));
        executor.execute(ALICE, data, 0);
    }

    // L-2: a bare ETH transfer (no calldata) to an EOA remains allowed.
    function testExecuteBareEthTransferToEOA() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = ALICE.balance;

        vm.prank(OWNER);
        vm.deal(OWNER, amount);
        executor.execute{value: amount}(ALICE, "", amount);

        assertEq(ALICE.balance, balanceBefore + amount);
    }

    function testExecuteReverts() public {
        FailingTarget failingTarget = new FailingTarget();
        bytes memory data = abi.encodeWithSelector(failingTarget.alwaysRevert.selector);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.ExecutionFailed.selector, 0));
        executor.execute(address(failingTarget), data, 0);
    }

    function testCannotReenterExecute() public {
        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(executor)));

        bytes memory data = abi.encodeWithSignature("doNothing()");
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.ExecutionFailed.selector, 0));
        executor.execute(address(attacker), data, 0);
    }
}
