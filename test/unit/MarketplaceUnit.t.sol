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

        // Assertion
        // 1. NFt owner change to player[0]
        // 2. order mapping change

        assert(NFT(nft).ownerOf(tokenId) == players[account]);
        assert(marketplace.getOrder(orderId).available == false);
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

        fulfillSellERC20(buyer, orderId);

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

    function testCanFulfillSellOrderWithERC20() external {
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

    function testCanFulfillSellOrderWithETH() external {
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

    function testCantFulfillSellOrderIfNotSendEnoughETH() external {
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

    function testCantFulfillSellOrderIfOwnerOrder() external {
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

    function testCantFulfillSellOrderIfOrderExpired() external {
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

    function testCantFulfillSellOrderIfOrderCancelled() external {
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

    function testCantFulfillSellOrderIfOrderFulfilled() external {
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

    function fulfillSellERC20(uint256 account, uint256 orderId) internal {
        vm.startPrank(players[account]);

        Token(marketplace.getOrder(orderId).token).approve(address(marketplace), marketplace.getOrder(orderId).price);

        marketplace.fulfillSellOrder(orderId);

        vm.stopPrank();
    }

    function fulfillSellETH(uint256 account, uint256 orderId) internal {
        vm.startPrank(players[account]);

        marketplace.fulfillSellOrder{value: marketplace.getOrder(orderId).price}(orderId);

        vm.stopPrank();
    }

    function testCanBuyOrderWithERC20() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = address(token1);
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        vm.startPrank(players[account]);

        Token(_token).approve(address(marketplace), _price);
        marketplace.buyOrder(_nft, _tokenId, _token, _price, _expired);

        vm.stopPrank();

        // Assertion
        // 1. Contract balance of token increase, player decrese
        // 2. Mapping check
        // 3. s_orderId equals 1

        assert(Token(_token).balanceOf(address(marketplace)) == _price);   
        assert(Token(_token).balanceOf(players[account]) == INITIAL_AMOUNT - _price);
        assert(marketplace.getOrderId() == 1);
        assert(marketplace.getOrder(0).available == true);
        assert(marketplace.getOrder(0).orderType == Marketplace.OrderType.BUY);
        assert(marketplace.getOrder(0).proposer == players[0]);
        assert(marketplace.getOrder(0).nft == _nft);
        assert(marketplace.getOrder(0).tokenId == _tokenId);
        assert(marketplace.getOrder(0).token == _token);
        assert(marketplace.getOrder(0).price == _price);
        assert(marketplace.getOrder(0).expired == _expired);
    }

    function testCanBuyOrderWithETH() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = ETH;
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        vm.startPrank(players[account]);

        marketplace.buyOrder{value: _price}(_nft, _tokenId, _token, _price, _expired);

        vm.stopPrank();

        // Assertion
        // 1. Contract balance of token increase, player decrese
        // 2. Mapping check
        // 3. s_orderId equals 1

        assert(address(marketplace).balance == _price);
        assert(players[account].balance == INITIAL_AMOUNT - _price);
        assert(marketplace.getOrderId() == 1);
        assert(marketplace.getOrder(0).available == true);
        assert(marketplace.getOrder(0).orderType == Marketplace.OrderType.BUY);
        assert(marketplace.getOrder(0).proposer == players[0]);
        assert(marketplace.getOrder(0).nft == _nft);
        assert(marketplace.getOrder(0).tokenId == _tokenId);
        assert(marketplace.getOrder(0).token == _token);
        assert(marketplace.getOrder(0).price == _price);
        assert(marketplace.getOrder(0).expired == _expired);
    }

    function testCantBuyOrderIfExpired() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = address(token1);
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp;

        vm.startPrank(players[account]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceInvalidOrder.selector
            )
        );

        marketplace.buyOrder(_nft, _tokenId, _token, _price, _expired);

        vm.stopPrank();
    }

    function testCantBuyOrderIfNotEnoughERC20() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = address(token1);
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        vm.startPrank(players[account]);

        vm.expectRevert();

        marketplace.buyOrder(_nft, _tokenId, _token, _price, _expired);

        vm.stopPrank();
    }

    function testCantBuyOrderIfNotEnoughETH() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = ETH;
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        vm.startPrank(players[account]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketplaceInsufficentAmount.selector
            )
        );

        marketplace.buyOrder{value: _price - 1}(_nft, _tokenId, _token, _price, _expired);

        vm.stopPrank();
    }

    function testCantBuyOrderIfOwnerOfNFT() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 0;
        address _token = address(token1);
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        vm.startPrank(players[account]);

        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.MarketPlaceInvalidOrder.selector
            )
        );

        marketplace.buyOrder(_nft, _tokenId, _token, _price, _expired);

        vm.stopPrank();
    }
    function testCanCancelBuyOrderETH() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = ETH;
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        vm.startPrank(players[account]);

        uint256 orderId = marketplace.buyOrder{value: _price}(_nft, _tokenId, _token, _price, _expired);
        assert(orderId == 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 29 days);

        vm.startPrank(players[account]);

        marketplace.cancelOrder(orderId);

        vm.stopPrank();

        // Assert what?
        // Balance return
        // Mapping? (not available anymore)
        
        assert(address(marketplace).balance == 0);
        assert(players[account].balance == INITIAL_AMOUNT);
        assert(marketplace.getOrder(orderId).available == false);
    }

    function testCanCancelBuyOrderERC20() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = address(token1);
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        vm.startPrank(players[account]);

        Token(_token).approve(address(marketplace), _price);

        uint256 orderId = marketplace.buyOrder(_nft, _tokenId, _token, _price, _expired);
        assert(orderId == 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 29 days);

        vm.startPrank(players[account]);

        marketplace.cancelOrder(orderId);

        vm.stopPrank();

        // Assert what?
        // Balance return
        // Mapping? (not available anymore)
        
        assert(Token(_token).balanceOf(address(marketplace)) == 0);
        assert(Token(_token).balanceOf(players[account]) == INITIAL_AMOUNT);
        assert(marketplace.getOrder(orderId).available == false);
    }

    function buyOrderWithEth(uint256 account, address _nft, uint256 _tokenId, address _token, uint256 _price, uint256 _expired) internal returns (uint256){
        vm.startPrank(players[account]);

        uint256 orderId = marketplace.buyOrder{value: _price}(_nft, _tokenId, _token, _price, _expired);

        vm.stopPrank();

        return orderId;
    }

    function buyOrderWithERC20(uint256 account, address _nft, uint256 _tokenId, address _token, uint256 _price, uint256 _expired) internal returns (uint256){
        vm.startPrank(players[account]);

        Token(_token).approve(address(marketplace), _price);

        uint256 orderId = marketplace.buyOrder(_nft, _tokenId, _token, _price, _expired);

        vm.stopPrank();

        return orderId;
    }

    function testFulfillBuyOrderEth() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = ETH;
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        uint256 orderId = buyOrderWithEth(account, _nft, _tokenId, _token, _price, _expired);


        uint256 seller = 1;


        vm.startPrank(players[seller]);

        NFT(_nft).approve(address(marketplace), _tokenId);
        marketplace.fulfillBuyOrder(orderId);

        vm.stopPrank();
        

        // Assertion:
        // NFT belongs to 0
        // Balance change: player[0], player[1], contract
        // Order not available anymore
        // console.log(players[account]);
        // console.log(players[seller]);   
        // console.log("ownerOf", NFT(_nft).ownerOf(_tokenId));
        // console.log("balanceOf", players[account].balance);
        // console.log("balanceOf", players[seller].balance);
        // console.log("balanceOf", address(marketplace).balance);
        // console.log("order", marketplace.getOrder(orderId).available);


        assert(NFT(_nft).ownerOf(_tokenId) == players[0]);
        assert(players[account].balance == INITIAL_AMOUNT - _price);
        assert(players[seller].balance == INITIAL_AMOUNT + _price);
        assert(address(marketplace).balance == 0);
        assert(marketplace.getOrder(orderId).available == false);
    }

        function testFulfillBuyOrderERC20() external {
        uint256 account = 0;
        address _nft = address(nft1);
        uint256 _tokenId = 1;
        address _token = address(token1);
        uint256 _price = 239 ether;
        uint256 _expired = block.timestamp + 100 days;

        uint256 orderId = buyOrderWithERC20(account, _nft, _tokenId, _token, _price, _expired);


        uint256 seller = 1;


        vm.startPrank(players[seller]);

        NFT(_nft).approve(address(marketplace), _tokenId);
        marketplace.fulfillBuyOrder(orderId);

        vm.stopPrank();
        

        // Assertion:
        // NFT belongs to 0
        // Balance change: player[0], player[1], contract
        // Order not available anymore

        assert(NFT(_nft).ownerOf(_tokenId) == players[0]);
        assert(Token(_token).balanceOf(players[account]) == INITIAL_AMOUNT - _price);
        assert(Token(_token).balanceOf(players[seller]) == INITIAL_AMOUNT + _price);
        assert(Token(_token).balanceOf(address(marketplace)) == 0);
        assert(marketplace.getOrder(orderId).available == false);

    }
    /*

    Attack how?
    1. Expired
    2. Not enough amount
    3. Not the owner of the nft. [x]
    4. Consider can call buyOrder mutliple times. ??
        - Same order with same price?
        - Same order with different price?
    */
   

   // test cancel buy order
   /*
    - Cant if expired [x]
    - Cant if fulfilled [x]
    - Cant if cancelled before [x]
    - Cant if not owner of the order [x]
    - Can (check assertation)

   */

  /*
  Test fulfill order
  - Cant if not nft owner
  - Cant if cancel, expired, fulfilled before
  - Can (assertion) (ERC20, eth)
  */
}