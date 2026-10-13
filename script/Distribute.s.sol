// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {ECU} from "../src/ECU.sol";
import {FarmVault} from "../src/FarmVault.sol";

/// @notice Deploys the token and the vault, then splits the supply exactly as §11.7 says.
///
/// @dev The table in ECONOMY.md §11.7 is the specification and this script is its only
///      implementation, so the shares live here as constants and the sum is asserted
///      rather than trusted:
///
///      | DEX liquidity | 15 % | the pool -- the only ECU anyone can buy at launch |
///      | Community     | 15 % | vesting contract                                  |
///      | Team          | 15 % | vesting contract, 3-year schedule                 |
///      | Listings      |  5 % | multisig, held rather than liquidity              |
///      | Co-op reserve | 35 % | the Vault                                         |
///      | Bank pool     | 15 % | the Vault                                         |
///
///      The last two are one transfer, not two. §11.7 is explicit that the Vault is "a
///      rollup, not a fourth balance": the reserve and the Bank pool are ledger accounts
///      whose tokens sit together in custody, and splitting them on chain would invent a
///      distinction the ledger is the authority on.
///
///      The LP slice goes to the deployer-nominated liquidity address rather than being
///      paired here. Pairing means creating a Uniswap V4 pool with the fee hook of §11.6,
///      whose parameters are immutable once set; doing that inside a distribution script
///      would bury the most consequential decision of the launch in a loop of transfers.
contract Distribute is Script {
    uint256 internal constant TOTAL = 100_000_000e18;

    uint256 internal constant LP_SHARE = 15;
    uint256 internal constant COMMUNITY_SHARE = 15;
    uint256 internal constant TEAM_SHARE = 15;
    uint256 internal constant LISTINGS_SHARE = 5;
    uint256 internal constant GAME_SHARE = 50; // 35 reserve + 15 Bank pool, one balance

    /// @notice Three years, the schedule §11.7 gives the team slice.
    uint64 internal constant TEAM_VESTING_SECONDS = 3 * 365 days;
    /// @notice The community slice vests too, over one year unless overridden.
    uint64 internal constant COMMUNITY_VESTING_SECONDS = 365 days;

    struct Destinations {
        address liquidity;
        address communityBeneficiary;
        address teamBeneficiary;
        address listingsMultisig;
        address operator;
        address guardian;
    }

    struct Deployment {
        ECU ecu;
        FarmVault vault;
        VestingWallet communityVesting;
        VestingWallet teamVesting;
    }

    function run() external returns (Deployment memory deployment) {
        Destinations memory to = Destinations({
            liquidity: vm.envAddress("LIQUIDITY_ADDRESS"),
            communityBeneficiary: vm.envAddress("COMMUNITY_BENEFICIARY"),
            teamBeneficiary: vm.envAddress("TEAM_BENEFICIARY"),
            listingsMultisig: vm.envAddress("LISTINGS_MULTISIG"),
            operator: vm.envAddress("VAULT_OPERATOR"),
            guardian: vm.envAddress("VAULT_GUARDIAN")
        });

        vm.startBroadcast();
        deployment = deployAll(to, uint64(block.timestamp));
        vm.stopBroadcast();

        _report(deployment, to);
    }

    /// @dev Split out, and public, so the tests exercise the real distribution rather than
    ///      a reimplementation of it that could drift from what actually gets broadcast.
    function deployAll(Destinations memory to, uint64 startAt) public returns (Deployment memory deployment) {
        require(LP_SHARE + COMMUNITY_SHARE + TEAM_SHARE + LISTINGS_SHARE + GAME_SHARE == 100, "shares must sum to 100");

        // The deployer holds the supply for the length of this script and nothing longer.
        deployment.ecu = new ECU(address(this));
        deployment.vault = new FarmVault(deployment.ecu, to.operator, to.guardian);

        deployment.communityVesting = new VestingWallet(to.communityBeneficiary, startAt, COMMUNITY_VESTING_SECONDS);
        deployment.teamVesting = new VestingWallet(to.teamBeneficiary, startAt, TEAM_VESTING_SECONDS);

        deployment.ecu.transfer(to.liquidity, _slice(LP_SHARE));
        deployment.ecu.transfer(address(deployment.communityVesting), _slice(COMMUNITY_SHARE));
        deployment.ecu.transfer(address(deployment.teamVesting), _slice(TEAM_SHARE));
        deployment.ecu.transfer(to.listingsMultisig, _slice(LISTINGS_SHARE));
        deployment.ecu.transfer(address(deployment.vault), _slice(GAME_SHARE));

        // Nothing may be left behind: a remainder in the deployer is supply nobody
        // accounted for, and the 100 M invariant the whole ledger rests on would be a
        // statement about a balance that is not where the spec says it is.
        require(deployment.ecu.balanceOf(address(this)) == 0, "undistributed remainder");
    }

    function _slice(uint256 share) internal pure returns (uint256) {
        return (TOTAL * share) / 100;
    }

    function _report(Deployment memory d, Destinations memory to) internal pure {
        console.log("ECU                ", address(d.ecu));
        console.log("FarmVault          ", address(d.vault));
        console.log("Community vesting  ", address(d.communityVesting));
        console.log("Team vesting       ", address(d.teamVesting));
        console.log("Liquidity           ", to.liquidity);
        console.log("Listings multisig   ", to.listingsMultisig);
    }
}
