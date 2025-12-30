// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { TokenPool } from "@chainlink-ccip/contracts/pools/TokenPool.sol";
import { RateLimiter } from "@chainlink-ccip/contracts/libraries/RateLimiter.sol";

contract ConfigurePoolScript is Script {
  function run(
    address localPool,
    uint64 remoteChainSelector,
    address remotePool,
    address remoteToken,
    bool outBoundRateLimiterIsEnabled,
    uint128 outBoundRateLimiterCapacity,
    uint128 outBoundRateLimterRate,
    bool inBoundRateLimiterIsEnabled,
    uint128 inBoundRateLimiterCapacity,
    uint128 inBoundRateLimterRate
  ) public {
    vm.startBroadcast();
    TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
    bytes[] memory remotePoolAddresses = new bytes[](1);
    remotePoolAddresses[0] = abi.encode(remotePool);
    chainsToAdd[0] = TokenPool.ChainUpdate({
      remoteChainSelector: remoteChainSelector,
      remotePoolAddresses: remotePoolAddresses,
      remoteTokenAddress: abi.encode(remoteToken),
      outboundRateLimiterConfig: RateLimiter.Config({
        isEnabled: outBoundRateLimiterIsEnabled, capacity: outBoundRateLimiterCapacity, rate: outBoundRateLimterRate
      }),
      inboundRateLimiterConfig: RateLimiter.Config({
        isEnabled: inBoundRateLimiterIsEnabled, capacity: inBoundRateLimiterCapacity, rate: inBoundRateLimterRate
      })
    });

    TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);

    vm.stopBroadcast();
  }
}
