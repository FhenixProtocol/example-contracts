// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity >=0.8.13 <0.9.0;

import "@fhenixprotocol/contracts/FHE.sol";

contract Lottery {
    euint8 private winningNumber;
    euint32 private currentPrize;
    mapping (address => euint32) rewards;

    uint256 public endingTime;
    uint32 public ticketPrice;
    uint32 public ticketCount;

    event LotteryTicketBought(uint ticketNo);

    error TooEarly(uint timeEnding, uint timeNow);
    error TooLate(uint timeEnding, uint timeNow);
    error InsufficientPayment(uint32 price);

    constructor(uint32 _ticketPrice, inEuint8 memory initialRandom) {
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

    function buyTicket(inEuint8 calldata encryptedGuess) public payable onlyBeforeEnd {
        if (msg.value < ticketPrice) {
            revert InsufficientPayment(ticketPrice);
        }

        euint8 guess = FHE.asEuint8(encryptedGuess);

        // add message value to prize:
        currentPrize = currentPrize.add(FHE.asEuint32(msg.value));
        ticketCount += 1;

        // check winner:
        ebool isWinner = winningNumber.eq(guess);

        // alter the next winning number - This ensures that every subsequent winningNumber will be
        // unpredictable by someone who isn't involved with the paying party
        winningNumber = winningNumber.xor(guess);

        // store player's reward:
        rewards[msg.sender] = FHE.select(isWinner, rewards[msg.sender].add(currentPrize), rewards[msg.sender]);
        currentPrize = FHE.select(isWinner, FHE.asEuint32(0), currentPrize);

        emit LotteryTicketBought(ticketCount);
    }

    function checkRewards(bytes32 publicKey) public view onlyAfterEnd returns (bytes memory){
        // check if I have rewards
        return FHE.sealoutput(rewards[msg.sender], publicKey);
    }

    function redeemRewards() public onlyAfterEnd {
        euint32 reward = rewards[msg.sender];
        rewards[msg.sender] = FHE.asEuint32(0);

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
