// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Quittance} from "../src/quittance/Quittance.sol";

/**
 * Stress: batch-settlement scaling.
 *
 * Measures redeemMany() gas as the batch size grows and confirms correctness at scale, so the
 * amortized per-voucher cost (and the practical batch ceiling under a block gas limit) is known.
 * Run with `forge test --match-contract QuittanceScale -vv` to print the gas table.
 */
contract QuittanceScaleTest is Test {
    Quittance q;
    uint256 payerPk;
    address payer;
    address payee = address(0xBEEF);

    function setUp() public {
        q = new Quittance();
        (payer, payerPk) = makeAddrAndKey("payer");
    }

    function _runBatch(uint256 n) internal returns (uint256 gasUsed) {
        uint256 total = n * 1 ether;
        vm.deal(payer, total);
        vm.prank(payer);
        q.depositNative{value: total}();

        Quittance.PaymentAuthorization[] memory auths = new Quittance.PaymentAuthorization[](n);
        bytes[] memory sigs = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            auths[i] = Quittance.PaymentAuthorization({
                payer: payer,
                payee: payee,
                token: address(0),
                amount: 1 ether,
                nonce: keccak256(abi.encode("scale", i)),
                validAfter: 0,
                validBefore: 0
            });
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPk, q.hashAuthorization(auths[i]));
            sigs[i] = abi.encodePacked(r, s, v);
        }

        uint256 g0 = gasleft();
        q.redeemMany(auths, sigs);
        gasUsed = g0 - gasleft();

        assertEq(payee.balance, total, "payee underpaid");
        assertEq(q.balanceOf(payer, address(0)), 0, "payer balance not drained");
    }

    function test_Scale_001() public {
        uint256 g = _runBatch(1);
        emit log_named_uint("redeemMany(1)   total gas", g);
    }

    function test_Scale_025() public {
        uint256 g = _runBatch(25);
        emit log_named_uint("redeemMany(25)  total gas", g);
        emit log_named_uint("redeemMany(25)  per-voucher", g / 25);
    }

    function test_Scale_050() public {
        uint256 g = _runBatch(50);
        emit log_named_uint("redeemMany(50)  total gas", g);
        emit log_named_uint("redeemMany(50)  per-voucher", g / 50);
    }

    function test_Scale_100() public {
        uint256 g = _runBatch(100);
        emit log_named_uint("redeemMany(100) total gas", g);
        emit log_named_uint("redeemMany(100) per-voucher", g / 100);
    }

    function test_Scale_250() public {
        uint256 g = _runBatch(250);
        emit log_named_uint("redeemMany(250) total gas", g);
        emit log_named_uint("redeemMany(250) per-voucher", g / 250);
    }
}
