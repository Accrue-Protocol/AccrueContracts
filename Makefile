-include .env

build: forge build

deploy-sepolia:
	forge script script/DeployInv.s.sol:DeployInv --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv

deploy-faucet-sepolia:
	forge script script/DeployFaucet.s.sol:DeployFaucet --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv

deploy-tokens-sepolia:
	forge script script/DeployTokens.s.sol:DeployTokens --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv