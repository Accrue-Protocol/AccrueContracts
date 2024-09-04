# INVEngine: Decentralized Finance (DeFi) Engine - Lend & Borrow

Welcome to the INVEngine repository. This smart contract system is designed to facilitate various financial operations in a decentralized manner on the Ethereum blockchain. This smart contract is in the alpha stage.


## Setup:

1. Clone the repository.
2. Install dependencies.
3. Compile the contract using Foundry.
4. Deploy to a local or testnet environment for testing.

In the script folder, modify the `DeployTokens.s.sol` and `HelperConfig.s.sol` files, adding your privateKey and wallet address to the `DEFAULT_ANVIL_PRIVATE_KEY` and `deployerAddress` variables, respectively.

4.1. **Deploy InvEngine**
- Run in the terminal: `make deploy-sepolia`

4.2. **Deploy tokens**
- First, copy the address of the invEngine contract you deployed and add it to line 60 of the `DeployTokens.s.sol` file.
- To deploy other tokens and add them to the invEngine as specified in the `DeployTokens.s.sol` file, run in the terminal: `make deploy-tokens-sepolia`.

5. Setup .env file

## Features:

1. **Repay**: Enables users to repay borrowed assets.
2. **Withdraw**: Allows users to withdraw their collateral.
3. **Liquidate**: Provides the mechanism to liquidate under-collateralized positions.
4. **Supply**: Lets users supply assets and receive wrapped tokens as a representation of their deposit.
5. **Accumulated Interest**: Calculate and display the accumulated interest over time.
6. **Internal Interest Calculation**: Efficiently manages and computes individual and global interests.

and much more... 

## Functions Overview:

- `repay`: Repay a specified amount of the borrowed asset.
- `withdraw`: Withdraw a specified amount of the collateral asset.
- `liquidate`: Execute a liquidation on under-collateralized accounts.
- `supply`: Supply assets to the contract and receive equivalent wrapped tokens.
- `getAccumulatedInterest`: View the accumulated interest for a specified token.
- `accrueInterest`: Update interest rates based on the latest activity.
- `_calculateUserInterestDue`: Compute the interest due for a specific user.

## Contribution:

Feel free to fork this repository and submit pull requests. All contributions are welcome. Please make sure to test your changes thoroughly before submitting.

## License:

This project is licensed under the MIT License.

## Contact:

For more information or queries, please reach out to [0xVictorFi](https://x.com/0xVictorFi).
