// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// solhint-disable no-console

import {BaseScript, console} from "./BaseScript.s.sol";

import {LiquidityMigrator, IERC1155} from "src/LiquidityMigrator.sol";
import {NiftyswapExchange20} from "@0xsequence/niftyswap/contracts/exchange/NiftyswapExchange20.sol";

/**
 * Migrates liquidity.
 * @dev Please ensure you have configured the following environment variables:
 * - SCRIPT_PK: Private key of the script.
 * - ERC1155_ADDR: Address of the ERC-1155 token contract.
 * - OLD_EXCHANGE_ADDR: Address of the Niftyswap Exchange for the old token pair.
 */
contract PrepareMigrateScript is BaseScript {
    function run() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = vm.envUint("TOKEN_ID"); //FIXME Get a list from config

        uint256 len = tokenIds.length;

        // Get LP amounts
        address[] memory scriptAddrs = new address[](len);
        address scriptAddr = config.lpOwnerAddr == address(0) ? vm.addr(config.scriptPk) : config.lpOwnerAddr;
        console.log("Preparing details for", vm.toString(scriptAddr));

        for (uint256 i = 0; i < len; i++) {
            scriptAddrs[i] = scriptAddr;
        }
        uint256[] memory lpAmounts = IERC1155(config.oldExchangeAddr).balanceOfBatch(scriptAddrs, tokenIds);

        // Get details
        (uint256[] memory tokenAmounts, uint256[] memory currencyAmounts) =
            expectedTokensOnRemoveLP(config.erc1155Addr, config.oldExchangeAddr, tokenIds, lpAmounts);

        // Output details
        string memory output = "[";
        for (uint256 i = 0; i < len; i++) {
            console.log("Token ID: ", tokenIds[i]);
            console.log("LP Amount: ", lpAmounts[i]);
            console.log("Token Amount: ", tokenAmounts[i]);
            console.log("Currency Amount: ", currencyAmounts[i]);

            // Note forge requires JSON to be alphabetically ordered for parsing
            // https://book.getfoundry.sh/cheatcodes/parse-json
            string memory obj = string(
                abi.encodePacked(
                    "{",
                    "\"currencyAmount\":",
                    vm.toString(currencyAmounts[i]),
                    ",",
                    "\"lpAmount\":",
                    vm.toString(lpAmounts[i]),
                    ",",
                    "\"tokenAmount\":",
                    vm.toString(tokenAmounts[i]),
                    ",",
                    "\"tokenId\":",
                    vm.toString(tokenIds[i]),
                    "}"
                )
            );

            output = string(abi.encodePacked(output, i == 0 ? "" : ",", obj));
        }
        output = string(abi.encodePacked(output, "]"));
        vm.writeJson(output, "./config.json");
    }

    function expectedTokensOnRemoveLP(
        address token,
        address exchangeOld,
        uint256[] memory ids,
        uint256[] memory lpAmounts
    ) private view returns (uint256[] memory tokenAmounts, uint256[] memory currencyAmounts) {
        NiftyswapExchange20 exchange = NiftyswapExchange20(exchangeOld);

        uint256[] memory totalLiquidityArray = exchange.getTotalSupply(ids);
        uint256[] memory currencyReserves = exchange.getCurrencyReserves(ids);

        tokenAmounts = new uint256[](ids.length);
        currencyAmounts = new uint256[](ids.length);

        IERC1155 erc1155Token = IERC1155(token);
        address[] memory owners = new address[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            owners[i] = exchangeOld;
        }
        uint256[] memory tokenReserves = erc1155Token.balanceOfBatch(owners, ids);

        for (uint256 i = 0; i < ids.length; i++) {
            if (lpAmounts[i] == 0) {
                // Skip
                console.log("WARNING LP amount zero for id", ids[i]);
                continue;
            }
            uint256 totalLiquidity = totalLiquidityArray[i];
            uint256 currencyReserve = currencyReserves[i];
            uint256 tokenReserve = tokenReserves[i];

            (currencyAmounts[i], tokenAmounts[i]) =
                _toRoundedLiquidity(exchange, ids[i], lpAmounts[i], totalLiquidity, currencyReserve, tokenReserve);
        }
    }

    /**
     * @dev Implementation of the _toRoundedLiquidity function from NiftyswapExchange20.sol
     * @param lpAmount The liquidity pool amount
     * @param totalLiquidity The total liquidity
     * @param currencyReserve The currency reserve
     * @param tokenReserve The token reserve
     * @return currencyAmount The currency amount
     * @return tokenAmount The token amount
     */
    function _toRoundedLiquidity(
        NiftyswapExchange20 exchange,
        uint256 tokenId,
        uint256 lpAmount,
        uint256 totalLiquidity,
        uint256 currencyReserve,
        uint256 tokenReserve
    ) private view returns (uint256, uint256) {
        uint256 currencyNumerator = lpAmount * currencyReserve;
        uint256 tokenNumerator = lpAmount * tokenReserve;

        uint256 soldTokenNumerator = tokenNumerator % totalLiquidity;
        uint256 boughtCurrencyNumerator;

        if (soldTokenNumerator != 0) {
            uint256 virtualTokenReserve = (tokenReserve - (tokenNumerator / totalLiquidity)) * totalLiquidity;
            uint256 virtualCurrencyReserve = (currencyReserve - (currencyNumerator / totalLiquidity)) * totalLiquidity;

            if (virtualCurrencyReserve != 0 && virtualTokenReserve != 0) {
                boughtCurrencyNumerator =
                    exchange.getSellPrice(soldTokenNumerator, virtualTokenReserve, virtualCurrencyReserve);

                (, uint256 royaltyAmount) = exchange.getRoyaltyInfo(tokenId, boughtCurrencyNumerator);
                boughtCurrencyNumerator -= royaltyAmount;

                currencyNumerator += boughtCurrencyNumerator;
            }
        }

        return (currencyNumerator / totalLiquidity, tokenNumerator / totalLiquidity);
    }
}
