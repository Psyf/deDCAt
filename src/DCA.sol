// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./gelato/OpsTaskCreator.sol";
import "./DCAEvents.sol";

contract DCA is DCAEvents, OpsTaskCreator {
    using SafeERC20 for IERC20;

    struct Order {
        address sender;
        address receiver;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountPerInterval;
        uint256 start_time;
        uint256 end_time;
        uint256 interval;
        uint256 lastExecuted;
    }

    ISwapRouter public immutable swapRouter;
    address WETH;
    mapping(bytes32 => Order) public orders;
    mapping(bytes32 => bytes32) public orderToTask;

    constructor(address swapRouterAddress, address _ops, address _fundsOwner, address _WETH)
        OpsTaskCreator(_ops, _fundsOwner)
    {
        swapRouter = ISwapRouter(swapRouterAddress);
        WETH = _WETH;
    }

    function hash(Order memory order) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                order.sender,
                order.receiver,
                order.tokenIn,
                order.tokenOut,
                order.fee,
                order.amountPerInterval,
                order.start_time,
                order.end_time,
                order.interval
            )
        );
    }

    function create(Order calldata order) public {
        // hash the order struct
        bytes32 orderId = hash(order);

        // check if the order is already in the mapping
        require(orders[orderId].sender == address(0), "Order already exists");
        orders[orderId] = order;

        // create the gelato order
        ModuleData memory moduleData = ModuleData({modules: new Module[](1), args: new bytes[](1)});

        moduleData.modules[0] = Module.RESOLVER;
        moduleData.args[0] = _resolverModuleArg(address(this), abi.encodeCall(this.checker, (orderId)));

        bytes32 taskId = _createTask(address(this), abi.encode(this.execute.selector), moduleData, WETH);
        orderToTask[orderId] = taskId;

        emit OrderCreated(
            orderId,
            order.sender,
            order.receiver,
            order.tokenIn,
            order.tokenOut,
            order.fee,
            order.amountPerInterval,
            order.start_time,
            order.end_time,
            order.interval
            );
    }

    // user has to approve amountPerInterval token before this can succeed. Best to do so at createOrder time
    // user also has to approve gelato feeToken (WETH) before this can succeed. Best to do so at createOrder time
    // user has to have balance of amountPerInterval token before timestamp
    function execute(bytes32 orderId) public {
        require(_isExecutable(orderId));

        Order storage order = orders[orderId];

        IERC20(order.tokenIn).safeTransferFrom(order.sender, address(this), order.amountPerInterval);
        IERC20(order.tokenIn).safeApprove(address(swapRouter), order.amountPerInterval);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: order.tokenIn,
            tokenOut: order.tokenOut,
            fee: order.fee,
            recipient: order.receiver,
            deadline: block.timestamp,
            amountIn: order.amountPerInterval,
            amountOutMinimum: 0, // todo: frontrun protection with slippage
            sqrtPriceLimitX96: 0
        });
        swapRouter.exactInputSingle(params);

        (uint256 fee, address feeToken) = _getFeeDetails();
        if (feeToken != address(0)) {
            IERC20(feeToken).safeTransferFrom(order.sender, address(this), fee);
            _transfer(fee, feeToken); // todo: can collapse into single call
        }

        order.lastExecuted = block.timestamp;
        emit OrderExecuted(orderId);
    }

    function cancel(bytes32 orderId) public {
        delete orders[orderId];
        _cancelTask(orderToTask[orderId]);
        emit OrderCancelled(orderId);
    }

    function checker(bytes32 orderId) external view returns (bool canExec, bytes memory execPayload) {
        canExec = _isExecutable(orderId);
        execPayload = abi.encodeWithSelector(this.execute.selector, orderId);
    }

    function _isExecutable(bytes32 orderId) internal view returns (bool) {
        Order memory order = orders[orderId];
        return (order.start_time <= block.timestamp) && (order.end_time >= block.timestamp)
            && (order.lastExecuted + order.interval <= block.timestamp);
    }
}
