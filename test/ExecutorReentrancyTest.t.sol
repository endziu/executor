// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseExecutorTest, ReentrantAttacker, Target} from "./BaseExecutorTest.t.sol";
import {Executor} from "../src/Executor.sol";

contract ExecutorReentrancyTest is BaseExecutorTest {
    ReentrantAttacker attacker;

    function setUp() public override {
        super.setUp();
        attacker = new ReentrantAttacker(payable(address(executor)));
    }

    function _assertReentryBlocked() internal view {
        assertEq(attacker.reentryRevertData(), abi.encodeWithSelector(Executor.ReentrancyGuard.selector));
    }

    function testExecuteBlocksReentrantExecute() public {
        bytes memory innerCall = abi.encodeWithSelector(Target.setNumber.selector, 42);
        attacker.setReentryCalldata(abi.encodeWithSelector(Executor.execute.selector, address(target1), innerCall, 0));

        vm.prank(OWNER);
        executor.execute{value: 1 ether}(address(attacker), "", 1 ether);

        _assertReentryBlocked();
        assertEq(target1.number(), 0);
    }

    function testExecuteBlocksReentrantWithdrawETH() public {
        vm.deal(address(executor), 1 ether);
        attacker.setReentryCalldata(
            abi.encodeWithSelector(Executor.withdrawEth.selector, 1 ether, payable(address(attacker)))
        );

        vm.prank(OWNER);
        executor.execute{value: 1 ether}(address(attacker), "", 1 ether);

        _assertReentryBlocked();
        assertEq(address(executor).balance, 1 ether);
    }

    function testWithdrawETHBlocksReentrantExecute() public {
        vm.deal(address(executor), 2 ether);
        bytes memory innerCall = abi.encodeWithSelector(Target.setNumber.selector, 42);
        attacker.setReentryCalldata(abi.encodeWithSelector(Executor.execute.selector, address(target1), innerCall, 0));

        vm.prank(OWNER);
        executor.withdrawEth(1 ether, payable(address(attacker)));

        _assertReentryBlocked();
        assertEq(target1.number(), 0);
        assertEq(address(attacker).balance, 1 ether);
    }
}
