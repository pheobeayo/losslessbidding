// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LosslessBidding is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Auction {
        address seller;
        IERC20 token;
        uint256 startingBid;
        uint256 currentBid;
        address currentBidder;
        uint256 endTime;
        bool active;
    }

    mapping(uint256 => Auction) public auctions;
    uint256 public nextAuctionId;
    uint256 public constant BONUS_PERCENTAGE = 10; // 10% bonus

    event AuctionCreated(uint256 indexed auctionId, address indexed seller, uint256 startingBid, uint256 endTime);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount);
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 winningBid);

    error AuctionNotActive();
    error AuctionAlreadyEnded();
    error BidTooLow();
    error NotYetEnded();

    // 1. CREATE AUCTION
    function createAuction(
        IERC20 token,
        uint256 startingBid,
        uint256 duration
    ) external returns (uint256) {
        require(startingBid > 0, "Invalid starting bid");
        require(duration > 0, "Invalid duration");

        uint256 auctionId = nextAuctionId++;
        
        auctions[auctionId] = Auction({
            seller: msg.sender,
            token: token,
            startingBid: startingBid,
            currentBid: 0,
            currentBidder: address(0),
            endTime: block.timestamp + duration,
            active: true
        });

        emit AuctionCreated(auctionId, msg.sender, startingBid, block.timestamp + duration);
        return auctionId;
    }

    // 2. PLACE BID
    function placeBid(uint256 auctionId, uint256 bidAmount) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        
        if (!auction.active) revert AuctionNotActive();
        if (block.timestamp >= auction.endTime) revert AuctionAlreadyEnded();
        require(msg.sender != auction.seller, "Seller cannot bid");

        // Calculate minimum bid required
        uint256 minimumBid = auction.currentBid > 0 
            ? auction.currentBid + (auction.currentBid * 11 / 100) // Current bid + 11% (10% bonus + 1% increment)
            : auction.startingBid;
        
        if (bidAmount < minimumBid) revert BidTooLow();

        // Transfer new bid to contract
        auction.token.safeTransferFrom(msg.sender, address(this), bidAmount);

        // Refund previous bidder with bonus (if exists)
        if (auction.currentBidder != address(0)) {
            uint256 refundAmount = auction.currentBid;
            uint256 bonusAmount = bidAmount * BONUS_PERCENTAGE / 100;
            
            auction.token.safeTransfer(auction.currentBidder, refundAmount + bonusAmount);
        }

        // Update auction state
        auction.currentBid = bidAmount;
        auction.currentBidder = msg.sender;

        emit BidPlaced(auctionId, msg.sender, bidAmount);
    }

    // 3. END AUCTION
    function endAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        
        if (!auction.active) revert AuctionNotActive();
        if (block.timestamp < auction.endTime) revert NotYetEnded();

        auction.active = false;

        if (auction.currentBidder != address(0)) {
            // Pay seller whatever remains in the contract for this auction
            // (The bonus was already paid out when the last bid was placed)
            uint256 contractBalance = auction.token.balanceOf(address(this));
            
            auction.token.safeTransfer(auction.seller, contractBalance);
            emit AuctionEnded(auctionId, auction.currentBidder, auction.currentBid);
        } else {
            emit AuctionEnded(auctionId, address(0), 0);
        }
    }

    // 4. VIEW FUNCTIONS
    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    function getMinimumBid(uint256 auctionId) external view returns (uint256) {
        Auction storage auction = auctions[auctionId];
        return auction.currentBid > 0 
            ? auction.currentBid + (auction.currentBid * 11 / 100)
            : auction.startingBid;
    }

    function isActive(uint256 auctionId) external view returns (bool) {
        Auction storage auction = auctions[auctionId];
        return auction.active && block.timestamp < auction.endTime;
    }

    function getTimeRemaining(uint256 auctionId) external view returns (uint256) {
        Auction storage auction = auctions[auctionId];
        return block.timestamp >= auction.endTime ? 0 : auction.endTime - block.timestamp;
    }
}