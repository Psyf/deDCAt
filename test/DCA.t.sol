// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/Test.sol";
import "../src/gelato/Types.sol";
import "../src/DCA.sol";

interface WethLike {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface gelatoIOps {
    function exec(
        address taskCreator,
        address execAddress,
        bytes memory execData,
        ModuleData calldata moduleData,
        uint256 txFee,
        address feeToken,
        bool useTaskTreasuryFunds,
        bool revertOnFailure
    ) external;
}

contract DCATest is DCAEvents, Test {
    using SafeERC20 for IERC20;

    DCA public dca;

    // arbitrum addresses
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address ops = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    uint256 fee = 1_000_000_000_000; // 0.0001 WETH

    function setUp() public {
        dca = new DCA(swapRouter, ops, address(this), WETH);

        // sender needs to have WETH (for gas, but for DCA too in this case)
        WethLike(WETH).deposit{value: 10_000_000_000_000_000_000}();

        // sender needs to approve DCA to spend WETH
        IERC20(WETH).safeApprove(address(dca), 10_000_000_000_000_000_000);
    }

    function getGenericOrder() internal view returns (DCA.Order memory) {
        DCA.Order memory order = DCA.Order({
            sender: address(this),
            receiver: address(this),
            tokenIn: WETH,
            tokenOut: USDC,
            fee: 500, // denotes the uniswap pool to use
            amountPerInterval: 1_000_000_000_000_000, // 0.1 WETH
            start_time: block.timestamp + 1 hours,
            end_time: block.timestamp + 1 days,
            interval: 1 hours,
            lastExecuted: 0
        });

        return order;
    }

    function testCreate() public {
        DCA.Order memory order = getGenericOrder();
        bytes32 expectedOrderId = dca.hash(order);

        vm.expectEmit(true, true, true, true);
        emit OrderCreated(
            expectedOrderId,
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

        dca.create(order);
    }

    function testCancel() public {
        DCA.Order memory order = getGenericOrder();
        bytes32 expectedOrderId = dca.hash(order);

        vm.expectEmit(true, true, true, true);
        emit OrderCancelled(expectedOrderId);

        dca.create(order);
        dca.cancel(expectedOrderId);
    }

    function testExecute() public {
        DCA.Order memory order = getGenericOrder();
        bytes32 expectedOrderId = dca.hash(order);

        dca.create(order);

        // should revert because the order is not ready to be executed
        vm.expectRevert();
        dca.execute(expectedOrderId);

        // time travel to the start of the order, succeeds
        vm.warp(order.start_time);
        dca.execute(expectedOrderId);

        // forced execution immediately should revert because interval has not passed
        vm.expectRevert();
        dca.execute(expectedOrderId);

        // vm time travel to next interval, execution should succeed
        vm.warp(order.start_time + order.interval);
        dca.execute(expectedOrderId);

        // gelato bot gets paid properly, mocking it here
        vm.warp(order.start_time + order.interval + order.interval);
        vm.startPrank(0x4775aF8FEf4809fE10bf05867d2b038a4b5B2146);
        ModuleData memory moduleData = ModuleData({modules: new Module[](1), args: new bytes[](1)});
        moduleData.modules[0] = Module.RESOLVER;
        moduleData.args[0] = abi.encode(address(dca), abi.encodeCall(dca.checker, (expectedOrderId)));
        (bool canExec, bytes memory execData) = dca.checker(expectedOrderId);
        assertEq(canExec, true);
        gelatoIOps(ops).exec(address(dca), address(dca), execData, moduleData, fee, WETH, false, false);
        // todo: check the bot got paid properly

        // time travel to the end of the order, execution should revert because the order is expired
        vm.warp(order.end_time + 1);
        vm.expectRevert();
        dca.execute(expectedOrderId);
    }
}
