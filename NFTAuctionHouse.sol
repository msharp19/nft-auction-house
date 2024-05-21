// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTAuctionHouse is Ownable {

    struct Auction{
      uint256 Id;
      Nft Nft;
      address Owner;
      address Bidder;
      string Title;
      string Description;
      uint256 StartDate;
      uint256 EndDate;
      uint256 Bid;
      uint256 MinimumBid;
      uint256 SettledAt;
      uint256 CancelledAt;
   }

   struct Nft{
      address ContractAddress;
      uint256 TokenId;
   }

   enum AuctionType{
       Time,
       Sale
   }

   mapping(address => bool) public SupportedNFTs;

   Auction[] public Auctions;

   mapping(address => uint256[]) public UsersAuctionsIndexes;
   mapping(address => uint256[]) public NftsAuctionsIndexes;

   event AuctionCreated(uint256 auctionId, address indexed sender, address indexed nftContractAddress, uint256 indexed tokenId, uint256 timestamp);
   event Outbid(uint256 auctionId, address indexed bidder, uint256 bid, uint256 timestamp);
   event BidRefunded(uint256 auctionId, address indexed bidder, uint256 bid, uint256 timestamp);
   event BidCreated(uint256 auctionId, address indexed bidder, uint256 bid, uint256 timestamp);
   event AuctionCancelled(uint256 auctionId, address indexed owner, uint256 timestamp);
   event SettleFailedAuction(uint256 auctionId, uint256 timestamp);
   event SettleSuccessfulAuction(uint256 auctionId, uint256 timestamp);

   constructor(){}

   function GetAuctions(uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory auctions){
      
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

   function GetOwnersAuctions(address owner, uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory auctions){
      
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

   function GetNFTContractsAuctions(address nftContract, uint256 pageNumber, uint256 perPage) public view returns(Auction[] memory auctions){
      
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

   function UpdateSupportedNFT(address nftContractAddress, bool supported) external {
      SupportedNFTs[nftContractAddress] = supported;
   }

   function CreateAuction(address nftContractAddress, uint256 tokenId, string memory title, string memory description,
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
      Auction memory auction = Auction((Auctions.length + 1), nft, msg.sender, address(0), title, description, startDate,
         endDate, 0, minimumBid, 0, 0);

      Auctions.push(auction);
      UsersAuctionsIndexes[msg.sender].push(Auctions.length-1);
      NftsAuctionsIndexes[nftContractAddress].push(Auctions.length-1);

      // Send event
      emit AuctionCreated(auction.Id, msg.sender, nftContractAddress, tokenId, block.timestamp);
   }

   function MakeBid(uint256 auctionId) payable external {
       
       Auction storage auction = Auctions[auctionId-1];

       // Validate general issues
       require(auction.StartDate < block.timestamp, 'Auction has not started');
       require(auction.EndDate > block.timestamp, 'Auction has already ended');
       require(msg.value > auction.MinimumBid, 'Minimum bid has not been met');
       require(auction.SettledAt == 0, 'Auction has already been completed');
       require(auction.CancelledAt == 0, 'Auction has been cancelled');
       require(msg.value > auction.Bid, 'Must exceed previous bid');

       // Return funds of previous bidder
       if(auction.Bidder != address(0))
       {
           payable(auction.Bidder).transfer(auction.Bid);
           emit Outbid(auction.Id, auction.Bidder, auction.Bid, block.timestamp);
       }

       auction.Bid = msg.value;
       auction.Bidder = msg.sender;

       emit BidCreated(auction.Id, auction.Bidder, auction.Bid, block.timestamp);
   }

   function CancelAuction(uint256 auctionId) external {

       Auction storage auction = Auctions[auctionId-1];
       IERC721 tokenContract = IERC721(auction.Nft.ContractAddress);
       
       // Validate general issues
       require(auction.EndDate > block.timestamp, 'Auction has already ended');
       require(auction.SettledAt == 0, 'Auction has already been completed');
       require(auction.CancelledAt == 0, 'Auction has been cancelled');

       // Cancel
       auction.CancelledAt = block.timestamp;

       // Return funds of previous bidder
       if(auction.Bidder != address(0))
       {
           payable(auction.Bidder).transfer(auction.Bid);
           emit BidRefunded(auction.Id, auction.Bidder, auction.Bid, block.timestamp);
       }

       tokenContract.transferFrom(address(this), auction.Owner, auction.Nft.TokenId);

       emit AuctionCancelled(auction.Id, auction.Owner, block.timestamp);
   }

   function SettleAuction(uint256 auctionId) external{
      
       Auction storage auction = Auctions[auctionId-1];
       IERC721 tokenContract = IERC721(auction.Nft.ContractAddress);

       // Validate general issues
       require(auction.EndDate <= block.timestamp, 'Auction has already ended');
       require(auction.SettledAt == 0, 'Auction has already been completed');
       require(auction.CancelledAt == 0, 'Auction has been cancelled');
       require(msg.sender == auction.Owner || msg.sender == auction.Bidder, 'Only owner of auction or top bidder can make settlement');

       auction.SettledAt = block.timestamp;
       
       // If there is no bidder, return the NFT to the owner
       if(auction.Bidder == address(0))
       {
           tokenContract.transferFrom(address(this), auction.Owner, auction.Nft.TokenId);

           emit SettleFailedAuction(auction.Id, block.timestamp);
       }
       // If there is a top bidder, send NFT to top bidder and pay owner the bid
       else 
       {
           tokenContract.transferFrom(address(this), auction.Bidder, auction.Nft.TokenId);

           payable(auction.Owner).transfer(auction.Bid);

           emit SettleSuccessfulAuction(auction.Id, block.timestamp);
       }
   }
}