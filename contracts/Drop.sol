// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import './RandomlyAssigned.sol';
import "./SafeMathLite.sol";
import "./SafePct.sol";

abstract contract Market {
    function isMember(address user) public view virtual returns (bool);
    function addToEscrow(address _address) external virtual payable;
}

contract Drop is 
    Pausable,
    ERC721Enumerable,
    Ownable, 
    RandomlyAssigned,
    ERC2981
{
    using Counters for Counters.Counter;
    using Strings for uint256;
    using SafePct for uint256;
    using SafeMathLite for uint256;

    string public baseURI;
    
    uint256 public regularCost;
    uint256 public memberCost;
    uint256 public whitelistCost;
    
    //Restrictions
    uint256 public maxSupply;
    uint256 public immutable reservedNft;
    uint256 public immutable maxMintAmount;

    Counters.Counter public reservedMintedNFT;

    address marketAddress;

    address[] private payees;
    uint16[] private shares;

    uint256 publicStartTime;
    uint256 whitelistStartTime;

    address immutable FACTORY_ADDRESS;

    struct Infos {
        uint256 regularCost;
        uint256 memberCost;
        uint256 whitelistCost;
        uint256 maxSupply;
        uint256 totalSupply;
        uint256 maxMintPerAddress;
        uint256 maxMintPerTx;
    }

    mapping(address => bool) public whitelistedAddresses;
    
    modifier onlyDropOwner() {
        require(msg.sender == FACTORY_ADDRESS || msg.sender == owner(), "not owner");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        uint256 maxMintAmount_,
        uint256 reservedNFT_,
        address marketAddress_
    ) 
    ERC721(name_, symbol_)
    RandomlyAssigned(maxSupply_, reservedNFT_) 
    {
        setBaseURI(baseURI_);
        maxSupply = maxSupply_;
        maxMintAmount = maxMintAmount_;
        reservedNft = reservedNFT_;
        marketAddress = marketAddress_;
        FACTORY_ADDRESS = msg.sender;
        _transferOwnership(tx.origin);
    }

    function getInfo() public view returns (Infos memory) {
        Infos memory allInfos;
        allInfos.regularCost = regularCost;
        allInfos.memberCost = memberCost;
        allInfos.whitelistCost = whitelistCost;
        allInfos.maxSupply = maxSupply;
        allInfos.totalSupply = totalSupply();
        allInfos.maxMintPerTx = maxMintAmount;

        return allInfos;
    }

    function isEbisusBayMember(address _address) private view returns(bool) {
        return Market(marketAddress).isMember(_address);
    }

    function addWhiteList(address[] calldata _addresses) public onlyOwner {
        uint len = _addresses.length;
        for(uint i = 0; i < len; i ++) {
            whitelistedAddresses[_addresses[i]] = true;
        }        
    }
    
    function addWhiteListAddress(address _address) public onlyOwner {
        whitelistedAddresses[_address] = true;
    }

    function removeWhiteList(address _address) public onlyOwner {
        if (whitelistedAddresses[_address]) {
            delete whitelistedAddresses[_address];
        }
    }

    function setRegularCost(uint256 _cost) external onlyDropOwner {
        regularCost = _cost;
    }

    function setMemberCost(uint256 _cost) external onlyDropOwner {
        memberCost = _cost;
    }

    function setWhitelistCost(uint256 _cost) external onlyDropOwner {
        whitelistCost = _cost;
    }

    function isWhitelist(address _address) public view returns(bool) {
        if (whitelistStartTime != 0 && block.timestamp < whitelistStartTime) {
            return false;
        }
        return whitelistedAddresses[_address];
    }

    function mint(uint256 _mintAmount) public payable whenNotPaused {
        require(publicStartTime == 0 || publicStartTime <= block.timestamp, "not started");

        uint256 supply = totalSupply();
        require(_mintAmount > 0, "need to mint at least 1 NFT");
        require(
            _mintAmount <= maxMintAmount,
            "max mint amount per session exceeded"
        );
        require((supply + _mintAmount) <= maxSupply, "max NFT limit exceeded");

        uint256 cost;
        if (isWhitelist(msg.sender)) {
            cost = whitelistCost;
        } else {              
            if (isEbisusBayMember(msg.sender)) {
                cost = memberCost;
            } else {
                cost = regularCost;
            }    
        }

        uint256 totalCost = cost.mul(_mintAmount);

        require(totalCost <= msg.value, "insufficient funds");

        for (uint256 i = 1; i <= _mintAmount; i++) {
            _mintRandomId(msg.sender);
        }
        
        Market market = Market(marketAddress);
        uint256 len = payees.length;
        uint256 amount;
        for(uint256 i = 0; i < len; i ++) {
            amount = totalCost.mulDiv(shares[i], 10000);
            market.addToEscrow{value : amount}(payees[i]);
        }  
    }

    function reservedMint(address _to, uint256 _mintAmount) public onlyOwner{
        require((reservedMintedNFT.current() + _mintAmount) <= reservedNft, "All Reserved NFT Minted");
        for (uint256 i = 1; i <= _mintAmount; i++) {
            reservedMintedNFT.increment();
            _safeMint(_to, reservedMintedNFT.current());
        }
    }

    function airdropMint(address _to, uint256 _amount) public onlyOwner {
        uint256 supply = totalSupply();
        require((supply + _amount) <= maxSupply, "max NFT limit exceeded");
        for (uint256 i = 1; i <= _amount; i++) {
            _mintRandomId(_to);
        }
    }

	function _mintRandomId(address to) private {
		uint256 id = nextToken();
		require(id > 0 && id <= maxSupply, "Mint not possible");
		_safeMint(to, id);
	}    

    //Get NFT Cost
    function mintCost(address _address) public view returns (uint256) {
        require(_address != address(0), "not address 0");
        if (isWhitelist(_address)) {
            return whitelistCost;
        }

        if (isEbisusBayMember(_address)) {
            return memberCost;
        }

        return regularCost;
    }

    // Can Mint Function
    function canMint(address) public view returns(uint256){
         return maxMintAmount;
    }

    function tokenURI(uint _tokenId) public view virtual override returns (string memory) {
      require(_exists(_tokenId),"ERC721Metadata: URI query for nonexistent token");

      string memory _tokenURI = string(abi.encodePacked(baseURI, "/", Strings.toString(_tokenId),".json"));

      return _tokenURI;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function pause() public onlyOwner{
        _pause();
    }

    function unpause() public onlyOwner{
        _unpause();
    }
    
    // internal
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function burn(uint256 tokenId) public {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721Burnable: caller is not owner nor approved");
        _burn(tokenId);
    }

    function lock() external onlyOwner {
        maxSupply = totalSupply();
    }

    function setPaymentShares(address[] calldata _newPayees, uint16[] calldata _newShares) external onlyDropOwner {
        require(_newPayees.length != 0, "empty payees");
        require(_newPayees.length == _newShares.length, "wrong payee numbers");
        
        if (!isCorrectShares(_newShares)) {
            revert("invalid shares");
        }
        payees = _newPayees;
        shares = _newShares;
    }

    function getPayees() public view returns(address[] memory) {
        return payees;
    }

    function getShares() public view returns(uint16[] memory) {
        return shares;
    }

    function isCorrectShares(uint16[] memory _shares) private pure returns (bool){
        uint256 len = _shares.length;
        uint256 totalFees;
        for(uint256 i = 0; i < len; i ++) {
            totalFees += _shares[i];
        }

        return totalFees == 10000;
    }

    function setPublicStartTime(uint256 _startTime) external onlyOwner {
        publicStartTime = _startTime;
    }
    
    function setWhitelistStartTime(uint256 _startTime) external onlyOwner {
        whitelistStartTime = _startTime;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
