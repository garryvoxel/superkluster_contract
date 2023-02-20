const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Giveaway with the account:", deployer.address);

    const voxelx = await hre.ethers.getContractFactory("VoxelxCollection");
    const address = '0x95cB0E33C84e1c94e88F6361e7864790c9992833';
    
    const VOXELX = await voxelx.attach(address);
    
    console.log("tokenURI: ", await VOXELX.tokenURI(992));
}

main()
.then(() => process.exit(0))
.catch((error) => {
  console.error(error);
  process.exit(1);
});