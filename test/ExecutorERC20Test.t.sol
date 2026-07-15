// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExecutorTest, EmptyRevertERC20, NoReturnERC20, RevertingERC20} from "./BaseExecutorTest.t.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorERC20Test is BaseExecutorTest {
    function testWithdrawERC20() public {
        uint256 amount = 1000;

        // Fund the executor with tokens
        token.mint(address(executor), amount);
        assertEq(token.balanceOf(address(executor)), amount);

        // Test withdrawal
        vm.prank(OWNER);
        executor.withdrawERC20(address(token), amount, ALICE);

        assertEq(token.balanceOf(address(executor)), 0);
        assertEq(token.balanceOf(ALICE), amount);
    }

    function testCannotWithdrawERC20AsNonOwner() public {
        uint256 amount = 1000;
        token.mint(address(executor), amount);

        vm.prank(ALICE);
        vm.expectRevert(Executor.NotOwner.selector);
        executor.withdrawERC20(address(token), amount, ALICE);
    }

    function testCannotWithdrawMoreERC20ThanBalance() public {
        uint256 amount = 1000;
        token.mint(address(executor), amount);

        vm.prank(OWNER);
        vm.expectRevert(Executor.InsufficientTokenBalance.selector);
        executor.withdrawERC20(address(token), amount + 1, ALICE);
    }

    function testRevertOnFailedERC20Transfer() public {
        uint256 amount = 1000;

        // Fund the executor
        token.mint(address(executor), amount);

        // Make transfers fail
        token.setTransferShouldFail(true);

        // Test withdrawal
        vm.prank(OWNER);
        vm.expectRevert(Executor.ERC20TransferFailed.selector);
        executor.withdrawERC20(address(token), amount, ALICE);

        // Verify balances didn't change
        assertEq(token.balanceOf(address(executor)), amount);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testCannotWithdrawERC20FromNonContractToken() public {
        vm.prank(OWNER);
        vm.expectRevert(Executor.InvalidTarget.selector);
        executor.withdrawERC20(ALICE, 1000, BOB);
    }

    function testCannotWithdrawERC20WithZeroToken() public {
        vm.prank(OWNER);
        vm.expectRevert(Executor.ZeroAddress.selector);
        executor.withdrawERC20(address(0), 1000, ALICE);
    }

    function testCannotWithdrawERC20ToZeroAddress() public {
        uint256 amount = 1000;
        token.mint(address(executor), amount);

        vm.prank(OWNER);
        vm.expectRevert(Executor.ZeroAddress.selector);
        executor.withdrawERC20(address(token), amount, address(0));
    }

    function testCannotWithdrawERC20BubblesRevertReason() public {
        RevertingERC20 revertingToken = new RevertingERC20();
        uint256 amount = 1000;
        revertingToken.mint(address(executor), amount);

        vm.prank(OWNER);
        vm.expectRevert("Transfer not allowed");
        executor.withdrawERC20(address(revertingToken), amount, ALICE);
    }

    function testRevertOnERC20TransferRevertingWithoutData() public {
        EmptyRevertERC20 emptyRevertToken = new EmptyRevertERC20();
        uint256 amount = 1000;
        emptyRevertToken.mint(address(executor), amount);

        vm.prank(OWNER);
        vm.expectRevert(Executor.ERC20TransferFailed.selector);
        executor.withdrawERC20(address(emptyRevertToken), amount, ALICE);
    }

    function testWithdrawNonStandardERC20NoReturnData() public {
        NoReturnERC20 nonStandardToken = new NoReturnERC20();
        uint256 amount = 1000;
        nonStandardToken.mint(address(executor), amount);

        vm.prank(OWNER);
        executor.withdrawERC20(address(nonStandardToken), amount, ALICE);

        assertEq(nonStandardToken.balanceOf(address(executor)), 0);
        assertEq(nonStandardToken.balanceOf(ALICE), amount);
    }
}
