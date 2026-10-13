// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title ECU -- the e-Farm token
/// @notice A plain ERC-20 with a fixed supply of 100,000,000, and nothing else
///         (ECONOMY.md §1, §11.6).
///
/// @dev **There is no owner.** The whole supply is minted once, in the constructor, to the
///      distributor that hands it to the launch destinations (§11.7). After that
///      transaction the contract has no privileged caller at all: no mint, no pause, no
///      blacklist, no upgrade path, no admin to renounce later and no one who could forget
///      to. "Ownership renounced after distribution" is therefore a property of the
///      bytecode rather than a promise about a future transaction.
///
///      **No transfer hook, no fee-on-transfer, no pair whitelist, no owner-adjustable
///      tax** -- §11.6 makes this a hard requirement, because a token that taxes or
///      rewrites transfers is rejected by listings and read as a honeypot by scanners.
///      Every fee in this economy is taken at the pool or inside the game's own ledger,
///      never in the token.
///
///      Burning is deliberately kept, and is not a privileged power: any holder may burn
///      their own balance, or an approved spender may burn from an allowance. The economy
///      needs it -- the revenue buyback burns half of what it buys (§11.4) and the pool's
///      sell fee is burned in ECU (§11.6) -- and neither of those is an admin action.
///
///      18 decimals, matching the ledger's `Numeric(38, 18)`, so one ledger unit is one
///      token unit and no rounding lives at the boundary.
contract ECU is ERC20, ERC20Burnable {
    /// @notice The entire supply that will ever exist: 100,000,000 ECU.
    uint256 public constant TOTAL_SUPPLY = 100_000_000e18;

    error ZeroRecipient();

    /// @param distributor Receives the whole supply, to split per §11.7. In production
    ///        this is the launch script's distributor contract or the deployer multisig;
    ///        it holds the tokens only for the length of the distribution.
    constructor(address distributor) ERC20("e-Farm ECU", "ECU") {
        if (distributor == address(0)) revert ZeroRecipient();
        _mint(distributor, TOTAL_SUPPLY);
    }
}
