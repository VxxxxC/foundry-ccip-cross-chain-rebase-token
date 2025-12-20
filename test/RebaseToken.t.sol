// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { RebaseToken } from "../src/RebaseToken.sol";
import { Vault } from "../src/Vault.sol";
import { IRebaseToken } from "../src/interfaces/IRebaseToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
  RebaseToken private rebaseToken;
  Vault private vault;

  address public owner = makeAddr("owner");
  address public user = makeAddr("user");

  error RebaseTokenTest__DepositFailed();

  function setUp() public {
    vm.startPrank(owner);
    vm.deal(owner, 1e18); // fund the owner with 1 ETH
    rebaseToken = new RebaseToken(); // call RebaseToken constructor
    vault = new Vault(address(IRebaseToken(address(rebaseToken)))); // pass rebase token address to vault constructor , cast to IRebaseToken interface
    rebaseToken.grantMintAndBurnRole(address(vault));

    (bool success,) = payable(address(vault)).call{ value: 1e18 }(""); // fund the vault with 1 ETH via fallback
    if (!success) {
      revert RebaseTokenTest__DepositFailed();
    }

    vm.stopPrank();
  }

  function addRewardsToVault(uint256 rewardAmount) public {
    (bool success,) = payable(address(vault)).call{ value: rewardAmount }("");
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
    addRewardsToVault(balanceAfterTime - deposit);

    // 3. redeem
    vm.prank(user);
    vault.redeem(type(uint256).max);

    uint256 ethBalance = address(user).balance;
    console.log("ETH balance after redeem:", ethBalance);

    assertEq(ethBalance, balanceAfterTime);
    assertGt(ethBalance, deposit);
  }

  function testTransfer(uint256 amount, uint256 amountToSend) public {
    amount = bound(amount, 1e5 + 1e5, type(uint96).max); // 1e5 + 1e5 to ensure at least 0.0001 ETH
    amountToSend = bound(amountToSend, 1e5, amount - 1e5); //  [1e5, amount - 1e5] to ensure at least 0.0001 ETH remains

    // 1. deposit
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    // 2. make another user
    address anotherUser = makeAddr("anotherUser");

    // 3. check both initial balances
    uint256 initialBalanceUser = rebaseToken.balanceOf(user);
    uint256 initialBalanceAnotherUser = rebaseToken.balanceOf(anotherUser);
    assertEq(initialBalanceUser, amount);
    assertEq(initialBalanceAnotherUser, 0);

    // 4. reduce the interest rate b owner
    vm.prank(owner);
    rebaseToken.setInterestRate(4e10); // 4e10 = 0.0000000004 tokens per second, default is 5e10

    // 5. transfer
    console.log("Deposit amount:", amount);
    console.log("Amount to send:", amountToSend);
    vm.prank(user);
    rebaseToken.transfer(anotherUser, amountToSend);

    // 6. check both final balances
    uint256 finalBalanceUser = rebaseToken.balanceOf(user);
    uint256 finalBalanceAnotherUser = rebaseToken.balanceOf(anotherUser);

    assertEq(finalBalanceUser, initialBalanceUser - amountToSend); // exact equal to initial - sent
    assertEq(finalBalanceAnotherUser, amountToSend);
    assertApproxEqAbs(finalBalanceAnotherUser, initialBalanceAnotherUser, amountToSend); // absolute approx equal to amountToSend

    // check the user interest rate has been inherited
    assertEq(rebaseToken.getUserInterestRate(user), 5e10);
    assertEq(rebaseToken.getUserInterestRate(anotherUser), 5e10);
  }

  function testCannotSetInterestRate(uint256 newInterestRate) public {
    vm.prank(user);
    vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
    rebaseToken.setInterestRate(newInterestRate);
  }

  function testCannotCallMintAndBurn(uint256 amountToMint, uint256 amountToBurn) public {
    vm.prank(user);
    vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
    rebaseToken.mint(user, amountToMint);

    vm.prank(user);
    vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
    rebaseToken.burn(user, amountToBurn);
  }

  function testPrincipalAmount(uint256 amount) public {
    amount = bound(amount, 1e5, type(uint96).max);
    // 1. deposit
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();
    assertEq(rebaseToken.principalBalanceOf(user), amount);

    // 2. warp time and check principal balance again
    vm.warp(block.timestamp + 1 hours);
    assertEq(rebaseToken.principalBalanceOf(user), amount);
  }

  function testGetRebaseTokenAddress() public view {
    assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
  }

  function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
    uint256 initialRate = rebaseToken.getInterestRate();
    newInterestRate = bound(newInterestRate, initialRate + 1, type(uint96).max);
    vm.prank(owner);
    vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
    rebaseToken.setInterestRate(newInterestRate);

    uint256 finalRate = rebaseToken.getInterestRate();
    assertEq(finalRate, initialRate);
  }
}
