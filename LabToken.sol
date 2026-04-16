// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LabToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Lab Token", "LAB") {
        _mint(msg.sender, initialSupply);
    }
}
