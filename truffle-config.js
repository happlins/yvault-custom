var HDWalletProvider = require("truffle-hdwallet-provider");  // 导入模块
var mnemonic = "xxx xxx xxx xxx xxx";  //MetaMask的助记词。
var INFURA_ID = "xxxx"

module.exports = {
    networks: {
        development: {
            host: "127.0.0.1",     // Localhost (default: none)
            port: 7545,            // Standard Ethereum port (default: none)
            network_id: "*",       // Any network (default: none)
        },
        kovan: {
            provider: function () {
                return new HDWalletProvider(mnemonic, "https://kovan.infura.io/v3/"+INFURA_ID, 0);
            },
            network_id: "*",  // match any network
            gas: 4600000,
            gasPrice: 12000000000,
            confirmations: 2,    // # of confs to wait between deployments. (default: 0)
            timeoutBlocks: 200,  // # of blocks before a deployment times out  (minimum/default: 50)
            skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
        }
    },

    mocha: {},
    compilers: {
        solc: {
            version: "0.5.17",    // Fetch exact version from solc-bin (default: truffle's version)
            docker: false,        // Use "0.5.1" you've installed locally with docker (default: false)
            settings: {          // See the solidity docs for advice about optimization and evmVersion
                optimizer: {
                    enabled: true,
                    runs: 200
                },
                evmVersion: "constantinople"
            }
        },
    },
};
