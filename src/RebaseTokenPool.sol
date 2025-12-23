// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { TokenPool } from "@chainlink-ccip/chains/evm/contracts/pools/TokenPool.sol";
import { Pool } from "@chainlink-ccip/chains/evm/contracts/libraries/Pool.sol";
import { RebaseToken } from "./RebaseToken.sol";

contract RebaseTokenPool is TokenPool {
  constructor(IERC20 _token, address[] memory allowList, address rmnProxy, address router)
    TokenPool(_token, 18, allowList, rmnProxy, router)
  { }

  function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
    external
    returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
  { }

  function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
    external
    returns (Pool.ReleaseOrMintOutV1 memory)
  { }
}
