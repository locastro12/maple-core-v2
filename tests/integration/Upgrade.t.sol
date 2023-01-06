// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Address } from "../../modules/contract-test-utils/contracts/test.sol";

import { IMapleProxyFactory }     from "../../modules/pool-v2/modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";
import { INonTransparentProxy }   from "../../modules/globals-v2/modules/non-transparent-proxy/contracts/interfaces/INonTransparentProxy.sol";
import { INonTransparentProxied } from "../../modules/globals-v2/modules/non-transparent-proxy/contracts/interfaces/INonTransparentProxied.sol";

import { MapleGlobals }      from "../../modules/globals-v2/contracts/MapleGlobals.sol";
import { MapleLoan as Loan } from "../../modules/loan-v400/contracts/MapleLoan.sol";
import { LoanManager }       from "../../modules/pool-v2/contracts/LoanManager.sol";
import { Liquidator }        from "../../modules/liquidations/contracts/Liquidator.sol";
import { PoolManager }       from "../../modules/pool-v2/contracts/PoolManager.sol";
import { WithdrawalManager } from "../../modules/withdrawal-manager/contracts/WithdrawalManager.sol";

import { TestBase } from "../../contracts/utilities/TestBase.sol";

contract GlobalsUpgradeTests is TestBase {

    address internal newImplementation = address(new MapleGlobals());

    function test_upgradeGlobals_notAdmin() external {
        INonTransparentProxy proxy = INonTransparentProxy(address(globals));

        vm.expectRevert("NTP:SI:NOT_ADMIN");
        proxy.setImplementation(newImplementation);

        vm.prank(governor);
        proxy.setImplementation(newImplementation);

        assertEq(INonTransparentProxied(globals).implementation(), newImplementation);
    }

    function test_upgradeGlobals() external {
        INonTransparentProxy proxy = INonTransparentProxy(address(globals));

        vm.prank(governor);
        proxy.setImplementation(newImplementation);

        assertEq(INonTransparentProxied(globals).implementation(), newImplementation);
    }

}

