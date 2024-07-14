// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LoanContract.sol";

contract LoanPool {
    struct LoanRecord {
        address loanContractAddress;
        address borrower;
        uint loanAmount;
        bool isBTC;
        uint collateralAmount;
    }

    LoanRecord[] public loanRecords;

    event LoanRequested(address indexed borrower, uint loanAmount, bool isBTC);
    event LoanContractCreated(address indexed loanContractAddress, address indexed borrower, uint loanAmount, bool isBTC);

    function requestLoan(uint _loanAmount, bool _isBTC) public {
        require(_loanAmount > 0, "Loan amount must be positive");

        // Create new loan contract
        LoanContract newLoan = new LoanContract(msg.sender, _loanAmount, _isBTC);

        // Calculate collateral amount
        uint collateralAmount = _isBTC ? _loanAmount * 10 : _loanAmount / 10;

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

    function getLoanDetails(uint _index) public view returns (address, address, uint, bool, uint) {
        LoanRecord memory loan = loanRecords[_index];
        return (loan.loanContractAddress, loan.borrower, loan.loanAmount, loan.isBTC, loan.collateralAmount);
    }

    function getTotalLoans() public view returns (uint) {
        return loanRecords.length;
    }
}
