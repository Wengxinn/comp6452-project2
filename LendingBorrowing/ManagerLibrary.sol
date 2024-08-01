// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BorrowContract.sol";
import "./LendContract.sol";
import "./WBTC.sol";
import "./Oracle.sol";
import "./Oracle_.sol";


/// @title Library containing view and pure (static) functions and structs
///        which can be invoked by Manager.sol
    
library ManagerLibrary {
    // Struct to store user available balance for withdrawal (For a specific user, how much ETH and wBTC they have for withdrawal)
    struct UserAvailableBalance {
        uint ethAmount;
        uint wBtcAmount;
    }

    
    /**
    * @dev Calculate the collateral amount corresponding to the loan request,
    *      including 1.5 overcollateralisation ratio
    *
    * @param loanAmount Amount of loan request
    * @param wantBTC Unit of loan request (is in BTC)
    * @param btcInEthPrice Currnet BTC price in ETH
    * @param collateralisationRatio Expected collaterisation value to the loan amount in percentage
    *
    * @return Collateral amount of the loan request
    **/
    function calculateCollateralAmount(uint loanAmount, bool wantBTC, uint btcInEthPrice, uint collateralisationRatio) external pure returns (uint) {
        if (wantBTC) {
            return loanAmount * btcInEthPrice * collateralisationRatio / 100;
        } else {
            return loanAmount / btcInEthPrice * collateralisationRatio / 100;
        }
    } 


    /**
    * @dev Get the current daily interest rate corresponding to the currency and real-time feed data
    *
    * @param wantBTC Unit of loan request (is in BTC)
    * @param oracle Address of oracle
    *
    * @return Current aily interest rate
    **/
    function getDailyInterestRate(bool wantBTC, Oracle_ oracle) external view returns (uint) {
        // Compute daily rate according to the data fed from oracle
        // For eth, apr is compounded monthly, so need to be divided by 30
        uint dailyRate;
        if (wantBTC) {
            // Data stored in 8 decimals
            dailyRate = (_getBtc1DayBaseRate(oracle)) / 100;
            // Convert to 7 decimals for consistency with eth
            dailyRate = dailyRate / 10;
        } else {
            // Data stored in 7 decimals
            dailyRate = (_getEth30DayApr(oracle)) / (30 * 100);
        }
        return dailyRate;
    }

    /**
    * @dev Get the current BTC price in Eth
    *
    * @param oracle Address of oracle
    *
    * @return Current BTC/ETH price returned by oracle
    **/
    function getBtcInEtcPrice(Oracle_ oracle) external view returns (uint) {
        // The data returned from oracle is stored in 18 decimals
        return uint(oracle.getLatestBtcPriceInEth()) / 10**18; 
    }


    /**
    * @dev Check preconditions for ETH repayment deposit
    *
    * @param borrowContract Borrow Contract instance
    * @param amount Amount of deposits
    **/
    function checkDepositETHRepayment(BorrowContract borrowContract, uint amount) external view {
        // Get repayment amount
        uint totalRepaymentAmount = borrowContract.totalRepaymentAmount() * 1 ether;
        require(amount == totalRepaymentAmount, "Incorrect ETH amount");
        require(!borrowContract.wantBTC(), "This BorrowContract does not support WBTC repayment");
        require(borrowContract.repaymentPendingStatus(), "Repayment request pending");
    }


   /**
    * @dev Check preconditions for WBTC repayment deposit
    *
    * @param borrowContract Borrow Contract instance
    * @param amount Amount of deposits
    **/
    function checkDepositWBTCRepayment(BorrowContract borrowContract, uint amount) external view {
        // Get repayment amount
        uint totalRepaymentAmount = borrowContract.totalRepaymentAmount();
        require(amount == totalRepaymentAmount, "Incorrect WBTC amount");
        require(borrowContract.wantBTC(), "This BorrowContract does not support ETH repayment");
        require(borrowContract.repaymentPendingStatus(), "Repayment request pending");
    }


   /**
    * @dev Check preconditions for ETH collateral deposit
    *
    * @param borrowContract Borrow Contract instance
    * @param amount Amount of deposits
    **/
    function checkDepositETHCollateral(BorrowContract borrowContract, uint amount) external view {
        // Get contract's expected collateral amount
        uint collateralAmount = borrowContract.collateralAmount() * 1 ether;
        require(amount == collateralAmount, "Incorrect ETH amount");
        require(borrowContract.wantBTC(), "This BorrowContract does not support ETH collateral");
    }


   /**
    * @dev Check preconditions for WBTC collateral deposit
    *
    * @param borrowContract Borrow Contract instance
    * @param amount Amount of deposits
    **/
    function checkDepositWBTCCollateral(BorrowContract borrowContract, uint amount) external view {
        // Get contract's expected collateral amount
        uint collateralAmount = borrowContract.collateralAmount();
        require(amount == collateralAmount, "Incorrect WBTC amount");
        require(!borrowContract.wantBTC(), "This BorrowContract does not support ETH collateral");
    }


    /**
    * @dev Get the current 30-day ETH apr
    *
    * @return Current 30-day ETH apr stored in 7 decimals returned by oracle
    **/
    function _getEth30DayApr(Oracle_ oracle) private view returns (uint) {
        return uint(oracle.getLatestEth30DayApr());
    }


    /**
    * @dev Get the current 1-Day BTC interest rate benchmark curve 
    *
    * @return Current 1-Day BTC interest rate benchmark curve stored in 8 decimals returned by oracle
    **/
    function _getBtc1DayBaseRate(Oracle_ oracle) private view returns (uint) {
        return uint(oracle.getBtc1DayBaseRate());
    }
}