// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExecutorTest} from "./BaseExecutorTest.t.sol";

contract ExecutorReceiveTest is BaseExecutorTest {
    function testReceiveEther() public {
        uint256 amount = 1 ether;

        // Send ETH directly to contract
        (bool success,) = address(executor).call{value: amount}("");
        assertTrue(success);
        assertEq(address(executor).balance, amount);
    }

    function testReceiveEtherFromDifferentAccounts() public {
        uint256 amount1 = 0.5 ether;
        uint256 amount2 = 1.5 ether;

        vm.prank(ALICE);
        (bool success1,) = address(executor).call{value: amount1}("");
        assertTrue(success1);

        vm.prank(BOB);
        (bool success2,) = address(executor).call{value: amount2}("");
        assertTrue(success2);

        assertEq(address(executor).balance, amount1 + amount2);
    }

    function testCannotSendWithData() public {
        uint256 amount = 1 ether;
        bytes memory data = hex"deadbeef";

        // Try to send ETH with data
        (bool success,) = address(executor).call{value: amount}(data);
        assertFalse(success);
        assertEq(address(executor).balance, 0);
    }

    function testReceiveMultipleTransactions() public {
        uint256 amount = 0.1 ether;

        for (uint256 i = 0; i < 5; i++) {
            (bool success,) = address(executor).call{value: amount}("");
            assertTrue(success);
        }

        assertEq(address(executor).balance, amount * 5);
    }
}
