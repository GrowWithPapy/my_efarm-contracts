# Audit report

> Audit the Foundry contracts in this repository as received (src/ECU.sol, src/FarmVault.sol, script/Distribute.s.sol) against docs/ECONOMY.md v1.0 and docs/MECHANICS.md. Context: My e-farm, a farm game on Base. ECU is a fixed-supply ERC-20 distributed once by the Distribute script (liquidity, team vesting, community vesting, listings multisig, FarmVault). In-game coins stay off-chain; the only ECU outflow to players is FarmVault paying against an EIP-712 voucher signed by an off-chain operator key, with a guardian that can pause and rotate. Priorities: (1) voucher logic — replay, nonce ordering, expiry, domain separator, signature malleability, rotation edge cases; (2) blast radius of a compromised operator key, and whether the vault should enforce a per-day outflow cap equal to the daily Exchange budget in ECONOMY.md; (3) guardian powers and hand-over; (4) Distribute script — allocation math, vesting schedules, leftover tokens, ownership renounce; (5) standard Solidity issues. Report reproducible findings only, each with severity and a minimal repro or test. Do not change code.

| | |
|---|---|
| Repository | https://github.com/GrowWithPapy/my_efarm-contracts.git |
| Commit | `3f9524e5ded5f582f026f0a71bb06ef0e5d62bd2` |
| Job | `7a954a11-c26a-4d9a-8bed-cd7ea15fb4ed` |
| Judged | 2026-10-13 20:48 UTC |
| Findings | 2 high · 1 medium · 5 low · 2 info |

Four agents audited the code as it is at `3f9524e`, each in one area (math, permissions, economics, control flow),
and a judge reproduced, merged and ranked what they found, then read the code once more itself. Nothing in the repository was changed or deployed.

## Findings

### 1. High: Distribute.run() mints the supply to the ephemeral script address, so the launch cannot be broadcast (and would strand 100 M ECU if it were)

`script/Distribute.s.sol:84`

```
        deployment.ecu = new ECU(address(this));
```

run() wraps deployAll() in vm.startBroadcast(). Under broadcast every CREATE and CALL is sent from the broadcaster EOA, but address(this) is still the script contract, which exists only inside forge's simulation and never on chain. The ECU constructor therefore mints all 100,000,000 ECU to that phantom address, and the five transfer calls on lines 90-94 are sent by the broadcaster, which holds 0 ECU. Forge 1.8.3 refuses the script at vm.startBroadcast() with 'Usage of address(this) detected in script contract'; under tooling without that guard the first transfer reverts with ERC20InsufficientBalance(broadcaster, 0, 15e24), and if the ECU creation alone were ever landed (for example with --skip-simulation) the whole fixed supply would sit at an address with no key and no code, permanently. The README's documented launch command therefore cannot distribute anything. test/Distribute.t.sol never sees this because it calls deployAll() directly from the test contract, outside broadcast, where the caller really is the script contract. Fix (keeps the §11.7 split and the no-owner token): mint to an account that actually sends the transfers, e.g. `(, address deployer,) = vm.readCallers();` after startBroadcast and `new ECU(deployer)` plus `require(ecu.balanceOf(deployer) == 0)` at the end; or deploy a one-shot distributor contract whose constructor creates the ECU to itself and performs the five transfers atomically so no EOA ever holds the supply. Add a test that drives run() under broadcast. Merged from four specialist reports (permissions, economics, flow, math), all reproduced.

**Reproduction**

Dry run: `LIQUIDITY_ADDRESS=0x..11 COMMUNITY_BENEFICIARY=0x..22 TEAM_BENEFICIARY=0x..33 LISTINGS_MULTISIG=0x..44 VAULT_OPERATOR=0x..55 VAULT_GUARDIAN=0x..66 forge script script/Distribute.s.sol:Distribute` (forge 1.8.3). Expected: ECU, FarmVault and two VestingWallets deployed and 15/15/15/5/50 M transferred with the deployer holding 0. Actual: `Error: script failed: Usage of address(this) detected in script contract. Script contracts are ephemeral and their addresses should not be relied upon.` In a Foundry test that sets the six env vars and calls script.run() (attached proof), the same path reverts with ERC20InsufficientBalance(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38, 0, 15000000000000000000000000): the broadcaster holds none of the supply that was minted to the script address. The existing suite passes 41/41 because it only calls deployAll() directly.

