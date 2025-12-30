// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { Vault } from "../src/Vault.sol";
import { IRebaseToken } from "../src/interfaces/IRebaseToken.sol";
import { RebaseToken } from "../src/RebaseToken.sol";
import { RebaseTokenPool } from "../src/RebaseTokenPool.sol";
import { IERC20 } from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import { CCIPLocalSimulatorFork, Register } from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import { RegistryModuleOwnerCustom } from "@chainlink-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import { TokenAdminRegistry } from "@chainlink-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";

contract TokenAndPoolDeployer is Script {
  function run() public returns (RebaseToken rebaseToken, RebaseTokenPool rebaseTokenPool) {
    CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
    Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
    vm.startBroadcast();
    rebaseToken = new RebaseToken();
    rebaseTokenPool = new RebaseTokenPool(
      IERC20(address(rebaseToken)), new address[](0), networkDetails.rmnProxyAddress, networkDetails.routerAddress
    );
    rebaseToken.grantMintAndBurnRole(address(rebaseTokenPool));
    RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress)
      .registerAdminViaOwner(address(rebaseToken));
    TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(rebaseToken));
    TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(address(rebaseToken), address(rebaseTokenPool));

    vm.stopBroadcast();
  }
}

contract VaultDeployer is Script {
  function run(
    address rebaseToken
  ) public returns (Vault vault) {
    vm.startBroadcast();
    vault = new Vault(IRebaseToken(rebaseToken));
    IRebaseToken(rebaseToken).grantMintAndBurnRole(address(vault));
    vm.stopBroadcast();
  }
}

contract SetPermission is Script {
  function grantRole(
    address token,
    address pool
  ) public {
    vm.startBroadcast();

    vm.stopBroadcast();
  }

  function setAdminAndPool(
    address token,
    address pool
  ) public {
    vm.startBroadcast();

    vm.stopBroadcast();
  }
}

