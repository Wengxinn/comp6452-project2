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

    // ===========================================================================================================================================================

    event CollateralDeposited(address indexed borrower, uint amount, bool isETH);

    // ===========================================================================================================================================================

    constructor(address _borrower, IERC20 _wBtc, uint _borrowAmount, bool _wantBTC, uint _collateralAmount, uint _btcInEthPrice, uint _dailyInterestRate, bool _activated) {
        borrower = _borrower;
        creator = msg.sender;
        wBtc = _wBtc;
        borrowAmount = _borrowAmount;
        wantBTC = _wantBTC;
        collateralAmount = _collateralAmount;
        btcInEthPrice = _btcInEthPrice;
        dailyInterestRate = _dailyInterestRate;
        activated = _activated;
    }


    /**
    * @dev Desposit collateral (specified in the msg.value) in ETH to the receiver
    *
    * @param receiver Payable address of the receiver of the collateral
    *
    **/
    function depositCollateralETH(address receiver) public payable {
        require((msg.value / 1 ether) == collateralAmount, "Incorrect ETH collateral amount");

        // Transfer the collateral to the contract
        (bool success, ) = payable(receiver).call{value: msg.value}("");
        require(success, "Transfer failed");

        emit CollateralDeposited(borrower, msg.value, wantBTC);
        activated = true;
    }


    /**
    * @dev Desposit collateral in BTC from the borrower's account to the receiver's account
    *
    * @param receiver Address of the receiver of the collateral
    * @param _wBtcCollateral Amount of collateral to be deposited
    *
    **/
    function depositCollateralBTC(address receiver, uint _wBtcCollateral) public {
        require(_wBtcCollateral == collateralAmount, "Incorrect BTC collateral amount");

        // Transfer the collateral from borrower's account to receiver's account
        require(wBtc.transferFrom(borrower, receiver, collateralAmount), "WBTC transfer failed");
        emit CollateralDeposited(borrower, _wBtcCollateral, wantBTC);
        activated = true;
    }


       /**
    * @dev Calculate compound interest following formula: (1 + daily rate) ** day, 
    *      taking into account the loan duration in days, and daily interest rate
    *
    * @param _days Loan duration in days
    * @param dailyRate Daily interest rate
    *
    * @return Compund interest stored in 7 decimals
    **/
    function _calculateInterest(uint _days, uint dailyRate) private pure returns (uint) {
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
    * @return Total repayment amount required for the loan request stored in 7 decimals
    **/
    function _calculateTotalRepaymentAmount(uint loanAmount, uint _days) private view returns (uint) {
        // Get compound interest stored in 7 decimals
        uint compoundInterest7Decimals = _calculateInterest(_days, dailyInterestRate);
        return loanAmount * compoundInterest7Decimals;
    }
}
