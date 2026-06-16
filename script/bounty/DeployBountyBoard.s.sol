// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {BountyBoard} from "../../src/bounty/BountyBoard.sol";

/**
 * @notice Deploys BountyBoard to the configured network.
 *
 * Usage:
 *   forge script script/bounty/DeployBountyBoard.s.sol \
 *     --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
 */
contract DeployBountyBoard is Script {
    function run() external returns (BountyBoard board) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        board = new BountyBoard();
        vm.stopBroadcast();
        console.log("BountyBoard deployed at:", address(board));
    }
}
