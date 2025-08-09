// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/LosslessBidding.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("TestToken", "TEST") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LosslessBiddingTest is Test {
    LosslessBidding public auction;
    MockToken public token;
    
    address public seller = makeAddr("seller");
    address public joe = makeAddr("joe");
    address public phil = makeAddr("phil");
    address public vee = makeAddr("vee");
    
    uint256 public constant STARTING_BID = 100e18;
    uint256 public constant AUCTION_DURATION = 1 days;

    event AuctionCreated(uint256 indexed auctionId, address indexed seller, uint256 startingBid, uint256 endTime);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount);
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 winningBid);

    function setUp() public {
        auction = new LosslessBidding();
        token = new MockToken();
        
        // Distribute tokens to test addresses (more tokens for complex scenarios)
        token.mint(seller, 100000e18);
        token.mint(joe, 100000e18);
        token.mint(phil, 100000e18);
        token.mint(vee, 100000e18);
        
        // Approve auction contract to spend tokens
        vm.prank(seller);
        token.approve(address(auction), type(uint256).max);
        vm.prank(joe);
        token.approve(address(auction), type(uint256).max);
        vm.prank(phil);
        token.approve(address(auction), type(uint256).max);
        vm.prank(vee);
        token.approve(address(auction), type(uint256).max);
    }

    //CREATE AUCTION TESTS
    function testCreateAuction() public {
        vm.expectEmit(true, true, false, false);
        emit AuctionCreated(0, seller, STARTING_BID, block.timestamp + AUCTION_DURATION);
        
        vm.prank(seller);
        uint256 auctionId = auction.createAuction(token, STARTING_BID, AUCTION_DURATION);
        
        assertEq(auctionId, 0);
        
        (address auctionSeller, IERC20 auctionToken, uint256 startingBid, uint256 currentBid, 
         address currentBidder, uint256 endTime, bool active) = auction.auctions(auctionId);
        
        assertEq(auctionSeller, seller);
        assertEq(address(auctionToken), address(token));
        assertEq(startingBid, STARTING_BID);
        assertEq(currentBid, 0);
        assertEq(currentBidder, address(0));
        assertEq(endTime, block.timestamp + AUCTION_DURATION);
        assertTrue(active);
    }

    function testCreateAuctionWithZeroStartingBid() public {
        vm.prank(seller);
        vm.expectRevert("Invalid starting bid");
        auction.createAuction(token, 0, AUCTION_DURATION);
    }

    function testCreateAuctionWithZeroDuration() public {
        vm.prank(seller);
        vm.expectRevert("Invalid duration");
        auction.createAuction(token, STARTING_BID, 0);
    }

    //BIDDING TESTS
    function testFirstBid() public {
        uint256 auctionId = _createAuction();
        uint256 bidAmount = STARTING_BID;
        
        uint256 balanceBefore = token.balanceOf(joe);
        
        vm.expectEmit(true, true, false, false);
        emit BidPlaced(auctionId, joe, bidAmount);
        
        vm.prank(joe);
        auction.placeBid(auctionId, bidAmount);
        
        // Check auction state
        (, , , uint256 currentBid, address currentBidder, ,) = auction.auctions(auctionId);
        assertEq(currentBid, bidAmount);
        assertEq(currentBidder, joe);
        
        // Check token transfer
        assertEq(token.balanceOf(joe), balanceBefore - bidAmount);
        assertEq(token.balanceOf(address(auction)), bidAmount);
    }

    function testSecondBidLosslessLogic() public {
        uint256 auctionId = _createAuction();
        
        // First bid
        uint256 firstBid = STARTING_BID;
        vm.prank(joe);
        auction.placeBid(auctionId, firstBid);
        
        // Second bid (must be at least 111% of first bid)
        uint256 secondBid = (firstBid * 111) / 100; // 111 tokens
        uint256 joeBalanceBefore = token.balanceOf(joe);
        uint256 philBalanceBefore = token.balanceOf(phil);
        
        vm.prank(phil);
        auction.placeBid(auctionId, secondBid);
        
        // Check auction state
        (, , , uint256 currentBid, address currentBidder, ,) = auction.auctions(auctionId);
        assertEq(currentBid, secondBid);
        assertEq(currentBidder, phil);
        
        // Check lossless logic: joe gets original bid + 10% bonus
        uint256 expectedRefund = firstBid + (secondBid * 10 / 100); // 100 + 11.1 = 111.1
        assertEq(token.balanceOf(joe), joeBalanceBefore + expectedRefund);
        assertEq(token.balanceOf(phil), philBalanceBefore - secondBid);
    }

    function testMultipleBidsLosslessChain() public {
        uint256 auctionId = _createAuction();
        
        // Bid 1: 100 tokens
        vm.prank(joe);
        auction.placeBid(auctionId, 100e18);
        
        // Bid 2: 111 tokens (111% of 100)
        vm.prank(phil);
        auction.placeBid(auctionId, 111e18);
        
        // Bid 3: 123.21 tokens (111% of 111)
        uint256 thirdBid = 123_21e16; // 123.21 tokens
        uint256 philBalanceBefore = token.balanceOf(phil);
        
        vm.prank(vee);
        auction.placeBid(auctionId, thirdBid);
        
        // Check that phil got refunded with bonus
        uint256 expectedRefund = 111e18 + (thirdBid * 10 / 100); // 111 + 12.321 = 123.321
        assertEq(token.balanceOf(phil), philBalanceBefore + expectedRefund);
        
        // Check auction state
        (, , , uint256 currentBid, address currentBidder, ,) = auction.auctions(auctionId);
        assertEq(currentBid, thirdBid);
        assertEq(currentBidder, vee);
    }

    function testBidTooLow() public {
        uint256 auctionId = _createAuction();
        
        // First bid
        vm.prank(joe);
        auction.placeBid(auctionId, STARTING_BID);
        
        // Try to bid too low
        uint256 lowBid = STARTING_BID + 1; // Should need at least 111 tokens
        vm.prank(phil);
        vm.expectRevert(LosslessBidding.BidTooLow.selector);
        auction.placeBid(auctionId, lowBid);
    }

    function testSellerCannotBid() public {
        uint256 auctionId = _createAuction();
        
        vm.prank(seller);
        vm.expectRevert("Seller cannot bid");
        auction.placeBid(auctionId, STARTING_BID);
    }

    function testBidOnInactiveAuction() public {
        uint256 auctionId = _createAuction();
        
        // End the auction first
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        auction.endAuction(auctionId);
        
        vm.prank(joe);
        vm.expectRevert(LosslessBidding.AuctionNotActive.selector);
        auction.placeBid(auctionId, STARTING_BID);
    }

    function testBidAfterEndTime() public {
        uint256 auctionId = _createAuction();
        
        // Fast forward past end time
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        
        vm.prank(joe);
        vm.expectRevert(LosslessBidding.AuctionAlreadyEnded.selector);
        auction.placeBid(auctionId, STARTING_BID);
    }

    // END AUCTION TESTS
    function testEndAuctionWithBids() public {
        uint256 auctionId = _createAuction();
        
        // Place some bids
        vm.prank(joe);
        auction.placeBid(auctionId, 100e18);
        
        vm.prank(phil);
        auction.placeBid(auctionId, 111e18);
        
        uint256 sellerBalanceBefore = token.balanceOf(seller);
        
        // Fast forward and end auction
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        
        vm.expectEmit(true, true, false, false);
        emit AuctionEnded(auctionId, phil, 111e18);
        
        auction.endAuction(auctionId);
        
        // Check seller payment (111 - 11.1 = 99.9 tokens)
        uint256 expectedPayment = 111e18 - (111e18 * 10 / 100);
        assertEq(token.balanceOf(seller), sellerBalanceBefore + expectedPayment);
        
        // Check auction is inactive
        (, , , , , , bool active) = auction.auctions(auctionId);
        assertFalse(active);
    }

    function testEndAuctionWithNoBids() public {
        uint256 auctionId = _createAuction();
        
        uint256 sellerBalanceBefore = token.balanceOf(seller);
        
        // Fast forward and end auction
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        
        vm.expectEmit(true, true, false, false);
        emit AuctionEnded(auctionId, address(0), 0);
        
        auction.endAuction(auctionId);
        
        // Seller should receive nothing
        assertEq(token.balanceOf(seller), sellerBalanceBefore);
    }

    function testEndAuctionTooEarly() public {
        uint256 auctionId = _createAuction();
        
        vm.expectRevert(LosslessBidding.NotYetEnded.selector);
        auction.endAuction(auctionId);
    }

    function testEndInactiveAuction() public {
        uint256 auctionId = _createAuction();
        
        // End auction once
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        auction.endAuction(auctionId);
        
        // Try to end again
        vm.expectRevert(LosslessBidding.AuctionNotActive.selector);
        auction.endAuction(auctionId);
    }

    // VIEW FUNCTION TESTS
    function testGetMinimumBid() public {
        uint256 auctionId = _createAuction();
        
        // Before any bids
        assertEq(auction.getMinimumBid(auctionId), STARTING_BID);
        
        // After first bid
        vm.prank(joe);
        auction.placeBid(auctionId, STARTING_BID);
        
        uint256 expectedMinimum = STARTING_BID + (STARTING_BID * 11 / 100);
        assertEq(auction.getMinimumBid(auctionId), expectedMinimum);
    }

    function testIsActive() public {
        uint256 auctionId = _createAuction();
        
        assertTrue(auction.isActive(auctionId));
        
        // After end time
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        assertFalse(auction.isActive(auctionId));
        
        // After ending auction
        auction.endAuction(auctionId);
        assertFalse(auction.isActive(auctionId));
    }

    function testGetTimeRemaining() public {
        uint256 auctionId = _createAuction();
        
        assertEq(auction.getTimeRemaining(auctionId), AUCTION_DURATION);
        
        // Fast forward halfway
        vm.warp(block.timestamp + AUCTION_DURATION / 2);
        assertEq(auction.getTimeRemaining(auctionId), AUCTION_DURATION / 2);
        
        // Past end time
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        assertEq(auction.getTimeRemaining(auctionId), 0);
    }

    //INTEGRATION TESTS 
    function testCompleteAuctionFlow() public {
        uint256 auctionId = _createAuction();
        
        // Bid sequence: 100 -> 111 -> 124  
        vm.prank(joe);
        auction.placeBid(auctionId, 100e18);
        // Contract: 100 tokens
        
        vm.prank(phil); 
        auction.placeBid(auctionId, 111e18);
        // Contract receives: 111, pays joe: 100+11=111, remaining: 100
        
        vm.prank(vee);
        auction.placeBid(auctionId, 124e18);
        // Contract receives: 124, pays phil: 111+12=123, remaining: 101
        
        uint256 sellerBalanceBefore = token.balanceOf(seller);
        uint256 contractBalance = token.balanceOf(address(auction));
        console.log("Contract balance before ending:", contractBalance);
        
        // End auction - seller gets whatever is left in contract
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        auction.endAuction(auctionId);
        
        // Seller should get the remaining contract balance
        assertEq(token.balanceOf(seller), sellerBalanceBefore + contractBalance);
        
        // Contract should be empty after auction ends
        assertEq(token.balanceOf(address(auction)), 0);
        
        // Auction should be inactive
        assertFalse(auction.isActive(auctionId));
    }

    // Helper function
    function _createAuction() internal returns (uint256) {
        vm.prank(seller);
        return auction.createAuction(token, STARTING_BID, AUCTION_DURATION);
    }

    // FUZZ TESTS
    function testFuzzBidding(uint256 startingBid, uint256 firstBid, uint256 secondBid) public {
        startingBid = bound(startingBid, 1e18, 100e18); 
        firstBid = bound(firstBid, startingBid, 1000e18); 
        secondBid = bound(secondBid, (firstBid * 111) / 100, 2000e18); 
        
        // Ensure bidders have enough tokens
        token.mint(joe, secondBid * 2);
        token.mint(phil, secondBid * 2);
        
        // Setup
        vm.prank(seller);
        uint256 auctionId = auction.createAuction(token, startingBid, AUCTION_DURATION);
        
        // First bid
        vm.prank(joe);
        auction.placeBid(auctionId, firstBid);
        
        uint256 joeBalanceBefore = token.balanceOf(joe);
        
        // Second bid
        vm.prank(phil);
        auction.placeBid(auctionId, secondBid);
        
        // Verify lossless property
        uint256 expectedRefund = firstBid + (secondBid * 10 / 100);
        assertEq(token.balanceOf(joe), joeBalanceBefore + expectedRefund);
    }
}