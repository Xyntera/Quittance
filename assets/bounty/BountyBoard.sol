// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Minimal ERC20 interface used for escrowing reward tokens (e.g. PROS).
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title BountyBoard
 * @author AgentBounty — a Pharos Skill Engine skill
 * @notice An on-chain task-bounty escrow primitive for the Pharos AI Agent economy.
 *
 *         Any wallet or agent can post a task with a reward escrowed in either the
 *         native coin (PHRS) or any ERC20 (e.g. PROS). Other agents submit their work
 *         (an off-chain result pointer such as an IPFS CID or URL). The poster approves
 *         exactly one submitter, which atomically releases the escrowed reward to that
 *         worker. If no one is approved, the poster can cancel an unanswered bounty, or
 *         reclaim the reward once an optional deadline has passed.
 *
 *         Design goals (this is a *reusable Skill*, not an app):
 *           - Self-contained: no external dependencies, single file, easy to audit & reuse.
 *           - Composable: agents call clear external functions and parse clear events.
 *           - Safe: checks-effects-interactions + reentrancy guard, pull of funds on
 *             post, push of funds on settle, with effects committed before transfers.
 *           - Agent-friendly: descriptive revert strings and view functions so an LLM
 *             agent can read state and interpret failures without an ABI decoder.
 */