contract LoanManagerUpgradeTests is TestBase {

    address internal newImplementation = address(new LoanManager());

    bytes internal upgradeCallData = new bytes(0);

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);

        IMapleProxyFactory(loanManagerFactory).registerImplementation(2, newImplementation, address(0));
        IMapleProxyFactory(loanManagerFactory).enableUpgradePath(1, 2, address(0));

        vm.stopPrank();
    }

    function test_upgradeLoanManager_noTimelock() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(LoanManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        globals.scheduleCall(address(loanManager), "LM:UPGRADE", scheduleArgs);

        // Wait for delay duration.
        vm.warp(start + 1 weeks);

        loanManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeLoanManager_delayNotPassed() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(LoanManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(loanManager), "LM:UPGRADE", scheduleArgs);

        // Warp to right before clearing delay.
        vm.warp(start + 1 weeks - 1);

        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        vm.warp(start + 1 weeks);
        loanManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeLoanManager_durationPassed() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(LoanManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(loanManager), "LM:UPGRADE", scheduleArgs);

        // Warp to right after duration end.
        vm.warp(start + 1 weeks + 2 days + 1);

        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        vm.warp(start + 1 weeks + 2 days);
        loanManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeLoanManager_timelockExtended() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(LoanManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.prank(poolDelegate);
        globals.scheduleCall(address(loanManager), "LM:UPGRADE", scheduleArgs);

        // Warp to beginning of timelock duration.
        vm.warp(start + 1 weeks);

        bool isValid = globals.isValidScheduledCall(poolDelegate, address(loanManager), "LM:UPGRADE", scheduleArgs);

        // Should be valid before we change the timelock settings.
        assertTrue(isValid);

        vm.prank(governor);
        globals.setTimelockWindow(address(loanManager), "LM:UPGRADE", 2 weeks, 1 weeks);

        isValid = globals.isValidScheduledCall(poolDelegate, address(loanManager), "LM:UPGRADE", scheduleArgs);
        assertTrue(!isValid);

        vm.startPrank(poolDelegate);

        // With timelock change, upgrade should now revert.
        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        // Warp to right before duration begin
        vm.warp(start + 2 weeks - 1);

        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        // Warp to past duration.
        vm.warp(start + 2 weeks + 1 weeks + 1);

        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        // Warp to right at duration end.
        vm.warp(start + 2 weeks + 1 weeks);

        loanManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeLoanManager_timelockShortened() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(LoanManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.prank(poolDelegate);
        globals.scheduleCall(address(loanManager), "LM:UPGRADE", scheduleArgs);

        // Warp to beginning of timelock duration.
        vm.warp(start + 1 weeks);

        bool isValid = globals.isValidScheduledCall(poolDelegate, address(loanManager), "LM:UPGRADE", scheduleArgs);

        // Should be valid before we change the timelock settings.
        assertTrue(isValid);

        vm.prank(governor);
        globals.setTimelockWindow(address(loanManager), "LM:UPGRADE", 2 days, 1 days);

        isValid = globals.isValidScheduledCall(poolDelegate, address(loanManager), "LM:UPGRADE", scheduleArgs);
        assertTrue(!isValid);

        vm.startPrank(poolDelegate);

        // With timelock change, we should be past the duration.
        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        // Warp to right before duration begin
        vm.warp(start + 2 days - 1);

        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        // Warp to past duration.
        vm.warp(start + 2 days + 1 days + 1);

        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        // Warp to right at duration end.
        vm.warp(start + 2 days + 1 days);

        loanManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeLoanManager_governor_noTimelockNeeded() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(LoanManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(loanManager), "LM:UPGRADE", scheduleArgs);

        // Warp to right before clearing delay.
        vm.warp(start + 1 weeks - 1);

        vm.expectRevert("LM:U:INVALID_SCHED_CALL");
        loanManager.upgrade(2, upgradeCallData);

        // Call upgrade using governor instead, unaffected by pool delegate's scheduled timelock.
        vm.stopPrank();

        vm.prank(governor);
        loanManager.upgrade(2, upgradeCallData);
    }

}

contract LiquidationUpgradeTests is TestBase {

    address internal borrower          = address(new Address());
    address internal lp                = address(new Address());
    address internal newImplementation = address(new LoanManager());

    bytes internal upgradeCallData = new bytes(0);

    Liquidator internal liquidator;
    Loan       internal loan;

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);

        IMapleProxyFactory(liquidatorFactory).registerImplementation(2, newImplementation, address(0));
        IMapleProxyFactory(liquidatorFactory).enableUpgradePath(1, 2, address(0));

        vm.stopPrank();

        depositLiquidity({
            lp: lp,
            liquidity: 1_500_000e6
        });

        setupFees({
            delegateOriginationFee:     500e6,
            delegateServiceFee:         275e6,
            delegateManagementFeeRate:  0.02e6,    // 1,000,000 * 3.1536% * 2% * 1,000,000 / (365 * 86400) = 20
            platformOriginationFeeRate: 0.001e6,   // 1,000,000 * 0.10%   * 3  * 1,000,000 / (365 * 86400) = 95.129375e6
            platformServiceFeeRate:     0.0066e6,  // 1,000,000 * 0.66%        * 1,000,000 / (365 * 86400) = 209.2846270e6
            platformManagementFeeRate:  0.08e6     // 1,000,000 * 3.1536% * 8% * 1,000,000 / (365 * 86400) = 80
        });

        loan = fundAndDrawdownLoan({
            borrower:    borrower,
            termDetails: [uint256(5 days), uint256(1_000_000), uint256(3)],
            amounts:     [uint256(100e18), uint256(1_000_000e6), uint256(1_000_000e6)],
            rates:       [uint256(0.031536e18), uint256(0), uint256(0.0001e18), uint256(0.031536e18 / 10)]
        });

        // Since we round up days when it comes to late interest, this payment is 6 days late.
        vm.warp(start + 1_000_000 + 5 days + 1);

        vm.prank(poolDelegate);
        poolManager.triggerDefault(address(loan), address(liquidatorFactory));

        ( , , , , , address liquidatorAddress ) = loanManager.liquidationInfo(address(loan));

        liquidator = Liquidator(liquidatorAddress);

        // Resetting start because we had to advance time to trigger default.
        start = block.timestamp;
    }

    function test_upgradeLiquidator_noTimelock() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(Liquidator.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        globals.scheduleCall(address(liquidator), "LIQ:UPGRADE", scheduleArgs);

        // Wait for delay duration.
        vm.warp(start + 1 weeks);

        liquidator.upgrade(2, upgradeCallData);
    }

    function test_upgradeLiquidator_delayNotPassed() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(Liquidator.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(liquidator), "LIQ:UPGRADE", scheduleArgs);

        // Warp to right before clearing delay.
        vm.warp(start + 1 weeks - 1);

        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        vm.warp(start + 1 weeks);
        liquidator.upgrade(2, upgradeCallData);
    }

    function test_upgradeLiquidator_durationPassed() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(Liquidator.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(liquidator), "LIQ:UPGRADE", scheduleArgs);

        // Warp to right after duration end.
        vm.warp(start + 1 weeks + 2 days + 1);

        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        vm.warp(start + 1 weeks + 2 days);
        liquidator.upgrade(2, upgradeCallData);
    }

    function test_upgradeLiquidator_timelockExtended() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(Liquidator.upgrade.selector, uint256(2), upgradeCallData);

        vm.prank(poolDelegate);
        globals.scheduleCall(address(liquidator), "LIQ:UPGRADE", scheduleArgs);

        // Warp to beginning of timelock duration.
        vm.warp(start + 1 weeks);

        bool isValid = globals.isValidScheduledCall(poolDelegate, address(liquidator), "LIQ:UPGRADE", scheduleArgs);

        // Should be valid before we change the timelock settings.
        assertTrue(isValid);

        vm.prank(governor);
        globals.setTimelockWindow(address(liquidator), "LIQ:UPGRADE", 2 weeks, 1 weeks);

        isValid = globals.isValidScheduledCall(poolDelegate, address(liquidator), "LIQ:UPGRADE", scheduleArgs);
        assertTrue(!isValid);

        vm.startPrank(poolDelegate);

        // With timelock change, upgrade should now revert.
        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        // Warp to right before duration begin
        vm.warp(start + 2 weeks - 1);

        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        // Warp to past duration.
        vm.warp(start + 2 weeks + 1 weeks + 1);

        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        // Warp to right at duration end.
        vm.warp(start + 2 weeks + 1 weeks);

        liquidator.upgrade(2, upgradeCallData);
    }

    function test_upgradeLiquidator_timelockShortened() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(Liquidator.upgrade.selector, uint256(2), upgradeCallData);

        vm.prank(poolDelegate);
        globals.scheduleCall(address(liquidator), "LIQ:UPGRADE", scheduleArgs);

        // Warp to beginning of timelock duration.
        vm.warp(start + 1 weeks);

        bool isValid = globals.isValidScheduledCall(poolDelegate, address(liquidator), "LIQ:UPGRADE", scheduleArgs);

        // Should be valid before we change the timelock settings.
        assertTrue(isValid);

        vm.prank(governor);
        globals.setTimelockWindow(address(liquidator), "LIQ:UPGRADE", 2 days, 1 days);

        isValid = globals.isValidScheduledCall(poolDelegate, address(liquidator), "LIQ:UPGRADE", scheduleArgs);
        assertTrue(!isValid);

        vm.startPrank(poolDelegate);

        // With timelock change, we should be past the duration.
        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        // Warp to right before duration begin
        vm.warp(start + 2 days - 1);

        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        // Warp to past duration.
        vm.warp(start + 2 days + 1 days + 1);

        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        // Warp to right at duration end.
        vm.warp(start + 2 days + 1 days);

        liquidator.upgrade(2, upgradeCallData);
    }

    function test_upgradeLiquidator_governor_noTimelockNeeded() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(Liquidator.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(liquidator), "LIQ:UPGRADE", scheduleArgs);

        // Warp to right before clearing delay.
        vm.warp(start + 1 weeks - 1);

        vm.expectRevert("LIQ:U:INVALID_SCHED_CALL");
        liquidator.upgrade(2, upgradeCallData);

        // Call upgrade using governor instead, unaffected by pool delegate's scheduled timelock.
        vm.stopPrank();

        vm.prank(governor);
        liquidator.upgrade(2, upgradeCallData);
    }

}

