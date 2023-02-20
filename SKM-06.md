# SKM-06

## Description

For add and buy operations, all relevant parameters are provided by the user and validated through the
center-controlled signer key.

## Recommendation

We would like to enquire about the scenario under which the contract is used in general and specifically
how these two functions will be used.

## addItem

We have 2 functions addItem() and buyItem() in SMMarketplace smart contract.
In marketplace we have 2 kind of collections - SKCollection and external collection.
1. External collection is NFT contract that contract deployer or nft owner imports to marketplace. 
The peculiarity is that most of these are stored in the on-chain.
2. SKCollection is NFT collection that are created inside marketplace.
Collection information is stored in offchain and NFT included in Collection is minted in SK721Collection and SK1155Collection.
[addItem] function is used in SKCollection NFT mint.
    - User [David] creates [collectionA] in marketplace and this info is stored in offchain.
    - User [David] creates NFT [itemA] in [collectionA] and this NFT info is stored in offchain too.
      [David] pays no gas fee to create NFT.
    - [David] wants to sell his [itemA] so he needs to list his NFT with price for sale.
      When [David] lists his [itemA] with [priceA] in marketplace, 
      * Frontend requests to backend that [David] lists his [itemA].
      * if [itemA] is already minted in on-chain, only list info is stored in off-chain. (in this case , user pays no gas fee.)
      * if [itemA] is still in off-chain, marketplace signer key(It is stored very securely with the help of Cloud Service so that it cannot be hacked.) signs message from 
      [itemA]'s info which is stored in offchain.
        Frontend will get this sign message from backend and call addItem function with sign message and tokenID, tokenURI etc.
        In addItem , smart contract verifies message if it is valid and was signed exactly in backend, and if verify is success  it will mint [itemA] in on-chain (to SK721 or SK1155 Collection)
        When transaction is success, list info is stored in off-chain.
      

## buyItem

- [David] lists his [itemA] with [priceA] in marketplace.
- [Erik] wants to buy [itemA] with [priceA].
   * Frontend requests [itemA]'s offchain unique id and [Erik]'s addreess to backend.
   * Backend gets [itemA]'s info from offchain using unique id such as NFT contract address,
   tokenID, quantity and price.
   * Backend signs [Contract address, tokenID, quantity, price, seller address, buyer address] using marketplace signer key and responses this message with plain info.
   * Frontend calls buyItem function with signed message and [itemA]'s info.
   In buyItem function , [David] will get tokens from [Erik] and [Erik] will get ownership of [itemA].

   addItem and buyItem are secured by the marketplace's private key and encryption algorithm.