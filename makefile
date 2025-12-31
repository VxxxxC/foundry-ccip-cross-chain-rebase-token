-include .env

# Defined Constant
AMOUNT=100000

DEFAULT_ZKSYNC_LOCAL_KEY=0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110
DEFAULT_ZKSYNC_ADDRESS=0x36615Cf349d7F6344891B1e7CA7C72883F5dc049

ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM=0x3139687Ee9938422F57933C3CDB3E21EE43c4d0F
ZKSYNC_TOKEN_ADMIN_REGISTRY=0xc7777f12258014866c677Bdb679D0b007405b7DF
ZKSYNC_ROUTER=0xA1fdA8aa9A8C4b945C45aD30647b01f07D7A0B16
ZKSYNC_RNM_PROXY_ADDRESS=0x3DA20FD3D8a8f8c1f1A5fD03648147143608C467
ZKSYNC_SEPOLIA_CHAIN_SELECTOR=6898391096552792247
ZKSYNC_LINK_ADDRESS=0x23A1aFD896c8c8876AF46aDc38521f4432658d1e

SEPOLIA_REGISTRY_MODULE_OWNER_CUSTOM=0x62e731218d0D47305aba2BE3751E7EE9E5520790
SEPOLIA_TOKEN_ADMIN_REGISTRY=0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82
SEPOLIA_ROUTER=0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
SEPOLIA_RNM_PROXY_ADDRESS=0xba3f6251de62dED61Ff98590cB2fDf6871FbB991
SEPOLIA_CHAIN_SELECTOR=16015286601757825753
SEPOLIA_LINK_ADDRESS=0x779877A7B0D9E8603169DdbD7836e478b4624789

# Deployed Contract Addresses
ZKSYNC_REBASE_TOKEN_ADDRESS=0xEb4c070c403dBAB3aAB51C161Fd1902c8c291C03
ZKSYNC_POOL_ADDRESS=0x1fE61b99F06F7719672316DB7d7978e06Fcdd491
SEPOLIA_REBASE_TOKEN_ADDRESS=0x58b376C7A25bDF3d07b8049f5A68a63e8B7f6a51
SEPOLIA_POOL_ADDRESS=0xE20f2BDF313071E8CC17DF67F4068909BEcbb789
VAULT_ADDRESS=0x6D9a241359581a43dF82f6dF1BF296d53Eb75955

.PHONY: clean zk-build

clean:
	forge clean

zk-build:
	foundryup-zksync
	forge build --zksync

deploy-token-on-zk:
	forge create src/RebaseToken.sol:RebaseToken --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account default_test_wallet --legacy --zksync --broadcast

deploy-pool-on-zk:
	forge create src/RebaseTokenPool.sol:RebaseTokenPool --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account default_test_wallet --legacy --zksync --broadcast --constructor-args ${ZKSYNC_REBASE_TOKEN_ADDRESS} [] ${ZKSYNC_RNM_PROXY_ADDRESS} ${ZKSYNC_ROUTER}

set-ccip-permission-for-pool-on-zk:
	cast send ${ZKSYNC_REBASE_TOKEN_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account default_test_wallet "grantMintAndBurnRole(address)" ${ZKSYNC_POOL_ADDRESS}

set-ccip-role-and-permission-zk:
	cast send ${ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM} "registerAdminViaOwner(address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account default_test_wallet
	cast send ${ZKSYNC_TOKEN_ADMIN_REGISTRY} "acceptAdminRole(address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account default_test_wallet
	cast send ${ZKSYNC_TOKEN_ADMIN_REGISTRY} "setPool(address,address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} ${ZKSYNC_POOL_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account default_test_wallet

deploy-token-and-pool-on-sepolia:
	forge script ./script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url ${SEPOLIA_RPC_URL} --account default_test_wallet --broadcast

deploy-vault:
	forge script ./script/Deployer.s.sol:VaultDeployer --rpc-url ${SEPOLIA_RPC_URL} --account default_test_wallet --broadcast --sig "run(address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS}

configure-sepolia-pool:
	forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript --rpc-url ${SEPOLIA_RPC_URL} --account default_test_wallet --broadcast --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" ${SEPOLIA_POOL_ADDRESS} ${ZKSYNC_SEPOLIA_CHAIN_SELECTOR} ${ZKSYNC_POOL_ADDRESS} ${ZKSYNC_REBASE_TOKEN_ADDRESS} false 0 0 false 0 0

deposit-fund-on-sepolia-vault:
	cast send ${VAULT_ADDRESS} --value ${AMOUNT} --rpc-url ${SEPOLIA_RPC_URL} --account default_test_wallet "deposit()"

configure-zk-pool:
	@POOL_BYTES=$$(cast abi-encode "f(address)" ${SEPOLIA_POOL_ADDRESS}); \
	TOKEN_BYTES=$$(cast abi-encode "f(address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS}); \
	cast send ${ZKSYNC_POOL_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account default_test_wallet \
	"applyChainUpdates(uint64[],(uint64,bytes[],bytes,(bool,uint128,uint128),(bool,uint128,uint128))[])" \
	"[${SEPOLIA_CHAIN_SELECTOR}]" \
	"[(${SEPOLIA_CHAIN_SELECTOR},[$$POOL_BYTES],$$TOKEN_BYTES,(false,0,0),(false,0,0))]"

bridge-fund-from-sepolia-to-zk:
	@echo "Bridging the funds using the script to ZKsync..."
	@WALLET_ADDRESS=$$(cast wallet address --account default_test_wallet); \
	SEPOLIA_BALANCE_BEFORE=$$(cast balance $$WALLET_ADDRESS --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL}); \
	echo "Sepolia balance before bridging: $$SEPOLIA_BALANCE_BEFORE"; \
	forge script ./script/BridgeTokens.s.sol:BridgeTokensScript --rpc-url ${SEPOLIA_RPC_URL} --account default_test_wallet --broadcast --sig "run(address,uint64,address,uint256,address,address)" $$WALLET_ADDRESS ${ZKSYNC_SEPOLIA_CHAIN_SELECTOR} ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${AMOUNT} ${SEPOLIA_LINK_ADDRESS} ${SEPOLIA_ROUTER}; \
	echo "Funds bridged to ZKsync"; \
	SEPOLIA_BALANCE_AFTER=$$(cast balance $$WALLET_ADDRESS --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL}); \
	echo "Sepolia balance after bridging: $$SEPOLIA_BALANCE_AFTER"
