// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// solhint-disable no-console

import {Script, console} from "forge-std/Script.sol";

struct Config {
    uint256 scriptPk;
    address lpOwnerAddr;
    address oldERC20Addr;
    address newERC20Addr;
    address erc1155Addr;
    address niftyswapFactory20Addr;
    uint256 lpFee;
    uint256 lpInstance;
    address oldExchangeAddr;
    address newExchangeAddr;
    address uniswapRouterAddr;
    uint256 minSwapDelta;
    uint256 swapFee;
    address migratorAddr;
    uint256 executionWindow;
}

// Note must be alphabetical to retain order after parsing with forge
// https://book.getfoundry.sh/cheatcodes/parse-json
struct LPConfig {
    uint256 currencyAmount;
    uint256 lpAmount;
    uint256 tokenAmount;
    uint256 tokenId;
}

/**
 * Base script. Manages reading configuration files.
 */
abstract contract BaseScript is Script {
    Config internal config;

    function setUp() public virtual {
        config.scriptPk = vm.envUint("SCRIPT_PK");
        config.lpOwnerAddr = vm.envAddress("LP_OWNER_ADDR");
        config.oldERC20Addr = vm.envAddress("OLD_ERC20_ADDR");
        config.newERC20Addr = vm.envAddress("NEW_ERC20_ADDR");
        config.erc1155Addr = vm.envAddress("ERC1155_ADDR");
        config.niftyswapFactory20Addr = vm.envAddress("NIFTYSWAP_FACTORY_20_ADDR");
        config.lpFee = vm.envUint("LP_FEE");
        config.lpInstance = vm.envUint("LP_INSTANCE");
        config.oldExchangeAddr = vm.envAddress("OLD_EXCHANGE_ADDR");
        config.newExchangeAddr = vm.envAddress("NEW_EXCHANGE_ADDR");
        config.uniswapRouterAddr = vm.envAddress("UNISWAP_ROUTER_ADDR");
        config.minSwapDelta = vm.envUint("MIN_SWAP_DELTA");
        config.swapFee = vm.envUint("SWAP_FEE");
        config.migratorAddr = vm.envAddress("MIGRATOR_ADDR");
        config.executionWindow = vm.envUint("EXECUTION_WINDOW_SECONDS");

        // Label addresses for nicer logs
        vm.label(config.lpOwnerAddr, "LP Owner");
        vm.label(vm.addr(config.scriptPk), "Script Runner");
        vm.label(config.oldERC20Addr, "Old ERC20");
        vm.label(config.newERC20Addr, "New ERC20");
        vm.label(config.erc1155Addr, "ERC1155");
        vm.label(config.niftyswapFactory20Addr, "Niftyswap Factory");
        vm.label(config.oldExchangeAddr, "Old Exchange");
        vm.label(config.newExchangeAddr, "New Exchange");
        vm.label(config.uniswapRouterAddr, "Uniswap Swap Router");
        vm.label(config.migratorAddr, "Migrator");
    }

    function getLpConfig() public view returns (LPConfig[] memory lpConfigs) {
        string memory data = vm.readFile("config.json");
        return abi.decode(vm.parseJson(data), (LPConfig[]));
    }
}