contract PoolManagerUpgradeTests is TestBase {

    address internal newImplementation = address(new PoolManager());

    bytes internal upgradeCallData = new bytes(0);

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);

        IMapleProxyFactory(poolManagerFactory).registerImplementation(2, newImplementation, address(0));
        IMapleProxyFactory(poolManagerFactory).enableUpgradePath(1, 2, address(0));

        vm.stopPrank();
    }

    function test_upgradePoolManager_noTimelock() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(PoolManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        globals.scheduleCall(address(poolManager), "PM:UPGRADE", scheduleArgs);

        // Wait for delay duration.
        vm.warp(start + 1 weeks);

        poolManager.upgrade(2, upgradeCallData);
    }

    function test_upgradePoolManager_delayNotPassed() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(PoolManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(poolManager), "PM:UPGRADE", scheduleArgs);

        // Warp to right before clearing delay.
        vm.warp(start + 1 weeks - 1);

        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        vm.warp(start + 1 weeks);
        poolManager.upgrade(2, upgradeCallData);
    }

    function test_upgradePoolManager_durationPassed() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(PoolManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(poolManager), "PM:UPGRADE", scheduleArgs);

        // Warp to right after duration end.
        vm.warp(start + 1 weeks + 2 days + 1);

        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        vm.warp(start + 1 weeks + 2 days);
        poolManager.upgrade(2, upgradeCallData);
    }

    function test_upgradePoolManager_timelockExtended() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(PoolManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.prank(poolDelegate);
        globals.scheduleCall(address(poolManager), "PM:UPGRADE", scheduleArgs);

        // Warp to beginning of timelock duration.
        vm.warp(start + 1 weeks);

        bool isValid = globals.isValidScheduledCall(poolDelegate, address(poolManager), "PM:UPGRADE", scheduleArgs);

        // Should be valid before we change the timelock settings.
        assertTrue(isValid);

        vm.prank(governor);
        globals.setTimelockWindow(address(poolManager), "PM:UPGRADE", 2 weeks, 1 weeks);

        isValid = globals.isValidScheduledCall(poolDelegate, address(poolManager), "PM:UPGRADE", scheduleArgs);
        assertTrue(!isValid);

        vm.startPrank(poolDelegate);

        // With timelock change, upgrade should now revert.
        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        // Warp to right before duration begin
        vm.warp(start + 2 weeks - 1);

        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        // Warp to past duration.
        vm.warp(start + 2 weeks + 1 weeks + 1);

        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        // Warp to right at duration end.
        vm.warp(start + 2 weeks + 1 weeks);

        poolManager.upgrade(2, upgradeCallData);
    }

    function test_upgradePoolManager_timelockShortened() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(PoolManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.prank(poolDelegate);
        globals.scheduleCall(address(poolManager), "PM:UPGRADE", scheduleArgs);

        // Warp to beginning of timelock duration.
        vm.warp(start + 1 weeks);

        bool isValid = globals.isValidScheduledCall(poolDelegate, address(poolManager), "PM:UPGRADE", scheduleArgs);

        // Should be valid before we change the timelock settings.
        assertTrue(isValid);

        vm.prank(governor);
        globals.setTimelockWindow(address(poolManager), "PM:UPGRADE", 2 days, 1 days);

        isValid = globals.isValidScheduledCall(poolDelegate, address(poolManager), "PM:UPGRADE", scheduleArgs);
        assertTrue(!isValid);

        vm.startPrank(poolDelegate);

        // With timelock change, we should be past the duration.
        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        // Warp to right before duration begin
        vm.warp(start + 2 days - 1);

        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        // Warp to past duration.
        vm.warp(start + 2 days + 1 days + 1);

        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        // Warp to right at duration end.
        vm.warp(start + 2 days + 1 days);

        poolManager.upgrade(2, upgradeCallData);
    }

    function test_upgradePoolManager_governor_noTimelockNeeded() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(PoolManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(poolManager), "PM:UPGRADE", scheduleArgs);

        // Warp to right before clearing delay.
        vm.warp(start + 1 weeks - 1);

        vm.expectRevert("PM:U:INVALID_SCHED_CALL");
        poolManager.upgrade(2, upgradeCallData);

        // Call upgrade using governor instead, unaffected by pool delegate's scheduled timelock.
        vm.stopPrank();

        vm.prank(governor);
        poolManager.upgrade(2, upgradeCallData);
    }
}

