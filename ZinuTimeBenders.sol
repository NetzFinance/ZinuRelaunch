// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ZinuTimeBenders is ERC721Enumerable, Ownable, ERC721Royalty {
    using Strings for uint256;

    uint256 public maxSupply;

    bool public revealed;

    string public baseURI;
    string public prerevealBaseURI;

    string public baseExtension = ".json";

    string public _contractURI;

    constructor(
        string memory _initBaseURI,
        string memory _initContractURI,
        string memory _initPrerevalURI,
        address _owner,
        address _royaltyFeeReceiver,
        uint96 _royaltyFeeNumerator,
        uint256 _maxSupply
    ) ERC721("ZINU TIME BENDERS", "ZINU") Ownable(_owner) {
        baseURI = _initBaseURI;
        _contractURI = _initContractURI;
        prerevealBaseURI = _initPrerevalURI;
        _setDefaultRoyalty(_royaltyFeeReceiver, _royaltyFeeNumerator);
        maxSupply = _maxSupply;
    }

    //===== NFT Mint Functions =====\\
    function airdropNftsViaMint(
        address[] memory _recipients,
        uint256[] memory _amounts
    ) external onlyOwner {
        uint256 amount;
        for (uint256 i = 0; i < _amounts.length; i++) {
            amount += _amounts[i];
        }
        require(
            totalSupply() + amount <= maxSupply,
            "Cant mint over max supply"
        );
        require(
            _recipients.length == _amounts.length,
            "recipients and Amount length must be equal"
        );
        require(
            _recipients.length <= 500 && _amounts.length <= 500,
            "recipients and Amount length must be less than 500 at a time"
        );
        for (uint256 i = 0; i < _recipients.length; i++) {
            _mint(_recipients[i], _amounts[i]);
        }
    }

    //===== Helper Functions =====\\
    function batchTransferNfts(address _to, uint256[] memory _tokenIds) public {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (ownerOf(_tokenIds[i]) != msg.sender) {
                revert("caller is not the owner of the nft");
            }
        }

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            safeTransferFrom(msg.sender, _to, _tokenIds[i]);
        }
    }

    function airdropNftsViaID(
        address[] memory _recipients,
        uint256[] memory _tokenIds
    ) external onlyOwner {
        require(
            _recipients.length == _tokenIds.length,
            "recipients and tokenIds length must be equal"
        );

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (ownerOf(_tokenIds[i]) != msg.sender) {
                revert("caller is not the owner of the nft");
            }
        }

        for (uint256 i = 0; i < _recipients.length; i++) {
            safeTransferFrom(msg.sender, _recipients[i], _tokenIds[i]);
        }
    }

    //===== Admin Functions =====\\
    function revealTimeBenders() external onlyOwner {
        revealed = true;
    }

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function setPrerevealBaseURI(string memory _newPrerevealBaseURI)
        external
        onlyOwner
    {
        prerevealBaseURI = _newPrerevealBaseURI;
    }

    function setBaseExtension(string memory _newBaseExtension)
        external
        onlyOwner
    {
        baseExtension = _newBaseExtension;
    }

    function setContractURI(string memory _newContractURI) external onlyOwner {
        _contractURI = _newContractURI;
    }

    function setRoyaltyFees(address _recipient, uint64 _feeNumerator)
        public
        onlyOwner
    {
        _setDefaultRoyalty(_recipient, _feeNumerator);
    }

    //===== Read Functions =====\\
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _ownerOf(tokenId) != address(0),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (revealed) {
            string memory currentBaseURI = _baseURI();
            return
                bytes(currentBaseURI).length > 0
                    ? string(
                        abi.encodePacked(
                            currentBaseURI,
                            tokenId.toString(),
                            baseExtension
                        )
                    )
                    : "";
        } else {
            return
                bytes(prerevealBaseURI).length > 0
                    ? string(
                        abi.encodePacked(
                            prerevealBaseURI,
                            tokenId.toString(),
                            baseExtension
                        )
                    )
                    : "";
        }
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    //===== Ovveride Functions =====\\
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable, ERC721Royalty)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }
}
