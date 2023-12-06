// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// solhint-disable no-console

import {BaseScript, console} from "./BaseScript.s.sol";

import {LiquidityMigrator} from "src/LiquidityMigrator.sol";
import {INiftyswapFactory20} from "@0xsequence/niftyswap/contracts/interfaces/INiftyswapFactory20.sol";

/**
 * Deploys the MigrateLiquidity contract and the Niftyswap Exchange for the new token pair.
 * @dev Please ensure you have configured the following environment variables:
 * - SCRIPT_PK: Private key of the deployer.
 * - ERC1155_ADDR: Address of the ERC-1155 token contract.
 * - NEW_ERC20_ADDR: Address of the ERC-20 token contract that you will migrate to.
 * - LP_FEE: Fee that will go to LPs. Number between 0 and 1000, where 10 is 1.0% and 100 is 10%.
 * - LP_INSTANCE: Instance # that allows to deploy new instances of an exchange.
 * - NIFTYSWAP_FACTORY_20_ADDR: Address of the NiftyswapFactory20 contract.
 */
contract DeployScript is BaseScript {
    function run() public {
        deployMigrator(config.scriptPk);
        deployNiftyswapLP(
            config.scriptPk,
            config.niftyswapFactory20Addr,
            config.erc1155Addr,
            config.newERC20Addr,
            config.lpFee,
            config.lpInstance
        );
    }

    function deployMigrator(uint256 pk) private {
        vm.startBroadcast(pk);
        LiquidityMigrator migrator = new LiquidityMigrator();
        vm.stopBroadcast();

        console.log("LiquidityMigrator deployed at", address(migrator));
    }

    function deployNiftyswapLP(
        uint256 pk,
        address factoryAddr,
        address token,
        address currency,
        uint256 lpFee,
        uint256 instance
    )
        private
        returns (address exchange)
    {
        INiftyswapFactory20 factory = INiftyswapFactory20(factoryAddr);
        exchange = factory.tokensToExchange(token, currency, lpFee, instance);
        if (exchange != address(0x0)) {
            console.log("NiftyswapExchange already deployed at", exchange);
            return exchange;
        }

        vm.startBroadcast(pk);
        factory.createExchange(token, currency, lpFee, instance);
        vm.stopBroadcast();
        exchange = factory.tokensToExchange(token, currency, lpFee, instance);

        console.log("NiftyswapExchange deployed at", exchange);
    }
}
