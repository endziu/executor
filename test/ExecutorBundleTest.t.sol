// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExecutorTest, FailingTarget} from "./BaseExecutorTest.t.sol";
import {Executor} from "../src/Executor.sol";
import {stdError} from "forge-std/StdError.sol";

contract ExecutorBundleTest is BaseExecutorTest {
    function testFuzzBundleExecuteForwardsExactValues(uint256 firstValue, uint256 secondValue, uint256 retained)
        public
    {
        firstValue = bound(firstValue, 0, 10 ether);
        secondValue = bound(secondValue, 0, 10 ether);
        retained = bound(retained, 0, 10 ether);
        vm.deal(address(executor), firstValue + secondValue + retained);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target2);
        data[0] = abi.encodeWithSelector(target1.receiveEther.selector);
        data[1] = abi.encodeWithSelector(target2.receiveEther.selector);
        values[0] = firstValue;
        values[1] = secondValue;

        vm.prank(OWNER);
        executor.bundleExecute(targets, data, values);

        assertEq(address(target1).balance, firstValue);
        assertEq(address(target2).balance, secondValue);
        assertEq(address(executor).balance, retained);
    }

    function testBundleExecuteSpendsStoredEther() public {
        vm.deal(address(executor), 2 ether);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target2);
        data[0] = abi.encodeWithSelector(target1.receiveEther.selector);
        data[1] = abi.encodeWithSelector(target2.receiveEther.selector);
        values[0] = 0.5 ether;
        values[1] = 0.5 ether;

        vm.prank(OWNER);
        executor.bundleExecute(targets, data, values);

        assertEq(address(target1).balance, 0.5 ether);
        assertEq(address(target2).balance, 0.5 ether);
        assertEq(address(executor).balance, 1 ether);
    }

    function testBundleExecuteCombinesStoredAndFreshEther() public {
        vm.deal(address(executor), 1 ether);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target2);
        data[0] = abi.encodeWithSelector(target1.receiveEther.selector);
        data[1] = abi.encodeWithSelector(target2.receiveEther.selector);
        values[0] = 0.75 ether;
        values[1] = 0.75 ether;

        vm.prank(OWNER);
        executor.bundleExecute{value: 1 ether}(targets, data, values);

        assertEq(address(target1).balance, 0.75 ether);
        assertEq(address(target2).balance, 0.75 ether);
        assertEq(address(executor).balance, 0.5 ether);
    }

    function testBundleExecuteRetainsExcessFreshEther() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(target1);
        data[0] = abi.encodeWithSelector(target1.receiveEther.selector);
        values[0] = 0.5 ether;

        vm.prank(OWNER);
        executor.bundleExecute{value: 1 ether}(targets, data, values);

        assertEq(address(target1).balance, 0.5 ether);
        assertEq(address(executor).balance, 0.5 ether);
    }

    function testBundleExecute() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target2);
        data[0] = abi.encodeWithSelector(target1.setNumber.selector, 42);
        data[1] = abi.encodeWithSelector(target2.setNumber.selector, 99);
        values[0] = 0;
        values[1] = 0;

        vm.prank(OWNER);
        executor.bundleExecute(targets, data, values);

        assertEq(target1.number(), 42);
        assertEq(target2.number(), 99);
    }

    function testBundleExecuteWithEther() public {
        uint256 amount1 = 0.25 ether;
        uint256 amount2 = 0.75 ether;

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target2);
        data[0] = abi.encodeWithSelector(target1.receiveEther.selector);
        data[1] = abi.encodeWithSelector(target2.receiveEther.selector);
        values[0] = amount1;
        values[1] = amount2;

        vm.prank(OWNER);
        vm.deal(OWNER, amount1 + amount2);
        executor.bundleExecute{value: amount1 + amount2}(targets, data, values);

        assertEq(address(target1).balance, amount1);
        assertEq(address(target2).balance, amount2);
    }

    function testBundleExecuteEmitsEvent() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target1);
        data[0] = abi.encodeWithSelector(target1.setNumber.selector, 42);
        data[1] = abi.encodeWithSelector(target1.setNumber.selector, 43);
        values[0] = 0;
        values[1] = 0;

        vm.prank(OWNER);
        vm.expectEmit();
        emit BundleExecuted(targets, values, data);
        executor.bundleExecute(targets, data, values);
    }

    function testCannotBundleExecuteWithMismatchedArrays() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](2);

        vm.prank(OWNER);
        vm.expectRevert(Executor.MismatchedArrays.selector);
        executor.bundleExecute(targets, data, values);
    }

    function testCannotBundleExecuteWithEmptyArrays() public {
        address[] memory targets = new address[](0);
        bytes[] memory data = new bytes[](0);
        uint256[] memory values = new uint256[](0);

        vm.prank(OWNER);
        vm.expectRevert(Executor.NoTargets.selector);
        executor.bundleExecute(targets, data, values);
    }

    function testBundleExecuteGas() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target2);
        data[0] = abi.encodeWithSelector(target1.setNumber.selector, 42);
        data[1] = abi.encodeWithSelector(target2.setNumber.selector, 99);
        values[0] = 0;
        values[1] = 0;

        uint256 gasBefore = gasleft();
        vm.prank(OWNER);
        executor.bundleExecute(targets, data, values);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("Bundle Execute Gas Used", gasUsed);
    }

    function testCannotBundleExecuteAboveAvailableBalance() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target1);
        data[0] = abi.encodeWithSelector(target1.receiveEther.selector);
        data[1] = abi.encodeWithSelector(target1.receiveEther.selector);
        values[0] = 0.5 ether;
        values[1] = 0.5 ether;

        vm.prank(OWNER);
        vm.deal(OWNER, 0.5 ether);
        vm.expectRevert(Executor.InsufficientBalance.selector);
        executor.bundleExecute{value: 0.5 ether}(targets, data, values);
    }

    function testCannotBundleExecuteWhenValueSumOverflows() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target2);
        values[0] = type(uint256).max;
        values[1] = 1;

        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        executor.bundleExecute(targets, data, values);
    }

    function testBundleExecuteWithZeroValues() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(target2);
        data[0] = "";
        data[1] = "";
        values[0] = 0;
        values[1] = 0;

        vm.prank(OWNER);
        executor.bundleExecute(targets, data, values);
    }

    function testBundleExecuteWithSingleCall() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(target1);
        data[0] = abi.encodeWithSelector(target1.setNumber.selector, 42);
        values[0] = 0;

        vm.prank(OWNER);
        executor.bundleExecute(targets, data, values);
        assertEq(target1.number(), 42);
    }

    function testCannotBundleExecuteWithZeroAddressTarget() public {
        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);
        uint256[] memory values = new uint256[](3);

        targets[0] = address(target1);
        targets[1] = address(0);
        targets[2] = address(target2);
        data[0] = abi.encodeWithSelector(target1.setNumber.selector, 42);
        data[1] = "";
        data[2] = abi.encodeWithSelector(target2.setNumber.selector, 99);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        vm.prank(OWNER);
        vm.expectRevert(Executor.InvalidTarget.selector);
        executor.bundleExecute(targets, data, values);

        assertEq(target1.number(), 0);
        assertEq(target2.number(), 0);
    }

    // L-2: a bundle leg carrying calldata to a codeless address reverts at that
    // index and rolls back the whole bundle.
    function testCannotBundleExecuteWithDataToCodelessTarget() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = ALICE; // EOA — no code
        data[0] = abi.encodeWithSelector(target1.setNumber.selector, 42);
        data[1] = abi.encodeWithSelector(target2.setNumber.selector, 99);
        values[0] = 0;
        values[1] = 0;

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.TargetNotContract.selector, 1));
        executor.bundleExecute(targets, data, values);

        assertEq(target1.number(), 0);
    }

    // L-2: bundle legs that are bare ETH transfers (no calldata) to EOAs remain
    // allowed.
    function testBundleExecuteBareEthTransferToEOA() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        uint256 amount = 1 ether;
        uint256 balanceBefore = BOB.balance;

        targets[0] = BOB;
        data[0] = "";
        values[0] = amount;

        vm.prank(OWNER);
        vm.deal(OWNER, amount);
        executor.bundleExecute{value: amount}(targets, data, values);

        assertEq(BOB.balance, balanceBefore + amount);
    }

    function testBundleExecuteRevertsWholeBundleOnFailedCall() public {
        FailingTarget failingTarget = new FailingTarget();

        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);
        uint256[] memory values = new uint256[](3);

        targets[0] = address(target1);
        targets[1] = address(failingTarget);
        targets[2] = address(target2);
        data[0] = abi.encodeWithSelector(target1.setNumber.selector, 42);
        data[1] = abi.encodeWithSelector(failingTarget.alwaysRevert.selector);
        data[2] = abi.encodeWithSelector(target2.setNumber.selector, 99);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.ExecutionFailed.selector, 1));
        executor.bundleExecute(targets, data, values);

        assertEq(target1.number(), 0);
        assertEq(target2.number(), 0);
    }

    function testBundleExecuteFailureRollsBackStoredAndFreshEther() public {
        FailingTarget failingTarget = new FailingTarget();
        vm.deal(address(executor), 2 ether);
        uint256 ownerBalanceBefore = OWNER.balance;

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(target1);
        targets[1] = address(failingTarget);
        data[0] = abi.encodeWithSelector(target1.setNumber.selector, 42);
        data[1] = abi.encodeWithSelector(failingTarget.alwaysRevert.selector);
        values[0] = 0;
        values[1] = 2.5 ether;

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Executor.ExecutionFailed.selector, 1));
        executor.bundleExecute{value: 1 ether}(targets, data, values);

        assertEq(target1.number(), 0);
        assertEq(address(executor).balance, 2 ether);
        assertEq(address(failingTarget).balance, 0);
        assertEq(OWNER.balance, ownerBalanceBefore);
    }
}
