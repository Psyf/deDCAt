pragma solidity 0.8.18;

contract DCAEvents {
    event OrderCreated(
        bytes32 indexed orderId,
        address indexed sender,
        address receiver,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountPerInterval,
        uint256 start_time,
        uint256 end_time,
        uint256 interval
    );

    event OrderExecuted(bytes32 indexed orderId);
    event OrderCancelled(bytes32 indexed orderId);
}
