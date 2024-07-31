// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// // Interface for ERC20 token
// interface IERC20 {
//     // transfer token from the account called this function to recipient account
//     function transfer(address recipient, uint256 amount) external returns (bool);
//     // transfer token between accounts
//     function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
//     // check the balance of an given account
//     function balanceOf(address account) external view returns (uint256);
// }

contract LandContract {
    // Define the structure of a deposit
    struct Deposit {
        address depositAccount;
        uint256 amount;
        uint256 depositTime;
        bool withdrawn;
    }

    // address public fundPool;
    uint256 public interestRate = 1;    // 1% interest rate
    uint256 public duration = 365 days; // Duration of 1 year
    
    mapping(address => Deposit) public deposits;

    // Constructor to set the token address and the fund pool address
    constructor() {
        // fundPool = msg.sender;
    }

    function interestCalculator(uint256 _amount) public view returns (uint256 _interest){
        uint256 interest = (_amount * interestRate) / 100;
        return interest;
    }

    function deposit(address _userAddress, address _Owner, uint256 _amount, address wBtcAddress) public {
        require(_amount > 0, "Deposit amount must more than zero");

        address userAddress = _userAddress;

        // Check if the user has enough balance
        uint256 userBalance = IERC20(userAddress).balanceOf(msg.sender);
        require(userBalance >= _amount, "Insufficient balance");

        // Check if the user has approved the transfer
        uint256 allowance = IERC20(wBtcAddress).allowance(_userAddress, address(this));
        require(allowance >= _amount, "Allowance is not enough");

        // Transfer tokens from the sender to the fund pool
        // IERC20(userAddress).transferFrom(msg.sender, fundPool, _amount);

        bool transferSuccess = IERC20(userAddress).transferFrom(_userAddress, _Owner, _amount);
        require(transferSuccess, "Token transfer failed");

        // Record deposit details on the block
        deposits[_userAddress] = Deposit({
            depositAccount: _userAddress,
            amount: _amount,
            depositTime: block.timestamp,
            withdrawn: false
        });
    }

    function withdrawn(address _userAddress, address _Owner, uint256 _amount) public {
        // Ensure the user has a deposit
        Deposit storage userDeposit = deposits[_userAddress];
        require(userDeposit.amount > 0, "No deposit found for this address");
        require(!userDeposit.withdrawn, "Deposit already withdrawn");
        require(userDeposit.amount >= _amount, "Withdraw amount exceeds deposit");

        // Mark the deposit as withdrawn
        userDeposit.withdrawn = true;

        // Transfer tokens back to the user
        bool transferSuccess = IERC20(_Owner).transfer(_userAddress, _amount);
        require(transferSuccess, "Token transfer failed");

        // Update deposit amount
        userDeposit.amount -= _amount;

        // If fully withdrawn, reset the deposit
        if (userDeposit.amount == 0) {
            userDeposit.depositTime = 0;
        }
    }
}