contract WithdrawalManagerUpgradeTests is TestBase {

    address internal newImplementation = address(new WithdrawalManager());

    bytes internal upgradeCallData = new bytes(0);

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);

        IMapleProxyFactory(withdrawalManagerFactory).registerImplementation(2, newImplementation, address(0));
        IMapleProxyFactory(withdrawalManagerFactory).enableUpgradePath(1, 2, address(0));

        vm.stopPrank();
    }

    function test_upgradeWithdrawalManager_noTimelock() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(WithdrawalManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        globals.scheduleCall(address(withdrawalManager), "WM:UPGRADE", scheduleArgs);

        // Wait for delay duration.
        vm.warp(start + 1 weeks);

        withdrawalManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeWithdrawalManager_delayNotPassed() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(WithdrawalManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(withdrawalManager), "WM:UPGRADE", scheduleArgs);

        // Warp to right before clearing delay.
        vm.warp(start + 1 weeks - 1);

        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        vm.warp(start + 1 weeks);
        withdrawalManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeWithdrawalManager_durationPassed() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(WithdrawalManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(withdrawalManager), "WM:UPGRADE", scheduleArgs);

        // Warp to right after duration end.
        vm.warp(start + 1 weeks + 2 days + 1);

        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        vm.warp(start + 1 weeks + 2 days);
        withdrawalManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeWithdrawalManager_timelockExtended() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(WithdrawalManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.prank(poolDelegate);
        globals.scheduleCall(address(withdrawalManager), "WM:UPGRADE", scheduleArgs);

        // Warp to beginning of timelock duration.
        vm.warp(start + 1 weeks);

        bool isValid = globals.isValidScheduledCall(poolDelegate, address(withdrawalManager), "WM:UPGRADE", scheduleArgs);

        // Should be valid before we change the timelock settings.
        assertTrue(isValid);

        vm.prank(governor);
        globals.setTimelockWindow(address(withdrawalManager), "WM:UPGRADE", 2 weeks, 1 weeks);

        isValid = globals.isValidScheduledCall(poolDelegate, address(withdrawalManager), "WM:UPGRADE", scheduleArgs);
        assertTrue(!isValid);

        vm.startPrank(poolDelegate);

        // With timelock change, upgrade should now revert.
        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        // Warp to right before duration begin
        vm.warp(start + 2 weeks - 1);

        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        // Warp to past duration.
        vm.warp(start + 2 weeks + 1 weeks + 1);

        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        // Warp to right at duration end.
        vm.warp(start + 2 weeks + 1 weeks);

        withdrawalManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeWithdrawalManager_timelockShortened() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(WithdrawalManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.prank(poolDelegate);
        globals.scheduleCall(address(withdrawalManager), "WM:UPGRADE", scheduleArgs);

        // Warp to beginning of timelock duration.
        vm.warp(start + 1 weeks);

        bool isValid = globals.isValidScheduledCall(poolDelegate, address(withdrawalManager), "WM:UPGRADE", scheduleArgs);

        // Should be valid before we change the timelock settings.
        assertTrue(isValid);

        vm.prank(governor);
        globals.setTimelockWindow(address(withdrawalManager), "WM:UPGRADE", 2 days, 1 days);

        isValid = globals.isValidScheduledCall(poolDelegate, address(withdrawalManager), "WM:UPGRADE", scheduleArgs);
        assertTrue(!isValid);

        vm.startPrank(poolDelegate);

        // With timelock change, we should be past the duration.
        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        // Warp to right before duration begin
        vm.warp(start + 2 days - 1);

        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        // Warp to past duration.
        vm.warp(start + 2 days + 1 days + 1);

        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        // Warp to right at duration end.
        vm.warp(start + 2 days + 1 days);

        withdrawalManager.upgrade(2, upgradeCallData);
    }

    function test_upgradeWithdrawalManager_governor_noTimelockNeeded() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(WithdrawalManager.upgrade.selector, uint256(2), upgradeCallData);

        vm.startPrank(poolDelegate);

        globals.scheduleCall(address(withdrawalManager), "WM:UPGRADE", scheduleArgs);

        // Warp to right before clearing delay.
        vm.warp(start + 1 weeks - 1);

        vm.expectRevert("WM:U:INVALID_SCHED_CALL");
        withdrawalManager.upgrade(2, upgradeCallData);

        // Call upgrade using governor instead, unaffected by withdrawal delegate's scheduled timelock.
        vm.stopPrank();

        vm.prank(governor);
        withdrawalManager.upgrade(2, upgradeCallData);
    }

}

contract UnscheduleCallTests is TestBase {

    bytes internal upgradeCallData = new bytes(0);

    function test_unscheduleCall_governor() external {
        bytes memory scheduleArgs = abi.encodeWithSelector(LoanManager.upgrade.selector, uint256(2), upgradeCallData);

        // PD schedules the upgrade call
        vm.prank(poolDelegate);
        globals.scheduleCall(address(loanManager), "LM:UPGRADE", scheduleArgs);

        vm.warp(start + 1 weeks);

        assertTrue(globals.isValidScheduledCall(poolDelegate, address(loanManager), "LM:UPGRADE", scheduleArgs));

        // Governor unschedule the upgrade call
        vm.prank(governor);
        globals.unscheduleCall(poolDelegate, address(loanManager), "LM:UPGRADE", scheduleArgs);

        assertTrue(!globals.isValidScheduledCall(poolDelegate, address(loanManager), "LM:UPGRADE", scheduleArgs));
    }

}