**Proof**: a Foundry test that fails on this code and passes once it is fixed.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Distribute} from "script/Distribute.s.sol";

/// @notice The broadcast entry point `run()` must distribute the whole supply, exactly as
///         `deployAll` does when a test calls it directly. Today it cannot: `deployAll` mints
///         the supply to `address(this)` -- the ephemeral script contract -- and under
///         `vm.startBroadcast()` the transfers are sent from the broadcaster, which holds
///         nothing. Forge additionally refuses the script outright ("Usage of `address(this)`
///         detected in script contract").
contract DistributeRunTest is Test {
    uint256 internal constant TOTAL = 100_000_000e18;

    address internal liquidity = address(0x11);
    address internal community = address(0x22);
    address internal team = address(0x33);
    address internal listings = address(0x44);
    address internal operator = address(0x55);
    address internal guardian = address(0x66);

    function setUp() public {
        vm.setEnv("LIQUIDITY_ADDRESS", vm.toString(liquidity));
        vm.setEnv("COMMUNITY_BENEFICIARY", vm.toString(community));
        vm.setEnv("TEAM_BENEFICIARY", vm.toString(team));
        vm.setEnv("LISTINGS_MULTISIG", vm.toString(listings));
        vm.setEnv("VAULT_OPERATOR", vm.toString(operator));
        vm.setEnv("VAULT_GUARDIAN", vm.toString(guardian));
    }

    function test_runDistributesTheWholeSupplyUnderBroadcast() public {
        Distribute script = new Distribute();

        // The same entry point `forge script ... --broadcast` executes.
        Distribute.Deployment memory d = script.run();

        assertEq(d.ecu.balanceOf(liquidity), 15_000_000e18, "liquidity");
        assertEq(d.ecu.balanceOf(address(d.communityVesting)), 15_000_000e18, "community");
        assertEq(d.ecu.balanceOf(address(d.teamVesting)), 15_000_000e18, "team");
        assertEq(d.ecu.balanceOf(listings), 5_000_000e18, "listings");
        assertEq(d.ecu.balanceOf(address(d.vault)), 50_000_000e18, "vault");
        assertEq(d.ecu.balanceOf(address(script)), 0, "ephemeral script address must hold nothing");
        assertEq(d.ecu.totalSupply(), TOTAL);
    }
}
```

### 2. High: FarmVault enforces no outflow bound: one voucher from the hot operator key moves the entire 50 M ECU custody in a single transaction

`src/FarmVault.sol:136`

```
        ecu.safeTransfer(to, amount);
