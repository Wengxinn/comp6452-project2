/// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./LoanContract.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Contract to manage loan requests and deploy loan contracts

contract LoanManager {
    uint constant EXCHANGERATE = 10;                        // Fixed ETH-BTC exchange rate (1 BTC = 10 ETH)

    struct UserCollateral {
        uint ethAmount;
        uint wBtcAmount;
    }

    address public manager;                                     // Address of loan manager
    IERC20 public wBtc;                                         // Wrapped BTC token
    uint public totalLoans;                                     // Total number of loans in the pool
    mapping (address => LoanContract) public loans;             // List of addresses of loans (address, LoanContract)
    mapping (address => bool) private _loanExists;              // List to track if loan exists (loan address, bool)
    mapping (address => UserCollateral) public collaterals;     // List of user collaterals (user address, UserCollateral)
    mapping (address => bool) private _collateralExists;        // List to track if user collateral exists (user address, bool)

    // Events
    event LoanRequested(address indexed borrower, uint loanAmount, bool isEth, uint collateralAmount);
    event LoanCreated(address indexed loanAddress, address indexed borrower, uint loanAmount, bool isEth, bool requestAccepted);
    event UserCollateralUpdated(address indexed user, uint amount, bool isEthCollateral);
    event LoanRequestAccepted(address indexed loanAddress);
    event LoanTransfered(address indexed borrower, uint loanAmount, bool isEth);



    constructor(IERC20 _wBtc) {
        // Set contract creator as the manager
        manager = msg.sender;

        // Set initial number of loans
        totalLoans = 0;

        // Address of WBTC on ethereum
        wBtc = _wBtc;
    }


    function requestLoan(uint loanAmount, bool isEth) public {
        // Check if the requested loan amount is valid
        require(loanAmount > 0, "Loan amount requested must be greater than 0");

        // Calculate collateral amount required
        uint collateralAmount = _calculateCollateralAmount(loanAmount, isEth);

        // Check borrower's held collateral (if any)
        // If borrower has sufficient collateral, accept the request straightaway
        bool requestAccepted;
        bool sufficientCollateral = _checkCollateral(msg.sender, collateralAmount, isEth);
        if (sufficientCollateral) {
            requestAccepted = true;
        } else {
            requestAccepted = false;
        }

        // Create new loan instance
        LoanContract newLoan = new LoanContract(msg.sender, loanAmount, isEth, collateralAmount, wBtc, requestAccepted);

        // Add loan address to the pool
        loans[address(newLoan)] = newLoan;
        _loanExists[address(newLoan)] = true;
        totalLoans++;

        emit LoanRequested(msg.sender, loanAmount, isEth, collateralAmount);
        emit LoanCreated(address(newLoan), msg.sender, loanAmount, isEth, requestAccepted);
    }

    function getLoanDetails(address loanAddress) public view returns (
        address borrower, 
        uint loanAmount, 
        bool isEth, 
        uint collateralAmount, 
        uint collateralPaid,
        bool requestAccepted
    ) {
        // Check if the loan address exists
        require(_loanExists[loanAddress], "Loan does not exist");

        // Get loan details
        LoanContract loan = LoanContract(loanAddress);
        borrower = loan.borrower();
        loanAmount = loan.loanAmount();
        isEth = loan.isEth();
        collateralAmount = loan.collateralAmount();
        collateralPaid = loan.collateralPaid();
        requestAccepted = loan.requestAccepted();
        return (borrower, loanAmount, isEth, collateralAmount, collateralPaid, requestAccepted);
    }

    function acceptLoanRequest(address loanAddress) public restricted {
        // Check if the loan address exists
        require(_loanExists[loanAddress], "Loan does not exist");

        // Get loan
        LoanContract loan = loans[loanAddress];
        bool isEthCollateral = !loan.isEth();

        // Update borrower's collateral record
        _updateUserCollateral(loan.borrower(), loan.collateralPaid(), isEthCollateral);
        
        // Set loan request accepted status to true
        loan.setRequestAccepted(true);

        emit LoanRequestAccepted(loanAddress);
    }

    function transferLoan(address loanAddress) public restricted {
        // Check if the loan address exists
        require(_loanExists[loanAddress], "Loan does not exist");

        // Get loan 
        LoanContract loan = loans[loanAddress];
        address borrower = loan.borrower();
        uint loanAmount = loan.loanAmount();
        bool isEth = loan.isEth();

        // Check if the loan has been accepted
        require(loan.requestAccepted(), "Loan request is pending");

        // Transfer the loan amount to borrower
        if (isEth) {
            payable(borrower).transfer(loanAmount);
        } else {
            require(wBtc.transfer(borrower, loanAmount), "WBTC transfer failed");
        }

        emit LoanTransfered(borrower, loanAmount, isEth);
    }

    function _updateUserCollateral(address user, uint amount, bool isEthCollateral) private restricted {
        UserCollateral memory c;

        // If user collateral record exists, update the record
        // Otherwise, create a new user record in the pool
        if (_collateralExists[user]) {
            c = collaterals[user];
        } else {
            _collateralExists[user] = true;
            c.ethAmount = 0;
            c.wBtcAmount = 0;
        }

        // Update user total collateral amount in the corresponding unit
        if (isEthCollateral) {
            c.ethAmount += amount;
        } else {
            c.wBtcAmount += amount;
        }

        // Update the user collateral record to the collateral pool
        collaterals[user] = c;

        emit UserCollateralUpdated(user, amount, isEthCollateral);
    }

    function _calculateCollateralAmount(uint loanAmount, bool isEth) private pure returns (uint collateralAmount) {
        // Pay equal value of BTC as collateral if borrow ETH and vice versa
        if (isEth) {
            collateralAmount = loanAmount / EXCHANGERATE;
        } else {
            collateralAmount = loanAmount * EXCHANGERATE;
        }
        return collateralAmount;
    }

    function _checkCollateral(address user, uint collateralAmount, bool isEth) private view returns (bool) {
        // If user collateral record doesn't exist, return false
        // If exist, check if the corresponding collateral amount is sufficient for the loan
        if (!_collateralExists[user]) {
            return false;
        } else {
            UserCollateral memory c = collaterals[user];
            if (isEth) {
                return (c.wBtcAmount >= collateralAmount);
            } else {
                return (c.ethAmount >= collateralAmount);
            }
        }
    }

    modifier restricted() {
        require(msg.sender == manager, "Restricted to manager only");
        _;
    }
}