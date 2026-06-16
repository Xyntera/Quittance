// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Quittance} from "../../src/quittance/Quittance.sol";

/**
 * Live stress: settle a large batch of signed vouchers in ONE transaction.
 *
 * Usage:
 *   QUIT=0x... N=100 forge script script/quittance/StressRedeemMany.s.sol \
 *     --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast --legacy
 */
contract StressRedeemMany is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address payer = vm.addr(pk);
        Quittance q = Quittance(payable(vm.envAddress("QUIT")));
        uint256 n = vm.envOr("N", uint256(100));
        address payee = 0x00000000000000000000000000000000C0FfeE00;
        uint256 amount = 1e10; // tiny per-voucher amount

        Quittance.PaymentAuthorization[] memory auths = new Quittance.PaymentAuthorization[](n);
        bytes[] memory sigs = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            auths[i] = Quittance.PaymentAuthorization({
                payer: payer,
                payee: payee,
                token: address(0),
                amount: amount,
                nonce: keccak256(abi.encode("live-stress", block.timestamp, i)),
                validAfter: 0,
                validBefore: 0
            });
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, q.hashAuthorization(auths[i]));
            sigs[i] = abi.encodePacked(r, s, v);
        }

        vm.startBroadcast(pk);
        q.depositNative{value: n * amount}();
        q.redeemMany(auths, sigs);
        vm.stopBroadcast();

        console.log("settled vouchers in one redeemMany tx:", n);
    }
}