```

withdraw() checks pause, zero address, amount != 0, expiry, nonce and the operator signature, then transfers whatever amount was signed. There is no per-voucher maximum, no per-day or rolling-window cap, no fraction-of-balance bound and no upper bound on expiry. The operator is, per .env.example, 'the backend's hot key'. ECONOMY.md bounds every legitimate exit far below the custody: §3.3(3) 'The reserve's only outflow is the Exchange, bounded by B = R·ln2/730 + EMA30' (about 33,000 ECU/day at R = 35 M), §1 caps each farm at max(500, 1.5×EMA7(daily_revenue)) per day behind a 48 h delay, and §9 gate 6 requires net ECU withdrawn over any rolling 7 days to stay under 15 % of the pool's ECU side (2.25 M at launch). None of that survives a key compromise: the attacker signs to=attacker, amount=50_000_000e18, nonce=0 and submits it in one block. The guardian's controls (pause, setOperator) are reactive and need a 2-of-3 Safe execution, which cannot land before a single drain transaction; the suite's testFuzz_anyAmountTheVaultHoldsCanBeVouchered codifies the unbounded behaviour as expected. Answer to priority (2): yes, an on-chain bound is warranted, but a cap exactly equal to the daily Exchange budget B would be too tight because §1 says the `deposited` bucket is always withdrawable and those exits are not Exchange outflow. Recommended minimal fix that preserves the operator/guardian design: a guardian-settable rolling-window cap (e.g. `maxOutflowPerWindow` over 24 h, sized to B plus a deposit-exit allowance, or gate 6's 2.25 M per 7 days) checked in withdraw() before the transfer, optionally plus a per-voucher ceiling and a maximum expiry horizon. A legitimate surge then waits for the next window or a guardian raise; a leaked key is limited to one window's budget instead of half the supply. Merged from four specialist reports, all reproduced.

**Reproduction**

State: FarmVault funded with 50_000_000e18 ECU (exactly what Distribute.s.sol deposits), operator = vm.addr(0xA11CE5). Input: sig = operator's EIP-712 signature over voucherDigest(0xBAD, 50_000_000e18, 0, block.timestamp + 1 hours); anyone calls withdraw(0xBAD, 50_000_000e18, 0, expiry, sig). Expected under ECONOMY.md §3.3 / §9 gate 6: refused as roughly 1,500x the daily budget and 22x the weekly bound. Actual: Withdrawn(0xBAD, 5e25, 0) is emitted, balanceOf(0xBAD) == 50_000_000e18, vault balance 0, in one transaction. The attached proof fails on the current code with 'next call did not revert as expected' and passes once any window or per-voucher cap below the vault balance is enforced.

**Proof**: a Foundry test that fails on this code and passes once it is fixed.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ECU} from "src/ECU.sol";
import {FarmVault} from "src/FarmVault.sol";

/// @notice Blast radius of a leaked operator key. ECONOMY.md bounds the game-side outflow
///         (the Exchange budget B = R*ln2/730, about 33,000 ECU/day at launch, and gate 6:
///         net withdrawals over 7 days <= 15 % of the pool's ECU side = 2.25 M). The vault
///         enforces no ceiling at all: one voucher signed by the hot key moves the entire
///         50 M custody in a single transaction, before any guardian can pause.
contract VaultOutflowCapTest is Test {
    ECU internal ecu;
    FarmVault internal vault;

    uint256 internal operatorKey = 0xA11CE5;
    address internal operator;
    address internal guardian = address(0x6A12D);
    address internal attacker = address(0xBAD);

    uint256 internal constant GAME_SIDE = 50_000_000e18;

    function setUp() public {
        operator = vm.addr(operatorKey);
        ecu = new ECU(address(this));
        vault = new FarmVault(ecu, operator, guardian);
        ecu.transfer(address(vault), GAME_SIDE); // the launch state of the vault (§11.7)
    }

    /// @dev A single voucher for the whole custody must not clear. Any per-day / per-voucher
    ///      ceiling sized anywhere near the spec's daily budget makes this revert.
    function test_oneVoucherCannotDrainTheEntireCustody() public {
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = vault.voucherDigest(attacker, GAME_SIDE, 0, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, digest);

        vm.expectRevert();
        vault.withdraw(attacker, GAME_SIDE, 0, expiry, abi.encodePacked(r, s, v));

        assertEq(ecu.balanceOf(address(vault)), GAME_SIDE, "custody drained in one transaction");
        assertEq(ecu.balanceOf(attacker), 0);
    }
}
```

### 3. Medium: setGuardian is single-step: a wrong address permanently removes the only pause and operator-rotation control

`src/FarmVault.sol:177`

```
        guardian = newGuardian;
```

The guardian is the only account that can pause, unpause, rotate the operator or hand over. setGuardian writes the new address immediately after a zero-address check only; there is no pending/accept step, no timelock and no other role that could restore it. A mistyped address, a Safe that exists only on another chain, or a contract that cannot send transactions takes effect at once and leaves the 50 M custody with a live operator key and no emergency control for the life of the contract, which also makes the missing outflow cap unrecoverable rather than merely slow to react to. The function will be exercised at the most delicate moment (migrating from the launch Safe). Fix: two-step hand-over (`pendingGuardian` set by the current guardian, `acceptGuardian()` called by the new address), the Ownable2Step shape vendored in lib/, so the outgoing guardian keeps its powers until the new one proves it can transact. The one-address/2-of-3 Safe design is unchanged. Merged from four specialist reports (two rated medium, two low); reproduced.

**Reproduction**

