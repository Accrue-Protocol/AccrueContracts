// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IInvToken {
    // Structs
    struct Configuration {
        uint256 lendFactor;
        uint256 borrowFactor;
        uint256 liquidationThreshold;
        address interestRateModel;
    }

    // Funções específicas do InvariantToken
    function burn(uint256 _amount) external;
    function mint(address _to, uint256 _amount) external returns (bool);

    // Funções padrão ERC20
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    // Eventos ERC20
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
