## Enable your tokens in CCIP (Burn & Mint): Register from an EOA using Foundry 
### Using Chainlink Local with CCIP for testing CrossChain locally
[Chainlink CCIP (Burn & Mint) Doc](https://docs.chain.link/ccip/tutorials/evm/cross-chain-tokens/register-from-eoa-burn-mint-hardhat)

1. Deploying Tokens: You will deploy your `BurnMintERC20` tokens on the Avalanche Fuji and Arbitrum Sepolia testnets.

2. Deploying Token Pools: Once your tokens are deployed, you will deploy `BurnMintTokenPool` token pools on Avalanche Fuji and Arbitrum Sepolia. These pools are essential for minting and burning tokens during cross-chain transfers. Each token will be linked to a pool, which will manage token transfers and ensure proper handling of assets across chains.

3. Claiming Mint and Burn Roles: You will call `grantMintAndBurnRoles` for the mint and burn roles for the token pools, allowing your token pools to control how tokens are minted and burned during cross-chain transfers.

4. Claiming and Accepting the Admin Role: This is a two-step process:

      1. You will call the `RegistryModuleOwnerCustom` contract's `registerAdminViaOwner` function to register your EOA as the token admin. This role is required to enable your token in CCIP.

      2. Once claimed, you will call the `TokenAdminRegistry` contract's `acceptAdminRole` function to complete the registration process.

5. Linking Tokens to Pools: You will call the `TokenAdminRegistry` contract's setPool function to associate each token with its respective token pool.

6. Configuring Token Pools: You will call the `applyChainUpdates` function on your token pools to configure each pool by setting cross-chain transfer parameters, such as token pool rate limits and enabled destination chains.

7. Minting Tokens: You will call the `mint` function to mint tokens on Avalanche Fuji for your EOA. These tokens will later be used to test cross-chain transfers to Arbitrum Sepolia.

8. kTransferring Tokens: Finally, you will transfer tokens from Avalanche Fuji to Arbitrum Sepolia using CCIP. You will have the option to pay CCIP fees in either LINK tokens or native gas tokens.

