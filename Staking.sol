// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenStaking {
    IERC20 public immutable stakingToken;
    mapping(address => uint256) public stakedBalance;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        bool success = stakingToken.transferFrom(msg.sender, address(this), amount);
        require(success, "transferFrom failed");

        stakedBalance[msg.sender] += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient staked balance");

        stakedBalance[msg.sender] -= amount;

        bool success = stakingToken.transfer(msg.sender, amount);
        require(success, "transfer failed");

        emit Withdrawn(msg.sender, amount);
    }
}
