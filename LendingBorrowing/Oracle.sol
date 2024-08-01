// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Oracle involving price feeds and Eth annual percentage reward feeds

contract Oracle {
    AggregatorV3Interface internal priceFeed;
    AggregatorV3Interface internal eth30DayAprFeed;
    AggregatorV3Interface internal btc1DayBaseRateFeed;

    // Sepolia Testnet 
    // BTC/ETH: 0x5fb1616F78dA7aFC9FF79e0371741a747D2a7F22: 20954713673392767000
    // 30-Day Eth Apr: 0xceA6Aa74E6A86a7f85B571Ce1C34f1A60B77CD29: 322131
    // Btc 1-day interest rate benchmark: 0x7DE89d879f581d0D56c5A7192BC9bDe3b7a9518e:  1450000
    constructor(address _priceFeedAddress, address _eth30DayAprFeedAddress, address _btc1DayBaseRateAddress) {
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        eth30DayAprFeed = AggregatorV3Interface(_eth30DayAprFeedAddress);
        btc1DayBaseRateFeed = AggregatorV3Interface(_btc1DayBaseRateAddress);
    }


    /**
    * @dev Get the current BTC price in Eth
    *
    * @return Current BTC/ETH price returned by oracle
    **/
    function getLatestBtcPriceInEth() public view returns (int) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }


    /**
    * @dev Get the current 30-day ETH apr
    *
    * @return Current 30-day ETH apr stored in 7 decimals returned by oracle
    **/
    function getLatestEth30DayApr() public view returns (int) {
        (, int ethApr, , , ) = eth30DayAprFeed.latestRoundData();
        return ethApr;
    }

    /**
    * @dev Get the current 1-Day BTC interest rate benchmark curve 
    *
    * @return Current 1-Day BTC interest rate benchmark curve stored in 8 decimals returned by oracle
    **/
    function getBtc1DayBaseRate() public view returns (int) {
        (, int ethApr, , , ) = btc1DayBaseRateFeed.latestRoundData();
        return ethApr;
    }
}