// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract Faucet {
    error Faucet__TransferFailed();
    error Faucet__Wait30Min();
    error Faucet__MaximumAmounteExceeded();

    mapping(address => mapping(address => uint256)) private lastSendAt;

    event DepositToken(address indexed user, address indexed token, uint256 indexed amount);
    event SendToken(address indexed user, address indexed token, uint256 indexed amount);

    constructor() {}

    receive() external payable {}

    fallback() external payable {}

    function depositToken(address token, uint256 amount) external {
        bool success = ERC20(token).transferFrom(msg.sender, address(this), amount);

        if (!success) {
            revert Faucet__TransferFailed();
        }

        emit DepositToken(msg.sender, token, amount);
    }

    function sendToken(address token, address beneficiary, uint256 amount) external {
        if (lastSendAt[beneficiary][token] + 30 minutes > block.timestamp) {
            revert Faucet__Wait30Min();
        }

        if (amount > 1 ether) {
            revert Faucet__MaximumAmounteExceeded();
        }

        lastSendAt[beneficiary][token] = block.timestamp;

        bool success = ERC20(token).transfer(beneficiary, amount);

        if (!success) {
            revert Faucet__TransferFailed();
        }

        emit SendToken(msg.sender, token, amount);
    }
}