State: vault with guardian G. Input: G calls setGuardian(0x1234) where nobody holds 0x1234's key. Then G calls pauseWithdrawals() and setGuardian(G). Expected: hand-over pending until 0x1234 accepts, G still able to pause. Actual: guardian() == 0x1234 immediately; both calls from G revert NotGuardian(); 0x1234 can never call anything, so pause and setOperator are unreachable forever. Reproduced in test/scratch/Judge.t.sol test_singleStepGuardianHandoverIsFinal (passes on current code).

### 4. Low: A signed voucher cannot be revoked, expiry is unbounded, and one unspent nonce blocks every later voucher for that recipient

`src/FarmVault.sol:125`

```
        if (nonce != expected) revert WrongNonce(expected, nonce);
```

Validity depends only on the current operator having signed, block.timestamp <= expiry (no on-chain maximum lifetime, type(uint256).max is accepted) and the nonce matching nonces[to], which only advances on a successful withdrawal. Three consequences. (a) Once a voucher is signed the only on-chain ways to stop it are the global pause (which only delays it until unpause) or a global setOperator rotation that invalidates every honest in-flight voucher too; ECONOMY.md §12 blocks withdrawals at risk >= 70 and freezes at >= 90, so a farm frozen after signing is still paid until expiry. (b) A corrected voucher at the same nonce does not supersede the first: whichever the holder submits first wins. (c) If voucher n for a recipient expires or is withheld, vouchers n+1.. are dead until the operator re-signs n; if the backend instead treats the expired voucher as void and moves on, the recipient is stuck forever. Fix: add a guardian-or-operator-callable `bumpNonce(address to)` (or a cancelled-digest set) so one recipient's queue can be voided without pausing everyone, and bound expiry on chain (e.g. `expiry <= block.timestamp + MAX_VOUCHER_LIFETIME`). The backend rule 'never advance the counter until nonces[to] has moved on chain' should be written down regardless. Merged from six specialist entries across four reports; all reproduced.

**Reproduction**

(a) Operator signs (player, 10_000_000e18, nonce 0, expiry = type(uint256).max). Guardian calls pauseWithdrawals() then unpauseWithdrawals(). Ten years later anyone calls withdraw with that voucher: succeeds, balanceOf(player) == 10_000_000e18. (b) Sign (player, 1000e18, 0, T+48h) then a corrected (player, 500e18, 0, T+48h); submit the first: player receives 1000e18, the corrected one reverts WrongNonce(1, 0). (c) Sign (player, 100e18, 0, t0+1h) and (player, 100e18, 1, t0+30d); warp to t0+2h: nonce 0 reverts VoucherExpired(t0+1h), nonce 1 reverts WrongNonce(0, 1). Reproduced in test/scratch/Judge.t.sol tests test_noPerVoucherRevocation, test_aSignedVoucherCannotBeSuperseded, test_expiredVoucherBlocksTheQueue (all pass on current code).

### 5. Low: Rotating the operator back to a previous key revives every unspent voucher that key ever signed

`src/FarmVault.sol:170`

```
        operator = newOperator;
```

The NatSpec says vouchers signed by the old operator 'stop working immediately', but nothing in the digest or storage records which operator generation a voucher belongs to; validity is decided only by signer == operator at submission time. A planned roll A -> B -> A, or re-installing a key believed clean, makes every unspent, unexpired voucher signed by A valid again, including ones a leaked copy of A produced with expiry = type(uint256).max (see the unbounded-expiry finding). Fix: include an operator epoch (incremented in setOperator) in the signed struct or in a per-epoch nonce namespace, so a voucher invalidated by rotation stays invalid. Reported by the math specialist; reproduced.

**Reproduction**

Operator A signs (player, 1000e18, nonce 0, expiry max). Guardian calls setOperator(B): withdraw with the voucher reverts BadSignature. Guardian calls setOperator(A): the same voucher now pays 1000e18 (balanceOf(player) == 1000e18). Expected: a voucher invalidated by rotation stays invalid. Reproduced in test/scratch/Judge.t.sol test_rotatingBackRevivesOldVouchers (passes on current code).

