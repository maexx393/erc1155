pragma solidity ^0.5.11;

import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./MyCollectible.sol";
import "./MyFactory.sol";
import "./IAnimalBox.sol";

/**
 * @title MyAnimalBox
 * MyAnimalBox - a randomized and openable animalbox of MyCollectibles
 */
contract MyAnimalBox is IAnimalBox, Ownable, Pausable, ReentrancyGuard, MyFactory {
  using SafeMath for uint256;

  // Event for logging animalbox opens
  event AnimalBoxOpened(uint256 indexed optionId, address indexed buyer, uint256 boxesPurchased, uint256 itemsMinted);
  event Warning(string message, address account);

  // Must be sorted by rarity
  enum Class {
    Common,
    Rare,
    Epic,
    Legendary,
    Divine,
    Hidden
  }
  uint256 constant NUM_CLASSES = 6;

  // NOTE: Price of the animalbox is set via sell orders on OpenSea
  struct OptionSettings {
    // Number of items to send per open.
    // Set to 0 to disable this Option.
    uint256 quantityPerOpen;
    // Probability in basis points (out of 10,000) of receiving each class (descending)
    uint16[NUM_CLASSES] classProbabilities;
  }
  mapping (uint256 => OptionSettings) public optionToSettings;
  mapping (uint256 => uint256[]) public classToTokenIds;
  mapping (uint256 => bool) public classIsPreminted;
  uint256 nonce = 0;
  uint256 constant INVERSE_BASIS_POINT = 10000;

  /**
   * @dev Example constructor. Calls setOptionSettings for you with
   *      sample settings
   * @param _proxyRegistryAddress The address of the OpenSea/Wyvern proxy registry
   *                              On Rinkeby: "0xf57b2c51ded3a29e6891aba85459d600256cf317"
   *                              On mainnet: "0xa5409ec958c83c3f309868babaca7c86dcb077c1"
   * @param _nftAddress The address of the non-fungible/semi-fungible item contract
   *                    that you want to mint/transfer with each open
   */
  constructor(
    address _proxyRegistryAddress,
    address _nftAddress
  ) MyFactory(
    _proxyRegistryAddress,
    _nftAddress
  ) public {
    // Example settings and probabilities
    // you can also call these after deploying
    setOptionSettings(Option.Basic, 3, [7300, 2100, 400, 100, 50, 50]);
    setOptionSettings(Option.Premium, 5, [7200, 2100, 400, 200, 50, 50]);
    setOptionSettings(Option.Gold, 7, [7000, 2100, 400, 400, 50, 50]);
  }

  //////
  // INITIALIZATION FUNCTIONS FOR OWNER
  //////

  /**
   * @dev If the tokens for some class are pre-minted and owned by the
   * contract owner, they can be used for a given class by setting them here
   */
  function setClassForTokenId(
    uint256 _tokenId,
    uint256 _classId
  ) public onlyOwner {
    _checkTokenApproval();
    _addTokenIdToClass(Class(_classId), _tokenId);
  }

  /**
   * @dev Alternate way to add token ids to a class
   * Note: resets the full list for the class instead of adding each token id
   */
  function setTokenIdsForClass(
    Class _class,
    uint256[] memory _tokenIds
  ) public onlyOwner {
    uint256 classId = uint256(_class);
    classIsPreminted[classId] = true;
    classToTokenIds[classId] = _tokenIds;
  }

  /**
   * @dev Remove all token ids for a given class, causing it to fall back to
   * creating/minting into the nft address
   */
  function resetClass(
    uint256 _classId
  ) public onlyOwner {
    delete classIsPreminted[_classId];
    delete classToTokenIds[_classId];
  }

  /**
   * @dev Set token IDs for each rarity class. Bulk version of `setTokenIdForClass`
   * @param _tokenIds List of token IDs to set for each class, specified above in order
   */
  function setTokenIdsForClasses(
    uint256[NUM_CLASSES] memory _tokenIds
  ) public onlyOwner {
    _checkTokenApproval();
    for (uint256 i = 0; i < _tokenIds.length; i++) {
      Class class = Class(i);
      _addTokenIdToClass(class, _tokenIds[i]);
    }
  }

  /**
   * @dev Set the settings for a particular animalbox option
   * @param _option The Option to set settings for
   * @param _quantityPerOpen The number of items to mint per open.
   *                         Set to 0 to disable this option.
   * @param _classProbabilities Array of probabilities (basis points, so integers out of 10,000)
   *                            of receiving each class. Should add up to 10k and be descending
   *                            in value.
   */
  function setOptionSettings(
    Option _option,
    uint256 _quantityPerOpen,
    uint16[NUM_CLASSES] memory _classProbabilities
  ) public onlyOwner {

    OptionSettings memory settings = OptionSettings({
      quantityPerOpen: _quantityPerOpen,
      classProbabilities: _classProbabilities
    });

    optionToSettings[uint256(_option)] = settings;
  }

  ///////
  // MAIN FUNCTIONS
  //////

  /**
   * @dev Open a animalbox manually and send what's inside to _toAddress
   * Convenience method for contract owner.
   */
  function open(
    uint256 _optionId,
    address _toAddress,
    uint256 _amount
  ) external {
    _mint(Option(_optionId), _toAddress, _amount, "");
  }

  /**
   * @dev Main minting logic for animalboxes
   * This is called via safeTransferFrom when MyAnimalBox extends MyFactory.
   * NOTE: prices and fees are determined by the sell order on OpenSea.
   */
  function _mint(
    Option _option,
    address _toAddress,
    uint256 _amount,
    bytes memory /* _data */
  ) internal whenNotPaused nonReentrant {
    // Load settings for this box option
    uint256 optionId = uint256(_option);
    OptionSettings memory settings = optionToSettings[optionId];

    require(settings.quantityPerOpen > 0, "MyAnimalBox#_mint: OPTION_NOT_ALLOWED");
    require(_canMint(msg.sender, _option, _amount), "MyAnimalBox#_mint: CANNOT_MINT");

    // Iterate over the quantity of boxes specified
    for (uint256 i = 0; i < _amount; i++) {
      // Iterate over the box's set quantity
      for (uint256 j = 0; j < settings.quantityPerOpen; j++) {
        Class class = _pickRandomClass(settings.classProbabilities);
        _sendTokenWithClass(class, _toAddress, 1);
      }
    }

    // Event emissions
    uint256 totalMinted = _amount.mul(settings.quantityPerOpen);
    emit AnimalBoxOpened(optionId, _toAddress, _amount, totalMinted);
  }

  function withdraw() public onlyOwner {
    msg.sender.transfer(address(this).balance);
  }

  /////
  // Metadata methods
  /////

  function name() external view returns (string memory) {
    return "My Animal Box";
  }

  function symbol() external view returns (string memory) {
    return "MYANIMAL";
  }

  function uri(uint256 _optionId) external view returns (string memory) {
    return Strings.strConcat(
      baseMetadataURI,
      "box/",
      Strings.uint2str(_optionId)
    );
  }

  /////
  // HELPER FUNCTIONS
  /////

  // Returns the tokenId sent to _toAddress
  function _sendTokenWithClass(
    Class _class,
    address _toAddress,
    uint256 _amount
  ) internal returns (uint256) {
    uint256 classId = uint256(_class);
    MyCollectible nftContract = MyCollectible(nftAddress);
    uint256 tokenId = _pickRandomAvailableTokenIdForClass(_class, _amount);
    if (classIsPreminted[classId]) {
      nftContract.safeTransferFrom(
        owner(),
        _toAddress,
        tokenId,
        _amount,
        ""
      );
    } else if (tokenId == 0) {
      tokenId = nftContract.create(_toAddress, _amount, "", "");
      classToTokenIds[classId].push(tokenId);
    } else {
      nftContract.mint(_toAddress, tokenId, _amount, "");
    }
    return tokenId;
  }

  function _pickRandomClass(
    uint16[NUM_CLASSES] memory _classProbabilities
  ) internal returns (Class) {
    uint16 value = uint16(_random().mod(INVERSE_BASIS_POINT));
    // Start at top class (length - 1)
    // skip common (0), we default to it
    for (uint256 i = _classProbabilities.length - 1; i > 0; i--) {
      uint16 probability = _classProbabilities[i];
      if (value < probability) {
        return Class(i);
      } else {
        value = value - probability;
      }
    }
    return Class.Common;
  }

  function _pickRandomAvailableTokenIdForClass(
    Class _class,
    uint256 _minAmount
  ) internal returns (uint256) {
    uint256 classId = uint256(_class);
    uint256[] memory tokenIds = classToTokenIds[classId];
    if (tokenIds.length == 0) {
      // Unminted
      require(
        !classIsPreminted[classId],
        "MyAnimalBox#_pickRandomAvailableTokenIdForClass: NO_TOKEN_ON_PREMINTED_CLASS"
      );
      return 0;
    }

    uint256 randIndex = _random().mod(tokenIds.length);

    if (classIsPreminted[classId]) {
      // Make sure owner() owns enough
      MyCollectible nftContract = MyCollectible(nftAddress);
      for (uint256 i = randIndex; i < randIndex + tokenIds.length; i++) {
        uint256 tokenId = tokenIds[i % tokenIds.length];
        if (nftContract.balanceOf(owner(), tokenId) >= _minAmount) {
          return tokenId;
        }
      }
      revert("MyAnimalBox#_pickRandomAvailableTokenIdForClass: NOT_ENOUGH_TOKENS_FOR_CLASS");
    } else {
      return tokenIds[randIndex];
    }
  }

  /**
   * @dev Pseudo-random number generator
   * NOTE: to improve randomness, generate it with an oracle
   */
  function _random() internal returns (uint256) {
    uint256 randomNumber = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, nonce)));
    nonce++;
    return randomNumber;
  }

  /**
   * @dev emit a Warning if we're not approved to transfer nftAddress
   */
  function _checkTokenApproval() internal {
    MyCollectible nftContract = MyCollectible(nftAddress);
    if (!nftContract.isApprovedForAll(owner(), address(this))) {
      emit Warning("Animalbox contract is not approved for trading collectible by:", owner());
    }
  }

  function _addTokenIdToClass(Class _class, uint256 _tokenId) internal {
    uint256 classId = uint256(_class);
    classIsPreminted[classId] = true;
    classToTokenIds[classId].push(_tokenId);
  }
}
