// TIME CARDS is deployed on BNB Smart Chain (BSC) mainnet, chainId 56.
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: { optimizer: { enabled: true, runs: 200 }, viaIR: true, evmVersion: "paris" }
  },
  defaultNetwork: "bsc",
  networks: {
    bsc: {
      url: "https://bsc-dataseed.bnbchain.org",
      chainId: 56
    }
  },
  etherscan: {
    apiKey: { bsc: process.env.BSCSCAN_API_KEY || "" }
  }
};
