// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { IRebaseToken } from "./interfaces/IRebaseToken.sol";

contract Vault {
  // pass the rebase token to the constructor
  // create a deposit function thats mints tokens to the users, equal to amount of ETH the users has sent
  // create a redeem function that burns tokens from the users, and sends the user ETH
  // create a way to add rewards to the vault

  // STATE VARIABLES
  IRebaseToken public immutable i_rebaseToken;

  // EVENTS
  event Deposit(address indexed user, uint256 amount);
  event Redeem(address indexed user, uint256 amount);

  // ERRORS
  error Vault__RedeemFailed();

  constructor(address _rebaseToken) {
    i_rebaseToken = IRebaseToken(_rebaseToken);
  }

  receive() external payable { } // fallback function to receive ETH

  /**
   * @notice Allow users to deposit ETH into the vault, and mint rebase token in return
   */
  function deposit() external payable {
    // use the amount of ETH that the user has sent to mint rebase tokens to the user
    i_rebaseToken.mint(msg.sender, msg.value);
    emit Deposit(msg.sender, msg.value);
  }

  /**
   * @notice Allow users to redeem their rebase tokens for ETH
   * @param _amount The amount of rebase tokens to redeem
   */
  function redeem(uint256 _amount) external {
    if (_amount == type(uint256).max) {
      _amount = i_rebaseToken.balanceOf(msg.sender);
    }

    // burn the rebase tokens from the user
    i_rebaseToken.burn(msg.sender, _amount);
    // send the user ETH equal to the amount of rebase tokens burned
    (bool success,) = payable(msg.sender).call{ value: _amount }("");
    if (!success) {
      revert Vault__RedeemFailed();
    }

    emit Redeem(msg.sender, _amount);
  }

  /**
   * @notice Get the address of the rebase token
   * @return address The address of the rebase token
   */
  function getRebaseTokenAddress() external view returns (address) {
    return address(i_rebaseToken);
  }
}
