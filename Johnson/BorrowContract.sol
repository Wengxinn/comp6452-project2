// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BorrowContract {

    // For now, fixed exchange rate: 1 BTC = 10 ETH
    uint public exchangeRate;

    address public borrower;
    uint public borrowAmount;

    bool public activated = false;


    // Needed collateral amount
    // If wantBTC is true, collateralAmount = borrowAmount * exchangeRate
    // If wantBTC is false, collateralAmount = borrowAmount / exchangeRate
    uint public collateralAmount;


    // true if borrowing BTC, false if borrowing ETH
    bool public wantBTC;


    event CollateralDeposited(address indexed borrower, uint amount, bool isETH);

    constructor(address _borrower, uint _borrowAmount, bool _wantBTC, uint _exchangeRate) {
        borrower = _borrower;
        borrowAmount = _borrowAmount;
        wantBTC = _wantBTC;
        exchangeRate = _exchangeRate;
        collateralAmount = wantBTC ? _borrowAmount * _exchangeRate : _borrowAmount / _exchangeRate;
    }

    function depositCollateral() public isOwner payable {
        require(msg.sender == borrower, "Only borrower can deposit collateral");
        if (wantBTC) {
            require(msg.value == collateralAmount, "Incorrect ETH collateral amount");
        } else {
            require(msg.value == collateralAmount, "Incorrect BTC collateral amount");
        }

        emit CollateralDeposited(borrower, msg.value, wantBTC);
        activated = true;
    }

    modifier isOwner {
        require(msg.sender == borrower, "Only borrower can call this function");
        _;
    }
}
