// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { RebaseToken } from "../src/RebaseToken.sol";
import { Vault } from "../src/Vault.sol";
import { IRebaseToken } from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
  RebaseToken private rebaseToken;
  Vault private vault;

  address public owner = makeAddr("owner");
  address public user = makeAddr("user");
  address public anotherUser = makeAddr("anotherUser");

  error RebaseTokenTest__DepositFailed();

  function setUp() public {
    vm.startPrank(owner);
    vm.deal(owner, 1e18); // fund the owner with 1 ETH
    rebaseToken = new RebaseToken();
    vault = new Vault(address(IRebaseToken(address(rebaseToken))));
    rebaseToken.grantMintAndBurnRole(address(vault));

    (bool success,) = payable(address(vault)).call{ value: 1e18 }(""); // fund the vault with 1 ETH via fallback
    if (!success) {
      revert RebaseTokenTest__DepositFailed();
    }

    vm.stopPrank();
  }

  function addRewardsToVault(uint256 rewardAmount) public {
    (bool success, ) = payable(address(vault)).call{value: rewardAmount}("");
  }

  function testDepositLinear(uint256 amount) public {
    vm.assume(amount > 1e4); // minimum deposit amount from fuzzy input
    amount = bound(amount, 1e4, type(uint96).max); // bound the fuzzy input to the amount from 0.01 ETH to max uint96)
    // 1. deposit
    vm.startPrank(user);
    vm.deal(user, amount); // set input amount for fuzzy testing
    vault.deposit{ value: amount }();

    // 2. check out rebase token balance
    uint256 initialBalance = rebaseToken.balanceOf(user);
    console.log("Initial balance:", initialBalance);
    assertEq(initialBalance, amount);

    // 3. warp the time and check the balance again
    vm.warp(block.timestamp + 1 hours);
    uint256 middleBalance = rebaseToken.balanceOf(user);
    console.log("New balance after 1 hour:", middleBalance);
    assertGt(middleBalance, initialBalance);

    // 4. warp the time again by the same amount and check the balance again
    vm.warp(block.timestamp + 1 hours);
    uint256 finalBalance = rebaseToken.balanceOf(user);
    console.log("New balance after another hour:", finalBalance);
    assertGt(finalBalance, middleBalance);

    // 5. check the balances between each hour to ensure linear growth
    uint256 interestFirstHour = middleBalance - initialBalance;
    uint256 interestSecondHour = finalBalance - middleBalance;
    assertApproxEqAbs(interestFirstHour, interestSecondHour, 1);

    vm.stopPrank();
  }

  function testRedeemStraightAway(uint256 amount) public {
    amount = bound(amount, 1e4, type(uint96).max);
    // 1. deposit
    vm.startPrank(user);
    vm.deal(user, amount);
    vault.deposit{ value: amount }();
    assertEq(address(user).balance, 0);
    assertEq(rebaseToken.balanceOf(user), amount);

    // 2. redeem
    vault.redeem(type(uint256).max);
    assertEq(rebaseToken.balanceOf(user), 0);
    assertEq(address(user).balance, amount);

    vm.stopPrank();
  }

  function testRedeemByAmount(uint256 amount) public {
    amount = bound(amount, 1e4, type(uint96).max);
    // 1. deposit
    vm.startPrank(user);
    vm.deal(user, amount);
    vault.deposit{ value: amount }();
    assertEq(address(user).balance, 0);
    assertEq(rebaseToken.balanceOf(user), amount);

    // 2. redeem
    vault.redeem(amount);
    assertEq(rebaseToken.balanceOf(user), 0);
    assertEq(address(user).balance, amount);

    vm.stopPrank();
  }

  function testRedeemAfterTimePassed(uint256 deposit, uint256 time) public {
    time = bound(time, 1000, type(uint96).max);
    deposit = bound(deposit, 1e5, type(uint96).max);
    console.log("Deposit amount:", deposit);
    console.log("Time warp seconds:", time);

    // 1. deposit
    vm.deal(user, deposit);
    vm.prank(user);
    vault.deposit{ value: deposit }();

    // 2. warp time
    vm.warp(block.timestamp + time);
    uint256 balanceAfterTime = rebaseToken.balanceOf(user);
    console.log("Balance after time warp:", balanceAfterTime);

    // 2b. add rewards to the vault to simulate interest
    vm.deal(owner, balanceAfterTime - deposit);
    vm.prank(owner);
    addRewardsToVault( balanceAfterTime - deposit );

    // 3. redeem
    vm.prank(user);
    vault.redeem(type(uint256).max);

    uint256 ethBalance = address(user).balance;
    console.log("ETH balance after redeem:", ethBalance);

    assertEq(ethBalance, balanceAfterTime);
    assertGt(ethBalance, deposit);
  }
}
