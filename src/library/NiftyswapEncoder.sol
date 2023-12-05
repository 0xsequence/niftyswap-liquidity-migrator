// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import {INiftyswapExchange20} from "@0xsequence/niftyswap/contracts/interfaces/INiftyswapExchange20.sol";

library NiftyswapEncoder {
    bytes4 internal constant ADDLIQUIDITY20_SIG = 0x82da2b73;
    bytes4 internal constant REMOVELIQUIDITY20_SIG = 0x5c0bf259;

    function encodeRemoveLiquidity(uint256[] memory minCurrencies, uint256[] memory minTokens, uint256 deadline)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encode(
            REMOVELIQUIDITY20_SIG, INiftyswapExchange20.RemoveLiquidityObj(minCurrencies, minTokens, deadline)
        );
    }

    function encodeAddLiquidity(uint256[] memory maxCurrency, uint256 deadline)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encode(ADDLIQUIDITY20_SIG, INiftyswapExchange20.AddLiquidityObj(maxCurrency, deadline));
    }
}
