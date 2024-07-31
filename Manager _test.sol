// SPDX-License-Identifier: GPL-3.0
        
pragma solidity >=0.8.00 <0.9.0;

// This import is automatically injected by Remix
import "remix_tests.sol"; 

// This import is required to use custom transaction context
// Although it may fail compilation in 'Solidity Compiler' plugin
// But it will work fine in 'Solidity Unit Testing' plugin
import "remix_accounts.sol";
import "../Manager.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract TestManager is Manager {
 address payable acc0;
 address acc1;
 address acc2;
 address private creator = TestsAccounts.getAccount(3); // Creator account
 address payable receiver = payable(TestsAccounts.getAccount(4));
 uint collateralAmount = 1 ether;
 Manager manager;
 WBTC wbtc;
 BorrowContract borrowContract;
    /// 'beforeAll' runs before all other tests
    /// More special functions are: 'beforeEach', 'beforeAll', 'afterEach' & 'afterAll'
    function beforeAll() public {
        // <instantiate contract
        acc0 = payable(msg.sender);
        acc1 = TestsAccounts.getAccount(1);
        acc2 = TestsAccounts.getAccount(2);

    }
    function testDepositCollateralETH() public {
        // Depositing ETH collateral
        bool success = payable(address(manager)).send(collateralAmount);
        Assert.ok(success, "Sending ETH failed");

        manager.depositCollateralETH{value: collateralAmount}(receiver);

        // Check if the collateral amount is recorded correctly
        (uint256 ethBalance) = manager.checkEthBalance(receiver);
        Assert.equal(ethBalance, collateralAmount, "Collateral amount mismatch");
    }
    function testDepositCollateralBTC() public {
        // Approve and deposit WBTC collateral
        wbtc.approve(address(manager), collateralAmount);
        manager.depositCollateralBTC(receiver, collateralAmount);

        // Check if the WBTC balance of receiver is correct
        uint256 receiverBalance = wbtc.balanceOf(receiver);
        Assert.equal(receiverBalance, collateralAmount, "Collateral amount mismatch");
    }


       function testCheckAllowance() public {
        uint allowance = manager.checkAllowance(creator, receiver);
        Assert.equal(allowance, collateralAmount, "Allowance amount mismatch");
    }

    function testCheckEthBalance() public {
        // Check ETH balance of borrower
        uint balance = manager.checkEthBalance(receiver);
        uint expectedBalance = receiver.balance; // Getting actual balance
        Assert.equal(balance, expectedBalance, "ETH balance mismatch");
    }

    function testCheckWBTCBalance() public {
        // Check WBTC balance of borrower
        uint balance = manager.checkWBTCBalance(receiver);
        uint expectedBalance = wbtc.balanceOf(receiver); // Getting actual balance
        Assert.equal(balance, expectedBalance, "WBTC balance mismatch");
    }
        function testWithdrawETH() public {
        uint withdrawAmount = 1 ether;
        // Set available balance for user in ETH
        uint initialETHBalance = manager.checkEthBalance(receiver);

        // Withdraw ETH
        manager.withdrawFunds(receiver, false);
        // Check if the user's ETH balance decreased
        uint remainingBalance = manager.checkEthBalance(receiver);
        Assert.equal(remainingBalance, initialETHBalance - withdrawAmount, "ETH balance mismatch after withdrawal");
    }
    function checkSuccess2() public pure returns (bool) {
        // Use the return value (true or false) to test the contract
        return true;
    }

    function testGetBorrowContractWantBTC() public {
            address payable  addressOfBorrowContract = acc0;

            bool wantBTC = Manager.getBorrowContractStatus(addressOfBorrowContract);
            Assert.ok(wantBTC, "Want BTC should be true");
}
    
}
    