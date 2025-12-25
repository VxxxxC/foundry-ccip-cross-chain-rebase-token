// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol"; 
import {CCIPLocalSimulatorFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract CrossChain is Test {
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    function setUp() public {
        sepoliaFork = vm.createSelectFork(vm.rpcUrl("sepolia-eth")); // Create and select a fork of Sepolia
        arbSepoliaFork = vm.createFork(vm.rpcUrl("arb-sepolia")); // Create a fork of Arbitrum Sepolia, but not yet selected 
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
    }
}