### 6. Low: Vesting wallets have no cliff: about 54,800 ECU of team plus community tokens become releasable on day one, and the 1-year community schedule is not in the spec

`script/Distribute.s.sol:88`

```
        deployment.teamVesting = new VestingWallet(to.teamBeneficiary, startAt, TEAM_VESTING_SECONDS);
```

Both OpenZeppelin VestingWallets start at the launch block's timestamp and vest linearly from the first second with no cliff; release(token) is permissionless. ECONOMY.md §11.7 lists both slices as 'Liquid? No' and states 'the circulating float at launch is the 15 % in the pool'; §9 says 'team (3 y vest)' and gives no community duration at all, so the 365-day constant on line 43 (whose comment says 'unless overridden' although nothing can override it) exists only in the script. After one day 13,698.63 ECU (team) + 41,095.89 ECU (community) = 54,794 ECU is releasable, about 1.7x the ~31,000-33,000 ECU/day Exchange budget the whole economy is tuned around; after 30 days about 1.64 M. The share arithmetic itself is exact. This is a spec-versus-implementation gap, not an arithmetic bug: either pass a later `startAt` or use the vendored OpenZeppelin VestingWalletCliff with a cliff matching the launch policy and record the community duration in ECONOMY.md, or amend §11.7 to say both slices unlock linearly from launch. The existing test test_nothingHasVestedAtLaunch checks only the exact launch second. Merged from five specialist entries; reproduced.

**Reproduction**

deployAll(to, START); vm.warp(START + 1): teamVesting.releasable(ecu) > 0. vm.warp(START + 1 days): teamVesting.releasable(ecu) == 13698630136986301369863 wei, communityVesting.releasable(ecu) == 41095890410958904109589 wei; vm.prank(0xDEAD); communityVesting.release(ecu) moves the community amount to the beneficiary. Expected per §11.7 'Liquid? No': 0 until an agreed cliff. Reproduced in test/scratch/Judge.t.sol test_vestingDayOneAndLpUnlocked (passes on current code and logs the amounts).

### 7. Low: The 15 % DEX liquidity slice is sent unlocked to a plain address although ECONOMY.md §9 specifies 'DEX LP (locked 2 y)'

`script/Distribute.s.sol:90`

```
        deployment.ecu.transfer(to.liquidity, _slice(LP_SHARE));
```

ECONOMY.md §9's parameter table reads '15 % DEX LP (locked 2 y)' and §11.7 says this slice sits in the Uniswap V4 pool on day one and is 'the only ECU anyone can buy'. The script transfers 15 M ECU to LIQUIDITY_ADDRESS with no lock, vesting wallet or requirement that the address be a contract; the README's list of deliberate omissions (no pool creation, no reserve split) does not mention the 2-year lock. Nothing on chain or in the script enforces that the tokens reach a pool or stay locked, so the holder of LIQUIDITY_ADDRESS can move or sell the entire launch float immediately. Fix options that keep the design: route the slice through an escrow/timelock the pool creator draws from, or document in ECONOMY.md/README that the 2-year lock applies to the V4 position after pairing as an off-chain operational step and name who enforces it. Merged from three specialist entries; reproduced.

**Reproduction**

deployAll with liquidity = 0x11 (an EOA). vm.prank(0x11); ecu.transfer(0x99, 15_000_000e18) succeeds at block.timestamp == start; balanceOf(0x99) == 15_000_000e18. Expected per §9: the LP allocation is locked for 2 years. Reproduced in test/scratch/Judge.t.sol test_vestingDayOneAndLpUnlocked.

### 8. Low: VestingWallet beneficiaries can be changed or renounced, contradicting .env.example, and renouncing strands the slice forever

`script/Distribute.s.sol:87`

```
        deployment.communityVesting = new VestingWallet(to.communityBeneficiary, startAt, COMMUNITY_VESTING_SECONDS);
```

