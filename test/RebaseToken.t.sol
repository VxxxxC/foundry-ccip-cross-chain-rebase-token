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

  // ============ ADDITIONAL TEST CASES FOR COVERAGE ============

  /**
   * @notice Test transferFrom function (ERC20 approval flow)
   */
  function testTransferFrom(uint256 amount, uint256 amountToSend) public {
    amount = bound(amount, 1e5 + 1e5, type(uint96).max);
    amountToSend = bound(amountToSend, 1e5, amount - 1e5);

    // 1. deposit as user
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    // 2. create spender and approve
    address spender = makeAddr("spender");
    vm.prank(user);
    rebaseToken.approve(spender, amountToSend);

    // 3. create recipient
    address recipient = makeAddr("recipient");

    // 4. check initial balances
    uint256 userInitialBalance = rebaseToken.balanceOf(user);
    assertEq(userInitialBalance, amount);
    assertEq(rebaseToken.balanceOf(recipient), 0);

    // 5. transferFrom by spender
    vm.prank(spender);
    rebaseToken.transferFrom(user, recipient, amountToSend);

    // 6. verify balances
    assertEq(rebaseToken.balanceOf(user), userInitialBalance - amountToSend);
    assertEq(rebaseToken.balanceOf(recipient), amountToSend);
  }

  /**
   * @notice Test transferFrom with type(uint256).max to transfer all tokens
   */
  function testTransferFromMaxAmount(uint256 amount) public {
    amount = bound(amount, 1e5, type(uint96).max);

    // 1. deposit as user
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    // 2. create spender with max approval
    address spender = makeAddr("spender");
    address recipient = makeAddr("recipient");
    vm.prank(user);
    rebaseToken.approve(spender, type(uint256).max);

    // 3. transferFrom with max uint256 (should transfer all)
    vm.prank(spender);
    rebaseToken.transferFrom(user, recipient, type(uint256).max);

    // 4. verify user balance is 0 and recipient has all
    assertEq(rebaseToken.balanceOf(user), 0);
    assertEq(rebaseToken.balanceOf(recipient), amount);
  }

  /**
   * @notice Test transfer with type(uint256).max to transfer all tokens
   */
  function testTransferMaxAmount(uint256 amount) public {
    amount = bound(amount, 1e5, type(uint96).max);

    // 1. deposit as user
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    address recipient = makeAddr("recipient");

    // 2. transfer with max uint256
    vm.prank(user);
    rebaseToken.transfer(recipient, type(uint256).max);

    // 3. verify
    assertEq(rebaseToken.balanceOf(user), 0);
    assertEq(rebaseToken.balanceOf(recipient), amount);
  }

  /**
   * @notice Test transferFrom inherits sender's interest rate when recipient has no balance
   */
  function testTransferFromInheritsInterestRate(uint256 amount) public {
    amount = bound(amount, 1e5, type(uint96).max);

    // 1. deposit
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    // 2. setup approval
    address spender = makeAddr("spender");
    address recipient = makeAddr("recipient");
    vm.prank(user);
    rebaseToken.approve(spender, amount);

    // 3. transferFrom
    vm.prank(spender);
    rebaseToken.transferFrom(user, recipient, amount / 2);

    // 4. verify recipient inherited user's interest rate
    assertEq(rebaseToken.getUserInterestRate(recipient), rebaseToken.getUserInterestRate(user));
  }

  /**
   * @notice Test transferFrom when recipient already has tokens (keeps their rate)
   */
  function testTransferFromRecipientKeepsOwnRate(uint256 amount) public {
    amount = bound(amount, 1e6, type(uint96).max);

    // 1. deposit for user
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    // 2. reduce interest rate
    vm.prank(owner);
    rebaseToken.setInterestRate(3e10);

    // 3. deposit for recipient with lower rate
    address recipient = makeAddr("recipient");
    vm.deal(recipient, amount / 2);
    vm.prank(recipient);
    vault.deposit{ value: amount / 2 }();

    uint256 recipientRateBefore = rebaseToken.getUserInterestRate(recipient);

    // 4. setup approval and transferFrom
    address spender = makeAddr("spender");
    vm.prank(user);
    rebaseToken.approve(spender, amount / 4);

    vm.prank(spender);
    rebaseToken.transferFrom(user, recipient, amount / 4);

    // 5. recipient keeps their original rate (not inherited from sender)
    assertEq(rebaseToken.getUserInterestRate(recipient), recipientRateBefore);
  }

  /**
   * @notice Test multiple deposits with different interest rates
   */
  function testMultipleDepositsWithRateChanges(uint256 amount) public {
    amount = bound(amount, 1e5, type(uint96).max / 2);

    // 1. first deposit at high rate
    vm.deal(user, amount * 2);
    vm.prank(user);
    vault.deposit{ value: amount }();

    uint256 firstRate = rebaseToken.getUserInterestRate(user);
    assertEq(firstRate, 5e10);

    // 2. reduce interest rate
    vm.prank(owner);
    rebaseToken.setInterestRate(2e10);

    // 3. second deposit at lower rate (rate should update)
    vm.prank(user);
    vault.deposit{ value: amount }();

    uint256 secondRate = rebaseToken.getUserInterestRate(user);
    assertEq(secondRate, 2e10); // user gets the new lower rate
  }

  /**
   * @notice Test zero amount transfer doesn't break anything
   */
  function testZeroTransfer() public {
    uint256 amount = 1e18;

    // 1. deposit
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    address recipient = makeAddr("recipient");

    // 2. transfer 0 tokens
    vm.prank(user);
    rebaseToken.transfer(recipient, 0);

    // 3. verify no change
    assertEq(rebaseToken.balanceOf(user), amount);
    assertEq(rebaseToken.balanceOf(recipient), 0);
  }

  /**
   * @notice Test transfer to self
   */
  function testTransferToSelf(uint256 amount) public {
    amount = bound(amount, 1e5, type(uint96).max);

    // 1. deposit
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    uint256 balanceBefore = rebaseToken.balanceOf(user);

    // 2. transfer to self
    vm.prank(user);
    rebaseToken.transfer(user, amount / 2);

    // 3. verify balance unchanged
    assertEq(rebaseToken.balanceOf(user), balanceBefore);
  }

  /**
   * @notice Test balanceOf when user has never interacted (multiplier edge case)
   */
  function testBalanceOfNewUser() public {
    address newUser = makeAddr("newUser");
    assertEq(rebaseToken.balanceOf(newUser), 0);
  }

  /**
   * @notice Test that interest accrues correctly after time passes then transfers
   */
  function testTransferAfterInterestAccrual(uint256 amount, uint256 time) public {
    amount = bound(amount, 1e5, type(uint96).max);
    time = bound(time, 1 hours, 30 days);

    // 1. deposit
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    // 2. warp time
    vm.warp(block.timestamp + time);

    uint256 balanceWithInterest = rebaseToken.balanceOf(user);
    assertGt(balanceWithInterest, amount);

    // 3. transfer half (including accrued interest)
    address recipient = makeAddr("recipient");
    uint256 transferAmount = balanceWithInterest / 2;

    vm.prank(user);
    rebaseToken.transfer(recipient, transferAmount);

    // 4. verify balances after transfer
    assertApproxEqAbs(rebaseToken.balanceOf(user), balanceWithInterest - transferAmount, 1);
    assertEq(rebaseToken.balanceOf(recipient), transferAmount);
  }

  /**
   * @notice Test interest rate can be set to same value (edge case)
   */
  function testSetSameInterestRate() public {
    uint256 currentRate = rebaseToken.getInterestRate();

    vm.prank(owner);
    rebaseToken.setInterestRate(currentRate); // same rate - should succeed

    assertEq(rebaseToken.getInterestRate(), currentRate);
  }

  /**
   * @notice Test interest rate can be set to zero
   */
  function testSetInterestRateToZero() public {
    vm.prank(owner);
    rebaseToken.setInterestRate(0);

    assertEq(rebaseToken.getInterestRate(), 0);

    // deposit and verify no interest accrues
    vm.deal(user, 1e18);
    vm.prank(user);
    vault.deposit{ value: 1e18 }();

    vm.warp(block.timestamp + 365 days);

    // balance should be unchanged since rate is 0
    assertEq(rebaseToken.balanceOf(user), 1e18);
  }

  /**
   * @notice Test vault redeem fails if vault has insufficient ETH
   */
  function testRedeemFailsWithInsufficientVaultBalance() public {
    uint256 depositAmount = 1e18;

    // 1. deposit
    vm.deal(user, depositAmount);
    vm.prank(user);
    vault.deposit{ value: depositAmount }();

    // 2. warp time so user has more tokens than ETH in vault
    vm.warp(block.timestamp + 365 days);

    uint256 balanceWithInterest = rebaseToken.balanceOf(user);
    assertGt(balanceWithInterest, depositAmount);

    // 3. try to redeem all - should fail because vault doesn't have enough ETH
    vm.prank(user);
    vm.expectRevert(Vault.Vault__RedeemFailed.selector);
    vault.redeem(type(uint256).max);
  }

  /**
   * @notice Test principal balance doesn't change with time (only actual balance changes)
   */
  function testPrincipalVsActualBalance(uint256 amount, uint256 time) public {
    amount = bound(amount, 1e5, type(uint96).max);
    time = bound(time, 1 hours, 30 days);

    // 1. deposit
    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    uint256 principalBefore = rebaseToken.principalBalanceOf(user);
    uint256 balanceBefore = rebaseToken.balanceOf(user);

    // 2. warp time
    vm.warp(block.timestamp + time);

    uint256 principalAfter = rebaseToken.principalBalanceOf(user);
    uint256 balanceAfter = rebaseToken.balanceOf(user);

    // 3. principal unchanged, actual balance increased
    assertEq(principalAfter, principalBefore);
    assertGt(balanceAfter, balanceBefore);
  }

  /**
   * @notice Test getUserInterestRate for user who never deposited
   */
  function testGetUserInterestRateNewUser() public {
    address newUser = makeAddr("newUser");
    assertEq(rebaseToken.getUserInterestRate(newUser), 0);
  }

  /**
   * @notice Test events are emitted correctly on deposit
   */
  function testDepositEmitsEvent(uint256 amount) public {
    amount = bound(amount, 1e5, type(uint96).max);

    vm.deal(user, amount);
    vm.prank(user);

    vm.expectEmit(true, false, false, true);
    emit Vault.Deposit(user, amount);

    vault.deposit{ value: amount }();
  }

  /**
   * @notice Test events are emitted correctly on redeem
   */
  function testRedeemEmitsEvent(uint256 amount) public {
    amount = bound(amount, 1e5, type(uint96).max);

    vm.deal(user, amount);
    vm.prank(user);
    vault.deposit{ value: amount }();

    vm.prank(user);
    vm.expectEmit(true, false, false, true);
    emit Vault.Redeem(user, amount);

    vault.redeem(amount);
  }

  /**
   * @notice Test interest rate change emits event
   */
  function testSetInterestRateEmitsEvent() public {
    uint256 newRate = 3e10;

    vm.prank(owner);
    vm.expectEmit(false, false, false, true);
    emit RebaseToken.InterestRateSet(newRate);

    rebaseToken.setInterestRate(newRate);
  }
}
