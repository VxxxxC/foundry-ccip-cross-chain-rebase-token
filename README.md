# Cross-chain Rebase Token

1. A protocol allows user deposit into a vault and in return, receive rebase tokens that represent their underlying balance
2. Rebase token -> balanceOf function is dynamic to show the changing balance withh time.
   - Balance increase linearly with time
   - mint tokens to our user every time they perform an action (mintingm burnin, transferring, or... bridging)
3. Interest rate
   - Indivually set an interest rate or each user based on some global interest rate of the protocol at the time the user deposits into vault.
   - This global interest rate can only decrease to incetivise/reward early adopters.
