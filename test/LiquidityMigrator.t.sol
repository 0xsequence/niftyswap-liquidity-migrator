// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// solhint-disable no-console

import {Test, console} from "forge-std/Test.sol";

import {LiquidityMigrator, ILiquidityMigrator} from "../src/LiquidityMigrator.sol";
import {NiftyswapEncoder} from "../src/library/NiftyswapEncoder.sol";

import {INiftyswapFactory20} from "@0xsequence/niftyswap/contracts/interfaces/INiftyswapFactory20.sol";
import {INiftyswapExchange20} from "@0xsequence/niftyswap/contracts/interfaces/INiftyswapExchange20.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "./uniswap/INonfungiblePositionManager.sol";

import {ERC1155Mock} from "@0xsequence/niftyswap/contracts/mocks/ERC1155Mock.sol";
import {ERC20Mock} from "@0xsequence/erc20-meta-token/contracts/mocks/ERC20Mock.sol";
import {IERC1155} from "@0xsequence/erc-1155/contracts/interfaces/IERC1155.sol";

contract LiquidityMigratorTest is Test {
    LiquidityMigrator public migrator;

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

    /**
     * Set up contracts.
     * @dev We deploy using the compiled bytecode from imported packages to ensure consistency with on chain contracts.
     * @dev We don't care about slippage or LP fees for this test.
     */
    function setUp() public {
        address setUpAddr = makeAddr("setUp");

        // Set up tokens
        setUpTokens(setUpAddr);
        setUpUniswap(address(erc20Old), address(erc20New), UNISWAP_FEE, setUpAddr);
        setUpExchanges(address(erc20Old), address(erc20New), address(erc1155), setUpAddr);

        // Create migrator
        migrator = new LiquidityMigrator();

        // Send LP tokens to migrator
        vm.prank(setUpAddr);
        IERC1155(address(exchangeOld)).safeTransferFrom(
            setUpAddr,
            address(migratingAddr),
            TOKEN_ID,
            1e18,
            ""
        );
    }

    /**
     * Create token contracts and mint to the setup addr.
     */
    function setUpTokens(address setUpAddr) private {
        erc20Old = new ERC20Mock();
        vm.label(address(erc20Old), "ERC20Old");
        erc20New = new ERC20Mock();
        vm.label(address(erc20New), "ERC20New");
        erc1155 = new ERC1155Mock();
        erc20Old.mockMint(setUpAddr, 10 * 1e18);
        erc20New.mockMint(setUpAddr, 10 * 1e18);
        erc1155.mintMock(setUpAddr, TOKEN_ID, 10 * 1e18, "");
    }

    /**
     * Create and add liquidity to uniswap v3 pool.
     */
    function setUpUniswap(address _erc20Old, address _erc20New, uint24 fee, address setUpAddr) private {
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
        erc20Pool = IUniswapV3Pool(_erc20Pool);
        erc20Pool.initialize(encodePriceSqrt(1, 1));

        // Add liquidity
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: erc20Pool.token0(),
            token1: erc20Pool.token1(),
            fee: fee,
            tickLower: -10,
            tickUpper: 10,
            amount0Desired: 1e18,
            amount1Desired: 1e18,
            amount0Min: 0,
            amount1Min: 0,
            recipient: setUpAddr,
            deadline: block.timestamp + 1 // solhint-disable-line not-rely-on-time
        });
        vm.startPrank(setUpAddr);
        erc20Old.approve(_nfpm, 1e18);
        erc20New.approve(_nfpm, 1e18);
        nfpm.mint(params);
        vm.stopPrank();
    }


    /**
     * Create both exchanges and add liquidity to the old one.
     */
    function setUpExchanges(address _erc20Old, address _erc20New, address _erc1155, address setUpAddr) private {
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

        // Add liquidity to old exchange
        uint256[] memory currencies = new uint256[](1);
        currencies[0] = 1e18;
        vm.startPrank(setUpAddr);
        erc20Old.approve(_exchangeOld, 1e18);
        erc1155.safeTransferFrom(
            setUpAddr,
            _exchangeOld,
            TOKEN_ID,
            1e18 / 10, // Less than 1e18 in LP
            NiftyswapEncoder.encodeAddLiquidity(currencies, block.timestamp + 1) // solhint-disable-line not-rely-on-time
        );
        vm.stopPrank();
    }

    //
    // Tests
    //

    function testIt() public {
        logBalance("migratingAddr", migratingAddr);
        logBalance("migrator", address(migrator));

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

        (uint160 sqrtPriceX96,,,,,,) = erc20Pool.slot0();
        bool zeroForOne = erc20Pool.token0() == address(erc20Old);
        ILiquidityMigrator.MigrationData memory data = ILiquidityMigrator.MigrationData({
            deadline: uint96(block.timestamp + 1), // solhint-disable-line not-rely-on-time
            minCurrencies: new uint256[](1), // 0 is ok
            minTokens: new uint256[](1), // 0 is ok
            erc20Old: address(erc20Old),
            erc20New: address(erc20New),
            erc20Router: address(erc20Router),
            swapFee: UNISWAP_FEE,
            sqrtPriceLimitX96: zeroForOne ? sqrtPriceX96 - 1 : sqrtPriceX96 + 1,
            exchangeNew: address(exchangeNew),
            erc1155: address(erc1155)
        });
        vm.prank(migratingAddr);
        IERC1155(address(exchangeOld)).safeTransferFrom(
            migratingAddr,
            address(migrator),
            TOKEN_ID,
            1e18,
            abi.encode(data)
        );

        logBalance("migratingAddr", migratingAddr);
        logBalance("migrator", address(migrator));

        (result) = exchangeNew.getCurrencyReserves(tokenIds);
        assertApproxEqRel(result[0], reserveOld, 1e18 / 1000); // Within 0.1% diff
        (result) = exchangeNew.getPrice_currencyToToken(tokenIds, amounts);
        assertApproxEqRel(result[0], priceTokenOld, 1e18 / 1000); // Within 0.1% diff
        (result) = exchangeNew.getPrice_tokenToCurrency(tokenIds, amounts);
        assertApproxEqRel(result[0], priceCurrencyOld, 1e18 / 1000); // Within 0.1% diff
    }

    function logBalance(string memory who, address owner) private {
        console.log(who, "Old balance", erc20Old.balanceOf(owner));
        console.log(who, "New balance", erc20New.balanceOf(owner));
        console.log(who, "ERC1155", erc1155.balanceOf(owner, TOKEN_ID));
        console.log(who, "Old LP balance", IERC1155(address(exchangeOld)).balanceOf(owner, TOKEN_ID));
        console.log(who, "New LP balance", IERC1155(address(exchangeNew)).balanceOf(owner, TOKEN_ID));
    }

    //
    // Helpers
    //
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
}
