// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IERC1155TokenReceiver} from "@0xsequence/erc-1155/contracts/interfaces/IERC1155TokenReceiver.sol";

interface ILiquidityMigrator is IERC1155TokenReceiver {
    //FIXME Order for gas efficiency
    // Send this as data to onERC1155Received to trigger migration
    struct MigrationData {
        // Remove liquidity params
        uint96 deadline;
        uint256[] minCurrencies;
        uint256[] minTokens;
        // ERC20 swap params
        address erc20Router;
        address erc20Old;
        address erc20New;
        uint24 swapFee;
        uint24 minSwapDelta; // Min amount of tokens to receive from swap as a percentage of input (10000 = 100%)
        // Add liquidity params
        address exchangeNew;
        address erc1155;
    }
}
