// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title InvariantToken
 * @author Victor
 *
 * This is the contract meant to be governed by INVEngine. This contract is just the ERC20 implementation of our token.
 *
 */
contract WrapToken is ERC20Burnable, Ownable {
    error InvariantToken_MustBeMoreThanZero();
    error InvariantToken_BurnAmountExceedsBalance();
    error InvariantToken_NotZeroAddress();

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert InvariantToken_MustBeMoreThanZero();
        }
        if (_amount < balance) {
            revert InvariantToken_BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert InvariantToken_NotZeroAddress();
        }
        if (_amount <= 0) {
            revert InvariantToken_MustBeMoreThanZero();
        }

        _mint(_to, _amount);

        return true;
    }
}
