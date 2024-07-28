// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Individual borrow contract

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

    // True if borrowing BTC, false if borrowing ETH
    bool public wantBTC;

    // ===========================================================================================================================================================

    event CollateralDeposited(address indexed borrower, uint amount, bool isETH);

    // ===========================================================================================================================================================

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


    /**
    * @dev Desposit collateral (specified in the msg.value) in ETH to the receiver
    *
    * @param receiver Payable address of the receiver of the collateral
    *
    **/
    function depositCollateralETH(address receiver) public payable {
        require((msg.value / 1 ether) == collateralAmount, "Incorrect ETH collateral amount");

        // Transfer the collateral to the contract
        (bool success, ) = payable(receiver).call{value: msg.value}("");
        require(success, "Transfer failed");

        emit CollateralDeposited(borrower, msg.value, wantBTC);
        activated = true;
    }


    /**
    * @dev Desposit collateral in BTC from the borrower's account to the receiver's account
    *
    * @param receiver Address of the receiver of the collateral
    * @param _wBtcCollateral Amount of collateral to be deposited
    *
    **/
    function depositCollateralBTC(address receiver, uint _wBtcCollateral) public {
        require(_wBtcCollateral == collateralAmount, "Incorrect BTC collateral amount");

        // Transfer the collateral from borrower's account to receiver's account
        require(wBtc.transferFrom(borrower, receiver, collateralAmount), "WBTC transfer failed");
        emit CollateralDeposited(borrower, _wBtcCollateral, wantBTC);
        activated = true;
    }
}
