// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// solhint-disable no-console

import {BaseScript, LPConfig, console} from "./BaseScript.s.sol";

import {ILiquidityMigrator} from "src/ILiquidityMigrator.sol";
import {INiftyswapFactory20} from "@0xsequence/niftyswap/contracts/interfaces/INiftyswapFactory20.sol";
import {IERC1155} from "@0xsequence/erc-1155/contracts/interfaces/IERC1155.sol";

/**
 * Migrates liquidity.
 * @dev Please ensure you have configured the following environment variables:
 * - SCRIPT_PK: Private key of the deployer.
 * - ERC1155_ADDR: Address of the ERC-1155 token contract.
 * - OLD_ERC20_ADDR: Address of the ERC-20 token contract that you will migrate from.
 * - NEW_ERC20_ADDR: Address of the ERC-20 token contract that you will migrate to.
 * - OLD_EXCHANGE_ADDR: Address of the Niftyswap Exchange for the old token pair.
 * - NEW_EXCHANGE_ADDR: Address of the Niftyswap Exchange for the new token pair. Obtain from deployment script.
 * - UNISWAP_ROUTER_ADDR: Address of the Uniswap Swap Router.
 * - MIN_SWAP_DELTA: The minimum percentage of Token B that must be obtained after swapping Token A.
 * - MIGRATOR_ADDR: Address of the LiquidityMigrator contract. Obtain from deployment script.
 * - EXECUTION_WINDOW_SECONDS: Deadline in which the migration is valid.
 */
contract MigrateLiquidityScript is BaseScript {
    LPConfig[] private lpConfigs;

    function setUp() public override {
        super.setUp();
        lpConfigs = getLpConfig();
    }

    function run() public {
        (ILiquidityMigrator.MigrationData memory data, uint256[] memory tokenIds, uint256[] memory lpAmounts) =
            prepareMigrationData();

        IERC1155 oldExchange = IERC1155(config.oldExchangeAddr);

        bool live = config.lpOwnerAddr == address(0);
        address scriptAddr = live ? vm.addr(config.scriptPk) : config.lpOwnerAddr;
        if (live) {
            console.log("Running migrating with", vm.toString(scriptAddr));
            vm.startBroadcast(config.scriptPk);
        } else {
            console.log("Simulating migration with", vm.toString(scriptAddr));
            vm.startBroadcast(scriptAddr);
        }
        oldExchange.safeBatchTransferFrom(scriptAddr, config.migratorAddr, tokenIds, lpAmounts, abi.encode(data));
        vm.stopBroadcast();
    }

    function prepareMigrationData()
        private
        view
        returns (ILiquidityMigrator.MigrationData memory data, uint256[] memory tokenIds, uint256[] memory lpAmounts)
    {
        // Create arrays
        uint256 len = lpConfigs.length;
        uint256[] memory minCurrencies = new uint256[](len);
        uint256[] memory minTokens = new uint256[](len);
        tokenIds = new uint256[](len);
        lpAmounts = new uint256[](len);
        for (uint256 i; i < len; i++) {
            minCurrencies[i] = lpConfigs[i].currencyAmount;
            minTokens[i] = lpConfigs[i].tokenAmount;
            tokenIds[i] = lpConfigs[i].tokenId;
            lpAmounts[i] = lpConfigs[i].lpAmount;
        }

        // Create data
        data = ILiquidityMigrator.MigrationData({
            deadline: uint96(block.timestamp + config.executionWindow), // solhint-disable-line not-rely-on-time
            minCurrencies: minCurrencies,
            minTokens: minTokens,
            erc20Old: config.oldERC20Addr,
            erc20New: config.newERC20Addr,
            erc20Router: config.uniswapRouterAddr,
            swapFee: uint24(config.swapFee),
            minSwapDelta: uint24(config.minSwapDelta),
            exchangeNew: config.newExchangeAddr,
            erc1155: config.erc1155Addr
        });
    }
}
