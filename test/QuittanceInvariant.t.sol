// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Quittance} from "../src/quittance/Quittance.sol";

/**
 * Stress: invariant testing.
 *
 * The runner fires thousands of randomly-sequenced deposit / withdraw / redeem calls from a
 * pool of actors (with valid EIP-712 signatures) and, after each step, asserts the two
 * properties a custodial settlement contract must never violate:
 *
 *   - SOLVENCY:     the contract's native balance always equals the sum of every payer's
 *                   internal balance — funds are never created, lost, or stuck.
 *   - CONSERVATION: deposited == withdrawn + settled + still-held.
 */
contract Handler is Test {
    Quittance public q;
    address[] public actors;
    uint256[] internal keys;

    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;
    uint256 public ghostSettled;

    constructor(Quittance _q) {
        q = _q;
        for (uint256 i; i < 4; ++i) {
            (address a, uint256 k) = makeAddrAndKey(string(abi.encodePacked("actor-", vm.toString(i))));
            actors.push(a);
            keys.push(k);
        }
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _pick(uint256 seed) internal view returns (address a, uint256 k) {
        uint256 i = seed % actors.length;
        return (actors[i], keys[i]);
    }

    function deposit(uint256 seed, uint256 amount) external {
        (address a,) = _pick(seed);
        amount = bound(amount, 1, 10 ether);
        vm.deal(a, amount);
        vm.prank(a);
        q.depositNative{value: amount}();
        ghostDeposited += amount;
    }

    function withdraw(uint256 seed, uint256 amount) external {
        (address a,) = _pick(seed);
        uint256 bal = q.balanceOf(a, address(0));
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(a);
        q.withdraw(address(0), amount);
        ghostWithdrawn += amount;
    }

    function redeem(uint256 payerSeed, uint256 payeeSeed, uint256 amount, bytes32 nonce) external {
        (address payer, uint256 pk) = _pick(payerSeed);
        (address payee,) = _pick(payeeSeed);
        uint256 bal = q.balanceOf(payer, address(0));
        if (bal == 0 || q.nonceUsed(payer, nonce)) return;
        amount = bound(amount, 1, bal);

        Quittance.PaymentAuthorization memory auth = Quittance.PaymentAuthorization({
            payer: payer,
            payee: payee,
            token: address(0),
            amount: amount,
            nonce: nonce,
            validAfter: 0,
            validBefore: 0
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, q.hashAuthorization(auth));
        q.redeem(auth, abi.encodePacked(r, s, v));
        ghostSettled += amount;
    }
}

contract QuittanceInvariantTest is Test {
    Quittance q;
    Handler handler;

    function setUp() public {
        q = new Quittance();
        handler = new Handler(q);
        targetContract(address(handler));
    }

    function invariant_solvency() public view {
        uint256 sum;
        uint256 n = handler.actorsLength();
        for (uint256 i; i < n; ++i) {
            sum += q.balanceOf(handler.actorAt(i), address(0));
        }
        assertEq(address(q).balance, sum, "solvency: contract balance != sum of internal balances");
    }

    function invariant_conservation() public view {
        uint256 held;
        uint256 n = handler.actorsLength();
        for (uint256 i; i < n; ++i) {
            held += q.balanceOf(handler.actorAt(i), address(0));
        }
        assertEq(
            handler.ghostDeposited(),
            handler.ghostWithdrawn() + handler.ghostSettled() + held,
            "conservation: value not conserved"
        );
    }
}
