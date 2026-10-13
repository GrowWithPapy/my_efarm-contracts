// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ECU} from "../src/ECU.sol";
import {FarmVault} from "../src/FarmVault.sol";

/// @notice Custody: what gets in, what gets out, and who may say so.
contract FarmVaultTest is Test {
    ECU internal ecu;
    FarmVault internal vault;

    uint256 internal operatorKey = 0xA11CE5;
    address internal operator;
    address internal guardian = address(0x6A12D);
    address internal player = address(0xF00D);
    address internal relayer = address(0xBEEF);

    function setUp() public {
        operator = vm.addr(operatorKey);
        ecu = new ECU(address(this));
        vault = new FarmVault(ecu, operator, guardian);

        ecu.transfer(address(vault), 1_000_000e18);
        ecu.transfer(player, 10_000e18);
    }

    // -- deposits ---------------------------------------------------------

    function test_depositPullsAndLogs() public {
        vm.startPrank(player);
        ecu.approve(address(vault), 500e18);

        vm.expectEmit(true, false, false, true, address(vault));
        emit FarmVault.Deposited(player, 500e18);
        vault.deposit(500e18);
        vm.stopPrank();

        assertEq(ecu.balanceOf(player), 9_500e18);
        assertEq(ecu.balanceOf(address(vault)), 1_000_500e18);
    }

    function test_depositNeedsAnAllowance() public {
        vm.prank(player);
        vm.expectRevert();
        vault.deposit(500e18);
    }

    function test_depositRefusesZero() public {
        vm.prank(player);
        vm.expectRevert(FarmVault.ZeroAmount.selector);
        vault.deposit(0);
    }

    /// @dev Pausing the exit must not trap the entrance.
    function test_depositsKeepWorkingWhilePaused() public {
        vm.prank(guardian);
        vault.pauseWithdrawals();

        vm.startPrank(player);
        ecu.approve(address(vault), 100e18);
        vault.deposit(100e18);
        vm.stopPrank();

        assertEq(ecu.balanceOf(address(vault)), 1_000_100e18);
    }

    // -- withdrawals ------------------------------------------------------

    function test_anOperatorVoucherPaysOut() public {
        bytes memory signature = _sign(player, 250e18, 0, block.timestamp + 1 hours);

        vm.prank(relayer); // anyone may submit: the signature is the authority
        vault.withdraw(player, 250e18, 0, block.timestamp + 1 hours, signature);

        assertEq(ecu.balanceOf(player), 10_250e18);
        assertEq(vault.nonces(player), 1);
    }

    function test_aVoucherCannotBeReplayed() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory signature = _sign(player, 250e18, 0, expiry);
        vault.withdraw(player, 250e18, 0, expiry, signature);

        vm.expectRevert(abi.encodeWithSelector(FarmVault.WrongNonce.selector, 1, 0));
        vault.withdraw(player, 250e18, 0, expiry, signature);
    }

    function test_vouchersMustBeSpentInOrder() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory second = _sign(player, 250e18, 1, expiry);

        vm.expectRevert(abi.encodeWithSelector(FarmVault.WrongNonce.selector, 0, 1));
        vault.withdraw(player, 250e18, 1, expiry, second);
    }

    function test_anExpiredVoucherIsRefused() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory signature = _sign(player, 250e18, 0, expiry);

        vm.warp(expiry + 1);

        vm.expectRevert(abi.encodeWithSelector(FarmVault.VoucherExpired.selector, expiry));
        vault.withdraw(player, 250e18, 0, expiry, signature);
    }

    function test_someoneElsesSignatureIsWorthless() public {
        uint256 stranger = 0xDEADBEEF;
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = vault.voucherDigest(player, 250e18, 0, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(stranger, digest);

        vm.expectRevert(FarmVault.BadSignature.selector);
        vault.withdraw(player, 250e18, 0, expiry, abi.encodePacked(r, s, v));
    }

    /// @dev The amount is signed, so a relayer cannot inflate it on the way through.
    function test_aTamperedAmountIsRefused() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory signature = _sign(player, 250e18, 0, expiry);

        vm.expectRevert(FarmVault.BadSignature.selector);
        vault.withdraw(player, 5_000e18, 0, expiry, signature);
    }

    /// @dev And so is the recipient: a voucher cannot be redirected.
    function test_aTamperedRecipientIsRefused() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory signature = _sign(player, 250e18, 0, expiry);

        vm.expectRevert(FarmVault.BadSignature.selector);
        vault.withdraw(relayer, 250e18, 0, expiry, signature);
    }

    function testFuzz_anyAmountTheVaultHoldsCanBeVouchered(uint128 amount) public {
        amount = uint128(bound(amount, 1, 1_000_000e18));
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory signature = _sign(player, amount, 0, expiry);

        vault.withdraw(player, amount, 0, expiry, signature);

        assertEq(ecu.balanceOf(player), 10_000e18 + amount);
    }

    // -- the guardian -----------------------------------------------------

    function test_pausingStopsWithdrawalsOnly() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory signature = _sign(player, 250e18, 0, expiry);

        vm.prank(guardian);
        vault.pauseWithdrawals();

        vm.expectRevert(FarmVault.Paused.selector);
        vault.withdraw(player, 250e18, 0, expiry, signature);

        vm.prank(guardian);
        vault.unpauseWithdrawals();
        vault.withdraw(player, 250e18, 0, expiry, signature);
        assertEq(ecu.balanceOf(player), 10_250e18);
    }

    function test_onlyTheGuardianPauses() public {
        vm.prank(player);
        vm.expectRevert(FarmVault.NotGuardian.selector);
        vault.pauseWithdrawals();
    }

    function test_theGuardianCanRotateTheOperator() public {
        uint256 newKey = 0xC0FFEE;
        vm.prank(guardian);
        vault.setOperator(vm.addr(newKey));

        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = vault.voucherDigest(player, 250e18, 0, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newKey, digest);
        vault.withdraw(player, 250e18, 0, expiry, abi.encodePacked(r, s, v));

        assertEq(ecu.balanceOf(player), 10_250e18);
    }

    /// @dev A rotation must invalidate the old key immediately, or a leak is not contained.
    function test_rotatingTheOperatorRetiresTheOldSignatures() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory signature = _sign(player, 250e18, 0, expiry);

        vm.prank(guardian);
        vault.setOperator(vm.addr(0xC0FFEE));

        vm.expectRevert(FarmVault.BadSignature.selector);
        vault.withdraw(player, 250e18, 0, expiry, signature);
    }

    function test_onlyTheGuardianRotates() public {
        vm.prank(player);
        vm.expectRevert(FarmVault.NotGuardian.selector);
        vault.setOperator(player);
    }

    function test_theGuardianCanHandOver() public {
        address next = address(0x5AFE);
        vm.prank(guardian);
        vault.setGuardian(next);

        vm.prank(next);
        vault.pauseWithdrawals();
        assertTrue(vault.withdrawalsPaused());
    }

    // -- the domain -------------------------------------------------------

    /// @dev The backend rebuilds this digest to sign vouchers, so the domain must be the
    ///      one app/api/signing.py uses: "e-Farm", version "1", this chain, this contract.
    function test_theDomainIsTheGames() public view {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("e-Farm")),
                keccak256(bytes("1")),
                block.chainid,
                address(vault)
            )
        );
        assertEq(vault.domainSeparator(), expected);
    }

    function _sign(address to, uint256 amount, uint256 nonce, uint256 expiry) internal view returns (bytes memory) {
        bytes32 digest = vault.voucherDigest(to, amount, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
