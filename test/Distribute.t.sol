// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Distribute} from "../script/Distribute.s.sol";
import {ECU} from "../src/ECU.sol";
import {FarmVault} from "../src/FarmVault.sol";

/// @notice Runs the real launch script and checks the result against the §11.7 table.
///
/// @dev This deliberately calls `deployAll` -- the same function `run()` broadcasts --
///      rather than re-adding up the shares here. A test that recomputed the split would
///      pass while the script sent the tokens somewhere else.
contract DistributeTest is Test {
    Distribute internal script;
    Distribute.Destinations internal to;
    Distribute.Deployment internal d;

    uint256 internal constant TOTAL = 100_000_000e18;
    uint64 internal constant START = 1_800_000_000;

    address internal liquidity = address(0x11);
    address internal community = address(0x22);
    address internal team = address(0x33);
    address internal listings = address(0x44);
    address internal operator = address(0x55);
    address internal guardian = address(0x66);

    function setUp() public {
        script = new Distribute();
        to = Distribute.Destinations({
            liquidity: liquidity,
            communityBeneficiary: community,
            teamBeneficiary: team,
            listingsMultisig: listings,
            operator: operator,
            guardian: guardian
        });
        d = script.deployAll(to, START);
    }

    // -- the table --------------------------------------------------------

    function test_liquidityGetsFifteenPercent() public view {
        assertEq(d.ecu.balanceOf(liquidity), 15_000_000e18);
    }

    function test_communityVestingHoldsFifteenPercent() public view {
        assertEq(d.ecu.balanceOf(address(d.communityVesting)), 15_000_000e18);
    }

    function test_teamVestingHoldsFifteenPercent() public view {
        assertEq(d.ecu.balanceOf(address(d.teamVesting)), 15_000_000e18);
    }

    function test_listingsMultisigGetsFivePercent() public view {
        assertEq(d.ecu.balanceOf(listings), 5_000_000e18);
    }

    /// @dev The reserve (35 %) and the Bank pool (15 %) are one balance on chain: §11.7
    ///      calls the Vault "a rollup, not a fourth balance", and the ledger is the
    ///      authority on how the 50 % divides.
    function test_theVaultHoldsTheGameSideHalf() public view {
        assertEq(d.ecu.balanceOf(address(d.vault)), 50_000_000e18);
    }

    /// @dev The invariant the entire off-chain ledger rests on. If the deployer kept a
    ///      remainder, "100 M ECU exist" would be true of the token and false of the game.
    function test_everythingIsDistributedAndNothingIsLeft() public view {
        uint256 accounted = d.ecu.balanceOf(liquidity) + d.ecu.balanceOf(address(d.communityVesting))
            + d.ecu.balanceOf(address(d.teamVesting)) + d.ecu.balanceOf(listings) + d.ecu.balanceOf(address(d.vault));

        assertEq(accounted, TOTAL);
        assertEq(d.ecu.totalSupply(), TOTAL);
        assertEq(d.ecu.balanceOf(address(script)), 0);
    }

    // -- vesting ----------------------------------------------------------

    function test_theTeamScheduleRunsThreeYears() public view {
        assertEq(d.teamVesting.owner(), team);
        assertEq(d.teamVesting.start(), START);
        assertEq(d.teamVesting.duration(), 3 * 365 days);
    }

    function test_theCommunityScheduleRunsOneYear() public view {
        assertEq(d.communityVesting.owner(), community);
        assertEq(d.communityVesting.duration(), 365 days);
    }

    /// @dev Day one is the moment the float matters most: the only sellable ECU must be
    ///      the 15 % in the pool, not a team slice that quietly unlocked.
    function test_nothingHasVestedAtLaunch() public {
        vm.warp(START);
        assertEq(d.teamVesting.releasable(address(d.ecu)), 0);
        assertEq(d.communityVesting.releasable(address(d.ecu)), 0);
    }

    function test_theTeamSliceIsHalfwayAtEighteenMonths() public {
        vm.warp(START + (3 * 365 days) / 2);
        assertApproxEqRel(d.teamVesting.releasable(address(d.ecu)), 7_500_000e18, 1e12);
    }

    function test_vestingPaysTheBeneficiaryAtTheEnd() public {
        vm.warp(START + 3 * 365 days);
        d.teamVesting.release(address(d.ecu));

        assertEq(d.ecu.balanceOf(team), 15_000_000e18);
        assertEq(d.ecu.balanceOf(address(d.teamVesting)), 0);
    }

    // -- the vault --------------------------------------------------------

    function test_theVaultIsWiredToTheTokenAndItsKeys() public view {
        assertEq(address(d.vault.ecu()), address(d.ecu));
        assertEq(d.vault.operator(), operator);
        assertEq(d.vault.guardian(), guardian);
        assertFalse(d.vault.withdrawalsPaused());
    }

    /// @dev Nobody can mint more, so the launch split is the whole and permanent story.
    function test_theTokenHasNoOwnerAfterDistribution() public view {
        (bool ok,) = address(d.ecu).staticcall(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
    }
}
