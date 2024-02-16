// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {PoolFactory} from "../../src/PoolFactory.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";

contract Handler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    int256 public starting_x;
    int256 public starting_y;
    int256 public expected_delta_x;
    int256 public expected_delta_y;
    int256 public actual_delta_x;
    int256 public actual_delta_y;

    address liquidtyProvider = makeAddr("lp");
    address swapper = makeAddr("swapper");

    constructor(TSwapPool _pool) public {
        pool = _pool;
        weth = ERC20Mock(pool.getWeth());
        poolToken = ERC20Mock(pool.getPoolToken());
    }

    function swapWethBasedOnOutputWeth(uint256 outputWeth) public {
        uint256 minwethToDeposit = pool.getMinimumWethDepositAmount();
        outputWeth = bound(outputWeth, minwethToDeposit, weth.balanceOf(address(pool)));
        if (outputWeth >= weth.balanceOf(address(pool))) {
            return;
        }
        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWeth,
            poolToken.balanceOf(address(pool)),
            weth.balanceOf(address(pool))
        );
        if (poolTokenAmount > type(uint64).max) {
            return;
        }

        starting_x = int256(poolToken.balanceOf(address(pool)));
        starting_y = int256(weth.balanceOf(address(pool)));
        expected_delta_y = int256(-1) * int256(outputWeth);
        expected_delta_x = int256(poolTokenAmount);

        // swap
        if (poolToken.balanceOf(swapper) < poolTokenAmount) {
            poolToken.mint(
                swapper,
                poolTokenAmount - poolToken.balanceOf(swapper) + 1
            );
        }
        vm.startPrank(swapper);
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        vm.stopPrank();

        // actual
        uint256 ending_x = poolToken.balanceOf(address(pool));
        uint256 ending_y = weth.balanceOf(address(pool));

        actual_delta_x = int256(ending_x) - int256(starting_x);
        actual_delta_y = int256(ending_y) - int256(starting_y);

    }

    function deposit(uint256 wethAmount) public {
        wethAmount = bound(wethAmount, pool.getMinimumWethDepositAmount(), type(uint64).max);

        // starting token amount
        starting_x = int256(poolToken.balanceOf(address(pool)));
        starting_y = int256(weth.balanceOf(address(pool)));

        // expected token amount
        expected_delta_y = int256(wethAmount);
        expected_delta_x = int256(
            pool.getPoolTokensToDepositBasedOnWeth(wethAmount)
        );

        vm.startPrank(liquidtyProvider);
        weth.mint(liquidtyProvider, wethAmount);
        poolToken.mint(liquidtyProvider, uint256(expected_delta_x));

        //approve
        weth.approve(address(pool), type(uint256).max);
        poolToken.approve(address(pool), type(uint256).max);

        // deposit
        pool.deposit(
            wethAmount,
            0,
            uint256(expected_delta_x),
            uint64(block.timestamp)
        );
        vm.stopPrank();

        //actual
        uint256 ending_x = poolToken.balanceOf(address(pool));
        uint256 ending_y = weth.balanceOf(address(pool));

        actual_delta_x = int256(ending_x) - int256(starting_x);
        actual_delta_y = int256(ending_y) - int256(starting_y);
    }
}
