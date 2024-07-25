// Added IERC20 public wBtc and a constructor to initialize it: This allows the contract to store the wBTC token contract address.
// Updated the LoanContract constructor call including the borrower address, loan amount, boolean for ETH (inverted from the isBTC value), collateral amount, the wBTC token contract address, and the initial requestAccepted status set to false.


/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LoanContract.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LoanPool {
    struct LoanRecord {
        address loanContractAddress;
        address borrower;
        uint256 loanAmount;
        bool isBTC;
        uint256 collateralAmount;
    }

    LoanRecord[] public loanRecords;
    IERC20 public wBtc;  // Add this line to store the wBTC contract address

    event LoanRequested(address indexed borrower, uint256 loanAmount, bool isBTC);
    event LoanContractCreated(address indexed loanContractAddress, address indexed borrower, uint256 loanAmount, bool isBTC);

    constructor(IERC20 _wBtc) {
        wBtc = _wBtc;  // Initialize the wBTC contract address
    }

    function requestLoan(uint256 _loanAmount, bool _isBTC) public {
        require(_loanAmount > 0, "Loan amount must be positive");

        // Set borrower to msg.sender (address of the person who calls this function)
        address payable _borrower = payable(msg.sender);

        // Calculate collateral amount
        uint256 collateralAmount = _isBTC ? _loanAmount * 10 : _loanAmount / 10;

        // Create new loan contract with the required parameters
        LoanContract newLoan = new LoanContract(
            _borrower,
            _loanAmount,
            !_isBTC,  // Pass false if BTC, true if ETH
            collateralAmount,
            wBtc,
            false  // Initial requestAccepted status is false
        );

        // Record the loan in the pool
        loanRecords.push(LoanRecord({
            loanContractAddress: address(newLoan),
            borrower: msg.sender,
            loanAmount: _loanAmount,
            isBTC: _isBTC,
            collateralAmount: collateralAmount
        }));

        emit LoanRequested(msg.sender, _loanAmount, _isBTC);
        emit LoanContractCreated(address(newLoan), msg.sender, _loanAmount, _isBTC);
    }

    function getLoanDetails(uint256 _index) public view returns (address, address, uint256, bool, uint256) {
        LoanRecord memory loan = loanRecords[_index];
        return (loan.loanContractAddress, loan.borrower, loan.loanAmount, loan.isBTC, loan.collateralAmount);
    }

    function getTotalLoans() public view returns (uint256) {
        return loanRecords.length;
    }
}
