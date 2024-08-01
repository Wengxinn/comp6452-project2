// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Individual borrow contract

contract BorrowContract {
    // Wrapped BTC token
    IERC20 public wBtc;

    // Contract creator
    address public creator;

    // Borrower address
    address public borrower;

    // Loan amount
    uint public borrowAmount;

    // Required collteral amount
    uint256 public collateralAmount;

    // BTC price in ETH when the loan request is initiated
    uint public btcInEthPrice;

    // Daily interest rate when the loan request is initiated
    uint public dailyInterestRate;

    // True if borrowing BTC, false if borrowing ETH
    bool public wantBTC;

    // True if contract has been activated, after collateral is deposited
    bool public activated;

    // Loan term (Expected loan duration)
    uint public loanTerm;

    // Loan's activation time
    uint public startTime;

    // Contract's active duration in days
    uint public loanDurationInDays;

    // Total repayment amount
    uint public totalRepaymentAmount;

    // Repayment pending status, True if repayment request is accepted
    bool public repaymentPendingStatus;

    // Loan's deadline
    uint public loanDeadline;

    // Remaining days until deadline
    uint public remainingDays;

    // ===========================================================================================================================================================
    /** Events **/

    // Event to be emitted when user successfully deposited required collateral
    event CollateralDeposited(address indexed borrower, uint amount, bool wantBTC);

    // Event to be emitted when the borrow contract is activated (after user deposited collateral)
    event BorrowContractActivated(address borrowContract, uint startTime, uint remainingDays);

    // Event to be emitted when the borrow contract is deactivated (after user repayed loan)
    event BorrowContractDeactivated(address borrowContract);

    // Event to be emitted when user cleared their repayment
    event LoanRepayed(address indexed borrower, uint amount, bool wantBTC);

    // ===========================================================================================================================================================

    constructor(address _creator, address _borrower, IERC20 _wBtc, uint _borrowAmount, bool _wantBTC, uint _collateralAmount, uint _btcInEthPrice, uint _dailyInterestRate, bool _activated, uint _loanTerm) {
        borrower = _borrower;
        creator = _creator;
        wBtc = _wBtc;
        borrowAmount = _borrowAmount;
        wantBTC = _wantBTC;
        collateralAmount = _collateralAmount;
        btcInEthPrice = _btcInEthPrice;
        dailyInterestRate = _dailyInterestRate;
        activated = _activated;
        loanTerm = _loanTerm;

        startTime = 0;
        loanDurationInDays = 0;
        totalRepaymentAmount = 0;
        repaymentPendingStatus = false;
        loanDeadline = 0;
        remainingDays = 0;
    }


    /**
    * @dev Desposit collateral (specified in the msg.value) in ETH to the receiver
    *
    * @param receiver Payable address of the receiver of the collateral
    **/
    function depositCollateralETH(address receiver) external payable contractNotActivated {
        require((msg.value / 1 ether) == collateralAmount, "Incorrect ETH collateral amount");

        // Transfer the collateral to the receiver's address
        (bool success, ) = payable(receiver).call{value: msg.value}("");
        require(success, "Transfer failed");

        emit CollateralDeposited(borrower, msg.value, !wantBTC);
    }


    /**
    * @dev Desposit collateral in BTC from the borrower's account to the receiver's account
    *
    * @param receiver Address of the receiver of the collateral
    * @param _wBtcCollateral Amount of collateral to be deposited
    **/
    function depositCollateralBTC(address receiver, uint _wBtcCollateral) external contractNotActivated {
        require(_wBtcCollateral == collateralAmount, "Incorrect WBTC collateral amount");

        // Transfer the collateral from borrower's account to the receiver's account
        require(wBtc.transferFrom(borrower, receiver, collateralAmount), "WBTC transfer failed");
        emit CollateralDeposited(borrower, _wBtcCollateral, !wantBTC);
    }

    /**
    * @dev Allow contract itself to receive ETH
    **/
    // receive() external payable {}
    // fallback() external payable {}


    /**
    * @dev Activate contract and start timer, 
    *      which can only be invoked by the manager contract
    **/
    function activateContract() external restricted contractNotActivated{
        activated = true;
        startTime = block.timestamp;
        loanDeadline = _getLoanDeadline();
        emit BorrowContractActivated(address(this), startTime, getRemainingDays());
    }


    /**
    * @dev Deactivate contract
    *      which can only be invoked by the manager contract
    **/
    function deactivateContract() external contractActivated {
        activated = false;
        emit BorrowContractDeactivated(address(this));
    }


    /**
    * @dev Allow users to request for repayment when they are ready
    *
    * @param balance User current account balance
    *
    *@return Current repayment pending status (if the user has the ability to pay)
    **/
    function requestRepayment(uint balance) external contractActivated returns (bool) {
        // Stop the timer and compute loan duration in days
        loanDurationInDays = (block.timestamp - startTime) / 1 days;

        // Get the total repayment for the loan duration and check if the balance is sufficient
        totalRepaymentAmount = _calculateTotalRepaymentAmount(borrowAmount, loanDurationInDays);
        if (balance >= totalRepaymentAmount) {
            repaymentPendingStatus = true;
        }
        return repaymentPendingStatus;
    }


    /**
    * @dev Transfer repayment amount in BTC from the borrower's account to the receiver's account
    *
    * @param receiver Address of the receiver of the repayment
    **/
    function repayLoanETH(address receiver) external contractActivated payable {
        require((msg.value / 1 ether) == totalRepaymentAmount, "Incorrect ETH repayment amount");

        // Transfer repayment ETH amount to the receiver's contract
        (bool success, ) = payable(receiver).call{value: msg.value}("");
        require(success, "Transfer failed");

        emit LoanRepayed(borrower, msg.value, wantBTC);
    }


    /**
    * @dev Transfer repayment amount in BTC from the borrower's account to the receiver's account
    *
    * @param receiver Address of the receiver of the collateral
    * @param _wBtcRepayment Amount of repayment to be transferred
    **/
    function repayLoanBTC(address receiver, uint _wBtcRepayment) external contractActivated {
        require(_wBtcRepayment == totalRepaymentAmount, "Incorrect WBTC repayment amount");

        // Transfer the WBTC repayment amount from borrower's account to the receiver's account
        require(wBtc.transferFrom(borrower, receiver, _wBtcRepayment), "WBTC transfer failed");
        emit LoanRepayed(borrower, _wBtcRepayment, wantBTC);
    }


    /**
    * @dev Get remaining number of days until the loan's deadline
    *
    * return Remaining days
    **/
    function getRemainingDays() public view contractActivated returns (uint) {
        if (block.timestamp >= loanDeadline) {
            return 0;
        } else {
            return (loanDeadline - startTime) / 1 days;
        }
    }


    // ===========================================================================================================================================================

    /**
    * @dev Calculate compound interest following formula: (1 + daily rate) ** day, 
    *      taking into account the loan duration in days, and daily interest rate
    *
    * @param _days Loan duration in days
    * @param dailyRate Daily interest rate
    *
    * @return Compund interest stored in 7 decimals
    **/
    function _calculateInterest(uint _days, uint dailyRate) private view contractActivated returns (uint) {
        // Compute compound interest according to the duration of loan (days)
        // Base
        uint compoundFactor = 10**7 + dailyRate;
        // Exponentiation by squaring
        // Start with 1 (1e7 in 7 decimals)
        uint256 compoundInterest = 10**7; 
        uint compoundExponent = _days;
        while (compoundExponent > 0) {
            // Odd exp: compoundInterest * compoundFactor (result * base)
            if (compoundExponent % 2 == 1) {
                compoundInterest = (compoundInterest * compoundFactor) / 10**7;
            }
            // Square base
            compoundFactor = (compoundFactor * compoundFactor) / 10**7;
            // Half the exponent (integer division)
            compoundExponent /= 2;
        }
        return compoundInterest;
    }


    /**
    * @dev Calculate total repayment amount corresponding to the loan request
    * taking into account the compound interest for specific duration in days
    *
    * @param loanAmount Amount of loan request
    * @param _days Loan duration in days
    *
    * @return Total repayment amount required for the loan request
    **/
    function _calculateTotalRepaymentAmount(uint loanAmount, uint _days) private view contractActivated returns (uint) {
        // Get compound interest stored in 7 decimals
        uint compoundInterest7Decimals = _calculateInterest(_days, dailyInterestRate);
        return (loanAmount * compoundInterest7Decimals) / 10**7 + loanAmount;
    }


    /**
    * @dev Get loan deadline after contract is activated
    *
    * @return Loan deadline
    **/
    function _getLoanDeadline() private view returns (uint) {
        return startTime + (loanTerm * 1 days);
    }


    /** 
     * @notice Only when the contract is activated
     */
    modifier contractActivated() {
        require(activated, "Can only be executed when the contract is activated");
        _;
    }


    /** 
     * @notice Only when the contract is not yet activated
     */
    modifier contractNotActivated() {
        require(!activated, "Can only be executed when the contract is not activated");
        _;
    }


    /** 
     * @notice Only the creator can do
     */
    modifier restricted() {
        require(msg.sender == creator, "Can only be executed by the contract creator");
        _;
    }
}