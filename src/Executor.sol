// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title Executor
 * @notice Smart contract for executing arbitrary calls with access control
 * @dev Implements ownership, reentrancy protection, and asset management
 * @dev Ownership is immutable by design. To rotate the owner key, deploy a new
 *      Executor with the new owner and migrate assets via withdrawEth/withdrawERC20.
 */
contract Executor {
    address public immutable OWNER;
    bool private transient locked;

    event Executed(address indexed target, uint256 value, bytes data, bytes32 resultHash);
    event BundleExecuted(address[] targets, uint256[] values, bytes[] data);
    event ETHWithdrawn(uint256 amount, address indexed to);
    event ERC20Withdrawn(address indexed token, uint256 amount, address indexed to);

    error NotOwner();
    error InvalidTarget();
    error TargetNotContract(uint256 index);
    error ExecutionFailed(uint256 index);
    error ERC20TransferFailed();
    error MismatchedArrays();
    error NoTransactionData();
    error NoTargets();
    error ZeroAddress();
    error ZeroAmount();
    error ReentrancyGuard();
    error InsufficientBalance();
    error InsufficientTokenBalance();
    error EthTransferFailed();

    /**
     * @dev Prevents reentrancy attacks
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (locked) revert ReentrancyGuard();
        locked = true;
    }

    function _nonReentrantAfter() internal {
        locked = false;
    }

    /**
     * @dev Restricts function access to contract owner
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view {
        if (msg.sender != OWNER) revert NotOwner();
    }

    /**
     * @dev Sets the contract owner
     * @param _owner Address of the contract owner
     */
    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        OWNER = _owner;
    }

    /**
     * @notice Executes a single transaction with optional ETH value
     * @dev Reverts if target is zero address or if call fails. On failure the
     *      target's revert reason is bubbled up; a target that reverts without
     *      data falls through to ExecutionFailed(0).
     * @param target Address of contract to call
     * @param data Function call data
     * @param value Amount of ETH to send with the call
     * @return result The raw bytes returned from the call
     */
    function execute(address target, bytes calldata data, uint256 value)
        external
        payable
        nonReentrant
        onlyOwner
        returns (bytes memory result)
    {
        if (target == address(0)) revert InvalidTarget();
        if (value == 0 && data.length == 0) revert NoTransactionData();
        // A call carrying calldata must hit a contract; a codeless target would
        // report success without executing anything. Bare ETH transfers (no
        // calldata) to EOAs remain allowed.
        if (data.length > 0 && target.code.length == 0) revert TargetNotContract(0);
        if (value > address(this).balance) revert InsufficientBalance();

        bool success;
        (success, result) = target.call{value: value}(data);
        if (!success) {
            // Surface the target's revert reason for diagnosability, mirroring
            // the withdraw paths. Falls through to ExecutionFailed(0) when the
            // target reverted without data.
            _bubbleRevert(result);
            revert ExecutionFailed(0);
        }

        // Log only the hash of the returned data. Emitting the raw buffer would
        // let a malicious target return an oversized payload that is re-copied
        // into the event, amplifying memory-expansion gas costs. The full
        // `result` is still returned to the caller.
        emit Executed(target, value, data, keccak256(result));
    }

    /**
     * @notice Executes multiple transactions in sequence
     * @dev External calls are made in a loop - ensure sufficient gas is provided
     * @dev Reverts the entire bundle if any target is the zero address or any call fails
     * @param targets Array of contract addresses to call
     * @param data Array of call data for each target
     * @param values Array of ETH values for each call
     */
    function bundleExecute(address[] calldata targets, bytes[] calldata data, uint256[] calldata values)
        external
        payable
        nonReentrant
        onlyOwner
    {
        if (targets.length != data.length || data.length != values.length) {
            revert MismatchedArrays();
        }
        if (targets.length == 0) revert NoTargets();

        uint256 totalValue = 0;
        for (uint256 i = 0; i < values.length; ++i) {
            totalValue += values[i];
        }
        if (totalValue > address(this).balance) revert InsufficientBalance();

        for (uint256 i = 0; i < targets.length; ++i) {
            if (targets[i] == address(0)) revert InvalidTarget();
            if (data[i].length > 0 && targets[i].code.length == 0) revert TargetNotContract(i);

            (bool success,) = targets[i].call{value: values[i]}(data[i]);
            if (!success) revert ExecutionFailed(i);
        }

        emit BundleExecuted(targets, values, data);
    }

    /**
     * @notice Withdraws ETH from contract
     * @dev Reverts if insufficient balance
     * @param amount Amount of ETH in wei
     * @param to Recipient address
     */
    function withdrawEth(uint256 amount, address payable to) external nonReentrant onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (to == address(this)) revert InvalidTarget();
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientBalance();

        (bool success, bytes memory returnData) = to.call{value: amount}("");
        if (!success) {
            _bubbleRevert(returnData);
            revert EthTransferFailed();
        }

        emit ETHWithdrawn(amount, to);
    }

    /**
     * @notice Withdraws ERC20 tokens from contract
     * @dev Reverts if insufficient balance or if token is not a contract
     * @dev Uses strict `_safeTransfer` validation (OZ SafeERC20 semantics): a
     *      `false`, short, or dirty return, or a call-revert, reverts with
     *      `ERC20TransferFailed`. A few legitimate non-standard tokens fail this
     *      path anyway — return-`false`-on-success (e.g. Tether Gold),
     *      `uint96`-capped balances above 2^96-1 (e.g. UNI/COMP), and
     *      zero-amount-revert tokens. No funds are locked: withdraw such tokens
     *      via the owner escape hatch `execute(token,
     *      abi.encodeCall(IERC20.transfer, (to, amount)), 0)`, which only checks
     *      call-level success.
     * @param token ERC20 token contract address
     * @param amount Token amount in smallest unit
     * @param to Recipient address
     */
    function withdrawERC20(address token, uint256 amount, address to) external nonReentrant onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (to == address(this)) revert InvalidTarget();
        if (token.code.length == 0) revert InvalidTarget();
        if (amount == 0) revert ZeroAmount();

        IERC20 erc20 = IERC20(token);
        if (erc20.balanceOf(address(this)) < amount) revert InsufficientTokenBalance();
        _safeTransfer(erc20, to, amount);

        emit ERC20Withdrawn(token, amount, to);
    }

    /**
     * @notice Gets contract owner address
     * @return Address of contract owner
     */
    function getOwner() external view returns (address) {
        return OWNER;
    }

    /**
     * @notice Gets contract's ETH balance
     * @return Balance in wei
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Safe ERC20 transfer implementation
     * @param token ERC20 token interface
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _safeTransfer(IERC20 token, address to, uint256 amount) private {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", to, amount);
        (bool success, bytes memory returndata) = address(token).call(data);

        if (!success) {
            // If call failed, bubble up any revert data
            _bubbleRevert(returndata);
            revert ERC20TransferFailed();
        }

        // Check return value for tokens that return bool. A short (<32 byte)
        // or dirty return is treated as a failure rather than reverting the
        // ABI decoder, mirroring OpenZeppelin SafeERC20.
        if (returndata.length > 0) {
            if (returndata.length < 32 || !abi.decode(returndata, (bool))) {
                revert ERC20TransferFailed();
            }
        }
    }

    /**
     * @dev Re-reverts with the given return data if any is present. If `returndata`
     *      is empty this is a no-op and the caller falls through to its own error.
     * @param returndata Raw return data from a failed low-level call
     */
    function _bubbleRevert(bytes memory returndata) private pure {
        if (returndata.length > 0) {
            assembly ("memory-safe") {
                revert(add(32, returndata), mload(returndata))
            }
        }
    }

    receive() external payable {}
}
