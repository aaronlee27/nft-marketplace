// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test, console } from "forge-std/Test.sol";
import { Marketplace } from "../../src/Marketplace.sol";
import { NFT } from "./ERC721.sol";
import { Token } from "./ERC20.sol";

contract MarketplaceUnitTest is Test {
    Marketplace marketplace;

    address public feeCollector = makeAddr("feeCollector");

    uint256 public constant MINT_PER_PERSON = 10;
    uint256 public constant NUM_PLAYERS = 3;
    uint256 public constant INITIAL_AMOUNT = 10000 ether;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address[3] players = [
        makeAddr("alice"),
        makeAddr("bob"),
        makeAddr("mark")
    ];

    mapping (address => mapping(address => uint256[])) nftOwners;

    uint256 public fee = 1000;
    NFT nft1;
    NFT nft2;

    Token token1;
    Token token2;

    function setUp() external {
        marketplace = new Marketplace(feeCollector, fee);
        nft1 = new NFT("NFT1", "NFT1");
        nft2 = new NFT("NFT2", "NFT2");
        token1 = new Token("Token1", "TK1");
        token2 = new Token("Token2", "TK2");

        for (uint i = 0; i < MINT_PER_PERSON; i++){
            for (uint j = 0; j < NUM_PLAYERS; j++){
                vm.broadcast(players[j]);
                nft1.mint();
            }
        }

        for (uint i = 0; i < MINT_PER_PERSON; i++){
            for (uint j = NUM_PLAYERS - 1; j >= 0; j--){
                vm.broadcast(players[j]);
                nft2.mint();
                if (j == 0) break;
            }
        }

        for (uint i = 0; i < NUM_PLAYERS; i++){
            token1.mint(players[i], INITIAL_AMOUNT);
            token2.mint(players[i], INITIAL_AMOUNT);
            vm.deal(players[i], INITIAL_AMOUNT);
        }


    }

    function testCanHaveAnOrder() external {
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        vm.startPrank(players[0]);

        NFT(nft).approve(address(marketplace), tokenId);

        marketplace.sellOrder(
            nft,
            tokenId,
            token,
            price,
            expired
        );
        vm.stopPrank();

        // Assertion
        // 1. Owner of nft is marketplace
        // 2. s_orderId increase to 1
        // 3. orders mapping update

        assert(NFT(nft).ownerOf(tokenId) == address(marketplace));
        assert(marketplace.getOrderId() == 1);
        assert(marketplace.getOrder(0).available == true);
        assert(marketplace.getOrder(0).orderType == Marketplace.OrderType.SELL);
        assert(marketplace.getOrder(0).proposer == players[0]);
        assert(marketplace.getOrder(0).nft == nft);
        assert(marketplace.getOrder(0).tokenId == tokenId);
        assert(marketplace.getOrder(0).token == token);
        assert(marketplace.getOrder(0).price == price);
        assert(marketplace.getOrder(0).expired == expired);
    }

    function testCantHaveOrderIfNotOwner() external {
        address nft = address(nft1);
        uint256 tokenId = 1;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        vm.startPrank(players[0]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceNFTNotOwner.selector,
                players[0],
                nft,
                tokenId
            )
        );

        marketplace.sellOrder(
            nft,
            tokenId,
            token,
            price,
            expired
        );
        vm.stopPrank();
    }

    function testCantHaveOrderIfExpiredTimeInvalid() external {
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp;

        vm.startPrank(players[0]);

        NFT(nft).approve(address(marketplace), tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceInvalidOrder.selector
            )
        );
        
        marketplace.sellOrder(
            nft,
            tokenId,
            token,
            price,
            expired
        );
        vm.stopPrank();
    }

    function placeOrder(uint256 account, address nft, uint256 tokenId, address token, uint256 price, uint256 expired) internal returns (uint256){
        vm.startPrank(players[account]);

        NFT(nft).approve(address(marketplace), tokenId);

        uint256 orderId = marketplace.sellOrder(
            nft,
            tokenId,
            token,
            price,
            expired
        );
        vm.stopPrank();

        return orderId;
    }

    function testCanCancelOrder() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        vm.startPrank(players[account]);

        marketplace.cancelOrder(orderId);

        vm.stopPrank();
    }

    function testCantCancelOrderIfCancelledBefore() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        vm.startPrank(players[account]);

        marketplace.cancelOrder(orderId);

        vm.stopPrank();

        vm.startPrank(players[account]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceOrderNotAvailable.selector,
                orderId
            )
        );

        marketplace.cancelOrder(orderId);

        vm.stopPrank();
    }

    function testCantCancelOrderIfOrderFulfilled() external { // test after test fulfill function
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        uint256 buyer = 1;

        fulfillERC20(buyer, orderId);

        vm.startPrank(players[account]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceOrderNotAvailable.selector,
                orderId
            )
        );

        marketplace.cancelOrder(orderId);

        vm.stopPrank();
    }

    function testCantCancelOrderIfOrderExpired() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        vm.startPrank(players[account]);

        vm.warp(block.timestamp + 101 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceOrderExpired.selector,
                orderId
            )
        );

        marketplace.cancelOrder(orderId);
    
        vm.stopPrank();
    }


    function testCantCancelOrderIfOrderNotOwner() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        vm.startPrank(players[1]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceUserNotPermitted.selector,
                players[1],
                orderId
            )
        );

        marketplace.cancelOrder(orderId);

        vm.stopPrank();
    }

    function testCantCancelIfOrderIdInvalid() external {
        vm.startPrank(players[0]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceOrderIdInvalid.selector,
                100
            )
        );

        marketplace.cancelOrder(100);


        vm.stopPrank();
    }

    function cancelOrder(uint256 account, uint256 orderId) internal {
        vm.startPrank(players[account]);

        marketplace.cancelOrder(orderId);

        vm.stopPrank();
    }

    function testCanFulfillOrderWithERC20() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        uint256 buyer = 1;

        vm.startPrank(players[buyer]);

        Token(token).approve(address(marketplace), price);
        marketplace.fulfillSellOrder(orderId);

        vm.stopPrank();

        // Assertion
        // 1. NFt owner change to player[1]
        // 2. Balance change (player[0] and player[1])
        // 3. order fulfilled (so that not available anymore)

        console.log("ownerOf", NFT(nft).ownerOf(tokenId)); 
        console.log("balanceOf", Token(token).balanceOf(players[account]));
        console.log("balanceOf", Token(token).balanceOf(players[buyer]));
        console.log("order", marketplace.getOrder(orderId).available);


        assert(NFT(nft).ownerOf(tokenId) == players[buyer]);
        assert(Token(token).balanceOf(players[account]) == INITIAL_AMOUNT + price);
        assert(Token(token).balanceOf(players[buyer]) == INITIAL_AMOUNT - price);
        assert(marketplace.getOrder(orderId).available == false);
    }

    function testCanFulfillOrderWithETH() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = ETH;
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        uint256 buyer = 1;

        

        vm.startPrank(players[buyer]);

        marketplace.fulfillSellOrder{value: price}(orderId);

        vm.stopPrank();

        // Assertion
        // 1. NFt owner change to player[1]
        // 2. Balance change (player[0] and player[1])
        // 3. order fulfilled (so that not available anymore)


        assert(NFT(nft).ownerOf(tokenId) == players[buyer]);
        assert(players[account].balance == INITIAL_AMOUNT + price);
        assert(players[buyer].balance == INITIAL_AMOUNT - price);
        assert(marketplace.getOrder(orderId).available == false);

    }

    function testCantFulfillOrderIfNotSendEnoughETH() external {
         uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = ETH;
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        uint256 buyer = 1;

        

        vm.startPrank(players[buyer]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketplaceInsufficentAmount.selector
            )
        );
        marketplace.fulfillSellOrder{value: price - 1}(orderId);

        vm.stopPrank();
    }

    function testCantFulfillOrderIfOwnerOrder() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        uint256 buyer = 0;

        vm.startPrank(players[buyer]);
        Token(token).approve(address(marketplace), price);


        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceUserNotPermitted.selector,
                players[buyer],
                orderId
            )
        );

        marketplace.fulfillSellOrder(orderId);

        vm.stopPrank();
    }

    function testCantFulfillOrderIfOrderExpired() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        uint256 buyer = 1;

        vm.startPrank(players[buyer]);

        vm.warp(block.timestamp + 101 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceOrderExpired.selector,
                orderId
            )
        );

        marketplace.fulfillSellOrder(orderId);

        vm.stopPrank();
    }

    function testCantFulfillOrderIfOrderCancelled() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        cancelOrder(account, orderId);

        uint256 buyer = 1;

        vm.startPrank(players[buyer]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceOrderNotAvailable.selector,
                orderId
            )
        );

        marketplace.fulfillSellOrder(orderId);

        vm.stopPrank();
    }

    function testCantFulfillOrderIfOrderFulfilled() external {
        uint256 account = 0;
        address nft = address(nft1);
        uint256 tokenId = 0;
        address token = address(token1);
        uint256 price = 276 ether;
        uint256 expired = block.timestamp + 100 days;

        uint256 orderId = placeOrder(account, nft, tokenId, token, price, expired);

        uint256 buyer = 1;

        vm.startPrank(players[buyer]);

        Token(token).approve(address(marketplace), price);
        marketplace.fulfillSellOrder(orderId);

        vm.stopPrank();

        vm.startPrank(players[buyer]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceOrderNotAvailable.selector,
                orderId
            )
        );

        marketplace.fulfillSellOrder(orderId);

        vm.stopPrank();
    }

    function fulfillERC20(uint256 account, uint256 orderId) internal {
        vm.startPrank(players[account]);

        Token(marketplace.getOrder(orderId).token).approve(address(marketplace), marketplace.getOrder(orderId).price);

        marketplace.fulfillSellOrder(orderId);

        vm.stopPrank();
    }

    



}