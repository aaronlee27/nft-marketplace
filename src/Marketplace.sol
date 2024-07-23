// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";


contract Marketplace is Ownable {
    using SafeERC20 for IERC20;

    error MarketPlaceNFTNotOwner(address _user, address _nft, uint256 _tokenId);
    error MarketPlaceOrderIdInvalid(uint256 _orderId);
    error MarketPlaceOrderNotAvailable(uint256 _orderId);
    error MarketPlaceOrderExpired(uint256 _orderId);
    error MarketPlaceUserNotPermitted(address _user, uint256 _orderId);
    error MarketPlaceInvalidOrder();
    error MarketplaceInsufficentAmount();

    enum OrderType {
        BUY,
        SELL
    }

    struct Order {
        OrderType orderType;
        address proposer;
        address nft;
        uint256 tokenId;
        address token;
        uint256 price;
        uint256 expired;
        bool available;
    }

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private feeCollector;
    uint256 private fee;
    uint256 private s_orderId;

    mapping (uint256 => Order) private orders;

    constructor(address _feeCollector, uint256 _fee) Ownable(msg.sender) {
        feeCollector = _feeCollector;
        fee = _fee;
    }

    modifier checkOwner(address _nft, uint256 _tokenId) {
        IERC721 nft = IERC721(_nft);
        if (nft.ownerOf(_tokenId) != msg.sender) {
            revert MarketPlaceNFTNotOwner(msg.sender, _nft, _tokenId);
        }
        _;
    }

    modifier checkValidOrder(uint256 _orderId) {
        if (_orderId >= s_orderId) {
            revert MarketPlaceOrderIdInvalid(_orderId);
        }
        if (!orders[_orderId].available) {
            revert MarketPlaceOrderNotAvailable(_orderId);
        }
        if (block.timestamp >= orders[_orderId].expired) {
            revert MarketPlaceOrderExpired(_orderId);
        }
        _;
    }

    function sellOrder(
        address _nft,
        uint256 _tokenId,
        address _token,
        uint256 _price,
        uint256 _expired
    )   external 
        checkOwner(_nft, _tokenId)
        returns (uint256 orderId)
    {
        if (block.timestamp >= _expired) {
            revert MarketPlaceInvalidOrder();
        }

        Order memory order = Order(
            OrderType.SELL,
            msg.sender,
            _nft,
            _tokenId,
            _token,
            _price,
            _expired,
            true
        );

        orderId = s_orderId;
        orders[orderId] = order;
        s_orderId++;

        IERC721(_nft).transferFrom(msg.sender, address(this), _tokenId);
        return orderId;
    }

    function buyOrder(
        address _nft,
        uint256 _tokenId,
        address _token,
        uint256 _price,
        uint256 _expired
    )   external payable
        returns (uint256 orderId)
    {
        if (block.timestamp >= _expired) {
            revert MarketPlaceInvalidOrder();
        }
        Order memory order = Order(
            OrderType.BUY,
            msg.sender,
            _nft,
            _tokenId,
            _token,
            _price,
            _expired,
            true
        );

        orderId = s_orderId;
        orders[orderId] = order;
        s_orderId++;

        if (_token == ETH) {
            if (msg.value < _price) {
                revert MarketplaceInsufficentAmount();
            }
        }
        else {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _price);
        }
    }

    function cancelOrder(
        uint256 _orderId
    )   external
        checkValidOrder(_orderId)
    {
        Order storage order = orders[_orderId];

        if (msg.sender != order.proposer){
            revert MarketPlaceUserNotPermitted(msg.sender, _orderId);
        }
        order.available = false;

        if (order.orderType == OrderType.SELL) {
            IERC721(order.nft).safeTransferFrom(address(this), msg.sender, order.tokenId);
        }

        else {
            if (order.token == ETH) {
                (bool success, ) = msg.sender.call{value: order.price}("");
                require(success, "Marketplace: ETH transfer failed");
            }

            else {
                IERC20(order.token).safeTransfer(msg.sender, order.price);
            }
        }
    }

    function fulfillSellOrder(
        uint256 _orderId
    )   external payable
        checkValidOrder(_orderId) 
    {
        Order storage order = orders[_orderId];

        if (msg.sender == order.proposer){
            revert MarketPlaceUserNotPermitted(msg.sender, _orderId);
        }

        order.available = false;

        if (order.token == ETH) {
            if (msg.value < order.price) {
                revert MarketplaceInsufficentAmount();
            }
            (bool success, ) = payable(order.proposer).call{value: order.price}("");
            require(success, "Marketplace: ETH transfer failed");
        }
        else {
            IERC20(order.token).safeTransferFrom(msg.sender, order.proposer, order.price);
        }
        
        IERC721(order.nft).safeTransferFrom(address(this), msg.sender, order.tokenId);
    }

    function fulfillBuyOrder(
        uint256 _orderId
    )   external 
        checkValidOrder(_orderId)
    {
        Order storage order = orders[_orderId];

        if (msg.sender == order.proposer){
            revert MarketPlaceUserNotPermitted(msg.sender, _orderId);
        }

        order.available = false;

        IERC721(order.nft).safeTransferFrom(msg.sender, order.proposer, order.price);

        if (order.token == ETH) {
            (bool success, ) = payable(msg.sender).call{value: order.price}("");
            require(success, "Marketplace: ETH transfer failed");
        }
        else {
            IERC20(order.token).safeTransfer(msg.sender, order.price);
        }
    }

    function collectFee(address token) external onlyOwner {
        if (token == ETH) {
            if (address(this).balance > 0){
                payable(feeCollector).transfer(address(this).balance);
            }
        }
        else {
            uint256 _balances = IERC20(token).balanceOf(address(this));
            if (_balances > 0){
                IERC20(token).safeTransfer(feeCollector, _balances);
            }
        }
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    } 

    function getFeeCollector() public view returns (address) {
        return feeCollector;
    }

    function getFee() public view returns (uint256) {
        return fee;
    }

    function getOrderId() public view returns (uint256) {
        return s_orderId;
    }

    function getOrder(uint256 _orderId) public view returns (Order memory) {
        return orders[_orderId];
    }

   function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4){
        return this.onERC721Received.selector;
    }
}