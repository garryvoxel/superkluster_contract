//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "hardhat/console.sol";
interface ISKCollection {
    function mintItem(
        address account,
        uint256 tokenId,
        uint256 supply,
        string memory tokenURI_
    ) external;

    function setMarketplaceAddress (
        address _marketplaceAddress
    ) external;

    function setTokenURI(uint256 tokenId, string memory tokenURI_) external;      
}

struct CollectionInfo {
    address collection;
    bool batch;
    uint256[] tokenIds;
    uint256[] quantities;
}
struct Receiver {
    address receiver;
    CollectionInfo[] collections;
}

struct CartCollection {
    address collection;
    bool batch;
    address[] creators;
    uint256[] tokenIds;
    uint256[] prices;
    uint256[] royaltyAmounts;
    string[] tokenURIs;
}
struct CartSeller {
    address seller;
    uint256 price;
    CartCollection[] collections;
}

contract SKMarketPlace is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    
    address private vxlToken;
    
    uint256 public serviceFee;
    uint256 public ethServiceFee;
    address private skTeamWallet;

    address public signer;
    address private timeLockController;

    mapping(address => bool) public skCollection;
    mapping(address => uint256) public nonces;
    mapping(address => uint256) private userRoyalties;
    mapping(address => uint256) private userETHRoyalties;

    bytes4 private constant InterfaceId_ERC721 = 0x80ac58cd;
    bytes4 private constant InterfaceId_ERC1155 = 0xd9b67a26;
    bytes4 private constant InterfaceId_ERC2981 = 0x2a55205a;
    bytes4 private constant InterfaceId_Reveal = 0xa811a37b;

    event BuyItem(
        address collection,
        address buyer,
        address seller,
        uint256 tokenId,
        uint256 quantity,
        uint256 mintQty,
        uint256 price,
        uint256 currency,
        uint256 timestamp
    );
    event AcceptItem(
        address collection,
        address seller,
        address buyer,
        uint256 tokenId,
        uint256 quantity,
        uint256 mintQty,
        uint256 price,
        uint256 timestamp
    );
    event TransferBundle(
        address from,
        uint256 timestamp
    );
    event BuyCart(
        address buyer,
        uint256 payload,
        uint256 currency,
        uint256 timestamp
    );

    function initialize(
        address _vxlToken,
        address _signer, 
        address _skTeamWallet, 
        address _timeLockController
    ) public initializer {
        vxlToken = _vxlToken;
        timeLockController = _timeLockController;
        skTeamWallet = _skTeamWallet;
        signer = _signer;
        ethServiceFee = serviceFee = 150;
    }

    modifier collectionCheck(address _collection) {
        require(
            IERC721(_collection).supportsInterface(InterfaceId_ERC721) ||
                IERC1155(_collection).supportsInterface(InterfaceId_ERC1155),
            "SKMarketPlace: This is not ERC721/ERC1155 collection"
        );
        _;
    }

    modifier onlyTimeLockController() {
        require(
            timeLockController == msg.sender,
            "only timeLock contract can access SKMarketPlace Contract"
        );
        _;                
    }

    function getClaimRoyalty() external view returns (uint256, uint256) {
        return (userRoyalties[msg.sender], userETHRoyalties[msg.sender]);
    }

    function acceptItem(
        address _collection,
        address _buyer,
        address _creator,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _price,
        uint256 _royaltyAmount,
        uint256 _mintQty,
        string memory _tokenURI,
        bool _shouldMint,
        uint256 deadline,
        bytes memory _signature        
    ) external whenNotPaused nonReentrant collectionCheck(_collection) {
        require(
            _buyer != address(0x0),
            "SKMarketPlace: Invalid buyer address"
        );

        _verifyBuyMessageAndMint(
            _collection,
            _buyer,
            _msgSender(),
            _creator,
            _tokenId,
            _quantity,
            _price,
            _royaltyAmount,
            _mintQty,
            _tokenURI,
            _shouldMint,
            deadline,
            _signature
        );

        _buyProcess(_collection, _msgSender(), _buyer, _creator, _tokenId, _quantity, _price, _royaltyAmount, 2);

        emit AcceptItem(
            _collection,
            _msgSender(),
            _buyer,
            _tokenId,
            _quantity,
            _mintQty,
            _price,
            block.timestamp
        );
    }

    function buyItemWithETH(
        address _collection,
        address _seller,
        address _creator,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _price,
        uint256 _royaltyAmount,
        uint256 _mintQty,
        string memory _tokenURI,
        bool _shouldMint,
        uint256 deadline,
        bytes memory _signature
    ) external payable whenNotPaused nonReentrant collectionCheck(_collection) {
        require(
            _seller != address(0x0),
            "SKMarketPlace: Invalid seller address"
        );

        require(msg.value >= _price * _quantity, 'SKMarketPlace: INSUFFICIENT_ETH_AMOUNT');
        
        _verifyBuyMessageAndMint(
            _collection,
            _msgSender(),
            _seller, 
            _creator,
            _tokenId,
            _quantity,
            _price,
            _royaltyAmount,
            _mintQty,
            _tokenURI,
            _shouldMint,
            deadline,
            _signature
        );

        _buyProcess(_collection, _seller, _msgSender(), _creator, _tokenId, _quantity, _price, _royaltyAmount, 1);

        emit BuyItem(_collection, _msgSender(), _seller, _tokenId, _quantity, _mintQty, _price, 1, block.timestamp);
    }

    function buyItem(
        address _collection,
        address _seller,
        address _creator,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _price,
        uint256 _royaltyAmount,
        uint256 _mintQty,
        string memory _tokenURI,
        bool _shouldMint,
        uint256 deadline,
        bytes memory _signature
    ) external whenNotPaused nonReentrant collectionCheck(_collection) {

        require(
            _seller != address(0x0),
            "SKMarketPlace: Invalid seller address"
        );

        _verifyBuyMessageAndMint(
            _collection,
            _msgSender(),
            _seller, 
            _creator,
            _tokenId,
            _quantity,
            _price,
            _royaltyAmount,
            _mintQty,
            _tokenURI,
            _shouldMint,
            deadline,
            _signature
        );

        _buyProcess(_collection, _seller, _msgSender(), _creator, _tokenId, _quantity, _price, _royaltyAmount, 2);
        
        emit BuyItem(_collection, _msgSender(), _seller, _tokenId, _quantity, _mintQty, _price, 2, block.timestamp);
    }

    function buyCart(
        CartSeller[] calldata _sellers,
        uint256 _cartPrice,
        uint256 _payload,
        uint256 deadline,
        bytes memory _signature
    ) external whenNotPaused nonReentrant {
        _verifyCartMessage(_sellers, _cartPrice, _payload, deadline, _signature);

        IERC20(vxlToken).transferFrom(_msgSender(), address(this), _cartPrice);
        uint256 totalFeeAmount = _buyCartProcess(_sellers, 2);

        if (totalFeeAmount > 0) {
            IERC20(vxlToken).transfer(skTeamWallet, totalFeeAmount);
        }
        emit BuyCart(_msgSender(), _payload, 2, block.timestamp);
    }

    function buyCartWithETH(
        CartSeller[] calldata _sellers,
        uint256 _cartPrice,
        uint256 _payload,
        uint256 deadline,
        bytes memory _signature
    ) external payable whenNotPaused nonReentrant {

        console.log("buyCartWithETH: ", msg.value);

        require(msg.value >= _cartPrice, 'SKMarketPlace: INSUFFICIENT_ETH_AMOUNT');

        _verifyCartMessage(_sellers, _cartPrice, _payload, deadline, _signature);

        uint256 totalFeeAmount = _buyCartProcess(_sellers, 1);

        if (totalFeeAmount > 0) {
            (bool sent, ) = skTeamWallet.call{ value: totalFeeAmount }("");
            require(sent, "SKMarketPlace: Failed to send ETH Fee");
        }

        emit BuyCart(_msgSender(), _payload, 1, block.timestamp);
    }

    function bundleTransfer(
        Receiver[] memory _receivers
    ) external whenNotPaused nonReentrant {
        require(
            _receivers.length > 0,
            "SKMarketPlace: Invalid receiver list"
        );

        for(uint256 i; i < _receivers.length; i = unsafe_inc(i)) {
            require(
                _receivers[i].receiver != address(0x0) && _receivers[i].collections.length > 0,
                "SKMarketPlace: Invalid receiver address or collection list"
            );
            for(uint256 j; j < _receivers[i].collections.length; j = unsafe_inc(j)) {
                require(
                    _receivers[i].collections[j].collection != address(0x0),
                    "SKMarketPlace: Invalid receiver's collection address"
                );
                if(_receivers[i].collections[j].batch) {
                    IERC1155(_receivers[i].collections[j].collection).safeBatchTransferFrom(
                        msg.sender,
                        _receivers[i].receiver,
                        _receivers[i].collections[j].tokenIds,
                        _receivers[i].collections[j].quantities,
                        ""
                    );               
                }
                else {
                    for(uint256 k; k < _receivers[i].collections[j].tokenIds.length; k = unsafe_inc(k)) {
                        IERC721( _receivers[i].collections[j].collection).safeTransferFrom(
                            msg.sender,
                            _receivers[i].receiver,
                            _receivers[i].collections[j].tokenIds[k]
                        );      
                    }
                }
            }            
        }

        emit TransferBundle(msg.sender, block.timestamp);          
    }

    function claimRoyalty(address account) external whenNotPaused nonReentrant {
        require(account != address(0x0), "Royalty claim address is invalid");
        uint256 balance = userRoyalties[_msgSender()];

        if(balance > 0) {
            IERC20(vxlToken).transfer(account, balance);
        }

        balance = userETHRoyalties[_msgSender()];

        if(balance > 0) {
            (bool sent, ) = account.call{ value: balance }("");
            require(sent, "SKMarketPlace: Failed to send ETH to claim user");    
        }

        userRoyalties[_msgSender()] = 0;
        userETHRoyalties[_msgSender()] = 0;
    }

    function setTimeLockController(address _timeLockController)
        external
        onlyTimeLockController
    {
        require(
            _timeLockController != address(0x0),
            "SKMarketPlace: Invalid TimeLockController"
        );
        timeLockController = _timeLockController;
    }

    function setSigner(address _signer) external onlyTimeLockController {
        require(_signer != address(0x0), "SKMarketPlace: Invalid signer");
        signer = _signer;
    }

    function setServiceFee(uint256 _serviceFee)
        external
        onlyTimeLockController
    {
        require(
            _serviceFee < 10000,
            "SKMarketPlace: ServiceFee should not reach 100 percent"
        );
        serviceFee = _serviceFee;
    }

    function setETHServiceFee(uint256 _ethServiceFee)
        external
        onlyTimeLockController
    {
        require(
            _ethServiceFee < 10000,
            "SKMarketPlace: ETHServiceFee should not reach 100 percent"
        );
        ethServiceFee = _ethServiceFee;
    }

    function setSKTeamWallet(address _skTeamWallet)
        external
        onlyTimeLockController
    {
        require(
            _skTeamWallet != address(0x0),
            "SKMarketPlace: Invalid admin team wallet address"
        );
        skTeamWallet = _skTeamWallet;
    }

    function setMarketAddressforNFTCollection(address _collection, address _newMarketplaceAddress)
        external
        whenNotPaused
        collectionCheck(_collection) 
        onlyTimeLockController
    {
        ISKCollection(_collection).setMarketplaceAddress(_newMarketplaceAddress);
    }

    function pause() external onlyTimeLockController {
        _pause();
    }

    function unpause() external onlyTimeLockController {
        _unpause();
    }

    function unsafe_inc(uint x) private pure returns (uint) {
        unchecked { return x + 1; }
    }

    function _royaltyProcess(
        address sender,
        address receiver,
        uint256 royaltyAmount,
        uint256 tokenAmount,
        uint256 currency
    ) private returns (uint256) {
        require(
            royaltyAmount < tokenAmount,
            "SKMarketPlace: RoyaltyAmount exceeds than tokenAmount"
        );

        if(currency == 1) {
            userETHRoyalties[receiver] += royaltyAmount;        
        }
        else {
            IERC20(vxlToken).transferFrom(sender, address(this), royaltyAmount);
            userRoyalties[receiver] += royaltyAmount;
        }
        
        unchecked {
            tokenAmount = tokenAmount - royaltyAmount;
        }
        return tokenAmount;
    }

    function _multiRoyaltyProcess(
        address[] memory receivers,
        uint256[] memory royaltyAmounts,
        uint256 tokenAmount,
        uint256 currency
    ) private returns (uint256) {

        uint256 totalRoyaltyAmount = 0;

        if(currency == 1) {
            for(uint256 i; i < receivers.length; i ++) {
                if(receivers[i] != address(0x0) && royaltyAmounts[i] > 0) {
                    userETHRoyalties[receivers[i]] += royaltyAmounts[i];
                    totalRoyaltyAmount += royaltyAmounts[i];
                }
            }
        }
        else {
            for(uint256 i; i < receivers.length; i ++) {
                if(receivers[i] != address(0x0) && royaltyAmounts[i] > 0) {
                    userRoyalties[receivers[i]] += royaltyAmounts[i];
                    totalRoyaltyAmount += royaltyAmounts[i];
                }
            }
        }
        
        if(totalRoyaltyAmount > 0) {
            require(
                totalRoyaltyAmount < tokenAmount,
                "SKMarketPlace: RoyaltyAmount exceeds than tokenAmount"
            );

            unchecked {
                tokenAmount = tokenAmount - totalRoyaltyAmount;
            }
        }
        return tokenAmount;
    }

    function _buyProcess(
        address _collection,
        address _seller,
        address _buyer,
        address _creator,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _price,
        uint256 _royaltyAmount,
        uint256 _currency
    ) private {
        uint256 tokenAmount = _price * _quantity;
        uint256 feeAmount = 0;

        uint256 _feePercentage = _currency == 1 ? ethServiceFee : serviceFee;

        if(_feePercentage > 0) {
            feeAmount = (tokenAmount * _feePercentage) / 10000;
            tokenAmount -= feeAmount;
        }

        if(IERC165(_collection).supportsInterface(InterfaceId_ERC2981)) {
            (address _receiver, uint256 royaltyAmount) = IERC2981(
                _collection
            ).royaltyInfo(_tokenId, _price);
            royaltyAmount = royaltyAmount * _quantity;

            if(royaltyAmount > 0) {
                tokenAmount = _royaltyProcess(_buyer, _receiver, royaltyAmount, tokenAmount, _currency);
            }
        }
        else if(_royaltyAmount > 0) {
            tokenAmount = _royaltyProcess(_buyer, _creator, _royaltyAmount, tokenAmount, _currency);
        }

        if(_currency == 1) {
            (bool sent, ) = _seller.call{ value: tokenAmount }("");
            require(sent, "SKMarketPlace: Failed to send ETH to seller");

            if(feeAmount > 0) {
                (sent, ) = skTeamWallet.call{ value: feeAmount }("");
                require(sent, "SKMarketPlace: Failed to send ETH Fee");
            }
        }
        else {
            IERC20(vxlToken).transferFrom(_buyer, _seller, tokenAmount);
            if(feeAmount > 0) {
                IERC20(vxlToken).transferFrom(_buyer, skTeamWallet, feeAmount);
            }
        }

        //ERC721
        if (IERC721(_collection).supportsInterface(InterfaceId_ERC721)) {
            IERC721(_collection).safeTransferFrom(
                _seller,
                _buyer,
                _tokenId
            );
        } else {
            IERC1155(_collection).safeTransferFrom(
                _seller,    
                _buyer,
                _tokenId,
                _quantity,
                ""
            );
        }   
    }

    function _verifyBuyMessageAndMint(
        address _collection,
        address _buyer,
        address _seller,
        address _creator,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _price,
        uint256 _royaltyAmount,
        uint256 _mintQty,
        string memory _tokenURI,
        bool _shouldMint,
        uint256 _deadline,
        bytes memory _signature
    ) private {

        require(
            block.timestamp <= _deadline,
            "SKMarketPlace: Invalid expiration in acceptItem"
        );

        uint256 _nonce = nonces[_msgSender()];

        bytes32 messageHash = keccak256(
                abi.encodePacked(
                    _collection,
                    _buyer,
                    _seller,
                    _creator,
                    _tokenId,
                    _quantity,
                    _price,
                    _royaltyAmount,
                    _mintQty,
                    _tokenURI,
                    _shouldMint,
                    _nonce,
                    _deadline
                )
            );

        bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(
            messageHash
        );

        require(
            ECDSA.recover(ethSignedMessageHash, _signature) == signer,
            "SKMarketPlace: Invalid Signature in buy"
        );

        if(_shouldMint) {
            ISKCollection(_collection).mintItem(
                _seller,
                _tokenId,
                _mintQty,
                _tokenURI
            );
        }

        _nonce = _nonce + 1;
        nonces[_msgSender()] = _nonce;
    }

    function _verifyCartMessage(
        CartSeller[] calldata _sellers,
        uint256 _cartPrice,
        uint256 _payload,
        uint256 deadline,
        bytes memory _signature
    ) private {

        require(
            _sellers.length > 0,
            "SKMarketPlace: Invalid seller list"
        );

        require(
            block.timestamp <= deadline,
            "SKMarketPlace: Invalid expiration in buyCart"
        );

        uint256 _nonce = nonces[_msgSender()];

        bytes memory data;

        for(uint i; i < _sellers.length; i = unsafe_inc(i)) {
            for(uint j; j < _sellers[i].collections.length; j = unsafe_inc(j)) {
                for(uint k; k < _sellers[i].collections[j].tokenIds.length; k = unsafe_inc(k)) {
                    data = abi.encodePacked(data,
                        _sellers[i].collections[j].creators[k],
                        _sellers[i].collections[j].tokenIds[k],
                        _sellers[i].collections[j].prices[k],
                        _sellers[i].collections[j].royaltyAmounts[k],
                        _sellers[i].collections[j].tokenURIs[k]
                    );
                }
                data = abi.encodePacked(data, _sellers[i].collections[j].collection, _sellers[i].collections[j].batch);
            }
            data = abi.encodePacked(data, _sellers[i].seller, _sellers[i].price);            
        }

        bytes32 messageHash = keccak256(abi.encodePacked(data, _msgSender(), _cartPrice, _payload, _nonce, deadline));

        require(
            ECDSA.recover(ECDSA.toEthSignedMessageHash(messageHash), _signature) == signer,
            "SKMarketPlace: Invalid Signature in buyCart"
        );

        _nonce = _nonce + 1;
        nonces[_msgSender()] = _nonce;
    }

    function _buyCartProcess(
        CartSeller[] calldata _sellers,
        uint256 _currency
    ) private returns(uint256) {
        uint256 totalFeeAmount;

        uint256 _feePercentage = _currency == 1 ? ethServiceFee : serviceFee;

        for(uint i; i < _sellers.length; i = unsafe_inc(i)) {
            uint256 tokenAmount = _sellers[i].price;
            uint256 feeAmount;

            if (_feePercentage > 0) {
                feeAmount = (tokenAmount * _feePercentage) / 10000;
                tokenAmount = tokenAmount - feeAmount;
                totalFeeAmount = totalFeeAmount + feeAmount;
            }

            CartSeller memory sellerInfo = _sellers[i];

            for(uint j; j < sellerInfo.collections.length; j = unsafe_inc(j)) {
                if(IERC165(sellerInfo.collections[j].collection).supportsInterface(InterfaceId_ERC2981)) {
                    address[] memory receivers = new address[](sellerInfo.collections[j].tokenIds.length);
                    uint256[] memory royaltyAmounts = new uint256[](sellerInfo.collections[j].tokenIds.length);
                    address collectionElm = sellerInfo.collections[j].collection;
                    for(uint k; k < sellerInfo.collections[j].tokenIds.length; k = unsafe_inc(k)) {
                        (address _receiver, uint256 royaltyAmount) = IERC2981(
                            collectionElm
                        ).royaltyInfo(sellerInfo.collections[j].tokenIds[k], sellerInfo.collections[j].prices[k]);
                        
                        receivers[k] = _receiver;
                        royaltyAmounts[k] = royaltyAmount;
                    }
                    tokenAmount = _multiRoyaltyProcess(receivers, royaltyAmounts, tokenAmount, _currency);
                }
                else {
                    tokenAmount = _multiRoyaltyProcess(sellerInfo.collections[j].creators, sellerInfo.collections[j].royaltyAmounts, tokenAmount, _currency);
                }

                for(uint k; k < sellerInfo.collections[j].tokenIds.length; k = unsafe_inc(k)) {
                    if(bytes(sellerInfo.collections[j].tokenURIs[k]).length > 0) {
                        ISKCollection(sellerInfo.collections[j].collection).mintItem(
                            sellerInfo.seller,
                            sellerInfo.collections[j].tokenIds[k],
                            1,
                            sellerInfo.collections[j].tokenURIs[k]
                        );
                    }
                }

                if(sellerInfo.collections[j].batch) {
                    uint256[] memory quantities = new uint256[](sellerInfo.collections[j].tokenIds.length);
                    
                    for(uint k; k < quantities.length; k = unsafe_inc(k)) {
                        quantities[k] = 1;
                    }

                    IERC1155(sellerInfo.collections[j].collection).safeBatchTransferFrom(
                        sellerInfo.seller,
                        _msgSender(),
                        sellerInfo.collections[j].tokenIds,
                        quantities,
                        ""
                    );
                }
                else {
                    for(uint k; k < sellerInfo.collections[j].tokenIds.length; k = unsafe_inc(k)) {
                        IERC721(sellerInfo.collections[j].collection).safeTransferFrom(
                            sellerInfo.seller,
                            _msgSender(),
                            sellerInfo.collections[j].tokenIds[k]
                        );
                    }
                }   
            }

            if(_currency == 1) {
                (bool sent, ) = sellerInfo.seller.call{ value: tokenAmount }("");
                require(sent, "SKMarketPlace: Failed to send ETH to seller");
            }
            else {
                IERC20(vxlToken).transfer(sellerInfo.seller, tokenAmount);
            }
            
        }

        return totalFeeAmount;
    }
}