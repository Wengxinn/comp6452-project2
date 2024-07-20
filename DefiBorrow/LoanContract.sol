/// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Contract to manage individual loans,collaterals and borrowing activities

contract LoanContract {
    address public borrower;                // Address of borrower
    uint public loanAmount;                 // Amount of loan request   
    bool public isEth;                      // Crypto unit of loan amount (true if ETH, false if otherwise)
    uint public collateralAmount;           // Amount of expected collateral  
    uint public collateralPaid;             // Amount of paid collateral       
    IERC20 public wBtc;                     // Wrapped BTC token
    bool public requestAccepted;            // Loan request status

    // Events
    event LoanCreated(address indexed borrower, uint loanAmount, bool isEth, bool requestAccepted);
    event CollateralDeposited(address indexed borrower, uint collateralAmount);

    constructor(address _borrower, uint _loanAmount, bool _isEth, uint _collateralAmount, IERC20 _wBtc, bool _requestAccepted) {
        borrower = _borrower;
        loanAmount = _loanAmount;
        isEth = _isEth;
        collateralAmount = _collateralAmount;
        wBtc = _wBtc;
        requestAccepted = _requestAccepted;

        emit LoanCreated(borrower, loanAmount, isEth, requestAccepted);
    }


    function depositEthCollateral() public payable borrowerRestricted requestPending ethOnly {
        // Paid collateral must be greater than the expected collateral amount
        // msg.value is the amount of eth sent by the borrower along with the transaction
        require (msg.value >= collateralAmount, "Incorrect ETH colleteral amount");
        collateralPaid = msg.value;

        emit CollateralDeposited(borrower, collateralPaid);
    }


    function depositBtcCollateral(uint wBtcCollateral) public borrowerRestricted requestPending btcOnly {
        // WBTC collateral must be greater than the expected collateral amount
        require(wBtcCollateral >= collateralAmount, "Incorrect BTC collateral amount");
        // Deposit WBTC as collateral
        require(wBtc.transferFrom(borrower, address(this), wBtcCollateral), "WBTC transfer failed");
        collateralPaid = wBtcCollateral;

        emit CollateralDeposited(borrower, collateralPaid);
    }



    function setRequestAccepted(bool status) external {
        requestAccepted = status;
    }

    modifier borrowerRestricted() {
        require(msg.sender == borrower, "Restricted to borrower only");
        _;
    }

    modifier ethOnly() {
        require(isEth == true, "Only supports ETH transaction");
        _;
    }

    modifier btcOnly() {
        require(isEth == false, "Only supports BTC transaction");
        _;
    }

    modifier requestPending() {
        require(requestAccepted == false, "Can deposit collateral only when loan request is pending");
        _;
    }
}