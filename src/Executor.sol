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
 */
contract Executor {
    address public immutable owner;
    bool private transient locked;

    event Executed(address indexed target, bytes data, bytes result);
    event BundleExecuted(address[] indexed targets, bytes[] data, bool[] success);
    event ETHWithdrawn(uint256 amount, address indexed to);
    event ERC20Withdrawn(address indexed token, uint256 amount, address indexed to);

    error NotOwner();
    error InvalidTarget();
    error ExecutionFailed(uint256 index);
    error ERC20TransferFailed();
    error MismatchedArrays();
    error NoTransactionData();
    error NoTargets();
    error IncorectEthValue();
    error ZeroAddress();
    error ReentrancyGuard();
    error InsufficientBalance();
    error InsufficientTokenBalance();
    error EthTransferFailed();

    /**
     * @dev Prevents reentrancy attacks
     */
    modifier nonReentrant() {
        if (locked) revert ReentrancyGuard();
        locked = true;
        _;
        locked = false;
    }

    /**
     * @dev Restricts function access to contract owner
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /**
     * @dev Sets the contract owner
     * @param _owner Address of the contract owner
     */
    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
    }

    /**
     * @notice Executes a single transaction with optional ETH value
     * @dev Reverts if target is zero address or if call fails
     * @param target Address of contract to call
     * @param data Function call data
     * @return result The raw bytes returned from the call
     */
    function execute(address target, bytes calldata data)
        external
        payable
        nonReentrant
        onlyOwner
        returns (bytes memory result)
    {
        if (target == address(0)) revert InvalidTarget();
        if (msg.value == 0 && data.length == 0) revert NoTransactionData();

        bool success;
        (success, result) = target.call{value: msg.value}(data);
        if (!success) revert ExecutionFailed(0);

        emit Executed(target, data, result);
    }

    /**
     * @notice Executes multiple transactions in sequence
     * @dev External calls are made in a loop - ensure sufficient gas is provided
     * @dev Individual call failures are recorded in results array, not reverted
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
        if (totalValue != msg.value) revert IncorectEthValue();

        bool[] memory results = new bool[](targets.length);

        for (uint256 i = 0; i < targets.length; ++i) {
            // Skip if target is address(0)
            if (targets[i] == address(0)) {
                results[i] = false;
                continue;
            }

            (bool success,) = targets[i].call{value: values[i]}(data[i]);
            results[i] = success;
        }

        emit BundleExecuted(targets, data, results);
    }

    /**
     * @notice Withdraws ETH from contract
     * @dev Reverts if insufficient balance
     * @param amount Amount of ETH in wei
     * @param to Recipient address
     */
    function withdrawETH(uint256 amount, address payable to) external nonReentrant onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (address(this).balance < amount) revert InsufficientBalance();

        (bool success, bytes memory returnData) = to.call{value: amount}("");
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }
            revert EthTransferFailed();
        }

        emit ETHWithdrawn(amount, to);
    }

    /**
     * @notice Withdraws ERC20 tokens from contract
     * @dev Reverts if insufficient balance
     * @param token ERC20 token contract address
     * @param amount Token amount in smallest unit
     * @param to Recipient address
     */
    function withdrawERC20(address token, uint256 amount, address to) external nonReentrant onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();

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
        return owner;
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
            // If call failed, check if there's revert data to bubble up
            if (returndata.length > 0) {
                assembly {
                    revert(add(32, returndata), mload(returndata))
                }
            }
            revert ERC20TransferFailed();
        }

        // Check return value for tokens that return bool
        if (returndata.length > 0) {
            if (!abi.decode(returndata, (bool))) {
                revert ERC20TransferFailed();
            }
        }
    }

    receive() external payable {}
}
