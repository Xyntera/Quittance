// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {BountyBoard, IERC20} from "../src/bounty/BountyBoard.sol";

/// @dev Standard ERC20 (returns bool) for happy-path token tests.
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev Non-standard ERC20 (no return values, like USDT) to test the low-level safe calls.
contract NoReturnERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract BountyBoardTest is Test {
    BountyBoard board;
    MockERC20 token;

    address poster = makeAddr("poster");
    address worker = makeAddr("worker");
    address worker2 = makeAddr("worker2");
    address stranger = makeAddr("stranger");

    function setUp() public {
        board = new BountyBoard();
        token = new MockERC20();
        vm.deal(poster, 100 ether);
        vm.deal(stranger, 10 ether);
    }

    // ----------------------------- native flow -----------------------------

    function test_PostNativeBounty_EscrowsFunds() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, 0, "ipfs://task");

        assertEq(id, 1);
        assertEq(board.bountyCount(), 1);
        assertEq(address(board).balance, 1 ether);
        assertTrue(board.isOpen(id));

        (address p, address t, uint256 reward,,,, BountyBoard.Status status,, string memory uri) =
            board.getBounty(id);
        assertEq(p, poster);
        assertEq(t, address(0));
        assertEq(reward, 1 ether);
        assertEq(uint8(status), uint8(BountyBoard.Status.Open));
        assertEq(uri, "ipfs://task");
    }

    function test_FullNativeLifecycle_PaysWinner() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 2 ether}(address(0), 2 ether, 0, "ipfs://task");

        vm.prank(worker);
        board.submitWork(id, "ipfs://result");
        assertTrue(board.hasSubmitted(id, worker));

        uint256 before = worker.balance;
        vm.prank(poster);
        board.approve(id, worker);

        assertEq(worker.balance, before + 2 ether);
        assertEq(address(board).balance, 0);
        assertEq(uint8(board.statusOf(id)), uint8(BountyBoard.Status.Paid));
    }

    function test_CancelNoSubmissions_RefundsPoster() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, 0, "ipfs://task");

        uint256 before = poster.balance;
        vm.prank(poster);
        board.cancel(id);

        assertEq(poster.balance, before + 1 ether);
        assertEq(uint8(board.statusOf(id)), uint8(BountyBoard.Status.Refunded));
    }

    function test_ReclaimAfterDeadline_RefundsPoster() public {
        uint64 deadline = uint64(block.timestamp + 1 days);
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, deadline, "ipfs://task");

        vm.prank(worker);
        board.submitWork(id, "ipfs://result");

        // cannot reclaim before deadline
        vm.prank(poster);
        vm.expectRevert("BountyBoard: deadline has not passed");
        board.reclaim(id);

        vm.warp(deadline + 1);
        uint256 before = poster.balance;
        vm.prank(poster);
        board.reclaim(id);
        assertEq(poster.balance, before + 1 ether);
        assertEq(uint8(board.statusOf(id)), uint8(BountyBoard.Status.Refunded));
    }

    // ----------------------------- ERC20 flow -----------------------------

    function test_FullERC20Lifecycle() public {
        token.mint(poster, 5 ether);
        vm.startPrank(poster);
        token.approve(address(board), 5 ether);
        uint256 id = board.postBounty(address(token), 5 ether, 0, "ipfs://task");
        vm.stopPrank();

        assertEq(token.balanceOf(address(board)), 5 ether);

        vm.prank(worker);
        board.submitWork(id, "ipfs://result");

        vm.prank(poster);
        board.approve(id, worker);
        assertEq(token.balanceOf(worker), 5 ether);
        assertEq(token.balanceOf(address(board)), 0);
    }

    function test_NonStandardERC20_Works() public {
        NoReturnERC20 usdt = new NoReturnERC20();
        usdt.mint(poster, 3 ether);
        vm.startPrank(poster);
        usdt.approve(address(board), 3 ether);
        uint256 id = board.postBounty(address(usdt), 3 ether, 0, "ipfs://task");
        vm.stopPrank();

        vm.prank(worker);
        board.submitWork(id, "ipfs://result");

        vm.prank(poster);
        board.approve(id, worker);
        assertEq(usdt.balanceOf(worker), 3 ether);
    }

    // ----------------------------- reverts -----------------------------

    function test_RevertWhen_ZeroAmount() public {
        vm.prank(poster);
        vm.expectRevert("BountyBoard: amount must be greater than zero");
        board.postBounty{value: 0}(address(0), 0, 0, "x");
    }

    function test_RevertWhen_NativeValueMismatch() public {
        vm.prank(poster);
        vm.expectRevert("BountyBoard: msg.value must equal amount for native reward");
        board.postBounty{value: 1 ether}(address(0), 2 ether, 0, "x");
    }

    function test_RevertWhen_NativeValueSentForERC20() public {
        token.mint(poster, 1 ether);
        vm.startPrank(poster);
        token.approve(address(board), 1 ether);
        vm.expectRevert("BountyBoard: do not send native value for ERC20 reward");
        board.postBounty{value: 1 ether}(address(token), 1 ether, 0, "x");
        vm.stopPrank();
    }

    function test_RevertWhen_DeadlineInPast() public {
        vm.warp(1000);
        vm.prank(poster);
        vm.expectRevert("BountyBoard: deadline already passed");
        board.postBounty{value: 1 ether}(address(0), 1 ether, 500, "x");
    }

    function test_RevertWhen_PosterSubmitsOwnBounty() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, 0, "x");
        vm.prank(poster);
        vm.expectRevert("BountyBoard: poster cannot submit to own bounty");
        board.submitWork(id, "r");
    }

    function test_RevertWhen_NonPosterApproves() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, 0, "x");
        vm.prank(worker);
        board.submitWork(id, "r");
        vm.prank(stranger);
        vm.expectRevert("BountyBoard: caller is not the poster");
        board.approve(id, worker);
    }

    function test_RevertWhen_ApproveNonSubmitter() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, 0, "x");
        vm.prank(poster);
        vm.expectRevert("BountyBoard: winner has not submitted");
        board.approve(id, worker);
    }

    function test_RevertWhen_CancelAfterSubmission() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, 0, "x");
        vm.prank(worker);
        board.submitWork(id, "r");
        vm.prank(poster);
        vm.expectRevert("BountyBoard: cannot cancel after a submission; use reclaim after deadline");
        board.cancel(id);
    }

    function test_RevertWhen_DoubleApprove() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, 0, "x");
        vm.prank(worker);
        board.submitWork(id, "r");
        vm.startPrank(poster);
        board.approve(id, worker);
        vm.expectRevert("BountyBoard: bounty is not open");
        board.approve(id, worker);
        vm.stopPrank();
    }

    function test_SubmissionCountDeduplicates() public {
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, 0, "x");
        vm.startPrank(worker);
        board.submitWork(id, "r1");
        board.submitWork(id, "r2");
        vm.stopPrank();
        vm.prank(worker2);
        board.submitWork(id, "r3");

        (,,,,, uint32 submissionCount,,,) = board.getBounty(id);
        assertEq(submissionCount, 2);
    }

    function test_TimeLeft() public {
        uint64 deadline = uint64(block.timestamp + 100);
        vm.prank(poster);
        uint256 id = board.postBounty{value: 1 ether}(address(0), 1 ether, deadline, "x");
        assertEq(board.timeLeft(id), 100);
        vm.warp(block.timestamp + 40);
        assertEq(board.timeLeft(id), 60);
        vm.warp(deadline + 1);
        assertEq(board.timeLeft(id), 0);
    }

    // ----------------------------- fuzz -----------------------------

    function testFuzz_NativeEscrowAndPay(uint96 amount) public {
        amount = uint96(bound(amount, 1, 50 ether));
        vm.deal(poster, amount);
        vm.prank(poster);
        uint256 id = board.postBounty{value: amount}(address(0), amount, 0, "x");
        vm.prank(worker);
        board.submitWork(id, "r");
        uint256 before = worker.balance;
        vm.prank(poster);
        board.approve(id, worker);
        assertEq(worker.balance, before + amount);
    }
}
