// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title IFarmAnimals -- livestock as ERC-1155 (phase 2)
/// @notice Interface only. No implementation ships in this phase.
///
/// @dev MECHANICS §7 names the livestock market as the natural home for animal tokens:
///      champion animals with lineage, sold at auction in ECU. ERC-1155 rather than 721
///      because most livestock is fungible within a species and stage -- forty adult
///      rabbits are forty of one id, not forty distinct tokens -- while a champion with a
///      pedigree can be given an id of its own.
///
///      What an implementation must not lose, and what makes this harder than minting a
///      collection: an animal in this game is **alive**. It ages, it falls sick, it breeds,
///      it can die of neglect at the daily tick, and a farm that sells its last buck can
///      never breed again (the game refuses that sale today). A token that can be
///      transferred while the animal behind it is mid-gestation, brooding a clutch or
///      pledged as loan collateral would let a player sell an obligation and keep the
///      benefit. So an implementation needs the game's consent at transfer time -- an
///      operator signature or a lock flag -- not merely an owner's.
interface IFarmAnimals is IERC1155 {
    /// @notice The species and life stage an id represents ("rabbit"/"adult", and so on).
    function kindOf(uint256 id) external view returns (string memory species, string memory stage);

    /// @notice True while the game has locked this id: collateral, brooding, or in a pen
    ///         whose sale would break the breeding core.
    function locked(uint256 id, address owner) external view returns (bool);
}
