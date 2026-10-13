// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title IFarmPlots -- village land as ERC-721 (phase 2)
/// @notice Interface only. No implementation ships in this phase.
///
/// @dev Land is the scarcest thing in the economy (ECONOMY.md §11.3): a village is a
///      thousand plots, a farm may own three at level 2 and six at level 3, and anything
///      beyond the two free plots granted at level 2 must be bought at the Town Hall's
///      Dutch auction or from another player. Today a plot is a row in the game database
///      and the transfer is an EIP-712 message the owner signs; this is the shape it takes
///      when that row becomes a token.
///
///      Two rules the game enforces off-chain that an implementation must carry with it,
///      because a token that forgets them would break the economy rather than extend it:
///
///      * **Granted plots are untradable.** The two free plots at level 2 are marked, and
///        marking is what stops a farm minting saleable land by levelling up. `granted`
///        exposes it; transfers of a granted plot must revert.
///      * **The per-level ownership cap still applies.** A transfer that would put the
///        receiver over its cap is not a valid trade, so an implementation needs the
///        game's view of the receiver's level at transfer time -- an oracle or an
///        operator-signed approval, not a guess made on chain.
interface IFarmPlots is IERC721 {
    /// @notice The village a plot belongs to, and its number within that village.
    function plotOf(uint256 tokenId) external view returns (uint256 village, uint256 number);

    /// @notice True for the free plots granted at level 2, which may never be transferred.
    function granted(uint256 tokenId) external view returns (bool);
}
