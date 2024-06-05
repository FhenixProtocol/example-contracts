// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity >=0.8.13 <0.9.0;

import "@fhenixprotocol/contracts/FHE.sol";

contract Lottery {
    uint8 private winningNumber;
    uint32 private currentPrize;
    mapping (address => uint32) rewards;

    uint256 public endingTime;
    uint32 public ticketPrice;
    uint32 public ticketCount;

    event LotteryTicketBought(uint ticketNo);

    error TooEarly(uint timeEnding, uint timeNow);
    error TooLate(uint timeEnding, uint timeNow);
    error InsufficientPayment(uint32 price);

    constructor(uint32 _ticketPrice, uint8 initialRandom) {
        // at first, the contract deployer knows the winning number, but he can only win the prize he put in
        // once another player buys a ticket, he doesn't know the winning number anymore
        winningNumber = FHE.asEuint8(initialRandom);

        // endingTime = block.timestamp + 10 days;
        // for testing purposes:
        endingTime = block.timestamp + 20 seconds;
        ticketPrice = _ticketPrice;
        currentPrize = FHE.asEuint32(0);
    }

    function fundPrize() public payable {
        currentPrize = FHE.add(currentPrize, FHE.asEuint32(msg.value));
    }

    function buyTicket(uint8 encryptedGuess) public payable onlyBeforeEnd {
        if (msg.value < ticketPrice) {
            revert InsufficientPayment(ticketPrice);
        }

        uint8 guess = FHE.asEuint8(encryptedGuess);

        // add message value to prize:
        currentPrize = currentPrize + FHE.asEuint32(msg.value);
        ticketCount += 1;

        // check winner:
        bool isWinner = winningNumber == guess;

        // alter the next winning number - This ensures that every subsequent winningNumber will be
        // unpredictable by someone who isn't involved with the paying party
        winningNumber = winningNumber ^ guess;

        // store player's reward:
        rewards[msg.sender] = isWinner ? rewards[msg.sender] + currentPrize : rewards[msg.sender];
        currentPrize = isWinner ? 0 : currentPrize;

        emit LotteryTicketBought(ticketCount);
    }

    function checkRewards(bytes32 publicKey) public view onlyAfterEnd returns (bytes memory){
        // Check if the sender has rewards
        uint32 reward = rewards[msg.sender];
        
        // Seal the reward output using the provided public key
        bytes memory sealedReward = FHE.sealoutput(reward, publicKey);
        
        // Return the sealed reward
        return sealedReward;
    }

    function redeemRewards() public onlyAfterEnd {
        uint32 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;

        payable(msg.sender).transfer(FHE.decrypt(reward));
    }

    modifier onlyBeforeEnd() {
        if (block.timestamp >= endingTime) revert TooLate(endingTime, block.timestamp);
        _;
    }

    modifier onlyAfterEnd() {
        if (block.timestamp < endingTime) revert TooEarly(endingTime, block.timestamp);
        _;
    }
}
