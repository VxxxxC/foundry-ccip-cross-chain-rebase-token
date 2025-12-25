// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { CCIPLocalSimulatorFork, Register } from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import { RebaseToken } from "../src/RebaseToken.sol";
import { RebaseTokenPool } from "../src/RebaseTokenPool.sol";
import { Vault } from "../src/Vault.sol";
import { IRebaseToken } from "../src/interfaces/IRebaseToken.sol";
import { IERC20 } from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import { RegistryModuleOwnerCustom } from "@chainlink-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import { TokenAdminRegistry } from "@chainlink-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import { RateLimiter } from "@chainlink-ccip/contracts/libraries/RateLimiter.sol";
import { TokenPool } from "@chainlink-ccip/contracts/pools/TokenPool.sol";

contract CrossChain is Test {
  uint256 sepoliaFork;
  uint256 arbSepoliaFork;
  CCIPLocalSimulatorFork ccipLocalSimulatorFork;

  RebaseToken sepoliaRebaseToken;
  RebaseToken arbSepoliaRebaseToken;

  RebaseTokenPool sepoliaPool;
  RebaseTokenPool arbSepoliaPool;

  Vault vault;

  Register.NetworkDetails sepoliaNetworkDetails;
  Register.NetworkDetails arbSepoliaNetworkDetails;

  address public owner = makeAddr("owner");

  function setUp() public {
    sepoliaFork = vm.createSelectFork(vm.rpcUrl("sepolia-eth")); // Create and select a fork of Sepolia
    arbSepoliaFork = vm.createFork(vm.rpcUrl("arb-sepolia")); // Create a fork of Arbitrum Sepolia, but not yet selected
    ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
    vm.makePersistent(address(ccipLocalSimulatorFork));

    // *NOTE 1. Deploy RebaseToken and config on Sepolia
    sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
    sepoliaRebaseToken = new RebaseToken();
    vault = new Vault(IRebaseToken(address(sepoliaRebaseToken)));
    sepoliaPool = new RebaseTokenPool(
      IERC20(address(sepoliaRebaseToken)),
      new address[](0),
      sepoliaNetworkDetails.rmnProxyAddress,
      sepoliaNetworkDetails.routerAddress
    );
    sepoliaRebaseToken.grantMintAndBurnRole(address(vault));
    sepoliaRebaseToken.grantMintAndBurnRole(address(sepoliaPool));
    RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
      .registerAdminViaOwner(address(sepoliaRebaseToken));
    TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaRebaseToken));
    TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
      .setPool(address(sepoliaRebaseToken), address(sepoliaPool));
    vm.stopPrank();

    // *NOTE 2. Deploy RebaseToken and config on Arbitrum Sepolia
    vm.selectFork(arbSepoliaFork); // Switch to Arbitrum Sepolia fork
    arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
    vm.startPrank(owner);
    arbSepoliaRebaseToken = new RebaseToken();
    arbSepoliaPool = new RebaseTokenPool(
      IERC20(address(arbSepoliaRebaseToken)),
      new address[](0),
      arbSepoliaNetworkDetails.rmnProxyAddress,
      arbSepoliaNetworkDetails.routerAddress
    );
    arbSepoliaRebaseToken.grantMintAndBurnRole(address(arbSepoliaPool));
    RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
      .registerAdminViaOwner(address(arbSepoliaRebaseToken));
    TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
      .acceptAdminRole(address(arbSepoliaRebaseToken));
    TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
      .setPool(address(arbSepoliaRebaseToken), address(arbSepoliaPool));

    configureTokenPool(
      sepoliaFork,
      address(sepoliaPool),
      arbSepoliaNetworkDetails.chainSelector,
      address(arbSepoliaPool),
      address(arbSepoliaRebaseToken)
    );
    configureTokenPool(
      arbSepoliaFork,
      address(arbSepoliaPool),
      sepoliaNetworkDetails.chainSelector,
      address(sepoliaPool),
      address(sepoliaRebaseToken)
    );
    vm.stopPrank();
  }

  function configureTokenPool(
    uint256 _fork,
    address _localPool,
    uint64 remoteChainSelector,
    address remotePool,
    address remoteTokenAddress
  ) public {
    vm.selectFork(_fork);
    vm.prank(owner);
    bytes[] memory remotePoolAddresses = new bytes[](1);
    remotePoolAddresses[0] = abi.encode(remotePool);
    TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
    chainsToAdd[0] = TokenPool.ChainUpdate({
      remoteChainSelector: remoteChainSelector,
      remotePoolAddresses: remotePoolAddresses,
      remoteTokenAddress: abi.encode(remoteTokenAddress),
      outboundRateLimiterConfig: RateLimiter.Config({ isEnabled: false, capacity: 0, rate: 0 }),
      inboundRateLimiterConfig: RateLimiter.Config({ isEnabled: false, capacity: 0, rate: 0 })
    });
    TokenPool(_localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
  }
}
