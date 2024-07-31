// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BorrowContract.sol";
import "./LendContract.sol";
// import "./WBTC.sol";
import "./Oracle.sol";
import "./Oracle_.sol";
import "./ManagerLibrary.sol";
    
contract ManagerHelper {
    // Owner (Manager)
    address public owner;

    // Collateralisation rate (%)
    uint public collateralisationRatio;

    // Wrapped BTC token
    IERC20 public wBtc;

    // Oracle
    Oracle_ public oracle;

    // Total number of loans in the pool
    uint public totalLoans;

    // Total number of lends in the pool
    uint public totalLends;

    // List of addresses of loans (address, BorrowContract)
    mapping (address => BorrowContract) public loans;

    // List to track if loan exists (loan address, bool)
    mapping (address => bool) private _loanExists;

    // List of addresses of loans (address, LendContract)
    mapping (address => LendContract) public lends;

    // List to track if lending exists (lend address, bool)
    mapping (address => bool) private _lendExists;

    // List of user available balance (user address, UserAvailableBalance from ManagerLibrary)
    mapping (address => ManagerLibrary.UserAvailableBalance) public availableBalances;

    // List to track if user available balance exists (user address, bool)
    mapping (address => bool) private _availableBalanceExists;

    // ===========================================================================================================================================================

    // Event to be emitted when a new BorrowContract is initialized, not yet finalized
    event BorrowContractInitialized(address borrowContractAddress, uint borrowAmount, bool wantBTC, uint collateralAmount, uint loanTerm, bool activated);

    // Event to be emitted when a new LendContract is initialized, not yet finalised
    event LendContractInitialized(address lendContractAddress, uint lendAmount, bool wantBTC, bool activated);

    // ===========================================================================================================================================================

    constructor(uint _collateralisationRatio, IERC20 _wBtc) {
        owner = msg.sender;

        collateralisationRatio = _collateralisationRatio;

        wBtc = _wBtc;

        // Sepolia Testnet feed addresses
        // address _priceFeedAddress = 0x5fb1616F78dA7aFC9FF79e0371741a747D2a7F22;
        // address _eth30DayAprFeedAddress = 0xceA6Aa74E6A86a7f85B571Ce1C34f1A60B77CD29;
        // address _btc1DayBaseRateFeedAddress = 0x7DE89d879f581d0D56c5A7192BC9bDe3b7a9518e;
        oracle = new Oracle_();

        // Set initial number of loans
        totalLoans = 0;

        // Set initial number of lends
        totalLends = 0;
    }


    /**
    * @dev Deploy a new BorrowContract instance when a new loan request is initiated, 
    *      where the required collateral has not been deposited, 
    *      and therefore not yet activated
    *
    * @param borrowAmount Amount of loan request
    * @param wantBTC Unit of loan request (is in BTC)
    *
    * @return Address of new BorrowContract
    **/
    function deployBorrowContract(address borrower, uint borrowAmount, bool wantBTC, uint loanTerm, uint btcInEthPrice, uint dailyInterestRate) public returns (address) {
        require(borrowAmount > 0, "Borrow amount must be greater than 0");

        // Check if the currency has enough currency to lend
        if (wantBTC) {
            require(wBtc.balanceOf(owner) >= borrowAmount, "Insufficient WBTC in the pool");
        } else {
            require(owner.balance >= borrowAmount, "Insufficient ETH in the pool");
        }

        // Allow users to choose loan terms: 1 week/1 month/3 months
        require(loanTerm == 7 || loanTerm == 30 || loanTerm == 90, "Loan term invalid");

        // Calculate collateral amount required
        uint collateralAmount = ManagerLibrary.calculateCollateralAmount(borrowAmount, wantBTC, btcInEthPrice, collateralisationRatio);
        
        // Create new loan instance
        BorrowContract newBorrowContract = new BorrowContract(owner, borrower, wBtc, borrowAmount, wantBTC, collateralAmount, btcInEthPrice, dailyInterestRate, false, loanTerm);

        // Add loan address to the pool
        loans[borrower] = newBorrowContract;
        _loanExists[address(newBorrowContract)] = true;
        totalLoans++;

        emit BorrowContractInitialized(address(newBorrowContract), borrowAmount, wantBTC, collateralAmount, loanTerm, false);
        return address(newBorrowContract);
    }


    function deployLendContract(address lender, uint lendAmount, bool wantBTC, uint dailyInterestRate) public returns (address) {
        require(lendAmount > 0, "Borrow amount must be greater than 0");

        // Check if the currency has enough currency to lend
        if (wantBTC) {
            require(wBtc.balanceOf(lender) >= lendAmount, "Insufficient WBTC balance");
        } else {
            require(address(lender).balance >= lendAmount, "Insufficient ETH balance");
        }
        
        // Create new lend contract instance
        LendContract newLendContract = new LendContract(owner, lender, wBtc, lendAmount, wantBTC, dailyInterestRate, false);

        // Add deposits address to the pool
        lends[lender] = newLendContract;
        _lendExists[address(newLendContract)] = true;
        totalLends++;

        emit LendContractInitialized(address(newLendContract), lendAmount, wantBTC, false);
        return address(newLendContract);
    }


    /**
    * @dev Add user available balance after a fund is released to the user in the pool 
    *
    * @param user Address of user
    * @param amount Amount of the fund released by the manager contract
    * @param wantBTC Unit of loan request (is in BTC)
    **/
    function addUserBalance(address user, uint amount, bool wantBTC) external {
        // If user collateral record exists, update the record
        // Otherwise, create a new user record in the pool
        ManagerLibrary.UserAvailableBalance memory b;
        if (_availableBalanceExists[user]) {
            b = availableBalances[user];
        } else {
            _availableBalanceExists[user] = true;
            b.ethAmount = 0;
            b.wBtcAmount = 0;
        }

        // Update user total available balance accordingly
        if (wantBTC) {
            b.wBtcAmount += amount;
        } else {
            b.ethAmount += amount;
        }

        // Update the user available balance to the pool
        availableBalances[user] = b;
    }


    /**
    * @dev Deduct user available balance after a fund is withdrawn from the pool 
    *
    * @param user Address of user
    * @param amount Amount of the fund withdrawn by the user
    * @param wantBTC Unit of loan request (is in BTC)
    **/
    function deductUserBalance(address user, uint amount, bool wantBTC) external {
        // If user collateral record exists, update the record
        // Otherwise, create a new user record in the pool
        ManagerLibrary.UserAvailableBalance memory b;
        if (_availableBalanceExists[user]) {
            b = availableBalances[user];
        } else {
            _availableBalanceExists[user] = true;
            b.ethAmount = 0;
            b.wBtcAmount = 0;
        }

        // Update user total available balance accordingly
        if (wantBTC) {
            require(b.wBtcAmount >= amount, "Insufficient WBTC available balance");
            b.wBtcAmount -= amount;
        } else {
            require(b.ethAmount >= amount, "Insufficient ETH available balance");
            b.ethAmount -= amount;
        }

        // Update the user available balance to the pool
        availableBalances[user] = b;
    }


    function getBorrowContract(address payable borrowContractAddress) public view returns (BorrowContract){
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract;
    }

    function getLendContract(address lendContractAddress) public view returns (LendContract) {
        require(_lendExists[lendContractAddress], "LendContract does not exist");
        LendContract lendContract = LendContract(lendContractAddress);
        return lendContract;
    }

    function getAvailableBalances(address user) public view returns (ManagerLibrary.UserAvailableBalance memory) {
        require(_availableBalanceExists[user], "User available balance does not exists");
        return availableBalances[user];
    }
}