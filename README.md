# COMP6452 Project 2 DEFI Lending Platform

## About
This DEFI lending and borrowing platform leverages the power of blockchain technology to create a decentralised, secure and transparent lending and borrowing environment. Built on the Ethereum network, the platform supports two cryptocurrencies, specifically Ethereum (ETH) and wrapped Bitcoin (wBTC). Users can borrow wBTC by supplying ETH as collateral (vice versa). On the other hand, users can deposit their assets to the lending pool to gain interests. The platform makes use of smart contract's trustless and transparent nature, as well as integrating oracles to obtain real-time data for accurate lending terms. 

## Features
1. The platform supports 2 cryptocurrencies: ETH and wBTC.
2. Lenders can deposit their assets into the pool and earn interest over time, contributing to the liquidity pool available for borrowers.
3. Borrowers can borrow their desired cryptocurrency while staking their held assets as collateral.
4. The collateral is significantly influenced by the fixed Collateralisation ratio, which means that users will need to supply higher amount of collateral (compared to the amount they are going to borrow). This is to ensure that the lending pool has the ability to cover debt for liquidation.
5. The platform pulls real-time data from oracle for accurate exchange and daily interest rate calculation. The data fed to the platform includes: 
   * current Bitcoin price in Ethereum (How much 1 Bitcoin worths in ETH) 
   * 30-day ETH APR (Annual percentage rate)
   * 1-Day Bitcoin interest rate benchmark curve
6. Borrowers are required to pay their debt, including the principal amount and compound interest over the loan period before the deadline.
7. After the repayment is verified, borrowers are able to get their staked collateral back from the pool.
8. Currently the lending term is fixed to 1 year, which indicates that lenders are only allowed to withdraw their deposits after the lending has matured. 
9. It's worth noting that instead of directly pushing the fund to the user accounts, our platform will first release the corresponding fund to user available balance in the pool. Users are being notified when the fund is released and ready to be withdrawn to their own accounts. 

## Smart contracts
1. `Manager.sol`
   * This contract acts as our factory contract, which includes all necessary functions for user interactions.
   * e.g. Users can specify the type of transaction activities (lending or borrowing), currency of the transaction, amount, etc.
2. `ManagerHelper.sol`
   * This contract contains all helper functions and initialisations of state variables, which can be invoked by the Manager Contract. 
3. `ManagerLibrary.sol`
   * The library contains functions and structs that can be invoked by the Manager Contract.
   * Note that since library does not support any gas consumption and state change, it only includes view and pure functions that mainly contribute to our internal calculations.
4. `BorrowContract.sol`
   * This contract manages individual loan contracts, handling all the details from loan initiation, collateral management, interest calculation, repayment, and contract deactivation.
5. `LendContract.sol`
   * This contract manages individual lending contracts, handling all the details from lending initiation, interest calculation, withdrawal and contract deactivation.
6. `Oracle.sol`
   * This contract interacts with Chainlink oracle, providing real-time data feeds essential for precise interest rate calculations.
7. `Oracle_.sol`
   * This contract is a mock oracle of `Oracle.sol` for local testing.
8. `WBTC.sol`
   * This contract is an ERC20 token implementation representing wBTC on the Ethereum blockchain, allowing users to make transactions using their tokens on Ethereum.