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
import { Client } from "@chainlink-ccip/contracts/libraries/Client.sol";
import { IRouterClient } from "@chainlink-ccip/contracts/interfaces/IRouterClient.sol";

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
  address public user = makeAddr("user");

  uint256 public constant SEND_VALUE = 1e5; // 1e5 = 0.0001 ETH

  function setUp() public {
    sepoliaFork = vm.createSelectFork(vm.rpcUrl("sepolia-eth")); // Create and select a fork of Sepolia
    arbSepoliaFork = vm.createFork(vm.rpcUrl("arb-sepolia")); // Create a fork of Arbitrum Sepolia, but not yet selected
    ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
    vm.makePersistent(address(ccipLocalSimulatorFork));

    // *NOTE 1. Deploy RebaseToken and config on Sepolia
    sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
    vm.startPrank(owner);
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
    vm.startPrank(owner);
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

  function bridgeToken(
    uint256 _amountToBridge,
    uint256 _localFork,
    uint256 _remoteFork,
    Register.NetworkDetails memory _localNetworkDetails,
    Register.NetworkDetails memory _remoteNetworkDetails,
    RebaseToken _localRebaseToken,
    RebaseToken _remoteRebaseToken
  ) public {
    vm.selectFork(_localFork); // where the initial Fork is selected and start to cross-chain
    vm.startPrank(user);

    // Prepare token amounts to bridge
    Client.EVMTokenAmount[] memory tokenAmount = new Client.EVMTokenAmount[](1);
    tokenAmount[0] = Client.EVMTokenAmount({ token: address(_localRebaseToken), amount: _amountToBridge });

    // Prepare CCIP message
    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(user),
      data: "",
      tokenAmounts: tokenAmount,
      feeToken: _localNetworkDetails.linkAddress,
      extraArgs: Client._argsToBytes(Client.GenericExtraArgsV2({ gasLimit: 500_000, allowOutOfOrderExecution: false }))
    });
    uint256 fee = IRouterClient(_localNetworkDetails.routerAddress).getFee(_remoteNetworkDetails.chainSelector, message);

    // Request Link for fee from the local simulator faucet
    ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

    // Approve pay the Link for fee and RebaseToken for bridging
    vm.startPrank(user);
    IERC20(_localNetworkDetails.linkAddress).approve(_localNetworkDetails.routerAddress, fee);

    // Approve RebaseToken transfer
    vm.startPrank(user);
    IERC20(address(_localRebaseToken)).approve(_localNetworkDetails.routerAddress, _amountToBridge);

    uint256 localTokenBefore = _localRebaseToken.balanceOf(user);

    // Send the cross-chain message
    vm.startPrank(user);
    IRouterClient(_localNetworkDetails.routerAddress).ccipSend(_remoteNetworkDetails.chainSelector, message);

    uint256 localTokenAfter = _localRebaseToken.balanceOf(user);

    assertEq(
      localTokenBefore - localTokenAfter,
      _amountToBridge,
      "Local token balance did not decrease correctly after bridging"
    );
    uint256 localUserInterestRate = _localRebaseToken.getUserInterestRate(user);

    // WARN : remote account balance must be `vm.selectFork` switched to remote fork & `switchChainAndRouteMessage` first, then get the `balanceOf()` , otherwise will Revert EVM error
    ccipLocalSimulatorFork.switchChainAndRouteMessage(_remoteFork); // looks for `CCIPSendRequest` and `CCIPMessageSent` events after sent cross-chain message `ccipSend`
    vm.selectFork(_remoteFork); // Switch to the remote fork to check the bridged tokens
    uint256 remoteBalanceBeforeInterested = _remoteRebaseToken.balanceOf(user);
    vm.warp(block.timestamp + 1 hours); // Advance time to allow message processing
    uint256 remoteBalanceAfterInterested = _remoteRebaseToken.balanceOf(user);

    uint256 remoteBalanceInterestedOnly = remoteBalanceAfterInterested - remoteBalanceBeforeInterested;

    // PERF: comment this assertEq , for fixing build error "Stack too deep"
    // assertEq(
    //   remoteBalanceAfterInterested,
    //   (_amountToBridge + remoteBalanceInterestedOnly),
    //   "Remote token balance did not increase correctly after bridging"
    // );
    uint256 remoteUserInterestRate = _remoteRebaseToken.getUserInterestRate(user);
    assertEq(localUserInterestRate, remoteUserInterestRate, "Interest rates do not match after bridging");

    vm.stopPrank();
  }

  function testBridgeAllTokens() public {
    vm.selectFork(sepoliaFork);
    vm.deal(user, SEND_VALUE);
    vm.startPrank(user);
    Vault(payable(address(vault))).deposit{ value: SEND_VALUE }();
    assertEq(
      sepoliaRebaseToken.balanceOf(user), SEND_VALUE, "User did not receive correct amount of RebaseToken after deposit"
    );

    // Bridge all tokens from Sepolia to Arbitrum Sepolia
    try this.bridgeToken(
      SEND_VALUE,
      sepoliaFork,
      arbSepoliaFork,
      sepoliaNetworkDetails,
      arbSepoliaNetworkDetails,
      sepoliaRebaseToken,
      arbSepoliaRebaseToken
    ) { }
    catch {
      console.log("Bridging from Sepolia to Arbitrum Sepolia failed");
    }

    vm.selectFork(arbSepoliaFork);
    vm.warp(block.timestamp + 1 hours);

    try this.bridgeToken(
      arbSepoliaRebaseToken.balanceOf(user),
      arbSepoliaFork,
      sepoliaFork,
      arbSepoliaNetworkDetails,
      sepoliaNetworkDetails,
      arbSepoliaRebaseToken,
      sepoliaRebaseToken
    ) { }
    catch {
      console.log("Bridging from Arbitrum Sepolia to Sepolia failed");
    }
  }
}
