// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BorrowContract.sol";

contract  Manager {
  
    // For now, fixed exchange rate: 1 BTC = 10 ETH
    // Later, will change it to a dynamic exchange rate (oracle)
    uint exchangeRate = 10;

    // The owner of the manager, this address will be the pool address (assumption)
    address public owner;

    // BorrowContract list
    BorrowContract[] public borrowContracts;

    // Event to be emitted when a new BorrowContract is Initialized, not yet finalized
    event BorrowContractInitialized(address BorrowContractAddress, uint borrowAmount, bool wantBTC, uint exchangeRate);

    // Event to be emiited when a new BorrowContract is activated
    event BorrowContractActivated(address BorrowContractAddress, uint borrowAmount, bool wantBTC, uint exchangeRate);


    constructor() {
        owner = msg.sender;
    }


    // Function to get the current exchange rate
    function getExchangeRate() public view returns (uint) {
        return exchangeRate;
    }


    // Function to deploy a new BorrowContract, but not yet set the collateral
    // When the new borrow contract is initialized, the function will return the address of the new BorrowContract
    // And the caller can call the depositCollateral function to set the collateral
    function deployBorrowContract(uint brorowAmount, bool wantBTC) public returns (address) {
        uint currentExchangeRate = getExchangeRate();
        BorrowContract newBorrowContract = new BorrowContract(msg.sender, brorowAmount, wantBTC, currentExchangeRate);
        borrowContracts.push(newBorrowContract);
        emit BorrowContractInitialized(address(newBorrowContract), brorowAmount, wantBTC, currentExchangeRate);
        return address(newBorrowContract);
    }


    // Function to get the exchangeRate of a specific BorrowContract
    function getBorrowContractExchangeRate(address borrowContractAddress) public view returns (uint) {
      BorrowContract borrowContract = BorrowContract(borrowContractAddress);
      return borrowContract.exchangeRate();
    }

    // Function to get the needed collateral amount of a specific BorrowContract
    function getCollateralAmount(address borrowContractAddress) public view returns (uint) {
      BorrowContract borrowContract = BorrowContract(borrowContractAddress);
      return borrowContract.collateralAmount();
    }

    // Function to deposit collateral to a specific BorrowContract
    function depositCollateral(address borrowContractAddress) public payable {
      BorrowContract borrowContract = BorrowContract(borrowContractAddress);
      borrowContract.depositCollateral{value: msg.value}();
      borrowContracts.push(borrowContract);
      emit BorrowContractActivated(borrowContractAddress, borrowContract.borrowAmount(), borrowContract.wantBTC(), borrowContract.exchangeRate());
    }
}