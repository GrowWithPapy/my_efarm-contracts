# e-Farm contracts

Two contracts ship in phase 1: the **ECU** token and the **FarmVault** that custodies the
game-side half of the supply. Everything else the game does — farms, plots, animals,
markets, the Bank — is off-chain, and `docs/ECONOMY.md` is the authority on it.

The guiding constraint, from ECONOMY.md §1: *the chain holds the token and the custody,
the ledger holds the economy.* A contract here should be boring enough that an auditor can
read it in one sitting, because the interesting rules are all in the Python.

## Layout

```
src/ECU.sol                 fixed-supply ERC-20, no owner, no hooks
src/FarmVault.sol           deposits in, operator-signed vouchers out
src/interfaces/             phase-2 shapes only (plots ERC-721, animals ERC-1155)
script/Distribute.s.sol     the launch distribution of §11.7
test/                       forge tests for all of the above
```

## Setup

Dependencies are git submodules, so a fresh clone needs:

```bash
git submodule update --init --recursive
cd contracts
forge build
forge test
```

## The two contracts

### ECU

A plain ERC-20 with `ERC20Burnable` and nothing else. 100 000 000 tokens, 18 decimals,
minted once in the constructor to the distributor.

Three deliberate absences, each of which an exchange or a scanner checks for:

- **No mint function.** The supply is fixed by construction, not by a renounced role, so
  there is no owner to compromise and no timelock to trust. "Ownership renounced after
  distribution" is satisfied here by never having an owner at all.
- **No transfer hook, no fee, no blacklist.** A token that takes a cut on transfer is
  indistinguishable from a honeypot to automated review. The 1.5 % sell fee of §11.6 lives
  in the pool hook, not in the token.
- **No pause.** Custody can be paused (below); the token cannot.

`burn` is kept because two spec'd flows destroy ECU: the §11.4 buyback and the §11.6 sell
fee. Both burn tokens the burner already holds.

### FarmVault

Custody for the 50 % that the game spends: the Co-op reserve and the Bank pool. §11.7
calls the Vault "a rollup, not a fourth balance" — the ledger decides how that 50 %
divides between farms, reserves and escrows, and the contract deliberately knows nothing
about any of it.

**In:** `deposit(amount)` pulls an approved amount and emits `Deposited`. Deposits are
never paused — stopping the exit must not trap the entrance.

**Out:** `withdraw(to, amount, nonce, expiry, signature)`, where the signature is an
EIP-712 `WithdrawalVoucher` from the operator key. Anyone may submit the transaction; the
signature is the authority and the tokens can only go to the `to` the operator named. The
nonce is per-recipient and sequential, and is spent before the transfer.

Note there are **two different signatures** in a withdrawal, and conflating them is the
easiest mistake to make here:

| | Signed by | Proves | Verified by |
|---|---|---|---|
| `Withdraw(farmId, amountMicros, nonce, deadline)` | the player's wallet | intent | the backend (`app/api/signing.py`) |
| `WithdrawalVoucher(to, amount, nonce, expiry)` | the operator key | authorisation | this contract |

They share the EIP-712 domain (`e-Farm`, version `1`) and nothing else. The game applies
the aged-harvest toll, the daily cap, the 48-hour delay and the risk state (§11.1, §12)
between the two — which is exactly why the chain cannot be the authority on withdrawals.

**Pausing** covers withdrawals only, and only the guardian may do it. The guardian is one
address in the contract and a 2-of-3 Safe in practice: keeping the threshold in the Safe
means the signing policy can change without redeploying custody. The guardian can also
rotate the operator, which invalidates every unspent voucher signed by the old key.

## Launch distribution

`script/Distribute.s.sol` deploys both contracts and splits the supply per §11.7:

| Slice | Share | Where |
|---|---|---|
| DEX liquidity | 15 % | the nominated liquidity address |
| Community | 15 % | `VestingWallet`, 1 year |
| Team | 15 % | `VestingWallet`, 3 years |
| Listings | 5 % | multisig |
| Co-op reserve + Bank pool | 50 % | the Vault, as one balance |

The script asserts the shares sum to 100 and that the deployer is left holding nothing.

Two things it deliberately does **not** do:

- **It does not create the pool.** Pairing liquidity means choosing Uniswap V4 pool
  parameters and the §11.6 fee hook, which are immutable once set. That decision should not
  be buried in a loop of transfers.
- **It does not split the reserve from the Bank pool.** They are ledger accounts, and
  inventing an on-chain distinction would create a second authority on a number the ledger
  already owns.

```bash
cp .env.example .env    # fill in every address
forge script script/Distribute.s.sol:Distribute \
  --rpc-url base_sepolia --broadcast --verify -vvvv
```

Deploy to Base Sepolia (84532) first and let the backend run a full deposit → tick →
voucher → withdraw cycle against it before Base mainnet (8453) is considered.

## Phase 2

`src/interfaces/` holds `IFarmPlots` (ERC-721) and `IFarmAnimals` (ERC-1155) as interfaces
only, with the rules any implementation has to carry across written into them: granted
plots are untradable, the per-level ownership cap survives a transfer, and an animal that
is collateral, brooding or the last breeding male of its pen cannot be sold out from under
the game. Tokenising living, obligation-bearing assets is harder than tokenising a
collection, which is why it is not in phase 1.
