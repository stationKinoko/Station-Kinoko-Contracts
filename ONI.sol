// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Counters.sol";

contract ONIS is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Strings for uint256;

    uint256 public constant ONIS_PUBLIC = 10000;
    uint256 public constant PURCHASE_LIMIT = 10;
    uint256 public allowListMaxMint = 10;
    uint256 public constant PRICE = 100 ether;
    
    bool private _isActive = false;
    bool private isAllowListActive = false;
    bool public revealed = false;

    mapping(uint256 => uint256) public feedNft;

    string private _tokenBaseURI = "";
    string public hiddenURI = "";
    
    mapping(address => bool) private _allowList;
    mapping(address => uint256) private _allowListClaimed;

    Counters.Counter private _publicONIS;

    constructor() ERC721("Oni", "ONI") {

    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    function setBaseURI(string memory URI) external onlyOwner {
        _tokenBaseURI = URI;
    }

    function setHiddenURI(string memory URI) external onlyOwner {
        hiddenURI = URI;
    }

    function reveal() public onlyOwner {
        revealed = true;
    }

    // owner minting
    function ownerMinting(address to, uint256 numberOfTokens)
        external
        payable
        onlyOwner
    {
        require(
            _publicONIS.current() < ONIS_PUBLIC,
            "Purchase would exceed ONIS_PUBLIC"
        );

        for (uint256 i = 0; i < numberOfTokens; i++) {
            uint256 tokenId = _publicONIS.current();

            if (_publicONIS.current() < ONIS_PUBLIC) {
                _publicONIS.increment();
                _safeMint(to, tokenId);
            }
        }
    }

    function flipActive() public onlyOwner {
        _isActive = !_isActive;
    }

    function flipIsAllowActive() public onlyOwner {
    isAllowListActive = !isAllowListActive;
    }
    
      // function setAllowListMaxMint(uint256 maxMint) external onlyOwner {
      //   allowListMaxMint = maxMint;
      // }
      
    function addToAllowList(address[] calldata addresses) external onlyOwner {
    for (uint256 i = 0; i < addresses.length; i++) {
        require(addresses[i] != address(0), "Can't add the null address");
        
        _allowList[addresses[i]] = true;
        
        /**
        * @dev We don't want to reset _allowListClaimed count
        * if we try to add someone more than once.
        */
        _allowListClaimed[addresses[i]] > 0 ? _allowListClaimed[addresses[i]] : 0;
    }
    }
    
    function allowListClaimedBy(address owner) external view returns (uint256){
    require(owner != address(0), "Zero address not on Allow List");

    return _allowListClaimed[owner];
    }

    function onAllowList(address addr) external view returns (bool) {
    return _allowList[addr];
    }

    function removeFromAllowList(address[] calldata addresses) external onlyOwner {
    for (uint256 i = 0; i < addresses.length; i++) {
        require(addresses[i] != address(0), "Can't add the null address");

        /// @dev We don't want to reset possible _allowListClaimed numbers.
        _allowList[addresses[i]] = false;
    }
    }
    
    function purchaseAllowList(uint256 numberOfTokens) external payable callerIsUser nonReentrant {
        require(
            numberOfTokens <= PURCHASE_LIMIT,
            "Can only mint up to 10 token"
        );
        
        require(isAllowListActive, "Allow List is not active");
        require(_allowList[msg.sender], "You are not on the Allow List");
        require(
            _publicONIS.current() < ONIS_PUBLIC,
            "Purchase would exceed max"
        );
        require(numberOfTokens <= allowListMaxMint, "Cannot purchase this many tokens");
        require(_allowListClaimed[msg.sender] + numberOfTokens <= allowListMaxMint, "Purchase exceeds max allowed");
        require(PRICE * numberOfTokens <= msg.value, "ETH amount is not sufficient");
        require(
            _publicONIS.current() < ONIS_PUBLIC,
            "Purchase would exceed ONIS_PUBLIC"
        );
        for (uint256 i = 0; i < numberOfTokens; i++) {
            uint256 tokenId = _publicONIS.current();

            if (_publicONIS.current() < ONIS_PUBLIC) {
                _publicONIS.increment();
                _allowListClaimed[msg.sender] += 1;
                _safeMint(msg.sender, tokenId);
            }
        }
        
      }

    function purchase(uint256 numberOfTokens) external payable callerIsUser nonReentrant {
        require(_isActive, "Contract is not active");
        require(
            numberOfTokens <= PURCHASE_LIMIT,
            "Can only mint up to 10 tokens"
        );
        require(
            _publicONIS.current() < ONIS_PUBLIC,
            "Purchase would exceed ONIS_PUBLIC"
        );
        require(
            PRICE * numberOfTokens <= msg.value,
            "ETH amount is not sufficient"
        );

        for (uint256 i = 0; i < numberOfTokens; i++) {
            uint256 tokenId = _publicONIS.current();

            if (_publicONIS.current() < ONIS_PUBLIC) {
                _publicONIS.increment();
                _safeMint(msg.sender, tokenId);
            }
        }
    }

    function walletOfOwner(address _owner) public view returns(uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for(uint256 i; i < tokenCount; i++){
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    function feedKinoko(uint256 tokenId, uint256 kinokofed) public returns (string memory) {

        if(msg.sender == ownerOf(tokenId)) {
            feedNft[tokenId] += kinokofed;
            return "You fed your UNI Kinoko!";
        } else {
            return "You can't feed other peoples UNIs!";
        }
    }

    function kinokoMultiplier() public view returns(uint256) {
        uint256 released = _publicONIS.current() * 10000;
        uint256 percentage = released / ONIS_PUBLIC;
        uint256 kinokoBoost = 10000 + percentage;
        return kinokoBoost;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        require(_exists(tokenId), "Token does not exist");

        if(revealed == false) {
            return hiddenURI;
        }

        return string(abi.encodePacked(_tokenBaseURI, tokenId.toString(), ".json"));
    }

    function returnAllowListactive() public onlyOwner view returns (bool) {
        return isAllowListActive;
    }

    function returnIsActive() public onlyOwner view returns (bool) {
        return _isActive;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;

        payable(msg.sender).transfer(balance);
    }
}