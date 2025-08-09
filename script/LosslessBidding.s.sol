// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {LosslessBidding} from "../src/LosslessBidding.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for demo purposes (only deploy on testnets)
contract DemoToken is ERC20 {
    constructor() ERC20("DemoToken", "DEMO") {
        _mint(msg.sender, 1000000 * 10**18); // Mint 1M tokens to deployer
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LosslessBiddingScript is Script {
    LosslessBidding public auction;
    DemoToken public demoToken;
    
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying contracts with address:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the LosslessBidding contract
        auction = new LosslessBidding();
        console.log("LosslessBidding deployed at:", address(auction));

        // Only deploy demo token on testnets (not mainnet)
        uint256 chainId = block.chainid;
        console.log("Chain ID:", chainId);
        
        // Deploy demo token for testing (avoid on mainnet)
        if (chainId != 1 && chainId != 137 && chainId != 56) { 
            demoToken = new DemoToken();
            console.log("DemoToken deployed at:", address(demoToken));
            
            // Demonstrate contract usage
            _demonstrateUsage();
        } else {
            console.log("Mainnet detected - skipping demo token deployment");
            console.log("Use existing ERC20 tokens for auctions");
        }

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    function _demonstrateUsage() internal {
        console.log("\n--- Demonstrating LosslessBidding Usage ---");
        
        // Create a sample auction
        uint256 startingBid = 100 * 10**18; // 100 tokens
        uint256 duration = 1 hours;
        
        uint256 auctionId = auction.createAuction(
            IERC20(address(demoToken)), 
            startingBid, 
            duration
        );
        
        console.log("Created auction with ID:", auctionId);
        console.log("Starting bid:", startingBid);
        console.log("Duration:", duration, "seconds");
        
        // Get auction details
        (
            address seller,
            IERC20 token,
            uint256 auctionStartingBid,
            uint256 currentBid,
            address currentBidder,
            uint256 endTime,
            bool active
        ) = auction.auctions(auctionId);
        
        console.log("Auction seller:", seller);
        console.log("Auction token:", address(token));
        console.log("Current bid:", currentBid);
        console.log("Current bidder:", currentBidder);
        console.log("End time:", endTime);
        console.log("Active:", active);
        console.log("Minimum bid required:", auction.getMinimumBid(auctionId));
        console.log("Time remaining:", auction.getTimeRemaining(auctionId));
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("LosslessBidding:", address(auction));
        
        if (address(demoToken) != address(0)) {
            console.log("DemoToken:", address(demoToken));
            console.log("Demo token supply:", demoToken.totalSupply());
        }
        
        console.log("Next auction ID:", auction.nextAuctionId());
        console.log("Bonus percentage:", auction.BONUS_PERCENTAGE());
        
        console.log("\n=== USAGE INSTRUCTIONS ===");
        console.log("1. To create an auction:");
        console.log("   auction.createAuction(tokenAddress, startingBid, duration)");
        console.log("\n2. To place a bid:");
        console.log("   token.approve(auctionAddress, bidAmount)");
        console.log("   auction.placeBid(auctionId, bidAmount)");
        console.log("\n3. To end an auction:");
        console.log("   auction.endAuction(auctionId)");
        console.log("\n4. View functions:");
        console.log("   auction.getAuction(auctionId)");
        console.log("   auction.getMinimumBid(auctionId)");
        console.log("   auction.isActive(auctionId)");
        console.log("   auction.getTimeRemaining(auctionId)");
    }

    // Additional helper function for creating auctions post-deployment
    function createSampleAuction(
        address tokenAddress,
        uint256 startingBid,
        uint256 duration
    ) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        uint256 auctionId = auction.createAuction(
            IERC20(tokenAddress),
            startingBid,
            duration
        );
        
        console.log("Created auction ID:", auctionId);
        console.log("Starting bid:", startingBid);
        console.log("Duration:", duration, "seconds");
        
        vm.stopBroadcast();
    }
}