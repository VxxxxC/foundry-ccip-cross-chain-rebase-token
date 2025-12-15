// // SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @dev An ERC20 token that supports rebasing functionality.
 * @notice This is cross-chain rebase token, that incentivises users to deposit into vault and gain interest in reward.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is global interest rate at the time of depositing
 */
contract RebaseToken is ERC20("RebaseToken", "RBTK") {
    // STATE VARIABLES
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = 5e10; // 5% initial interest rate, scaled by 1e10
    mapping(address => uint256) public s_userInterestRate;
    mapping(address => uint256) public s_userLastUpdatedTimestamp;

    // ERRORS
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentRate, uint256 newRate);

    // EVENTS
    event InterestRateSet(uint256 newInterestRate);

    constructor() {}

    function setInterestRate(uint256 newInterestRate) external {
        if (newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, newInterestRate);
        }
        s_interestRate = newInterestRate;
        emit InterestRateSet(newInterestRate);
    }

    /**
     * @notice Mint the rebase token to user when they deposit into vault
     * @param _to The user address to mint the rebase token to
     * @param _amount The amount of rebase token to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Calculate the balance for the user including the interest that has accumulated since last updated timestamp
     * @notice (principal balance) + some interest that has accrued
     * @param _user The user the calculate the balance for
     * @return The balance of the user including the interest that has accumulated since last updated timestamp
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the user current principal balance (the number of tokens have been minted to user)
        // multiply the principal balance by interest rate that has accumulated since last updated timestamp
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdated(_user);
    }

    /**
     * @notice Calculate the accumulated interest for user since last updated timestamp
     * @param _user The user to calculate the accumulated interest for
     * @return linearInterest The accumulated interest multiplier
     */
    function _calculateUserAccumulatedInterestSinceLastUpdated(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last updated
        // this will going to be linear growth with time
        // 1. Calculate the time since last updated
        // 2. Calculate the amount of linear growth
        //
        // (principal amount) + principal amount * user interest rate * time elapsed
        // deposit : 10 tokens
        // interest rate: 0.5 token per seconds
        // time elapsed: 2 seconds
        // total = 10 + 10 * 0.5 * 2 = 20 tokens
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    function _mintAccruedInterest(address _user) internal {
        // [1] Find their current balance of rebase tokens that have minted to user -> principal balance
        // [2] Calculate their current balance including interest -> balanceOf
        // Calculate the number of tokens that need to be minted to user -> [2] - [1]
        // Call _mint to mint the tokens to the user
        // Set the user last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    /**
     *
     * @notice Get the interest rate for user
     * @param _user The address of the user
     * @return The interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
