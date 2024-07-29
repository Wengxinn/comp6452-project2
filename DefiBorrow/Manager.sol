// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BorrowContract.sol";
import "./WBTC.sol";
import "./Oracle.sol";
import "./Oracle_.sol";


/// @title Contract to manage the whole lending pool and all lending and borrowing activities

/// TODO: liquidation (grace period, reminder), off chain data storage

contract Manager {
    // Struct to store user available balance for withdrawal (For a specific user, how much ETH and wBTC they have for withdrawal)
    struct UserAvailableBalance {
        uint ethAmount;
        uint wBtcAmount;
    }

    // Collateralisation rate (%)
    uint public COLLATERALISATIONRATE;

    // The owner of the manager, this address will be the pool address (assumption)
    address public owner;

    // Wrapped BTC token
    IERC20 public wBtc;

    // wBTC address
    address public wBtcAddress;

    // Oracle
    Oracle_ private _oracle;

    // Total number of loans in the pool
    uint public totalLoans;

    // List of addresses of loans (address, BorrowContract)
    mapping (address => BorrowContract) public loans;
    
    // List to track if loan exists (loan address, bool)
    mapping (address => bool) private _loanExists;

    // List of user available balance (user address, UserAvailableBalance)
    mapping (address => UserAvailableBalance) public availableBalances;

    // List to track if user available balance exists (user address, bool)
    mapping (address => bool) private _availableBalanceExists;


    // ===========================================================================================================================================================
    /** Events **/

    // Event to be emitted when a new BorrowContract is initialized, not yet finalized
    event BorrowContractInitialized(address BorrowContractAddress, uint borrowAmount, bool wantBTC, bool activated);
    
    // Event to be emitted when loan repayment is requested to inform users about total repayment amount
    event LoanRepaymentRequested(address BorrowContractAddress, uint totalRepaymentAmount, bool repaymentPendingStatus);

    // Event to be emitted when user successfully withdraw a fund from the smart contract
    event FundWithdrawn(address user, uint amount, bool wantBTC);

    // ===========================================================================================================================================================
    /** Constructor and user-interacted functions **/

    constructor() {
        // Set contract creator as the owner
        owner = msg.sender;

        // Set initial number of loans
        totalLoans = 0;

        // Collateralisation rate (fixed to 1500%)
        COLLATERALISATIONRATE = 150;

        // Deploy WBTC contract and assign wBTC address
        wBtcAddress = address(new WBTC(1000000000000000000000000));
        setWBTCAddress(wBtcAddress);

        // Sepolia Testnet feed addresses
        // address _priceFeedAddress = 0x5fb1616F78dA7aFC9FF79e0371741a747D2a7F22;
        // address _eth30DayAprFeedAddress = 0xceA6Aa74E6A86a7f85B571Ce1C34f1A60B77CD29;
        // address _btc1DayBaseRateFeedAddress = 0x7DE89d879f581d0D56c5A7192BC9bDe3b7a9518e;
        _oracle = new Oracle_();
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
    function deployBorrowContract(uint borrowAmount, bool wantBTC, uint loanTerm) public returns (address) {
        require(borrowAmount > 0, "Borrow amount must be greater than 0");

        // Check if the currency has enough currency to lend
        if (wantBTC) {
            require(wBtc.balanceOf(address(this)) >= borrowAmount, "Insufficient WBTC in the pool");
        } else {
            require(address(this).balance >= borrowAmount, "Insufficient ETH in the pool");
        }

        // Allow users to choose loan terms: 1 week/1 month/3 months
        require(loanTerm == 7 || loanTerm == 30 || loanTerm == 90, "Loan term invalid");

        // Current btc price in eth => How much Eth equivalent to 1 Btc
        uint btcInEthPrice = _getBtcInEtcPrice();

        // Calculate collateral amount required
        uint collateralAmount = _calculateCollateralAmount(borrowAmount, wantBTC, btcInEthPrice);

        // Get current daily interest correponding to the currency of the loan
        uint dailyInterestRate = _getDailyInterestRate(wantBTC);

        // Check borrower's held collateral (if any)
        // If borrower has sufficient collateral, accept the request straightaway
        // bool sufficientCollateral = _checkEnoughCollateral(msg.sender, collateralAmount, wantBTC);
        
        // Create new loan instance
        BorrowContract newBorrowContract = new BorrowContract(msg.sender, wBtc, borrowAmount, wantBTC, collateralAmount, btcInEthPrice, dailyInterestRate, false, loanTerm);

        // Add loan address to the pool
        loans[msg.sender] = newBorrowContract;
        _loanExists[address(newBorrowContract)] = true;
        totalLoans++;

        emit BorrowContractInitialized(address(newBorrowContract), borrowAmount, wantBTC, false);
        return address(newBorrowContract);
    }


    /**
    * @dev Allow contract itself to receive ETH
    **/
    receive() external payable {}


    /**
    * @dev Allow borrower to deposit collateral in ETH to the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    **/
    function depositCollateralETH(address payable borrowContractAddress) public payable {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);

        // Get contract's expected collateral amount
        uint collateralAmount = borrowContract.collateralAmount() * 1 ether;

        // Check borrower's condition to deposit collateral
        require(msg.sender == borrowContract.borrower(), "Only borrower can deposit collateral");
        require(msg.value == collateralAmount, "Incorrect ETH amount");
        require(checkEthBalance((msg.sender)) >= collateralAmount, "Insufficient balance");

        // User transfers ETH to the Manager contract
        if (borrowContract.wantBTC()) {
            borrowContract.depositCollateralETH{value: msg.value}(address(this));
        } else {
            revert("This BorrowContract does not support WBTC collateral");
        }

        // Activate the borrow contract
        borrowContract.activateContract();
    }


    /**
    * @dev Allow borrower to deposit collateral in BTC to the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    * @param amount Amount of WBTC to be deposited to the BorrowContract as collateral
    **/
    function depositCollateralBTC(address payable borrowContractAddress, uint amount) public {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);

        // Get contract's expected collateral amount
        uint collateralAmount = borrowContract.collateralAmount();

        // Check borrower's condition to deposit collateral
        require(msg.sender == borrowContract.borrower(), "Only borrower can deposit collateral");
        require(amount == collateralAmount, "Incorrect WBTC amount");
        require((checkWBTCBalance(msg.sender)) >= collateralAmount, "Insufficient balance");

        // User transfers WBTC to the Manager contract
        if (!borrowContract.wantBTC()) {
            borrowContract.depositCollateralBTC(address(this), collateralAmount);
        } else {
            revert("This BorrowContract does not support ETH collateral");
        }

        // Activate the borrow contract
        borrowContract.activateContract();
    }


    /**
    * @dev Allow borrower to request repayment of their loan when they are ready
    *
    * @param borrowContractAddress Address of BorrowContract
    **/
    function requestRepayment(address payable borrowContractAddress) public {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        require(msg.sender == borrowContract.borrower(), "Only borrower can request repayment");

        // Request repayment to ensure user has the ability to repay loan
        uint balance;
        if (borrowContract.wantBTC()) {
            balance = checkWBTCBalance(msg.sender);
        } else {
            balance = checkEthBalance(msg.sender);
        }
        uint totalRepaymentAmount = borrowContract.requestRepayment(balance);
        emit LoanRepaymentRequested(borrowContractAddress, totalRepaymentAmount, borrowContract.repaymentPendingStatus());
    }


    /**
    * @dev Allow borrower to repay loan in ETH to the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    **/
    function repayLoanETH(address payable borrowContractAddress) public payable {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);

        // Check borrower's condition to repay loan
        uint totalRepaymentAmount = borrowContract.totalRepaymentAmount();
        require(msg.sender == borrowContract.borrower(), "Only borrower can repay loan");
        require(borrowContract.repaymentPendingStatus(), "Repayment request pending");
        require(msg.value == totalRepaymentAmount, "Incorrect ETH amount");
        require(checkEthBalance(msg.sender) >= totalRepaymentAmount, "Insufficient balance");

        // User transfers ETH to the Manager contract
        if (!borrowContract.wantBTC()) {
            borrowContract.repayLoanETH{value: msg.value}(address(this));
        } else {
            revert("This BorrowContract does not support WBTC repayment");
        }

        // Deactivate the borrow contract
        borrowContract.deactivateContract();
    }


    /**
    * @dev Allow borrower to repay loan in BTC to the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    **/
    function repayLoanBTC(address payable borrowContractAddress, uint amount) public {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        require(msg.sender == borrowContract.borrower(), "Only borrower can deposit collateral");
        
        // Check borrower's condition to repay loan
        uint totalRepaymentAmount = borrowContract.totalRepaymentAmount();
        require(borrowContract.repaymentPendingStatus(), "Repayment request not yet initiated");
        require(amount == totalRepaymentAmount, "Incorrect BTC amount");
        require(checkEthBalance(msg.sender) >= totalRepaymentAmount, "Insufficient balance");

        // Transfer BTC to the Manager contract
        if (!borrowContract.wantBTC()) {
            borrowContract.repayLoanBTC(address(this), amount);
        } else {
            revert("This BorrowContract does not support ETH repayment");
        }

        // Deactivate the borrow contract
        borrowContract.deactivateContract();
    }


    /**
    * @dev Allow user to withdraw available funds stored in the pool
    *
    * @param user Address of user
    * @param wantBTC Unit of loan request (is in BTC)
    **/
    function withdrawFunds(address payable user, bool wantBTC) public payable{
        // Check if user's available balance exists
        require(_availableBalanceExists[user], "User's available balance does not exist");
        
        // Check if there are sufficient funds for user withdrawal in the pool
        UserAvailableBalance memory userBalances = availableBalances[user];
        if (wantBTC) {
            require(msg.value <= userBalances.wBtcAmount, "Insufficient funds in WBTC for withdrawal");
            fundWBTC(user, msg.value);
        } else {
            require(msg.value <= userBalances.ethAmount, "Insufficient funds in ETH for withdrawal");
            fundEth(user, msg.value);
        }
        // Deduct user available balance in the pool
        _deductUserBalance(user, msg.value, wantBTC);
        emit FundWithdrawn(user, msg.value, wantBTC);
    }


    /**
    * @dev Check how much remaining of the spender's WBTC allowance
    *
    * @return Spender's remaining allowance over the owner
    **/
    function checkAllowance(address _owner, address _spender) public view returns(uint) {
        return wBtc.allowance(_owner, _spender);
    }


    /**
    * @dev Check user's current ETH balance
    *
    * @param user Address of user
    *
    * @return Current ETH balance corresponding to the user account
    **/
    function checkEthBalance(address user) public view returns (uint) {
        return user.balance;
    }


    /**
    * @dev Check user's current WBTC balance
    *
    * @param user Address of user
    *
    * @return Current WBTC balance corresponding to the user account
    **/
    function checkWBTCBalance(address user) public view returns (uint) {
        return wBtc.balanceOf(user);
    }


    // ===========================================================================================================================================================
    /** Restricted functions **/

    /**
    * @dev Set WBTC address, 
    *      which can only be invoked by the contract owner.
    *
    * @param _wBtc Address of wrapped Bitcoin
    **/
    function setWBTCAddress(address _wBtc) public restricted {
        wBtc = IERC20(_wBtc);
    }  


    /**
    * @dev Fund the user with a specific amount of WBTC, 
    *      which can only invoked by the contract owner
    *
    * @param user Address of user
    * @param amount Funded amount of WBTC
    **/
    function fundWBTC(address user, uint amount) public restricted {
        require(amount > 0, "Amount must be greater than 0");

        // Check if the contract has enough wBTC to transfer
        uint contractBalance = checkWBTCBalance(address(this));
        require(contractBalance >= amount, "Contract does not have enough WBTC");

        // Transfer wBTC to the user from the owner
        require(wBtc.transfer(user, amount), "WBTC transfer failed");
    }


    /**
    * @dev Fund the user with a specific amount of ETH, 
    *      which can only invoked by the contract owner
    *
    * @param user Address of user
    * @param amount Funded amount of ETH
    **/
    function fundEth(address payable user, uint amount) public restricted payable {
        // Check if the contract has enough ETH to transfer
        uint contractBalance = checkEthBalance(address(this));
        require(contractBalance >= amount, "Contract does not have enough ETH");
        user.transfer(amount);
    }


    /**
    * @dev Release fund to user available balance stored in the pool, 
    *      but the fund has not yet been transferred to user account
    *
    * @param borrowContractAddress Address of BorrowContract
    * @param amount Amount of released fund
    * @param wantBTC Unit of loan request (is in BTC)
    **/
    function releaseFund(address borrowContractAddress, uint amount, bool wantBTC) public restricted {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);

        require(borrowContract.activated(), "Contract has not been activated");
        _addUserBalance(borrowContract.borrower(), amount, wantBTC);
    }


    /**
    * @dev Release collateral to user available balance stored in the pool, 
    *      but the fund has not yet been transferred to user account
    *
    * @param borrowContractAddress Address of BorrowContract
    * @param amount Amount of released fund
    * @param wantBTC Unit of loan request (is in BTC)
    **/
    function releaseCollateral(address borrowContractAddress, uint amount, bool wantBTC) public restricted {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);

        // Borrow contract will be deactivated and the repayment pending status will be true when repayment is done
        require(!borrowContract.activated() && borrowContract.repaymentPendingStatus(), "Repayment amount has not been cleared");
        _addUserBalance(borrowContract.borrower(), amount, wantBTC);
    }


    // ===========================================================================================================================================================
    /** Functions to interact with individual BorrowContract **/

    /**
    * @dev Get the borrow amount of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Borrow amount corresponding to the loan
    **/
    function getBorrowContractBorrowAmount(address payable borrowContractAddress) public view returns (uint) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.borrowAmount();
    }


    /**
    * @dev Get the collateral amount of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Collateral amount corresponding to the loan
    **/
    function getBorrowContractCollateralAmount(address payable borrowContractAddress) public view returns (uint) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.collateralAmount();
    }


    /**
    * @dev Get the current BTC price in ETH of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Current BTC price in ETH
    **/
    function getBorrowContractBtcInEthPrice(address payable borrowContractAddress) public view returns (uint) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.btcInEthPrice();
    }


    /**
    * @dev Get the daily interest rate of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Daily interest rate corresponding to the loan
    **/
    function getBorrowContractDailyInterestRate(address payable borrowContractAddress) public view returns (uint) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.dailyInterestRate();
    }


    /**
    * @dev Get the currency (BTC or ETH) of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Currency of the loan (is in BTC)
    **/
    function getBorrowContractWantBTC(address payable borrowContractAddress) public view returns (bool) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.wantBTC();
    }


    /**
    * @dev Get the current status (is activated) of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Contract's activation status
    **/
    function getBorrowContractStatus(address payable borrowContractAddress) public view returns (bool) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.activated();
    }


    /**
    * @dev Get the loan term of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Loan term attached to the BorrowContract
    **/
    function getBorrowContractLoanTerm(address payable borrowContractAddress) public view returns (uint) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.loanTerm();
    }


    /**
    * @dev Get activation time of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Contract's activated time
    **/
    function getBorrowContractStartTime(address payable borrowContractAddress) public view returns (uint) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.startTime();
    }


    /**
    * @dev Get total repayment amount of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Total repayment amount corresponding to the loan
    **/
    function getBorrowContractTotalRepaymentAmount(address payable borrowContractAddress) public view returns (uint) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.totalRepaymentAmount();
    }


    /**
    * @dev Get current repayment pending status of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Current repayment pending status corresponding to the loan
    **/
    function getBorrowContractRepaymentPendingStatus(address payable borrowContractAddress) public view returns (bool) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.repaymentPendingStatus();
    }


    /**
    * @dev Get loan deadline of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Deadline of repayment corresponding to the loan
    **/
    function getBorrowContractLoanDeadline(address payable borrowContractAddress) public view returns (uint) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.loanDeadline();
    }


    /**
    * @dev Get the borrower address of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Borrower address corresponding to the loan
    **/
    function getBorrowContractBorrower(address payable borrowContractAddress) public view returns (address) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.borrower();
    }


    /**
    * @dev Get the creator of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Contract's creator
    **/
    function getBorrowContractCreator(address payable borrowContractAddress) public view returns (address) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.creator();
    }


    // ===========================================================================================================================================================
    /** Private functions for internal implementations **/

    /**
    * @dev Get the current BTC price in Eth
    *
    * @return Current BTC/ETH price returned by oracle
    **/
    function _getBtcInEtcPrice() private view returns (uint) {
        // The data returned from oracle is stored in 18 decimals
        return uint(_oracle.getLatestBtcPriceInEth()) / 10**18; 

    }


    /**
    * @dev Get the current 30-day ETH apr
    *
    * @return Current 30-day ETH apr stored in 7 decimals returned by oracle
    **/
    function _getEth30DayApr() private view returns (uint) {
        return uint(_oracle.getLatestEth30DayApr());
    }


    /**
    * @dev Get the current 1-Day BTC interest rate benchmark curve 
    *
    * @return Current 1-Day BTC interest rate benchmark curve stored in 8 decimals returned by oracle
    **/
    function _getBtc1DayBaseRate() private view returns (uint) {
        return uint(_oracle.getBtc1DayBaseRate());
    }


    /**
    * @dev Get the current daily interest rate corresponding to the currency
    *
    * @param wantBTC Unit of loan request (is in BTC)
    * @return Current aily interest rate
    **/
    function _getDailyInterestRate(bool wantBTC) private view returns (uint) {
        // Compute daily rate according to the data fed from oracle
        // For eth, apr is compounded monthly, so need to be divided by 30
        uint dailyRate;
        if (wantBTC) {
            // Data stored in 8 decimals
            dailyRate = (_getBtc1DayBaseRate()) / 100;
            // Convert to 7 decimals for consistency with eth
            dailyRate = dailyRate / 10;
        } else {
            // Data stored in 7 decimals
            dailyRate = (_getEth30DayApr()) / (30 * 100);
        }
        return dailyRate;
    }


    /**
    * @dev Calculate the collateral amount corresponding to the loan request,
    *      including 1.5 overcollateralisation ratio
    *
    * @param loanAmount Amount of loan request
    * @param wantBTC Unit of loan request (is in BTC)
    * @param btcInEthPrice Currnet BTC price in ETH
    *
    * @return Collateral amount of the loan request
    **/
    function _calculateCollateralAmount(uint loanAmount, bool wantBTC, uint btcInEthPrice) private view returns (uint) {
        if (wantBTC) {
            return loanAmount * btcInEthPrice * COLLATERALISATIONRATE / 100;
        } else {
            return loanAmount / btcInEthPrice * COLLATERALISATIONRATE / 100;
        }
    } 


    /**
    * @dev Add user available balance after a fund is released to the user in the pool 
    *
    * @param user Address of user
    * @param amount Amount of the fund released by the manager contract
    * @param wantBTC Unit of loan request (is in BTC)
    **/
    function _addUserBalance(address user, uint amount, bool wantBTC) private {
        // If user collateral record exists, update the record
        // Otherwise, create a new user record in the pool
        UserAvailableBalance memory b;
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
    function _deductUserBalance(address user, uint amount, bool wantBTC) private {
        // If user collateral record exists, update the record
        // Otherwise, create a new user record in the pool
        UserAvailableBalance memory b;
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


    // ===========================================================================================================================================================
    /** Modifiers **/
    
    /** 
     * @notice Only the contract owner can do
     */
    modifier restricted() {
        require (msg.sender == owner, "Can only be executed by the owner");
        _;
    }
  

}