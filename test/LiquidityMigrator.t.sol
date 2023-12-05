// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

// solhint-disable no-console
// solhint-disable no-inline-assembly

import {Test, console} from "forge-std/Test.sol";

import {ILiquidityMigrator} from "../src/ILiquidityMigrator.sol";
import {PublicLiquidityMigrator} from "./PublicLiquidityMigrator.sol";
import {NiftyswapEncoder} from "../src/library/NiftyswapEncoder.sol";

import {INiftyswapFactory20} from "@0xsequence/niftyswap/contracts/interfaces/INiftyswapFactory20.sol";
import {INiftyswapExchange20} from "@0xsequence/niftyswap/contracts/interfaces/INiftyswapExchange20.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "./uniswap/INonfungiblePositionManager.sol";
import {FullMath} from "src/uniswap/FullMath.sol";

import {ERC1155Mock} from "@0xsequence/niftyswap/contracts/mocks/ERC1155Mock.sol";
import {ERC20Mock} from "@0xsequence/erc20-meta-token/contracts/mocks/ERC20Mock.sol";
import {IERC1155} from "@0xsequence/erc-1155/contracts/interfaces/IERC1155.sol";

contract LiquidityMigratorTest is Test {
    PublicLiquidityMigrator public migrator;

    ERC20Mock public erc20Old;
    ERC20Mock public erc20New;
    ERC1155Mock public erc1155;

    uint256 private constant TOKEN_ID = 0;
    uint24 private constant UNISWAP_FEE = 500;

    INiftyswapExchange20 public exchangeOld;
    INiftyswapExchange20 public exchangeNew;

    ISwapRouter public erc20Router;
    IUniswapV3Pool public erc20Pool;

    address public migratingAddr = makeAddr("migrating");
    address public setUpAddr = makeAddr("setUp");

    /**
     * Set up contracts.
     * @dev We deploy using the compiled bytecode from imported packages to ensure consistency with on chain contracts.
     * @dev We don't care about slippage or LP fees for this test.
     */
    function setUp() public {
        // Set up tokens
        setUpTokens();
        setUpUniswap(address(erc20Old), address(erc20New), UNISWAP_FEE);
        setUpExchanges(address(erc20Old), address(erc20New), address(erc1155));

        // Create migrator
        migrator = new PublicLiquidityMigrator();
    }

    /**
     * Create token contracts and mint to the setup addr.
     */
    function setUpTokens() private {
        erc20Old = new ERC20Mock();
        vm.label(address(erc20Old), "ERC20Old");
        erc20New = new ERC20Mock();
        vm.label(address(erc20New), "ERC20New");
        erc1155 = new ERC1155Mock();
        erc20Old.mockMint(setUpAddr, 100 * 1e18);
        erc20New.mockMint(setUpAddr, 100 * 1e18);
    }

    /**
     * Create and add liquidity to uniswap v3 pool.
     */
    function setUpUniswap(address _erc20Old, address _erc20New, uint24 fee) private {
        // Create pool
        address _factory =
            deployCode("node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json");
        vm.label(_factory, "UniswapV3Factory");
        IUniswapV3Factory factory = IUniswapV3Factory(_factory);
        address _nfpm = deployCode(
            "node_modules/@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json",
            abi.encode(_factory, address(0), "")
        );
        vm.label(_nfpm, "NonfungiblePositionManager");
        INonfungiblePositionManager nfpm = INonfungiblePositionManager(_nfpm);
        address _erc20Router = deployCode(
            "node_modules/@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json",
            abi.encode(_factory, address(0))
        );
        vm.label(_erc20Router, "SwapRouter");
        erc20Router = ISwapRouter(_erc20Router);

        address _erc20Pool = factory.createPool(_erc20Old, _erc20New, fee); // Low fee tier
        vm.label(_erc20Pool, "UniswapPool");
        erc20Pool = IUniswapV3Pool(_erc20Pool);
        erc20Pool.initialize(encodePriceSqrt(1, 1));

        // Add liquidity
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: erc20Pool.token0(),
            token1: erc20Pool.token1(),
            fee: fee,
            tickLower: -10,
            tickUpper: 10,
            amount0Desired: 10e18,
            amount1Desired: 10e18,
            amount0Min: 0,
            amount1Min: 0,
            recipient: setUpAddr,
            deadline: block.timestamp + 1 // solhint-disable-line not-rely-on-time
        });
        vm.startPrank(setUpAddr);
        erc20Old.approve(_nfpm, 10e18);
        erc20New.approve(_nfpm, 10e18);
        nfpm.mint(params);
        vm.stopPrank();
    }

    /**
     * Create both exchanges and add liquidity to the old one.
     */
    function setUpExchanges(address _erc20Old, address _erc20New, address _erc1155) private {
        address _factory = deployCode(
            "node_modules/@0xsequence/niftyswap/artifacts/contracts/exchange/NiftyswapFactory20.sol/NiftyswapFactory20.json",
            abi.encode(address(this))
        );
        vm.label(_factory, "NiftyswapFactory20");
        INiftyswapFactory20 factory = INiftyswapFactory20(_factory);

        factory.createExchange(_erc1155, _erc20Old, 10, 0);
        address _exchangeOld = factory.tokensToExchange(_erc1155, _erc20Old, 10, 0);
        vm.label(_exchangeOld, "NiftyswapExchange20Old");
        exchangeOld = INiftyswapExchange20(_exchangeOld);

        factory.createExchange(_erc1155, _erc20New, 10, 0);
        address _exchangeNew = factory.tokensToExchange(_erc1155, _erc20New, 10, 0);
        vm.label(_exchangeNew, "NiftyswapExchange20New");
        exchangeNew = INiftyswapExchange20(_exchangeNew);
    }

    // Add liquidity to old exchange
    function addExchangeLiquidity(
        address exchangeAddr,
        uint256 currencyAmount,
        uint256 tokenId,
        uint256 tokenAmount,
        address lpTokenHolder
    )
        private
    {

        uint256[] memory currencies = new uint256[](1);
        currencies[0] = currencyAmount;

        IERC1155 exchangeToken = IERC1155(exchangeAddr);
        uint256 lpBal = exchangeToken.balanceOf(setUpAddr, tokenId);

        erc20Old.mockMint(setUpAddr, currencyAmount);
        erc1155.mintMock(setUpAddr, tokenId, tokenAmount, "");
        vm.startPrank(setUpAddr);
        erc20Old.approve(exchangeAddr, currencyAmount);

        erc1155.safeTransferFrom(
            setUpAddr,
            exchangeAddr,
            tokenId,
            tokenAmount,
            NiftyswapEncoder.encodeAddLiquidity(currencies, block.timestamp + 1) // solhint-disable-line not-rely-on-time
        );
        lpBal = exchangeToken.balanceOf(setUpAddr, tokenId) - lpBal;
        exchangeToken.safeTransferFrom(setUpAddr, lpTokenHolder, tokenId, lpBal, "");
        vm.stopPrank();
    }

    //
    // End to End
    //
    function testEndToEnd() public {
        migrator.setProcessOnReceive(true); // Normal processing
        addExchangeLiquidity(address(exchangeOld), 1e18, TOKEN_ID, 1e18 / 10, migratingAddr);

        logBalance("Before migratingAddr", migratingAddr);
        logBalance("Before migrator", address(migrator));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = TOKEN_ID;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e10;
        uint256[] memory result;
        (result) = exchangeOld.getCurrencyReserves(tokenIds);
        uint256 reserveOld = result[0];
        (result) = exchangeOld.getPrice_currencyToToken(tokenIds, amounts);
        uint256 priceTokenOld = result[0];
        (result) = exchangeOld.getPrice_tokenToCurrency(tokenIds, amounts);
        uint256 priceCurrencyOld = result[0];

        ILiquidityMigrator.MigrationData memory data = ILiquidityMigrator.MigrationData({
            deadline: uint96(block.timestamp + 1), // solhint-disable-line not-rely-on-time
            minCurrencies: new uint256[](1), // 0 is ok
            minTokens: new uint256[](1), // 0 is ok
            erc20Old: address(erc20Old),
            erc20New: address(erc20New),
            erc20Router: address(erc20Router),
            swapFee: UNISWAP_FEE,
            minSwapDelta: 9990,
            exchangeNew: address(exchangeNew),
            erc1155: address(erc1155)
        });
        vm.prank(migratingAddr);
        IERC1155(address(exchangeOld)).safeTransferFrom(
            migratingAddr, address(migrator), TOKEN_ID, 1e18, abi.encode(data)
        );

        logBalance("After migratingAddr", migratingAddr);
        logBalance("After migrator", address(migrator));

        (result) = exchangeNew.getCurrencyReserves(tokenIds);
        assertApproxEqRel(result[0], reserveOld, 1e18 / 1000); // Within 0.1% diff
        (result) = exchangeNew.getPrice_currencyToToken(tokenIds, amounts);
        assertApproxEqRel(result[0], priceTokenOld, 1e18 / 1000); // Within 0.1% diff
        (result) = exchangeNew.getPrice_tokenToCurrency(tokenIds, amounts);
        assertApproxEqRel(result[0], priceCurrencyOld, 1e18 / 1000); // Within 0.1% diff
    }

    //FIXME End to end with multiple LPs of diff pricings

    //
    // Remove Liquidity
    //
    function testRemoveLiquidity(
        uint256 tokenAmount,
        uint256 currencyAmount,
        uint256 minCurrency,
        uint256 minToken,
        uint256 tokenId
    )
        public
    {
        ILiquidityMigrator.MigrationData memory data = baseData();
        tokenAmount = _bound(tokenAmount, 100, 1e18);
        currencyAmount = _bound(currencyAmount, 1000, 1e18);
        uint256[] memory minCurrencies = new uint256[](1);
        minCurrencies[0] = _bound(minCurrency, 1, currencyAmount);
        data.minCurrencies = minCurrencies;
        uint256[] memory minTokens = new uint256[](1);
        minTokens[0] = _bound(minToken, 1, tokenAmount);
        data.minTokens = minTokens;

        addExchangeLiquidity(address(exchangeOld), currencyAmount, tokenId, tokenAmount, address(migrator));

        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = IERC1155(address(exchangeOld)).balanceOf(address(migrator), tokenId); // LP

        migrator.callRemoveLiquidity(address(exchangeOld), ids, amounts, data);

        assertGe(erc20Old.balanceOf(address(migrator)), data.minCurrencies[0]);
        assertGe(erc1155.balanceOf(address(migrator), tokenId), data.minTokens[0]);
        assertEq(IERC1155(address(exchangeOld)).balanceOf(address(migrator), tokenId), 0);
    }

    //
    // Swap ERC20
    //
    function testSwapERC20(uint256 balanceOld) public {
        balanceOld = _bound(balanceOld, 1000, 1e18);

        ILiquidityMigrator.MigrationData memory data = baseData();

        erc20Old.mockMint(address(migrator), balanceOld);
        uint256 balanceNew = erc20New.balanceOf(address(migrator));

        migrator.callSwapERC20(data);

        //Note We aren't validating Uniswap correctness. Only that one went down and another went up
        assertLe(erc20Old.balanceOf(address(migrator)), balanceOld);
        assertGe(erc20New.balanceOf(address(migrator)), balanceNew);
    }

    //
    // Deposit Liquidity
    //
    function testDepositLiquidityStable(
        uint256[] memory ids,
        uint256[] memory amounts,
        uint256 balance
    )
        public
    {
        (ids, amounts) = boundIdsAndAmounts(ids, amounts, 3);
        balance = _bound(balance, 1000 * ids.length, 100e18);
        uint256[] memory currencies = new uint256[](ids.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            currencies[i] = balance / amounts.length;
        }

        ILiquidityMigrator.MigrationData memory data = baseData();

        erc20New.mockMint(address(migrator), balance);
        erc1155.batchMintMock(address(migrator), ids, amounts, "");

        (uint256[] memory lpBalance) = migrator.callDepositLiquidity(ids, amounts, data, currencies, balance, balance);

        uint256[] memory zeros = new uint256[](ids.length);
        address[] memory thiss = new address[](ids.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            thiss[i] = address((address(migrator)));
        }
        assertEq(zeros, erc1155.balanceOfBatch(thiss, ids)); // Everything used
        assertEq(lpBalance, IERC1155(data.exchangeNew).balanceOfBatch(thiss, ids)); // LP output correct
        assertApproxEqAbs(0, erc20New.balanceOf(address(migrator)), 3); // Rounding error
        assertEq(exchangeNew.getCurrencyReserves(ids), currencies); // Reserves correct
    }

    function testDepositLiquidityDiffPrices(
        uint256[] memory ids,
        uint256[] memory amounts,
        uint256 balanceNew,
        uint256[] memory currencies
    ) public {
        (ids, amounts) = boundIdsAndAmounts(ids, amounts, 3);
        uint256 len = ids.length;
        assembly {
            mstore(currencies, len)
        }
        uint256 balanceOld;
        uint256 lowestCurr = type(uint256).max;
        for (uint256 i = 0; i < len; i++) {
            currencies[i] = _bound(currencies[i], 1000, 1e18);
            balanceOld += currencies[i];
            if (currencies[i] < lowestCurr) {
                lowestCurr = currencies[i];
            }
        }
        // For large spreads new currency bal to deposit must exceed 1000 for the smallest LP
        // vm.assume(lowestCurr < 100e18);
        lowestCurr = FullMath.mulDiv(1000 * ids.length, balanceOld, lowestCurr);
        balanceNew = _bound(balanceNew, lowestCurr, 100e18);

        ILiquidityMigrator.MigrationData memory data = baseData();

        erc20New.mockMint(address(migrator), balanceNew);
        erc1155.batchMintMock(address(migrator), ids, amounts, "");

        (uint256[] memory lpBalance) = migrator.callDepositLiquidity(ids, amounts, data, currencies, balanceOld, balanceNew);

        uint256[] memory zeros = new uint256[](ids.length);
        address[] memory thiss = new address[](ids.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            thiss[i] = address((address(migrator)));
        }
        assertEq(zeros, erc1155.balanceOfBatch(thiss, ids)); // Everything used
        assertEq(lpBalance, IERC1155(data.exchangeNew).balanceOfBatch(thiss, ids)); // LP output correct
        assertApproxEqAbs(0, erc20New.balanceOf(address(migrator)), 3); // Rounding error

        uint256[] memory reserves = exchangeNew.getCurrencyReserves(ids);
        for (uint256 i = 0; i < len; i++) {
            console.log("curr, res", currencies[i], reserves[i]);
            assertEq(reserves[i], FullMath.mulDiv(balanceNew, currencies[i], balanceOld)); // Reserves correct
            if (i > 0) {
                // Price ratio accounting for rounding error
                assertApproxEqAbs(currencies[i] / reserves[i], currencies[i - 1] / reserves[i - 1], balanceOld);
                assertApproxEqAbs(reserves[i] / currencies[i], reserves[i - 1] / currencies[i - 1], balanceOld);
            }
        }
    }

    //
    // Recover Tokens
    //
    function testRecoverTokens(
        address receiver,
        uint256 erc20OldBal,
        uint256 erc20NewBal,
        uint256[] memory ids,
        uint256[] memory amounts
    )
        public
    {
        assumeSafeAddress(receiver);
        (ids, amounts) = boundIdsAndAmounts(ids, amounts, 3);
        erc20OldBal = _bound(erc20OldBal, 1, 100e18);
        erc20NewBal = _bound(erc20NewBal, 1, 100e18);

        address _migrator = address(migrator);

        erc20Old.mockMint(_migrator, erc20OldBal);
        erc20New.mockMint(_migrator, erc20NewBal);
        ILiquidityMigrator.MigrationData memory data = baseData();
        data.exchangeNew = address(erc1155); // Pretend this is LP
        erc1155.batchMintMock(_migrator, ids, amounts, "");

        migrator.callRecoverTokens(receiver, data, ids, amounts);

        {
            assertEq(erc20Old.balanceOf(_migrator), 0);
            assertEq(erc20New.balanceOf(_migrator), 0);
            assertEq(erc20Old.balanceOf(receiver), erc20OldBal);
            assertEq(erc20New.balanceOf(receiver), erc20NewBal);
            for (uint256 i = 0; i < ids.length; i++) {
                assertEq(erc1155.balanceOf(_migrator, ids[i]), 0);
                assertEq(erc1155.balanceOf(receiver, ids[i]), amounts[i]);
            }
        }
    }

    //
    // Helpers
    //
    function baseData() private view returns (ILiquidityMigrator.MigrationData memory data) {
        return ILiquidityMigrator.MigrationData({
            deadline: uint96(block.timestamp + 1), // solhint-disable-line not-rely-on-time
            minCurrencies: new uint256[](0),
            minTokens: new uint256[](0),
            erc20Old: address(erc20Old),
            erc20New: address(erc20New),
            erc20Router: address(erc20Router),
            swapFee: UNISWAP_FEE,
            minSwapDelta: 9000, // 10.0% in/out diff
            exchangeNew: address(exchangeNew),
            erc1155: address(erc1155)
        });
    }

    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) private pure returns (uint160 price) {
        return uint160(sqrt(reserve1 / reserve0) * 2 ** 96);
    }

    function sqrt(uint256 x) private pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function logBalance(string memory who, address owner) internal view {
        console.log(who, "Old ERC20 balance", erc20Old.balanceOf(owner));
        console.log(who, "New ERC20 balance", erc20New.balanceOf(owner));
        console.log(who, "ERC1155", erc1155.balanceOf(owner, TOKEN_ID));
        console.log(who, "Old LP balance", IERC1155(address(exchangeOld)).balanceOf(owner, TOKEN_ID));
        console.log(who, "New LP balance", IERC1155(address(exchangeNew)).balanceOf(owner, TOKEN_ID));
    }

    function assumeSafeAddress(address addr) internal view {
        vm.assume(addr != address(0));
        assumeNotPrecompile(addr);
        assumeNotForgeAddress(addr);
        vm.assume(addr.code.length == 0); // Non contract
        vm.assume(addr != setUpAddr);
    }

    function sortArray(uint256[] memory arr) internal pure returns (uint256[] memory sorted) {
        sorted = arr;
        for (uint256 i = 0; i < sorted.length; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (sorted[i] > sorted[j]) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }
    }

    function assumeNoDuplicates(uint256[] memory arr) internal pure {
        for (uint256 i = 0; i < arr.length; i++) {
            for (uint256 j = i + 1; j < arr.length; j++) {
                vm.assume(arr[i] != arr[j]);
            }
        }
    }

    function boundIdsAndAmounts(uint256[] memory ids, uint256[] memory amounts, uint256 maxLength)
        internal
        view
        returns (uint256[] memory outputIds, uint256[] memory outputAmounts)
    {
        uint256 maxLen = ids.length > amounts.length ? ids.length : amounts.length;
        maxLen = maxLen > maxLength ? maxLength : (maxLen == 0 ? 1 : maxLen);
        assembly {
            mstore(ids, maxLen)
        }
        console.log("maxLen", maxLen);
        console.log("ids.length", ids.length);
        console.log("amounts.length", amounts.length);

        // Check ids
        assumeNoDuplicates(ids);
        outputIds = sortArray(ids);

        // Limit amounts
        outputAmounts = new uint256[](maxLen);
        for (uint256 i = 0; i < maxLen; i++) {
            console.log(i);
            if (maxLen > amounts.length) {
                outputAmounts[i] = 1;
            } else {
                outputAmounts[i] = _bound(amounts[i], 1, type(uint96).max);
            }
        }
    }

    function fixArrayLength(uint256[] memory arr, uint256 length) internal pure returns (uint256[] memory output) {
        output = arr;
        assembly {
            mstore(output, length)
        }
        return output;
    }

    function boundDeadline(uint96 deadline) internal view returns (uint96) {
        return uint96(_bound(uint256(deadline), block.timestamp + 1, type(uint96).max));
    }
}
