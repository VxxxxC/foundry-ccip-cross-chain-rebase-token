// // SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @dev An ERC20 token that supports rebasing functionality.
 * @notice This is cross-chain rebase token, that incentivises users to deposit into vault and gain interest in reward.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is global interest rate at the time of depositing
 */
contract RebaseToken is ERC20("RebaseToken", "RBTK"), Ownable(msg.sender), AccessControl {
    // STATE VARIABLES
    uint256 private constant PRECISION_FACTOR = 1e18; // 1e18 = 1.0 in precision factor
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = 5e10; // 5e10 = 0.00000005 tokens per second per token deposited
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    // ERRORS
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentRate, uint256 newRate);

    // EVENTS
    event InterestRateSet(uint256 newInterestRate);

    constructor() {}

    /**
     * @notice Transfer tokens from user to other recipient
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return bool return true if the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from sender to recipient
     * @param _sender The address of the sender
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return bool return true if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    function setInterestRate(uint256 newInterestRate) external onlyOwner {
        if (newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, newInterestRate);
        }
        s_interestRate = newInterestRate;
        emit InterestRateSet(newInterestRate);
    }

    /**
     * @notice Get the principal balance of the user. This is the number of tokens that have currently been minted to the user, not including any interest that has accrued since the last time the user interacted with the protocol.
     * @param _user The address of the user
     * @return The principal balance of the user
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the rebase token to user when they deposit into vault
     * @param _to The user address to mint the rebase token to
     * @param _amount The amount of rebase token to mint
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The user address to burn the rebase token from
     * @param _amount The amount of rebase token to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = this.balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
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
        uint256 principal = super.balanceOf(_user);
        console.log("Principal:", principal);
        uint256 multiplier = _calculateUserAccumulatedInterestSinceLastUpdated(_user);
        console.log("Multiplier:", multiplier);

        if (multiplier == 1) {
            return principal;
        }

        return (principal * multiplier / PRECISION_FACTOR);
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

    /**
     * @notice Mint the accrued interest to user since the last time they interacted with the protocol (e.g. mint, burn, transfer)
     * @param _user The user to mint the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // [1] Find their current balance of rebase tokens that have minted to user -> principal balance
        uint256 principalBalance = super.balanceOf(_user);
        // [2] Calculate their current balance including interest -> balanceOf
        uint256 currentBalanceWithInterest = balanceOf(_user);
        // Calculate the number of tokens that need to be minted to user -> [2] - [1]
        uint256 balanceIncrease = currentBalanceWithInterest - principalBalance;
        // Set the user last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // Call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    /**
     *
     * @notice Get the interest rate for user
     * @param _user The address of the user
     * @return uint256 The interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Get the global interest rate of the contract that is currently set. Any future depositors will receive this interest rate.
     * @return uint256 global interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }
}
