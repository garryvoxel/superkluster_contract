const hre = require("hardhat");
async function main() {

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // We get the contract to deploy
    const Voxelx = await hre.ethers.getContractFactory("VoxelxCollection");
    const voxelx = await Voxelx.deploy("Voxelx NFT", "Voxelx", "https://gateway.pinata.cloud/ipfs/QmZFBivjMWUUyKE3t7TPpdrmAUTWp9gWGF1cLvGny9yJ6M/");
    

    await voxelx.deployed();

    console.log("Voxelx deployed to:", voxelx.address);
}
  
main()
.then(() => process.exit(0))
.catch((error) => {
    console.error(error);
    process.exit(1);
});