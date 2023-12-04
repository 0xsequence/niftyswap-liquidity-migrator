// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {LiquidityMigrator, ILiquidityMigrator} from "../src/LiquidityMigrator.sol";

/// @dev Exposes internal functions for testing.
/// @dev Adds toggle for processing end to end on LP tokens received
contract PublicLiquidityMigrator is LiquidityMigrator {
    bool private _processOnReceive;

    function setProcessOnReceive(bool processOnReceive) external {
        _processOnReceive = processOnReceive;
    }

    function onERC1155Received(address operator, address from, uint256 id, uint256 amount, bytes calldata callData)
        public
        override
        returns (bytes4)
    {
        if (_processOnReceive) {
            return super.onERC1155Received(operator, from, id, amount, callData);
        }
        return ERC1155_RECEIVED_VALUE;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata callData
    )
        public
        override
        returns (bytes4)
    {
        if (_processOnReceive) {
            return super.onERC1155BatchReceived(operator, from, ids, amounts, callData);
        }
        return ERC1155_BATCH_RECEIVED_VALUE;
    }

    function callRemoveLiquidity(
        address exchange,
        uint256[] memory ids,
        uint256[] memory amounts,
        MigrationData memory data
    )
        external
    {
        super.removeLiquidity(exchange, ids, amounts, data);
    }

    function callSwapERC20(MigrationData memory data) external {
        super.swapERC20(data);
    }

    function callDepositLiquidity(
        uint256[] memory ids,
        uint256[] memory amounts,
        MigrationData memory data
    )
        external
        returns (uint256[] memory lpBalance)
    {
        return super.depositLiquidity(ids, amounts, data);
    }

    function callRecoverTokens(address from, MigrationData memory data, uint256[] memory ids, uint256[] memory lpBalance)
        external
    {
        super.recoverTokens(from, data, ids, lpBalance);
    }
}
