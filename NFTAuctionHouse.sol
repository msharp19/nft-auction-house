// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTAuction is Ownable {

    struct Auction{
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

   struct Nft{
      address ContractAddress;
      uint256 TokenId;
   }

   struct Bid{
      bool Exists;
      uint256 Id;
      address Bidder;
      uint256 Value;
      uint256 XAbove;
      uint256 ReplacesPreviousBidId;
      uint256 Timestamp;
   }

   mapping(address => bool) public SupportedNFTs;

   Auction[] public Auctions;
   Bid[] public Bids;

   mapping(address => uint256[]) public UsersAuctionsIndexes;
   mapping(address => uint256[]) public NftsAuctionsIndexes;
   mapping(address => uint256[]) public UsersBidIndexes;
   mapping(uint256 => uint256[]) public AuctionsBidIndexes;

   event AuctionCreated(uint256 auctionId, address indexed sender, address indexed nftContractAddress, uint256 indexed tokenId, uint256 timestamp);
   event Outbid(uint256 bidId, uint256 outbidByBidId, uint256 auctionId, address indexed bidder, uint256 timestamp);
   event BidRefunded(uint256 bidId, uint256 auctionId, address indexed bidder, uint256 bid, uint256 timestamp);
   event BidCreated(uint256 bidId, uint256 auctionId, address indexed bidder, uint256 bid, uint256 timestamp);
   event AuctionCancelled(uint256 auctionId, address indexed owner, uint256 timestamp);
   event SettleFailedAuction(uint256 auctionId, uint256 timestamp);
   event SettleSuccessfulAuction(uint256 auctionId, uint256 timestamp);

   constructor(){}

   function getAuction(uint256 auctionId) public view returns(Auction memory auction){
      auction = Auctions[auctionId-1];
   }

   function getAuctions(uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory auctions){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      // The number of auctions that will be returned (to set array)
      uint256 remaining = Auctions.length - startingIndex;
      uint256 pageSize = ((startingIndex+1)>Auctions.length) ? 0 : (remaining < perPage) ? remaining : perPage;

      // Create the page
      Auction[] memory pageOfAuctions = new Auction[](pageSize);

      // Add each item to the page
      uint256 pageItemIndex = 0;
      for(uint256 i = startingIndex;i < (startingIndex + pageSize);i++){
          // Get the auction
          Auction memory auction = Auctions[i];

          // Add to page
          pageOfAuctions[pageItemIndex] = auction;

          // Increment page item index
          pageItemIndex++;
      }

      return pageOfAuctions;
   }

   function getOwnersAuctions(address owner, uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory auctions){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      uint256[] memory indexes = UsersAuctionsIndexes[owner];

      // The number of auctions that will be returned (to set array)
      uint256 remaining = indexes.length - startingIndex;
      uint256 pageSize = ((startingIndex+1)>Auctions.length) ? 0 : (remaining < perPage) ? remaining : perPage;

      // Create the page
      Auction[] memory pageOfAuctions = new Auction[](pageSize);

      // Add each item to the page
      uint256 pageItemIndex = 0;
      for(uint256 i = startingIndex;i < (startingIndex + pageSize);i++){
          // Get the auction
          Auction memory auction = Auctions[indexes[i]];

          // Add to page
          pageOfAuctions[pageItemIndex] = auction;

          // Increment page item index
          pageItemIndex++;
      }

      return pageOfAuctions;
   }

   function getNFTContractsAuctions(address nftContract, uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory auctions){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      uint256[] memory indexes = NftsAuctionsIndexes[nftContract];

      // The number of auctions that will be returned (to set array)
      uint256 remaining = indexes.length - startingIndex;
      uint256 pageSize = ((startingIndex+1)>Auctions.length) ? 0 : (remaining < perPage) ? remaining : perPage;

      // Create the page
      Auction[] memory pageOfAuctions = new Auction[](pageSize);

      // Add each item to the page
      uint256 pageItemIndex = 0;
      for(uint256 i = startingIndex;i < (startingIndex + pageSize);i++){
          // Get the auction
          Auction memory auction = Auctions[indexes[i]];

          // Add to page
          pageOfAuctions[pageItemIndex] = auction;

          // Increment page item index
          pageItemIndex++;
      }

      return pageOfAuctions;
   }

    function getBid(uint256 bidId) public view returns(Bid memory bid){
      bid = Bids[bidId-1];
   }

   function getBids(uint256 pageNumber, uint256 perPage) public view returns(Bid[] memory bids){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      // The number of bids that will be returned (to set array)
      uint256 remaining = Bids.length - startingIndex;
      uint256 pageSize = ((startingIndex+1)>Bids.length) ? 0 : (remaining < perPage) ? remaining : perPage;

      // Create the page
      Bid[] memory pageOfBids = new Bid[](pageSize);

      // Add each item to the page
      uint256 pageItemIndex = 0;
      for(uint256 i = startingIndex;i < (startingIndex + pageSize);i++){
          // Get the bid
          Bid memory bid = Bids[i];

          // Add to page
          pageOfBids[pageItemIndex] = bid;

          // Increment page item index
          pageItemIndex++;
      }

      return pageOfBids;
   }

   function getOwnersBids(address owner, uint256 pageNumber, uint256 perPage) public view returns(Bid[] memory bids){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      uint256[] memory indexes = UsersBidIndexes[owner];

      // The number of bids that will be returned (to set array)
      uint256 remaining = indexes.length - startingIndex;
      uint256 pageSize = ((startingIndex+1)>Bids.length) ? 0 : (remaining < perPage) ? remaining : perPage;

      // Create the page
      Bid[] memory pageOfBids = new Bid[](pageSize);

      // Add each item to the page
      uint256 pageItemIndex = 0;
      for(uint256 i = startingIndex;i < (startingIndex + pageSize);i++){
          // Get the bid
          Bid memory bid = Bids[indexes[i]];

          // Add to page
          pageOfBids[pageItemIndex] = bid;

          // Increment page item index
          pageItemIndex++;
      }

      return pageOfBids;
   }

   function getAuctionsBids(uint256 auctionId, uint256 pageNumber, uint256 perPage) public view returns(Bid[] memory bids){
      
      // Validate page limit
      require(perPage <= 1000, "Page limit exceeded");

      // Get the index to start from
      uint256 startingIndex = pageNumber * perPage;

      uint256[] memory indexes = AuctionsBidIndexes[auctionId];

      // The number of auctions that will be returned (to set array)
      uint256 remaining = indexes.length - startingIndex;
      uint256 pageSize = ((startingIndex+1)>Bids.length) ? 0 : (remaining < perPage) ? remaining : perPage;

      // Create the page
      Bid[] memory pageOfBids = new Bid[](pageSize);

      // Add each item to the page
      uint256 pageItemIndex = 0;
      for(uint256 i = startingIndex;i < (startingIndex + pageSize);i++){
          // Get the bid
          Bid memory auction = Bids[indexes[i]];

          // Add to page
          pageOfBids[pageItemIndex] = auction;

          // Increment page item index
          pageItemIndex++;
      }

      return pageOfBids;
   }

   function updateSupportedNFT(address nftContractAddress, bool supported) onlyOwner external {
      SupportedNFTs[nftContractAddress] = supported;
   }

   function createAuction(address nftContractAddress, uint256 tokenId, string memory title, 
       uint256 startDate, uint256 endDate, uint256 minimumBid) external {

      IERC721 tokenContract = IERC721(nftContractAddress);
      
      // Validate general issues
      require(SupportedNFTs[nftContractAddress] == true, 'Contract not supported');
      require(tokenContract.ownerOf(tokenId) == msg.sender, 'Sender does not own token');
      require(tokenContract.getApproved(tokenId) == address(this), 'This auction house is not approved to take token');
      require(endDate > startDate, 'End date must be after the start date');
      require(endDate >= block.timestamp, 'End date must be later than now');

      // Transfer the NFT to this contract
      tokenContract.transferFrom(msg.sender, address(this), tokenId);

      // Create the records
      Nft memory nft = Nft(nftContractAddress, tokenId);
      Auction memory auction = Auction((Auctions.length + 1), nft, msg.sender, title, startDate,
         endDate, 0, minimumBid, 0, 0);

      Auctions.push(auction);
      UsersAuctionsIndexes[msg.sender].push(Auctions.length-1);
      NftsAuctionsIndexes[nftContractAddress].push(Auctions.length-1);

      // Send event
      emit AuctionCreated(auction.Id, msg.sender, nftContractAddress, tokenId, block.timestamp);
   }

   function makeBid(uint256 auctionId) payable external {
       
       Auction storage auction = Auctions[auctionId-1];

       // Validate general issues
       require(auction.StartDate < block.timestamp, 'Auction has not started');
       require(auction.EndDate > block.timestamp, 'Auction has already ended');
       require(msg.value > auction.MinimumBid, 'Minimum bid has not been met');
       require(auction.SettledAt == 0, 'Auction has already been completed');
       require(auction.CancelledAt == 0, 'Auction has been cancelled');
       require(msg.sender != auction.Owner, 'Owners cant bid on their own auction');

       uint256 previousBidId = auction.CurrentBidId;
       address previousBidder = address(0);
       uint256 previousBid = 0;
       if(previousBidId > 0){
          Bid memory currentBid = Bids[auction.CurrentBidId-1];
          require(msg.value > currentBid.Value, 'Must exceed previous bid');        
          previousBidder = currentBid.Bidder;
          previousBid = currentBid.Value;    
       }
      
       Bid memory newBid = Bid(true, Bids.length + 1, msg.sender, msg.value, msg.value - previousBid, previousBidId, block.timestamp);
       Bids.push(newBid);
       UsersBidIndexes[msg.sender].push(Bids.length-1);
       AuctionsBidIndexes[auction.Id].push(Bids.length-1);

       auction.CurrentBidId = newBid.Id;

       // Return funds of previous bidder
       if (previousBidId > 0 && previousBidder != address(0)) {
           payable(previousBidder).transfer(previousBid);
           emit Outbid(previousBidId, newBid.Id, auction.Id, previousBidder, block.timestamp);
       }

       emit BidCreated(newBid.Id, auction.Id, newBid.Bidder, newBid.Value, block.timestamp);
   }

   function cancelAuction(uint256 auctionId) external {

       Auction storage auction = Auctions[auctionId-1];
       IERC721 tokenContract = IERC721(auction.Nft.ContractAddress);
       
       // Validate general issues
       require(auction.EndDate > block.timestamp, 'Auction has already ended');
       require(auction.SettledAt == 0, 'Auction has already been completed');
       require(auction.CancelledAt == 0, 'Auction has been cancelled');
       require(msg.sender == auction.Owner, 'Only owner can cancel auction');

       // Cancel
       auction.CancelledAt = block.timestamp;

       // Return funds of previous bidder
       if (auction.CurrentBidId > 0) {
            Bid memory currentBid = Bids[auction.CurrentBidId-1];
            address bidder = currentBid.Bidder;
            uint256 bid = currentBid.Value;

            auction.CurrentBidId = 0;

            payable(bidder).transfer(bid);
            emit BidRefunded(currentBid.Id, auction.Id, bidder, bid, block.timestamp);
        }

       tokenContract.transferFrom(address(this), auction.Owner, auction.Nft.TokenId);

       emit AuctionCancelled(auction.Id, auction.Owner, block.timestamp);
   }

   function settleAuction(uint256 auctionId) external {
       Auction storage auction = Auctions[auctionId - 1];
       IERC721 tokenContract = IERC721(auction.Nft.ContractAddress);

       // Validate general issues
       require(auction.EndDate <= block.timestamp, 'Auction has not ended');
       require(auction.SettledAt == 0, 'Auction has already been completed');
       require(auction.CancelledAt == 0, 'Auction has been cancelled');
       require(msg.sender == auction.Owner, 'Only owner of auction or top bidder can make settlement');  

       // Update state before external call
       auction.SettledAt = block.timestamp;

       // If there is no bidder, return the NFT to the owner
       if (auction.CurrentBidId == 0) {
           tokenContract.transferFrom(address(this), auction.Owner, auction.Nft.TokenId);
           emit SettleFailedAuction(auction.Id, block.timestamp);
       } else {
           Bid memory currentBid = Bids[auction.CurrentBidId];
           address bidder = currentBid.Bidder;
           uint256 bid = currentBid.Value;

           // Transfer NFT to top bidder and pay owner the bid
           tokenContract.transferFrom(address(this), bidder, auction.Nft.TokenId);
           payable(auction.Owner).transfer(bid);

           emit SettleSuccessfulAuction(auction.Id, block.timestamp);
    }
}
}
