// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

contract InvFeeManager is ReentrancyGuard, AccessControl {
    using SafeTransferLib for ERC20;

    /*///////////////////////////////////////////////////////////////
                         ERRORS & WARNINGS
    //////////////////////////////////////////////////////////////*/
    error Treasury__CannotDepositZero();
    error Treasury__CannotWithdrawZero();
    error Treasury__InsufficientFunds();

    /*///////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address token => uint256 fees) private s_fees;
    mapping(address token => uint256 fees) private s_TotalFeesAccumulated;

    bytes32 private constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 private constant NOTIFIER_ROLE = keccak256("NOTIFIER_ROLE");

    /*///////////////////////////////////////////////////////////////
                         CONSTRUCTOR & FALLBACK
    //////////////////////////////////////////////////////////////*/

    constructor(address owner, address notifier) {
        _grantRole(OWNER_ROLE, owner);
        _grantRole(NOTIFIER_ROLE, notifier);
    }

    /*///////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(address token, uint256 amount) external nonReentrant onlyRole(NOTIFIER_ROLE) {
        if (amount == 0) revert Treasury__CannotDepositZero();

        s_fees[token] += amount;
        s_TotalFeesAccumulated[token] += amount;

        // receive tokens
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address token, address receiver, uint256 amount) external nonReentrant onlyRole(OWNER_ROLE) {
        if (amount == 0) revert Treasury__CannotWithdrawZero();
        if (s_fees[token] < amount) revert Treasury__InsufficientFunds();

        s_fees[token] -= amount;

        // send tokens
        ERC20(token).safeTransfer(receiver, amount);
    }

    /*///////////////////////////////////////////////////////////////
                         VIEWS & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getFees(address token) external view returns (uint256) {
        return s_fees[token];
    }

    function getTotalFeesAccumulated(address token) external view returns (uint256) {
        return s_TotalFeesAccumulated[token];
    }

    function getOwnerRole() external pure returns (bytes32) {
        return OWNER_ROLE;
    }

    function getNotifierRole() external pure returns (bytes32) {
        return NOTIFIER_ROLE;
    }
}
