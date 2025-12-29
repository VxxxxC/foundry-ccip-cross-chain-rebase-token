// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { IRouterClient } from "@chainlink-ccip/contracts/interfaces/IRouterClient.sol";
import { Client } from "@chainlink-ccip/contracts/libraries/Client.sol";
import { IERC20 } from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";

contract BridgeTokens is Script {
  function run(
    address localTokenAddress,
    uint256 transferAmount,
    address receiverAddress,
    uint64 destinationChainSelector,
    address routerAddress,
    address linkTokenAddress
  ) public {
    vm.startBroadcast();
    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({ token: localTokenAddress, amount: transferAmount });
    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(receiverAddress),
      data: "",
      tokenAmounts: tokenAmounts,
      feeToken: linkTokenAddress,
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({ gasLimit: 0 }))
    });

    uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
    IERC20(linkTokenAddress).approve(routerAddress, ccipFee);
    IERC20(localTokenAddress).approve(routerAddress, transferAmount);
    IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
    vm.stopBroadcast();
  }
}
