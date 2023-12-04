// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ILiquidityMigrator} from "./ILiquidityMigrator.sol";
import {IERC20} from "@0xsequence/erc-1155/contracts/interfaces/IERC20.sol";
import {IERC1155} from "@0xsequence/erc-1155/contracts/interfaces/IERC1155.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import {NiftyswapEncoder} from "./library/NiftyswapEncoder.sol";
import {FullMath} from "./uniswap/FullMath.sol";

contract LiquidityMigrator is ILiquidityMigrator {
    bytes4 internal constant ERC1155_RECEIVED_VALUE = 0xf23a6e61;
    bytes4 internal constant ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

    bytes4 internal constant ADDLIQUIDITY20_SIG = 0x82da2b73;
    bytes4 internal constant REMOVELIQUIDITY20_SIG = 0x5c0bf259;

    bool private processing;

    /**
     * Handle the receipt of a single ERC1155 token type.
     * @notice This is the entrypoint for migrating liquidity.
     * @dev This function is also called when liquidity token are withdrawn to this contract.
     */
    function onERC1155Received(address, address from, uint256 id, uint256 amount, bytes calldata callData)
        public
        virtual
        returns (bytes4)
    {
        if (!processing) {
            processing = true;
            uint256[] memory ids = new uint256[](1);
            ids[0] = id;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = amount;
            processMigration(from, msg.sender, ids, amounts, callData);
            processing = false;
        }
        return ERC1155_RECEIVED_VALUE;
    }

    /**
     * Handle the receipt of a single ERC1155 token type.
     * @notice This is the entrypoint for migrating liquidity.
     * @dev This function is also called when liquidity token are withdrawn to this contract.
     */
    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata callData
    )
        public
        virtual
        returns (bytes4)
    {
        if (!processing) {
            processing = true;
            processMigration(from, msg.sender, ids, amounts, callData);
            processing = false;
        }
        return ERC1155_BATCH_RECEIVED_VALUE;
    }

    /**
     * Process a migration request.
     * @param from The address that sent the LP tokens.
     * @param exchange The current exchange.
     * @param ids The LP token ids.
     * @param amounts The LP token amounts.
     * @param callData The encoded data for the migration.
     * @dev This is trigger once the LP tokens are received.
     */
    function processMigration(
        address from,
        address exchange,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes calldata callData
    )
        internal
    {
        // Decode data
        MigrationData memory data = decodeMigrationData(callData);

        removeLiquidity(exchange, ids, amounts, data);
        swapERC20(data);
        uint256[] memory lpBalance;
        (lpBalance) = depositLiquidity(ids, amounts, data);
        recoverTokens(from, data, ids, lpBalance);
    }

    /**
     * Remove liquidity from the exchange.
     * @param exchange The exchange to remove liquidity from.
     * @param ids The LP token ids.
     * @param amounts The LP token amounts.
     * @param data The migration data.
     */
    function removeLiquidity(
        address exchange,
        uint256[] memory ids,
        uint256[] memory amounts,
        MigrationData memory data
    )
        internal
    {
        // Remove liquidity by sending LP tokens to iteself
        IERC1155(exchange).safeBatchTransferFrom(
            address(this),
            exchange,
            ids,
            amounts,
            NiftyswapEncoder.encodeRemoveLiquidity(data.minCurrencies, data.minTokens, data.deadline)
        );
    }

    /**
     * Swap ERC20 tokens.
     * @param data The migration data.
     * @dev This swaps the current old ERC20 balance of this contract.
     */
    function swapERC20(MigrationData memory data) internal {
        // Swap ERC20
        uint256 balanceOld = IERC20(data.erc20Old).balanceOf(address(this));
        TransferHelper.safeApprove(data.erc20Old, data.erc20Router, balanceOld);
        uint256 amountOutMinimum = FullMath.mulDiv(balanceOld, data.minSwapDelta, 10000);
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: data.erc20Old,
            tokenOut: data.erc20New,
            fee: data.swapFee,
            recipient: address(this),
            deadline: data.deadline,
            amountIn: balanceOld,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });
        ISwapRouter(data.erc20Router).exactInputSingle(swapParams);
    }

    /**
     * Deposit liquidity into the new exchange.
     * @param ids The LP token ids.
     * @param amounts The LP token amounts.
     * @param data The migration data.
     */
    function depositLiquidity(
        uint256[] memory ids,
        uint256[] memory amounts,
        MigrationData memory data
    )
        internal
        returns (uint256[] memory lpBalance)
    {
        uint256 balanceNew = IERC20(data.erc20New).balanceOf(address(this));
        // Calculate rates
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        address[] memory thiss = new address[](ids.length);
        uint256[] memory currencies = new uint256[](ids.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            thiss[i] = address(this); // This is annoying
            currencies[i] = FullMath.mulDiv(balanceNew, amounts[i], totalAmount); //FIXME This is wrong. The ratio should look at the withdrawn ERC20 price
        }

        TransferHelper.safeApprove(data.erc20New, data.exchangeNew, balanceNew);
        uint256[] memory amountsNew = IERC1155(data.erc1155).balanceOfBatch(thiss, ids);
        IERC1155(data.erc1155).safeBatchTransferFrom(
            address(this),
            data.exchangeNew,
            ids,
            amountsNew,
            NiftyswapEncoder.encodeAddLiquidity(currencies, data.deadline)
        );
        lpBalance = IERC1155(data.exchangeNew).balanceOfBatch(thiss, ids);
    }

    /**
     * Return any remaining tokens to the caller.
     * @notice This includes newly minted LP tokens.
     * @dev This can happen to do slippage and rounding errors.
     */
    function recoverTokens(address from, MigrationData memory data, uint256[] memory ids, uint256[] memory lpBalance)
        internal
    {
        IERC1155(data.exchangeNew).safeBatchTransferFrom(address(this), from, ids, lpBalance, "");
        TransferHelper.safeTransfer(data.erc20Old, from, IERC20(data.erc20Old).balanceOf(address(this)));
        TransferHelper.safeTransfer(data.erc20New, from, IERC20(data.erc20New).balanceOf(address(this)));
    }

    function decodeMigrationData(bytes calldata data) internal pure returns (MigrationData memory migrationData) {
        // Decode data
        migrationData = abi.decode(data, (MigrationData));
    }
}
