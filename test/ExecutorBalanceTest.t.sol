// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExecutorTest, ETHRejectingContract, ETHRejectingWithReasonContract} from "./BaseExecutorTest.t.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorBalanceTest is BaseExecutorTest {
    function testGetBalance() public {
        assertEq(executor.getBalance(), 0);
        uint256 amount = 1 ether;
        (bool success,) = address(executor).call{value: amount}("");
        require(success, "Transfer failed");
        assertEq(executor.getBalance(), amount);
    }

    function testWithdrawETH() public {
        uint256 amount = 1 ether;

        // First fund the executor
        vm.deal(address(executor), amount);
        assertEq(address(executor).balance, amount);

        // Test withdrawal
        vm.prank(OWNER);
        executor.withdrawEth(amount, payable(OWNER));

        assertEq(address(executor).balance, 0);
        assertEq(OWNER.balance, INITIAL_BALANCE + amount);
    }

    function testCannotWithdrawETHAsNonOwner() public {
        uint256 amount = 1 ether;
        vm.deal(address(executor), amount);

        vm.prank(ALICE);
        vm.expectRevert(Executor.NotOwner.selector);
        executor.withdrawEth(amount, payable(ALICE));
    }

    function testCannotWithdrawMoreThanBalance() public {
        uint256 amount = 1 ether;
        vm.deal(address(executor), amount);

        vm.prank(OWNER);
        vm.expectRevert(Executor.InsufficientBalance.selector);
        executor.withdrawEth(amount + 1, payable(ALICE));
    }

    function testCannotWithdrawETHToZeroAddress() public {
        uint256 amount = 1 ether;
        vm.deal(address(executor), amount);

        vm.prank(OWNER);
        vm.expectRevert(Executor.ZeroAddress.selector);
        executor.withdrawEth(amount, payable(address(0)));
    }

    function testCannotWithdrawETHToRejectingContract() public {
        ETHRejectingContract rejecter = new ETHRejectingContract();
        uint256 amount = 1 ether;
        vm.deal(address(executor), amount);

        vm.prank(OWNER);
        vm.expectRevert(Executor.EthTransferFailed.selector);
        executor.withdrawEth(amount, payable(address(rejecter)));
    }

    function testCannotWithdrawETHBubblesRevertReason() public {
        ETHRejectingWithReasonContract rejecter = new ETHRejectingWithReasonContract();
        uint256 amount = 1 ether;
        vm.deal(address(executor), amount);

        vm.prank(OWNER);
        vm.expectRevert("I reject your ETH");
        executor.withdrawEth(amount, payable(address(rejecter)));
    }
}
