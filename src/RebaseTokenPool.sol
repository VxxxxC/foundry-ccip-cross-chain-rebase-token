// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { TokenPool } from "@chainlink-ccip/chains/evm/contracts/pools/TokenPool.sol";
import { Pool } from "@chainlink-ccip/chains/evm/contracts/libraries/Pool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RebaseToken } from "./RebaseToken.sol";

contract RebaseTokenPool is TokenPool {
  constructor(
    IERC20 _token,
    address[] memory allowList,
    address rmnProxy,
    address router
  ) TokenPool(_token, 18, allowList, rmnProxy, router) { }

  function lockOrBurn(
    Pool.LockOrBurnInV1 calldata lockOrBurnIn
  ) public virtual override returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut) {
    _validateLockOrBurn(lockOrBurnIn);

    uint256 userInterestRate = RebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
    RebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
    lockOrBurnOut = Pool.LockOrBurnOutV1({
      destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
      destPoolData: abi.encode(userInterestRate) // encode and send user interest rate to destination chain
    });
  }

  function releaseOrMint(
    Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
  ) public virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
    _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount);
    uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256)); // receive and decode user interest rate from source chain
    RebaseToken(address(i_token))
      .mint(releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount, userInterestRate);

    return Pool.ReleaseOrMintOutV1({ destinationAmount: releaseOrMintIn.sourceDenominatedAmount });
  }
}
