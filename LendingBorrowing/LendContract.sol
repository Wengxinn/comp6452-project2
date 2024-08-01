// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendContract {
    // Wrapped BTC token
    IERC20 public wBtc;

    // Contract creator
    address public creator;

    // Lender address
    address public lender;

    // Deposited amount
    uint public lendAmount;

    // Daily interest rate when the loan request is initiated
    uint public dailyInterestRate;

    // True if borrowing BTC, false if borrowing ETH
    bool public wantBTC;

    // True if contract has been activated, after collateral is deposited
    bool public activated;

    // Expected deposit duration in days
    uint public DEPOSITTERM;

    // Contract's active duration in days
    uint public durationInDays;

    // Loan's activation time
    uint public startTime;

    // Total withdrawal amount
    uint public totalWithdrawalAmount;

    //  Mature deadline
    uint public deadline;

    // Remaining days until maturity
    uint public remainingDays;

    // ===========================================================================================================================================================
    /** Events **/

    // Event to be emitted when user successfully deposited fund
    event FundDeposited(address indexed lender, uint amount, bool wantBTC);

    // Event to be emitted when the lend contract is activated
    event LendContractActivated(address lendContract, uint startTime, uint remainingDays);

    // Event to be emitted when the lend contract is deactivated (after deposit matures)
    event LendContractDeactivated(address lendContract);

    // ===========================================================================================================================================================


    // Constructor to set the token address and the fund pool address
    constructor(address _creator, address _lender, IERC20 _wBtc, uint _lendAmount, bool _wantBTC, uint _dailyInterestRate, bool _activated) {
        lender = _lender;
        creator = _creator;
        wBtc = _wBtc;
        lendAmount = _lendAmount;
        wantBTC = _wantBTC;
        dailyInterestRate = _dailyInterestRate;
        activated = _activated;

        startTime = 0;
        durationInDays = 0;
        DEPOSITTERM = 365 days;
        totalWithdrawalAmount = 0;
        remainingDays = 0;
    }


    /**
    * @dev Desposit ETH to the receiver
    *
    * @param receiver Payable address of the receiver
    **/
    function depositETH(address receiver) external payable contractNotActivated {
        require(msg.value / 1 ether == lendAmount, "Incorrect ETH amount");
        // Transfer eth to the receiver's address
        (bool success, ) = payable(receiver).call{value: msg.value}("");
        require(success, "Transfer failed");
        emit FundDeposited(lender, msg.value, wantBTC);
    }


    /**
    * @dev Desposit BTC to the receiver's account
    *
    * @param receiver Address of the receiver
    * @param amount Amount to be deposited
    **/
    function depositBTC(address receiver, uint amount) external contractNotActivated {
        require(amount == lendAmount, "Incorrect WBTC amount");
        // Transfer WBTC to the receiver's account
        require(wBtc.transferFrom(lender, receiver, amount), "WBTC transfer failed");
        emit FundDeposited(lender, amount, wantBTC);
    }


    /**
    * @dev Activate contract and start timer, 
    *      which can only be invoked by the manager contract
    **/
    function activateContract() external restricted contractNotActivated{
        activated = true;
        startTime = block.timestamp;
        deadline = _getDeadline();
        emit LendContractActivated(address(this), startTime, remainingDays);
    }


    /**
    * @dev Allow users to request for withdrawal only after the deposit is mature
    *
    * s@return Status of the request indicating if the user is allowed to withdraw
    **/
    function requestWithdrawal() external contractActivated returns (bool) {
        // Stop the timer and compute duration in days
        durationInDays = (block.timestamp - startTime) / 1 days;

        // Get the total withdrawal amount for the duration
        totalWithdrawalAmount = _calculateTotalWithdrawalAmount(lendAmount, durationInDays);
        if (durationInDays >= DEPOSITTERM) {
            activated = false;
            remainingDays = 0;
            emit LendContractDeactivated(address(this));
            return true;
        } else {
            remainingDays = getRemainingDays();
        }
        return false;
    }


    /**
    *@dev Get the number of remaining days until the deadline (mature date)
    *
    *@return Remaining days 
    **/
    function getRemainingDays() public view contractActivated returns (uint) {
        if (block.timestamp >= deadline) {
            return 0;
        } else {
            return (deadline - startTime) / 1 days;
        }
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
    * @dev Calculate total withdrawal amount corresponding to the withdrawal request
    * taking into account the compound interest for specific duration in days
    *
    * @param _lendAmount Amount of deposit
    * @param _days Duration in days
    *
    * @return Total withdrawal amount required for the withdrawal request
    **/
    function _calculateTotalWithdrawalAmount(uint _lendAmount, uint _days) private view contractActivated returns (uint) {
        // Get compound interest stored in 7 decimals
        uint compoundInterest7Decimals = _calculateInterest(_days, dailyInterestRate);
        return (_lendAmount * compoundInterest7Decimals) / 10**7 + _lendAmount;
    }


    /**
    * @dev Get deadline after contract is activated
    *
    * @return Mature deadline
    **/
    function _getDeadline() private view returns (uint) {
        return startTime + DEPOSITTERM;
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