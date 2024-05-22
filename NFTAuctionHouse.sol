// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NFTAuction is Ownable, ReentrancyGuard, IERC721Receiver {

    struct Auction {
        uint256 Id;
        Nft Nft;
        address Owner;
        string Title;
        uint256 StartDate;
        uint256 EndDate;
        uint256 CurrentBidId;
        uint256 MinimumBid;
        uint256 SettledAt;
        uint256 CancelledAt;
    }

    struct Nft {
        address ContractAddress;
        uint256 TokenId;
    }

    struct Bid {
        bool Exists;
        uint256 Id;
        address Bidder;
        uint256 Value;
        uint256 XAbove;
        uint256 ReplacesPreviousBidId;
        uint256 Timestamp;
    }

    mapping(address => bool) public supportedNFTs;

    Auction[] public auctions;
    Bid[] public bids;

    uint256 private auctionIdCounter;
    uint256 private bidIdCounter;

    mapping(address => uint256[]) private _usersAuctionsIndexes;
    mapping(address => uint256[]) private _nftsAuctionsIndexes;
    mapping(address => uint256[]) private _usersBidIndexes;
    mapping(uint256 => uint256[]) private _auctionsBidIndexes;

    event AuctionCreated(uint256 auctionId, address indexed sender, address indexed nftContractAddress, uint256 indexed tokenId, uint256 timestamp);
    event Outbid(uint256 bidId, uint256 outbidByBidId, uint256 auctionId, address indexed bidder, uint256 timestamp);
    event BidRefunded(uint256 bidId, uint256 auctionId, address indexed bidder, uint256 bid, uint256 timestamp);
    event BidCreated(uint256 bidId, uint256 auctionId, address indexed bidder, uint256 bid, uint256 timestamp);
    event AuctionCancelled(uint256 auctionId, address indexed owner, uint256 timestamp);
    event SettleFailedAuction(uint256 auctionId, uint256 timestamp);
    event SettleSuccessfulAuction(uint256 auctionId, uint256 timestamp);

    constructor() {}

    function updateSupportedNFT(address nftContractAddress, bool supported) external onlyOwner {
        supportedNFTs[nftContractAddress] = supported;
    }

    function createAuction(address nftContractAddress, uint256 tokenId, string memory title, 
        uint256 startDate, uint256 endDate, uint256 minimumBid) external nonReentrant {

        IERC721 tokenContract = IERC721(nftContractAddress);
        
        // Validate general issues
        require(supportedNFTs[nftContractAddress], 'Contract not supported');
        require(tokenContract.ownerOf(tokenId) == msg.sender, 'Sender does not own token');
        require(tokenContract.getApproved(tokenId) == address(this) || tokenContract.isApprovedForAll(msg.sender, address(this)), 'This auction house is not approved to take token');
        require(endDate > startDate, 'End date must be after the start date');
        require(endDate >= block.timestamp, 'End date must be later than now');

        // Transfer the NFT to this contract
        tokenContract.safeTransferFrom(msg.sender, address(this), tokenId);

        // Create the records
        Nft memory nft = Nft(nftContractAddress, tokenId);
        Auction memory auction = Auction({
            Id: auctionIdCounter + 1,
            Nft: nft,
            Owner: msg.sender,
            Title: title,
            StartDate: startDate,
            EndDate: endDate,
            CurrentBidId: 0,
            MinimumBid: minimumBid,
            SettledAt: 0,
            CancelledAt: 0
        });

        auctionIdCounter++;
        auctions.push(auction);
        _usersAuctionsIndexes[msg.sender].push(auctionIdCounter - 1);
        _nftsAuctionsIndexes[nftContractAddress].push(auctionIdCounter - 1);

        // Send event
        emit AuctionCreated(auction.Id, msg.sender, nftContractAddress, tokenId, block.timestamp);
    }

    function makeBid(uint256 auctionId) external payable nonReentrant {
        require(auctionId > 0 && auctionId <= auctions.length, "Invalid auction ID");

        Auction storage auction = auctions[auctionId - 1];

        // Validate general issues
        require(auction.StartDate < block.timestamp, 'Auction has not started');
        require(auction.EndDate > block.timestamp, 'Auction has already ended');
        require(msg.value > auction.MinimumBid, 'Minimum bid has not been met');
        require(auction.SettledAt == 0, 'Auction has already been completed');
        require(auction.CancelledAt == 0, 'Auction has been cancelled');
        require(msg.sender != auction.Owner, 'Owners can\'t bid on their own auction');

        uint256 previousBidId = auction.CurrentBidId;
        address previousBidder = address(0);
        uint256 previousBid = 0;
        if (previousBidId > 0) {
            Bid memory currentBid = bids[previousBidId - 1];
            require(msg.value > currentBid.Value, 'Must exceed previous bid');        
            previousBidder = currentBid.Bidder;
            previousBid = currentBid.Value;    
        }
        
        Bid memory newBid = Bid({
            Exists: true,
            Id: bidIdCounter + 1,
            Bidder: msg.sender,
            Value: msg.value,
            XAbove: msg.value - previousBid,
            ReplacesPreviousBidId: previousBidId,
            Timestamp: block.timestamp
        });

        bidIdCounter++;
        bids.push(newBid);
        _usersBidIndexes[msg.sender].push(bidIdCounter - 1);
        _auctionsBidIndexes[auction.Id].push(bidIdCounter - 1);
        auction.CurrentBidId = newBid.Id;

        // Emit event before refund to adhere to CEI pattern
        emit BidCreated(newBid.Id, auction.Id, newBid.Bidder, newBid.Value, block.timestamp);

        // Return funds of previous bidder
        if (previousBidId > 0 && previousBidder != address(0)) {
            (bool success, ) = payable(previousBidder).call{value: previousBid}("");
            require(success, "Refund to previous bidder failed");
            emit Outbid(previousBidId, newBid.Id, auction.Id, previousBidder, block.timestamp);
        }
    }

    function cancelAuction(uint256 auctionId) external nonReentrant {
        require(auctionId > 0 && auctionId <= auctions.length, "Invalid auction ID");

        Auction storage auction = auctions[auctionId - 1];
        IERC721 tokenContract = IERC721(auction.Nft.ContractAddress);
        
        // Validate general issues
        require(auction.EndDate > block.timestamp, 'Auction has already ended');
        require(auction.SettledAt == 0, 'Auction has already been completed');
        require(auction.CancelledAt == 0, 'Auction has been cancelled');
        require(msg.sender == auction.Owner, 'Only owner can cancel auction');

        // Update state before external call
        auction.CancelledAt = block.timestamp;

        // Return funds of previous bidder
        if (auction.CurrentBidId > 0) {
            Bid memory currentBid = bids[auction.CurrentBidId - 1];
            address bidder = currentBid.Bidder;
            uint256 bid = currentBid.Value;

            auction.CurrentBidId = 0;

            (bool success, ) = payable(bidder).call{value: bid}("");
            require(success, "Refund to previous bidder failed");
            emit BidRefunded(currentBid.Id, auction.Id, bidder, bid, block.timestamp);
        }

        tokenContract.safeTransferFrom(address(this), auction.Owner, auction.Nft.TokenId);

        emit AuctionCancelled(auction.Id, auction.Owner, block.timestamp);
    }

    function settleAuction(uint256 auctionId) external nonReentrant {
        require(auctionId > 0 && auctionId <= auctions.length, "Invalid auction ID");

        Auction storage auction = auctions[auctionId - 1];
        IERC721 tokenContract = IERC721(auction.Nft.ContractAddress);

        // Validate general issues
        require(auction.EndDate <= block.timestamp, 'Auction has not ended');
        require(auction.SettledAt == 0, 'Auction has already been completed');
        require(auction.CancelledAt == 0, 'Auction has been cancelled');
        require(msg.sender == auction.Owner || auction.CurrentBidId > 0, 'Only owner of auction or top bidder can make settlement.');

        // Update state before external call
        auction.SettledAt = block.timestamp;

        // If there is no bidder, return the NFT to the owner
        if (auction.CurrentBidId > 0) {
            Bid memory currentBid = bids[auction.CurrentBidId - 1];

            require(msg.sender == auction.Owner || msg.sender == currentBid.Bidder, 'Only owner of auction or top bidder can make settlement');

            address bidder = currentBid.Bidder;
            uint256 bid = currentBid.Value;

            // Transfer NFT to top bidder and pay owner the bid
            tokenContract.safeTransferFrom(address(this), bidder, auction.Nft.TokenId);
            (bool success, ) = payable(auction.Owner).call{value: bid}("");
            require(success, "Transfer to auction owner failed");
            emit SettleSuccessfulAuction(auction.Id, block.timestamp);
        } else {
            tokenContract.safeTransferFrom(address(this), auction.Owner, auction.Nft.TokenId);
            emit SettleFailedAuction(auction.Id, block.timestamp);
        }
    }

   function getAuction(uint256 auctionId) public view returns(Auction memory auction){
      require(auctionId > 0 && auctionId <= auctions.length, "Invalid auction ID");
      return auctions[auctionId - 1];
   }

   function getAuctions(uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      // The number of auctions that will be returned (to set array)
      uint256 remaining = auctions.length - startingIndex;
      uint256 pageSize = remaining < perPage ? remaining : perPage;

      // Create the page
      Auction[] memory pageOfAuctions = new Auction[](pageSize);

      // Add each item to the page
      for(uint256 i = 0; i < pageSize; i++){
          pageOfAuctions[i] = auctions[startingIndex + i];
      }

      return pageOfAuctions;
   }

   function getOwnersAuctions(address owner, uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      uint256[] memory indexes = _usersAuctionsIndexes[owner];

      // The number of auctions that will be returned (to set array)
      uint256 remaining = indexes.length - startingIndex;
      uint256 pageSize = remaining < perPage ? remaining : perPage;

      // Create the page
      Auction[] memory pageOfAuctions = new Auction[](pageSize);

      // Add each item to the page
      for(uint256 i = 0; i < pageSize; i++){
          pageOfAuctions[i] = auctions[indexes[startingIndex + i]];
      }

      return pageOfAuctions;
   }

   function getNFTContractsAuctions(address nftContract, uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      uint256[] memory indexes = _nftsAuctionsIndexes[nftContract];

      // The number of auctions that will be returned (to set array)
      uint256 remaining = indexes.length - startingIndex;
      uint256 pageSize = remaining < perPage ? remaining : perPage;

      // Create the page
      Auction[] memory pageOfAuctions = new Auction[](pageSize);

      // Add each item to the page
      for(uint256 i = 0; i < pageSize; i++){
          pageOfAuctions[i] = auctions[indexes[startingIndex + i]];
      }

      return pageOfAuctions;
   }

    function getBid(uint256 bidId) public view returns(Bid memory bid){
        require(bidId > 0 && bidId <= bids.length, "Invalid bid ID");
        return bids[bidId - 1];
    }

    function getBids(uint256 pageNumber, uint256 perPage) public view returns(Bid[] memory){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      // The number of bids that will be returned (to set array)
      uint256 remaining = bids.length - startingIndex;
      uint256 pageSize = remaining < perPage ? remaining : perPage;

      // Create the page
      Bid[] memory pageOfBids = new Bid[](pageSize);

      // Add each item to the page
      for(uint256 i = 0; i < pageSize; i++){
          pageOfBids[i] = bids[startingIndex + i];
      }

      return pageOfBids;
   }

   function getOwnersBids(address owner, uint256 pageNumber, uint256 perPage) public view returns(Bid[] memory){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      uint256[] memory indexes = _usersBidIndexes[owner];

      // The number of bids that will be returned (to set array)
      uint256 remaining = indexes.length - startingIndex;
      uint256 pageSize = remaining < perPage ? remaining : perPage;

      // Create the page
      Bid[] memory pageOfBids = new Bid[](pageSize);

      // Add each item to the page
      for(uint256 i = 0; i < pageSize; i++){
          pageOfBids[i] = bids[indexes[startingIndex + i]];
      }

      return pageOfBids;
   }

   function getAuctionsBids(uint256 auctionId, uint256 pageNumber, uint256 perPage) public view returns(Bid[] memory){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      uint256[] memory indexes = _auctionsBidIndexes[auctionId];

      // The number of auctions that will be returned (to set array)
      uint256 remaining = indexes.length - startingIndex;
      uint256 pageSize = remaining < perPage ? remaining : perPage;

      // Create the page
      Bid[] memory pageOfBids = new Bid[](pageSize);

      // Add each item to the page
      for(uint256 i = 0; i < pageSize; i++){
          pageOfBids[i] = bids[indexes[startingIndex + i]];
      }

      return pageOfBids;
   }

   function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
   }
}
