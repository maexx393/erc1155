const MyCollectible = artifacts.require("MyCollectible");
const MyAnimalBox = artifacts.require("MyAnimalBox");

// Set to false if you only want the collectible to deploy
const ENABLE_ANIMALBOX = true
// Set if you want to create your own collectible
const NFT_ADDRESS_TO_USE = undefined // e.g. Enjin: '0xfaafdc07907ff5120a76b34b731b278c38d6043c'
// If you want to set preminted token ids for specific classes
const TOKEN_ID_MAPPING = undefined // { [key: number]: Array<[tokenId: string]> }

module.exports = function(deployer, network) {
  // OpenSea proxy registry addresses for rinkeby and mainnet.
  let proxyRegistryAddress
  if (network === 'rinkeby') {
    proxyRegistryAddress = "0xf57b2c51ded3a29e6891aba85459d600256cf317";
  } else {
    proxyRegistryAddress = "0xa5409ec958c83c3f309868babaca7c86dcb077c1";
  }

  if (!ENABLE_ANIMALBOX) {
    deployer.deploy(MyCollectible, proxyRegistryAddress, {gas: 5000000});
  } else if (NFT_ADDRESS_TO_USE) {
    deployer.deploy(MyAnimalBox, proxyRegistryAddress, NFT_ADDRESS_TO_USE, {gas: 5000000})
      .then(setupAnimalbox);
  } else {
    deployer.deploy(MyCollectible, proxyRegistryAddress, {gas: 5000000})
      .then(() => {
        return deployer.deploy(MyAnimalBox, proxyRegistryAddress, MyCollectible.address, {gas: 5000000});
      })
      .then(setupAnimalbox);
  }
};

async function setupAnimalbox() {
  if (!NFT_ADDRESS_TO_USE) {
    const collectible = await MyCollectible.deployed();
    await collectible.transferOwnership(MyAnimalBox.address);
  }

  if (TOKEN_ID_MAPPING) {
    const animalbox = await MyAnimalBox.deployed();
    for (const rarity in TOKEN_ID_MAPPING) {
      console.log(`Setting token ids for rarity ${rarity}`)
      const tokenIds = TOKEN_ID_MAPPING[rarity]
      await animalbox.setTokenIdsForClass(rarity, tokenIds);
    }
  }
}
