// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BorrowContract.sol";
import "./LendContract.sol";
import "./ManagerHelper.sol";
import "./ManagerLibrary.sol";
import "./WBTC.sol";


/// @title Contract to manage the whole lending pool and all lending and borrowing activities

contract Manager {
    // Manager helper contract
    ManagerHelper private _h;

    // Collateralisation ratio (%)
    uint public collateralisationRatio;

    // The owner of the manager, this address will be the pool address (assumption)
    address public owner;

    // Wrapped BTC token
    IERC20 public wBtc;

    // Total number of loans in the pool
    uint public totalLoans;

    // Total number of lends in the pool
    uint public totalLends;

    // ===========================================================================================================================================================
    /** Events **/
    
    // Event to be emitted when loan repayment is requested to inform users about total repayment amount
    event LoanRepaymentRequested(address borrowContractAddress, uint totalRepaymentAmount, uint remainingDays, bool repaymentPendingStatus);

    // Event to be emitted when lend withdrawal is requested to inform users about total repayment amount
    event LendWithdrawalRequested(address LendContractAddress, uint totalWithdrawalAmount, uint remainingDays);

    // Event to be emitted when user successfully withdraw a fund from the smart contract
    event FundWithdrawn(address user, uint amount, bool wantBTC);

    event ContractActivated(address borrowContractAddress, uint deadline, string email);

    event ContractFunded(address contractAddress);

    // ===========================================================================================================================================================
    /** Constructor and user-interacted functions **/

    constructor() {
        // Set contract creator as the owner
        owner = msg.sender;

        // Deploy WBTC contract and mint the amount of token
        address _wBtc = address(new WBTC(1000000000000000000000000));
        wBtc = IERC20(_wBtc);

        // Deploy ManagerHelper contract
         _h = new ManagerHelper(150, wBtc);

        // Collateralisation rate (fixed to 150%)
        collateralisationRatio = _h.collateralisationRatio();

        // Set initial number of loans and lends
        totalLoans = _h.totalLoans();
        totalLoans = _h.totalLends();
    }


    /**
    * @dev Deploy a new either a lend or borrow contract instance 
    *      according to the user input
    *
    * @param amount Amount of loan/lend request
    * @param wantBTC Unit of loan/lend request (is in BTC)
    * @param wantBorrow Transaction type (lend/borrow)
    * @param loanTerm Expected duration of the loan, should be 0 when wantBorrow is false
    *
    * @return Address of new BorrowContract
    **/
    function deployContract(uint amount, bool wantBTC, bool wantBorrow, uint loanTerm) public returns (address) {
        require(amount > 0, "Amount must be greater than 0");

        // Current btc price in eth => How much Eth equivalent to 1 Btc
        uint btcInEthPrice = ManagerLibrary.getBtcInEtcPrice(_h.oracle());

        // Get current daily interest correponding to the currency of the loan
        uint dailyInterestRate = ManagerLibrary.getDailyInterestRate(wantBTC, _h.oracle());

        if (wantBorrow) {
            return _h.deployBorrowContract(msg.sender, amount, wantBTC, loanTerm, btcInEthPrice, dailyInterestRate);
        } else {
            // No loan term for lending
            require(loanTerm == 0, "Loan term should be 0 for lending");
            return _h.deployLendContract(msg.sender, amount, wantBTC, dailyInterestRate);
        }
    }


<<<<<<< HEAD

    /**
    * @dev Allow user to deposit ETH including collateral and repayment deposits during borrowing,
    *      activate the BorrowContract after successfully depositing collateral, 
    *      deactivate the BorrowContract after successfully depositing repayment
    *
    * @param borrowContractAddress payable address of BorrowContract
    * @param wantRepay True if depositing repayment
    **/
    function borrowDepositETH(address payable borrowContractAddress, bool wantRepay) public payable {
=======
    function borrowDepositETH(address payable borrowContractAddress, bool wantRepay, string memory _email) public payable {
>>>>>>> 6ff0c9b4ea4a0b1f9f13e442c27658cc72b9e57b
        // Get borrow contract if exists
        BorrowContract borrowContract = _h.getBorrowContract(borrowContractAddress);
        require(msg.sender == borrowContract.borrower(), "Only borrower can deposit");
        
        if (wantRepay) {
            // Check depositing ETH repayment condition
            ManagerLibrary.checkDepositETHRepayment(borrowContract, msg.value);

            // Transfer repayment amount to Manager contract 
            borrowContract.repayLoanETH{value: msg.value}(address(this));

            // Deactivate the borrow contract
            borrowContract.deactivateContract();
        } else {
            // Check depositing ETH collateral condition
            ManagerLibrary.checkDepositETHCollateral(borrowContract, msg.value);

            // Transfer collateral to Manager contract
            borrowContract.depositCollateralETH{value: msg.value}(address(this));

            // Activate the borrow contract
            borrowContract.activateContract();

            emit ContractActivated(borrowContractAddress, borrowContract.loanDeadline(), _email);
        }
    }


<<<<<<< HEAD
    /**
    * @dev Allow user to deposit WBTC including collateral and repayment deposits during borrowing,
    *      activate the BorrowContract after successfully depositing collateral, 
    *      deactivate the BorrowContract after successfully depositing repayment
    *
    * @param borrowContractAddress payable address of BorrowContract
    * @param wantRepay True if depositing repayment
    **/
    function borrowDepositWBTC(address payable borrowContractAddress, uint amount, bool wantRepay) public {
=======
    function borrowDepositWBTC(address payable borrowContractAddress, uint amount, bool wantRepay, string memory _email) public {
>>>>>>> 6ff0c9b4ea4a0b1f9f13e442c27658cc72b9e57b
        // Get borrow contract if exists
        BorrowContract borrowContract = _h.getBorrowContract(borrowContractAddress);
        require(msg.sender == borrowContract.borrower(), "Only borrower can deposit");
        
        if (wantRepay) {
            // Check depositing WBTC repayment condition
            ManagerLibrary.checkDepositWBTCRepayment(borrowContract, amount);
            require(checkWBTCBalance(msg.sender) >= amount, "Insufficient balance");

            // Transfer repayment amount to Manager contract 
            borrowContract.repayLoanBTC(address(this), amount);

            // Deactivate the borrow contract
            borrowContract.deactivateContract();
        } else {
            // Check depositing ETH collateral condition
            ManagerLibrary.checkDepositWBTCCollateral(borrowContract, amount);
            require(checkWBTCBalance(msg.sender) >= amount, "Insufficient balance");

            // Transfer collateral to Manager contract
            borrowContract.depositCollateralBTC(address(this), amount);

            // Activate the borrow contract
            borrowContract.activateContract();

            emit ContractActivated(borrowContractAddress, borrowContract.loanDeadline(), _email);
        }
    }


    /**
    * @dev Allow user to deposit either ETH or WBTC during lending,
    *      activate the LendContract after successfully depositing
    *
    * @param lendContractAddress payable address of LendContract
    * @param amount Amount of deposit
    * @param wantBTC True if depositing WBTC
    **/
    function lendDeposit(address payable lendContractAddress, uint amount, bool wantBTC) public payable {
        // Get lend contract if exists
        LendContract lendContract = _h.getLendContract(lendContractAddress);
        require(msg.sender == lendContract.lender(), "Only lender can deposit");

        if (wantBTC) {
            require(lendContract.wantBTC(), "This LendContract does not support ETH deposit");
            lendContract.depositBTC(address(this), amount);
        } else {
            require(!lendContract.wantBTC(), "This LendContract does not support WBTC deposit");
            lendContract.depositETH{value: msg.value}(address(this));
        }

        // Activate the lend contract
        lendContract.activateContract();
    }


    /**
    * @dev Allow contract itself to receive ETH
    **/
    receive() external payable {}
    // fallback() external payable {}


    /**
    * @dev Allow borrower to request repayment of their loan when they are ready
    *
    * @param borrowContractAddress Payable address of BorrowContract
    **/
    function requestRepayment(address payable borrowContractAddress) public {
        // Get borrow contract if exists
        BorrowContract borrowContract = _h.getBorrowContract(borrowContractAddress);
        require(msg.sender == borrowContract.borrower(), "Only borrower can request repayment");

        // Request repayment to ensure user has the ability to repay loan
        uint balance;
        if (borrowContract.wantBTC()) {
            balance = checkWBTCBalance(msg.sender);
        } else {
            balance = checkEthBalance(msg.sender);
        }
        require(borrowContract.requestRepayment(balance), "Insufficient balance for repayment");
        emit LoanRepaymentRequested(borrowContractAddress, borrowContract.totalRepaymentAmount(), borrowContract.remainingDays(), borrowContract.repaymentPendingStatus());
    }


    /**
    * @dev Allow lender to request withdrawal of their deposits after mature
    *
    * @param lendContractAddress Payable address of LendContract
    **/
    function requestLendingWithdrawal(address payable lendContractAddress) public {
        // Get lend contract if exists
        LendContract lendContract = _h.getLendContract(lendContractAddress);
        require(msg.sender == lendContract.lender(), "Only lender can request withdrawal");

        require(lendContract.requestWithdrawal(), "Lend deposit is not mature");
        emit LendWithdrawalRequested(lendContractAddress, lendContract.totalWithdrawalAmount(), lendContract.remainingDays());
    }


    /**
    * @dev Allow user to withdraw funds from their available balance in the pool,
    *      which are released by the smart contract
    *
    * @param user Payable address of user
    * @param amount Amount of withdrawal
    * @param wantBTC Currency of the withdrawal
    **/
    function withdrawFunds(address payable user, uint amount, bool wantBTC) public payable{
        require(user == msg.sender, "Only user corresponding to the available balance can withdraw funds");
        
        // Get user's available balance if exists
        ManagerLibrary.UserAvailableBalance memory userBalances = _h.getAvailableBalances(user);

        // Check if there are sufficient funds for user withdrawal in the pool
        if (wantBTC) {
            require(amount <= userBalances.wBtcAmount, "Insufficient funds in WBTC for withdrawal");
            require(wBtc.transfer(user, amount), "WBTC transfer failed");
        } else {
            require(amount <= userBalances.ethAmount, "Insufficient funds in ETH for withdrawal");
            user.transfer(amount * 1 ether);
        }
        // Deduct user available balance in the pool
        _h.deductUserBalance(user, amount, wantBTC);
        emit FundWithdrawn(user, amount, wantBTC);
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


    /**
    * @dev Check user's current available balances for both ETH and WBTC in the pool
    *
    * @param user Address of user
    *
    * @return Current available balance in the pool corresponding to the user 
    **/
    function checkUserAvailableBalance(address user) public view returns (ManagerLibrary.UserAvailableBalance memory) {
        return _h.getAvailableBalances(user);
    }

    // function checkContractStatus(address payable contractAddress, bool wantBorrow) public view returns (bool) {
    //     if (wantBorrow) {
    //         // Get borrow contract if exists
    //         BorrowContract borrowContract = _h.getBorrowContract(contractAddress);
    //         return borrowContract.activated();
    //     } else {
    //         LendContract lendContract = _h.getLendContract(contractAddress);
    //         return lendContract.activated();
    //     }
    // }

    // function deactivateContract(address payable contractAddress, bool wantBorrow) public {
    //     if (wantBorrow) {
    //         // Get borrow contract if exists
    //         BorrowContract borrowContract = _h.getBorrowContract(contractAddress);
    //         borrowContract.deactivateContract();
    //     } else {
    //         LendContract lendContract = _h.getLendContract(contractAddress);
    //         lendContract.deactivateContract();
    //     }
    // }


    // ===========================================================================================================================================================
    /** Restricted functions **/

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
    * @dev Release assets such as funds and collateral to user available balance in the pool, 
    *      which can be pulled by the corresponding user
    *
    * @param contractAddress Payable address of contract (BorrowContract/LendContract)
    * @param wantFund True if releasing fund and false if releasing collateral in borrowing
    *                 should always be false for lending
    *
    **/
    function releaseAsset(address payable contractAddress, bool wantFund, bool wantBorrow) public restricted {
        if (wantBorrow) {
            // Get borrow contract if exists
            BorrowContract borrowContract = _h.getBorrowContract(contractAddress);
            if (wantFund) {
                require(borrowContract.activated(), "Contract has not been activated");
                _h.addUserBalance(borrowContract.borrower(), borrowContract.borrowAmount(), borrowContract.wantBTC());
            } else {
                // Borrow contract will be deactivated and the repayment pending status will be true when repayment is done
                require(!borrowContract.activated() && borrowContract.repaymentPendingStatus(), "Repayment has not been cleared");
                _h.addUserBalance(borrowContract.borrower(), borrowContract.collateralAmount(), !borrowContract.wantBTC());
            }
        } else {
            // wantFund not supported for lending
            require(!wantFund, "Should be false for lending");
            // Get lend contract if exists
            LendContract lendContract = _h.getLendContract(contractAddress);
            require(!lendContract.activated() && lendContract.remainingDays() == 0, "Lend deposit is not mature");
            _h.addUserBalance(lendContract.lender(), lendContract.lendAmount(), lendContract.wantBTC());
        }

        emit ContractFunded(contractAddress);
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