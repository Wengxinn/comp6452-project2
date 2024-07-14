// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LoanContract {

    
    // For now, fixed exchange rate: 1 BTC = 10 ETH
    uint constant exchangeRate = 10; 
    

    address public borrower;
    uint public loanAmount;
    uint public collateralAmount;

    // true if borrowing BTC, false if borrowing ETH
    bool public isBTC; 

    event LoanCreated(address indexed borrower, uint loanAmount, bool isBTC, uint collateralAmount);
    event CollateralDeposited(address indexed borrower, uint amount, bool isETH);

    constructor(address _borrower, uint _loanAmount, bool _isBTC) {
        borrower = _borrower;
        loanAmount = _loanAmount;
        isBTC = _isBTC;
        collateralAmount = isBTC ? loanAmount * exchangeRate : loanAmount / exchangeRate;

        emit LoanCreated(borrower, loanAmount, isBTC, collateralAmount);
    }

    function depositCollateral() public payable {
        require(msg.sender == borrower, "Only borrower can deposit collateral");
        if (isBTC) {
            require(msg.value == collateralAmount, "Incorrect ETH collateral amount");
        } else {
            require(msg.value == collateralAmount, "Incorrect BTC collateral amount");
        }

        emit CollateralDeposited(borrower, msg.value, isBTC);
    }
}
