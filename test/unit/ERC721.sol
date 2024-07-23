// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFT is ERC721{
    uint256 private s_tokenCounter;

    mapping (uint256 tokenId => string URI) private s_tokenIdToURI;

    constructor (string memory _name, string memory _symbol) ERC721(_name, _symbol) {
        s_tokenCounter = 0;
    }

    string _tokenURI = "dakmem";
    

    function mint() public {
        s_tokenIdToURI[s_tokenCounter] = _tokenURI;
        _safeMint(msg.sender, s_tokenCounter);
        s_tokenCounter++;
    }

    function tokenURI(uint256 _tokenId) public override view returns (string memory){
        return s_tokenIdToURI[_tokenId];
    }


}