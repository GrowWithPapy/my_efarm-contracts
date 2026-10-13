// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ECU} from "../src/ECU.sol";

/// @notice The token's whole promise is what it does NOT do, so most of this file is
///         about absent behaviour: no mint, no owner, no hook, no tax.
contract ECUTest is Test {
    ECU internal ecu;
    address internal distributor = address(0xD15);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        ecu = new ECU(distributor);
    }

    function test_mintsTheWholeSupplyOnce() public view {
        assertEq(ecu.totalSupply(), 100_000_000e18);
        assertEq(ecu.balanceOf(distributor), 100_000_000e18);
    }

    function test_hasEighteenDecimalsToMatchTheLedger() public view {
        assertEq(ecu.decimals(), 18);
    }

    function test_isNamedForTheGame() public view {
        assertEq(ecu.name(), "e-Farm ECU");
        assertEq(ecu.symbol(), "ECU");
    }

    function test_refusesAZeroDistributor() public {
        vm.expectRevert(ECU.ZeroRecipient.selector);
        new ECU(address(0));
    }

    /// @dev The supply is fixed by the absence of a mint function. If this ever compiles
    ///      against a mint, the token has stopped being what §11.6 requires.
    function test_hasNoMintFunction() public view {
        // `mint(address,uint256)` and `owner()` are simply not part of the ABI.
        assertEq(_supports("mint(address,uint256)"), false);
        assertEq(_supports("owner()"), false);
        assertEq(_supports("pause()"), false);
        assertEq(_supports("setTaxRate(uint256)"), false);
        assertEq(_supports("blacklist(address)"), false);
    }

    /// @dev No fee-on-transfer: what leaves one balance arrives whole in the other. A
    ///      taxing token is read as a honeypot by scanners and refused by listings.
    function testFuzz_transferMovesTheWholeAmount(uint128 amount) public {
        amount = uint128(bound(amount, 1, 1_000_000e18));
        vm.prank(distributor);
        ecu.transfer(alice, amount);

        assertEq(ecu.balanceOf(alice), amount);
        assertEq(ecu.balanceOf(distributor), 100_000_000e18 - amount);
        assertEq(ecu.totalSupply(), 100_000_000e18);
    }

    function testFuzz_transferFromMovesTheWholeAmount(uint128 amount) public {
        amount = uint128(bound(amount, 1, 1_000_000e18));
        vm.prank(distributor);
        ecu.transfer(alice, amount);
        vm.prank(alice);
        ecu.approve(bob, amount);

        vm.prank(bob);
        ecu.transferFrom(alice, bob, amount);

        assertEq(ecu.balanceOf(bob), amount);
        assertEq(ecu.balanceOf(alice), 0);
    }

    /// @dev Burning is a holder's own power, not an admin's: the buyback (§11.4) and the
    ///      pool's sell fee (§11.6) both need it.
    function test_aHolderCanBurnItsOwn() public {
        vm.prank(distributor);
        ecu.transfer(alice, 1_000e18);

        vm.prank(alice);
        ecu.burn(400e18);

        assertEq(ecu.balanceOf(alice), 600e18);
        assertEq(ecu.totalSupply(), 100_000_000e18 - 400e18);
    }

    function test_burningNeedsYourOwnTokensOrAnAllowance() public {
        vm.prank(distributor);
        ecu.transfer(alice, 1_000e18);

        vm.prank(bob);
        vm.expectRevert();
        ecu.burnFrom(alice, 100e18);
    }

    function _supports(string memory signature) internal view returns (bool) {
        (bool ok,) = address(ecu).staticcall(abi.encodeWithSignature(signature));
        return ok;
    }
}
