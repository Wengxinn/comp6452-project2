// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract BorrowContract {

    // For now, fixed exchange rate: 1 BTC = 10 ETH
    uint public exchangeRate;

    address public creditors;

    address public borrower;

    uint public borrowAmount;

    bool public activated;

    uint256 public collateralAmount;

    // Wrapped BTC token
    IERC20 public wBtc;


    // true if borrowing BTC, false if borrowing ETH
    bool public wantBTC;


    event CollateralDeposited(address indexed borrower, uint amount, bool isETH);


    constructor(address _borrower, IERC20 _wBtc, uint _borrowAmount, bool _wantBTC, uint _collateralAmount, uint _exchangeRate, bool _activated) {
        borrower = _borrower;
        creditors = msg.sender;
        wBtc = _wBtc;
        borrowAmount = _borrowAmount;
        wantBTC = _wantBTC;
        collateralAmount = _collateralAmount;
        exchangeRate = _exchangeRate;
        activated = _activated;
    }


    function depositCollateralETH(address receiver) public payable {
        require((msg.value / 1 ether) == collateralAmount, "Incorrect ETH collateral amount");
        // Transfer the collateral to the contract
        payable(receiver).transfer(msg.value);
        emit CollateralDeposited(borrower, msg.value, wantBTC);
        activated = true;
    }

    function depositCollateralBTC(uint _wBtcCollateral) public {
        require(_wBtcCollateral == collateralAmount, "Incorrect BTC collateral amount");
        emit CollateralDeposited(borrower, _wBtcCollateral, wantBTC);
        activated = true;
    }



    modifier isOwner {
        require(msg.sender == borrower, "Only borrower can call this function");
        _;
    }
}