OpenZeppelin 5.7 VestingWallet is Ownable with the beneficiary as owner, and release(token) pays owner(). .env.example states 'Beneficiaries of the two vesting contracts. These addresses cannot be changed afterwards', which is false: the beneficiary can call transferOwnership (OZ's own NOTE: 'it is possible to sell unvested tokens'), and can call renounceOwnership, after which owner() == address(0) and every release(token) reverts with ERC20InvalidReceiver, locking the remaining 15 M slice permanently with no recovery. Neither property is a contract bug, but the launch runbook and the spec's 'team (3 y vest)' commitment assume the beneficiary cannot move the schedule to a buyer. Fix: document that the beneficiary is a transferable owner and must be a Safe, or wrap VestingWallet with renounceOwnership overridden to revert (and transferOwnership restricted) so the 3-year team commitment is not escapable or accidentally bricked. Judge's own finding; reproduced.

**Reproduction**

deployAll(to, START) with teamBeneficiary = 0x33. vm.prank(0x33); teamVesting.transferOwnership(0x77): owner() == 0x77 (expected per .env.example: not changeable). vm.prank(0x77); teamVesting.renounceOwnership(); vm.warp(START + 30 days); teamVesting.release(ecu) reverts (transfer to address(0)); the 15 M remains unreachable. Reproduced in test/scratch/Judge.t.sol test_vestingBeneficiaryCanRenounceAndStrand (passes on current code).

### 9. Info: Trust assumptions: the guardian has instant full custody via setOperator; the operator must be an EOA (no ERC-1271); pause is one-way for deposits

`src/FarmVault.sol:170`

```
        operator = newOperator;
```

Documented powers, not bypasses. (a) setOperator has no delay, so whoever controls the guardian address can appoint a key it holds and sign a voucher for the whole balance in the next transaction; combined with the missing outflow cap, the 2-of-3 Safe signers are a path to all 50 M ECU, and a guardian hand-over is also a custody hand-over. If a narrower guardian is wanted, put a short timelock on setOperator while keeping pause instant. (b) Verification uses ECDSA.tryRecover only (65-byte signatures, high-s rejected, zero signer rejected since operator != 0); there is no ERC-1271 path, so if VAULT_OPERATOR is ever set to a contract (Safe, HSM wrapper) no voucher can validate until the guardian rotates to an EOA. (c) The guardian can pause withdrawals indefinitely while deposits keep flowing, so players can be trapped one-way. These match the stated design and should appear in the launch runbook. Merged from three specialist entries; reproduced.

**Reproduction**

(a) guardian calls setOperator(g) with g a key it holds, then withdraw(g, 50_000_000e18, 0, expiry, sig_by_g) succeeds and g holds the entire custody (test/scratch/Judge.t.sol test_guardianCanAppointItselfOperatorAndDrain). (b) new FarmVault(ecu, address(aContract), guardian): every withdraw reverts BadSignature (test_contractOperatorCanNeverValidate). High-s malleated signatures are rejected with BadSignature (test_highSRejected), so no malleability issue exists.

### 10. Info: Test suite never exercises the broadcast path or any outflow bound, so neither high finding fails a test today

`test/Distribute.t.sol:40`

```
        d = script.deployAll(to, START);
```

DistributeTest calls deployAll directly, so the script contract is both the ECU distributor and the caller of every transfer; the broadcast path through run(), where sender and address(this) differ, is never executed and the address(this) defect is invisible. FarmVaultTest's testFuzz_anyAmountTheVaultHoldsCanBeVouchered asserts that any amount clears on one voucher, encoding the absence of an outflow bound as expected behaviour. Also untested: high-s signatures (OZ rejects them; a regression test would pin it), a voucher submitted exactly at expiry (accepted by design), vesting amounts after the launch second, operator rotate-back, and any multi-day withdrawal sequence. Add a test that drives run() under broadcast, tests for the cap once added, and day-1 vesting assertions. Merged from the permissions specialist; reproduced.

**Reproduction**

`forge test` passes 41/41 on the current tree while test/scratch/Proof_24722058997d.t.sol (script.run() under broadcast) fails with ERC20InsufficientBalance and test/scratch/Proof_a7af1dda5956.t.sol (50 M single voucher) fails with 'next call did not revert as expected'.

---

Judge's submission `ee06755e2c9d0ab60b706246db72482b688662ca779eea09783544785f9ec604`, accepted on the IdentityMD network. Acceptance means the report met the job's checks;
it is not a guarantee that the code has no other defects.