contract BountyBoard {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum Status {
        None, // 0 - bounty id never created
        Open, // 1 - escrowed, accepting submissions / awaiting approval
        Paid, // 2 - approved & reward released to the winner
        Refunded // 3 - cancelled or reclaimed; reward returned to the poster
    }

    struct Bounty {
        address poster; // who funded and owns the bounty
        address token; // address(0) == native PHRS, else ERC20 token address
        uint256 reward; // amount held in escrow for the winner
        uint64 createdAt; // block timestamp at posting
        uint64 deadline; // 0 == no deadline; after it the poster may reclaim()
        uint32 submissionCount; // number of submissions received
        Status status; // lifecycle state
        address winner; // set when approved & paid
        string metadataURI; // task description pointer (IPFS CID / URL / inline text)
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice Total number of bounties ever posted. Ids are 1-based (1..bountyCount).
    uint256 public bountyCount;

    /// @notice id => bounty record.
    mapping(uint256 => Bounty) private _bounties;

    /// @notice id => worker => has this worker submitted at least once.
    mapping(uint256 => mapping(address => bool)) public hasSubmitted;

    /// @dev Reentrancy guard state (1 = unlocked, 2 = locked).
    uint256 private _lock = 1;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event BountyPosted(
        uint256 indexed id,
        address indexed poster,
        address indexed token,
        uint256 reward,
        uint64 deadline,
        string metadataURI
    );
    event WorkSubmitted(uint256 indexed id, address indexed worker, string resultURI);
    event BountyApproved(uint256 indexed id, address indexed winner, address indexed token, uint256 reward);
    event BountyRefunded(uint256 indexed id, address indexed poster, address indexed token, uint256 reward);

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier nonReentrant() {
        require(_lock == 1, "BountyBoard: reentrant call");
        _lock = 2;
        _;
        _lock = 1;
    }

    // ---------------------------------------------------------------------
    // Write functions
    // ---------------------------------------------------------------------

    /**
     * @notice Post a new bounty and escrow its reward.
     * @dev    For native rewards pass token=address(0) and send msg.value == amount.
     *         For ERC20 rewards pass the token address, set msg.value to 0, and approve
     *         this contract for `amount` beforehand (the contract pulls via transferFrom).
     * @param token       address(0) for native PHRS, otherwise the ERC20 token address.
     * @param amount      Reward amount to escrow (must be > 0).
     * @param deadline    Unix timestamp after which the poster may reclaim; 0 = no deadline.
     * @param metadataURI Pointer to the task description (IPFS CID, URL, or inline text).
     * @return id The new bounty id (1-based).
     */
    function postBounty(address token, uint256 amount, uint64 deadline, string calldata metadataURI)
        external
        payable
        nonReentrant
        returns (uint256 id)
    {
        require(amount > 0, "BountyBoard: amount must be greater than zero");
        require(deadline == 0 || deadline > block.timestamp, "BountyBoard: deadline already passed");

        if (token == address(0)) {
            require(msg.value == amount, "BountyBoard: msg.value must equal amount for native reward");
        } else {
            require(msg.value == 0, "BountyBoard: do not send native value for ERC20 reward");
            _pullERC20(token, msg.sender, amount);
        }

        id = ++bountyCount;
        Bounty storage b = _bounties[id];
        b.poster = msg.sender;
        b.token = token;
        b.reward = amount;
        b.createdAt = uint64(block.timestamp);
        b.deadline = deadline;
        b.status = Status.Open;
        b.metadataURI = metadataURI;

        emit BountyPosted(id, msg.sender, token, amount, deadline, metadataURI);
    }

    /**
     * @notice Submit work for an open bounty.
     * @dev    Submissions are recorded on-chain (a flag + the WorkSubmitted event). The
     *         actual deliverable lives off-chain at `resultURI`. The poster reviews
     *         submissions off-chain and approves one on-chain.
     * @param id        The bounty id.
     * @param resultURI Pointer to the submitted deliverable (IPFS CID / URL).
     */
    function submitWork(uint256 id, string calldata resultURI) external {
        Bounty storage b = _bounties[id];
        require(b.status == Status.Open, "BountyBoard: bounty is not open");
        require(b.deadline == 0 || block.timestamp <= b.deadline, "BountyBoard: deadline has passed");
        require(msg.sender != b.poster, "BountyBoard: poster cannot submit to own bounty");

        if (!hasSubmitted[id][msg.sender]) {
            hasSubmitted[id][msg.sender] = true;
            b.submissionCount += 1;
        }

        emit WorkSubmitted(id, msg.sender, resultURI);
    }

    /**
     * @notice Approve a submitter as the winner and release the escrowed reward to them.
     * @dev    Only the poster may call. The winner must have submitted at least once.
     * @param id     The bounty id.
     * @param winner The address to pay (must have submitted).
     */
    function approve(uint256 id, address winner) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(b.status == Status.Open, "BountyBoard: bounty is not open");
        require(msg.sender == b.poster, "BountyBoard: caller is not the poster");
        require(hasSubmitted[id][winner], "BountyBoard: winner has not submitted");

        // effects before interaction
        b.status = Status.Paid;
        b.winner = winner;
        uint256 reward = b.reward;
        address token = b.token;

        _payout(token, winner, reward);

        emit BountyApproved(id, winner, token, reward);
    }

    /**
     * @notice Cancel an open bounty that has received no submissions and refund the poster.
     * @dev    Restricted to the zero-submission case so workers who already delivered are
     *         never rug-pulled. Use reclaim() for the timed-out path.
     * @param id The bounty id.
     */
    function cancel(uint256 id) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(b.status == Status.Open, "BountyBoard: bounty is not open");
        require(msg.sender == b.poster, "BountyBoard: caller is not the poster");
        require(b.submissionCount == 0, "BountyBoard: cannot cancel after a submission; use reclaim after deadline");

        _refund(b, id);
    }

    /**
     * @notice Reclaim the reward of an open bounty whose deadline has passed.
     * @dev    Lets a poster recover funds if they never approved a winner in time, even
     *         if submissions exist. Requires a non-zero deadline that is now in the past.
     * @param id The bounty id.
     */
    function reclaim(uint256 id) external nonReentrant {
        Bounty storage b = _bounties[id];
        require(b.status == Status.Open, "BountyBoard: bounty is not open");
        require(msg.sender == b.poster, "BountyBoard: caller is not the poster");
        require(b.deadline != 0 && block.timestamp > b.deadline, "BountyBoard: deadline has not passed");

        _refund(b, id);
    }

    // ---------------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------------

    /// @notice Read the full record for a bounty.
    function getBounty(uint256 id)
        external
        view
        returns (
            address poster,
            address token,
            uint256 reward,
            uint64 createdAt,
            uint64 deadline,
            uint32 submissionCount,
            Status status,
            address winner,
            string memory metadataURI
        )
    {
        Bounty storage b = _bounties[id];
        return (
            b.poster,
            b.token,
            b.reward,
            b.createdAt,
            b.deadline,
            b.submissionCount,
            b.status,
            b.winner,
            b.metadataURI
        );
    }

    /// @notice True if the bounty is currently accepting submissions / awaiting approval.
    function isOpen(uint256 id) external view returns (bool) {
        return _bounties[id].status == Status.Open;
    }

    /// @notice Seconds left before the deadline. Returns 0 if no deadline or already passed.
    function timeLeft(uint256 id) external view returns (uint256) {
        uint64 deadline = _bounties[id].deadline;
        if (deadline == 0 || block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    /// @notice Numeric status of a bounty (0 None, 1 Open, 2 Paid, 3 Refunded).
    function statusOf(uint256 id) external view returns (Status) {
        return _bounties[id].status;
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _refund(Bounty storage b, uint256 id) private {
        b.status = Status.Refunded;
        uint256 reward = b.reward;
        address token = b.token;
        address poster = b.poster;

        _payout(token, poster, reward);

        emit BountyRefunded(id, poster, token, reward);
    }

    function _payout(address token, address to, uint256 amount) private {
        if (token == address(0)) {
            (bool ok,) = payable(to).call{value: amount}("");
            require(ok, "BountyBoard: native transfer failed");
        } else {
            _pushERC20(token, to, amount);
        }
    }

    /// @dev transferFrom that tolerates non-standard ERC20s that return no value.
    function _pullERC20(address token, address from, uint256 amount) private {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "BountyBoard: ERC20 transferFrom failed");
    }

    /// @dev transfer that tolerates non-standard ERC20s that return no value.
    function _pushERC20(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "BountyBoard: ERC20 transfer failed");
    }
}
