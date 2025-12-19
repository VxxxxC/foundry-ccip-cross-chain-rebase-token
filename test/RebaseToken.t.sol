// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    error RebaseTokenTest__DepositFailed();

    function setUp() public {
        vm.startPrank(owner);
        vm.deal(owner, 1e18); // fund the owner with 1 ETH
        rebaseToken = new RebaseToken();
        vault = new Vault(address(IRebaseToken(address(rebaseToken))));
        rebaseToken.grantMintAndBurnRole(address(vault));

        (bool success,) = payable(address(vault)).call{value: 1e18}(""); // fund the vault with 1 ETH via fallback
        if (!success) {
            revert RebaseTokenTest__DepositFailed();
        }

        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        vm.assume(amount > 1e4); // minimum deposit amount from fuzzy input
        amount = bound(amount, 1e4, type(uint96).max); // bound the fuzzy input to the amount from 0.01 ETH to max uint96)
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount); // set input amount for fuzzy testing
        vault.deposit{value: amount}();

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
}
