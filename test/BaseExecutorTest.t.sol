// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Executor} from "../src/Executor.sol";

contract Target {
    uint256 public number;

    function setNumber(uint256 _number) external {
        number = _number;
    }

    function receiveEther() external payable {}

    fallback() external {}
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    bool public willTransferFail; // Add this line

    // Add this function
    function setTransferShouldFail(bool _fail) external {
        willTransferFail = _fail;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        if (willTransferFail) return false; // Add this line
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract FailingTarget {
    function alwaysRevert() external pure {
        revert("Custom revert message");
    }
}

contract ReentrantAttacker {
    Executor public executorTarget;
    bytes public reentryCalldata;
    bytes public reentryRevertData;

    constructor(address payable _executor) {
        executorTarget = Executor(_executor);
    }

    function setReentryCalldata(bytes calldata data) external {
        reentryCalldata = data;
    }

    receive() external payable {
        (bool success, bytes memory returnData) = address(executorTarget).call(reentryCalldata);
        require(!success, "reentry unexpectedly succeeded");
        reentryRevertData = returnData;
    }
}

contract ETHRejectingContract {
    receive() external payable {
        revert();
    }
}

contract ETHRejectingWithReasonContract {
    receive() external payable {
        revert("I reject your ETH");
    }
}

contract RevertingERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert("Transfer not allowed");
    }
}

contract EmptyRevertERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert();
    }
}

contract NoReturnERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address recipient, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
    }
}

// Returns a non-standard short (4-byte) buffer from transfer. A naive
// abi.decode(returndata, (bool)) reverts on this; a correct length-gated
// decoder must treat it as a failed transfer.
contract ShortReturnERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        assembly {
            mstore(0, 1)
            return(0, 4)
        }
    }
}

contract BaseExecutorTest is Test {
    Executor public executor;
    Target public target1;
    Target public target2;
    MockERC20 public token;

    address constant ALICE = address(0x1);
    address constant BOB = address(0x2);
    address constant OWNER = address(0xabc);
    uint256 constant INITIAL_BALANCE = 100 ether;

    event Executed(address indexed target, bytes data, bytes32 resultHash);
    event BundleExecuted(address[] targets, bytes[] data);

    function setUp() public virtual {
        executor = new Executor(OWNER);
        target1 = new Target();
        target2 = new Target();
        token = new MockERC20();

        // Fund test addresses
        vm.deal(ALICE, INITIAL_BALANCE);
        vm.deal(BOB, INITIAL_BALANCE);
        vm.deal(address(this), INITIAL_BALANCE);
        vm.deal(OWNER, INITIAL_BALANCE);
    }
}
