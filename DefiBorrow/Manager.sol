// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BorrowContract.sol";
import "./WBTC.sol";
import "./Oracle.sol";
import "./Oracle_.sol";


/// @title Contract to manage the whole lending pool and all lending and borrowing activities

/// TODO: WBTC transfer, repayment, liquidation

contract Manager {
    // Struct to store user collateral (For a specific user, how much ETH and wBTC they have)
    struct UserCollateral {
        uint ethAmount;
        uint wBtcAmount;
    }

    // Collateralisation rate (%)
    uint public COLLATERALISATIONRATE;

    // The owner of the manager, this address will be the pool address (assumption)
    address public owner;

    // Wrapped BTC token
    IERC20 public wBtc;

    // Oracle
    Oracle_ private _oracle;

    // Total number of loans in the pool
    uint public totalLoans;

    // List of addresses of loans (address, BorrowContract)
    mapping (address => BorrowContract) public loans;
    
    // List to track if loan exists (loan address, bool)
    mapping (address => bool) private _loanExists;

    // List of user collaterals (user address, UserCollateral)
    mapping (address => UserCollateral) public collaterals;

    // List to track if user collateral exists (user address, bool)
    mapping (address => bool) private _collateralExists;


    // ===========================================================================================================================================================
    

    // Event to be emitted when a new BorrowContract is initialized, not yet finalized
    event BorrowContractInitialized(address BorrowContractAddress, uint borrowAmount, bool wantBTC, bool activated);

    // Event to be emiited when a new BorrowContract is activated
    event BorrowContractActivated(address BorrowContractAddress, uint borrowAmount, bool wantBTC, uint btcInEthPrice);
    
    
    // ===========================================================================================================================================================


    constructor() {
        // Set contract creator as the owner
        owner = msg.sender;

        // Set initial number of loans
        totalLoans = 0;

        // Collateralisation rate
        COLLATERALISATIONRATE = 150;

        // Deploy WBTC contract and assign wBTC address
        address _wBtc = address(new WBTC(1000000000000000000000000));
        setWBTCAddress(_wBtc);

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
    function deployBorrowContract(uint borrowAmount, bool wantBTC) public returns (address) {
        require(borrowAmount > 0, "Borrow amount must be greater than 0");

        // Check if the currency has enough currency to lend
        if (wantBTC) {
            require(wBtc.balanceOf(address(this)) >= borrowAmount, "Insufficient wBTC in the pool");
        } else {
            require(address(this).balance >= borrowAmount, "Insufficient ETH in the pool");
        }

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
        BorrowContract newBorrowContract = new BorrowContract(msg.sender, wBtc, borrowAmount, wantBTC, collateralAmount, btcInEthPrice, dailyInterestRate, false);

        // Add loan address to the pool
        loans[msg.sender] = newBorrowContract;
        _loanExists[address(newBorrowContract)] = true;
        totalLoans++;

        emit BorrowContractInitialized(address(newBorrowContract), borrowAmount, wantBTC, false);
        return address(newBorrowContract);
    }


    /**
    * @dev Allow borrower to deposit collateral in ETH to the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    **/
    function depositCollateralETH(address payable borrowContractAddress) public payable {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);

        // Convert collateral amount to Wei
        uint collateralAmount = borrowContract.collateralAmount() * 1 ether;

        require(msg.value == collateralAmount, "Incorrect ETH amount");
        require(msg.sender.balance >= collateralAmount, "Insufficient balance");
        require(msg.sender == borrowContract.borrower(), "Only borrower can deposit collateral");

        // User transfers ETH to the Manager owner
        if (borrowContract.wantBTC()) {
            borrowContract.depositCollateralETH{value: msg.value}(owner);
        } else {
            revert("This BorrowContract does not support ETH collateral");
        }
        emit BorrowContractActivated(borrowContractAddress, borrowContract.borrowAmount(), borrowContract.wantBTC(), borrowContract.btcInEthPrice());
    }


    /**
    * @dev Allow borrower to deposit collateral in BTC to the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    * @param collateralAmount Amount of WBTC to be deposited to the BorrowContract as collateral
    *
    **/
    function depositCollateralBTC(address payable borrowContractAddress, uint collateralAmount) public {
        // Check if the BorrowContract exists
        require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        require(msg.sender == borrowContract.borrower(), "Only borrower can deposit collateral");

        // Transfer BTC to the manager owner
        if (!borrowContract.wantBTC()) {
            borrowContract.depositCollateralBTC(owner, collateralAmount);
        } else {
            revert("This BorrowContract does not support BTC collateral");
        }
        emit BorrowContractActivated(msg.sender, borrowContract.borrowAmount(), borrowContract.wantBTC(), borrowContract.btcInEthPrice());
    }


    // function repayLoan(address )


    /**
    * @dev Check how much remaining of the spender's WBTC allowance
    *
    * @return Spender's remaining allowance over the owner
    **/
    function checkAllowance(address _owner, address _spender) public view returns(uint) {
        return wBtc.allowance(_owner, _spender);
    }


    /**
    * @dev Fund the user with a specific amount of WBTC, 
    *      which can only invoked by the contract owner
    *
    * @param user Address of user
    * @param amount Funded amount of WBTC
    *
    **/
    function fundWBTC(address user, uint amount) public {
        require(msg.sender == owner, "Only owner can fund wBTC");
        require(amount > 0, "Amount must be greater than 0");

        // Check if the contract has enough wBTC to transfer
        uint contractBalance = wBtc.balanceOf(address(this));
        require(contractBalance >= amount, "Contract does not have enough wBTC");

        // Transfer wBTC to the user from the owner
        require(wBtc.transfer(user, amount), "WBTC transfer failed");
    }


    /**
    * @dev Set WBTC address, 
    *      which can only be invoked by the contract owner.
    *
    * @param _wBtc Address of wrapped Bitcoin
    **/
    function setWBTCAddress(address _wBtc) public {
        require(msg.sender == owner, "Only owner can set WBTC address");
        wBtc = IERC20(_wBtc);
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
    

    /**
    * @dev Get the borrow amount of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Borrow amount corresponding to the loan
    *
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
    *
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
    *
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
    *
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
    *
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
    *
    **/
    function getBorrowContractStatus(address payable borrowContractAddress) public view returns (bool) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.activated();
    }


    /**
    * @dev Get the borrower address of the specified BorrowContract
    *
    * @param borrowContractAddress Address of BorrowContract
    *
    * @return Borrower address corresponding to the loan
    *
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
    *
    **/
    function getBorrowContractCreator(address payable borrowContractAddress) public view returns (address) {
        BorrowContract borrowContract = BorrowContract(borrowContractAddress);
        return borrowContract.creator();
    }


    // ===========================================================================================================================================================


    /**
    * @dev Authorise the use of WBTC allowance to the user
    *
    * @param amount Amount of approved WBTC allowance
    **/
    function _approveWBTC(address user, uint amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(wBtc.approve(user, amount), "Approval failed");
    }


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


    // Function to check if the user already has enough collateral for a loan
    // function _checkEnoughCollateral(address user, uint collateralAmount, bool wantBTC) private view returns (bool) {
    //   // If user collateral record doesn't exist, return false
    //   // If exist, check if the corresponding collateral amount is sufficient for the loan
    //   if (!_collateralExists[user]) {
    //       return false;
    //   } else {
    //       UserCollateral memory c = collaterals[user];
    //       if (wantBTC) {
    //           return (c.wBtcAmount >= collateralAmount);
    //       } else {
    //           return (c.ethAmount >= collateralAmount);
    //       }
    //   }
    // }

  

}