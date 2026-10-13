// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title FarmVault -- custody for the game-side half of the supply
/// @notice ECU enters by deposit and leaves only against a voucher the game's operator
///         signed (ECONOMY.md §1, §11.7).
///
/// @dev **What this contract is.** §11.7 calls the Vault "a rollup, not a fourth balance":
///      the Co-op reserve and the Bank pool -- 50 % of supply -- sit here as one ERC-20
///      balance, and the off-chain ledger is the authority on how that balance divides
///      between farms, reserves and escrows. This contract therefore deliberately knows
///      nothing about farms, buckets or the economy. It moves tokens in, and it moves them
///      out when the operator says so.
///
///      **Deposits are open and permissionless.** `deposit` pulls an approved amount and
///      emits `Deposited`, which the backend watches to credit the sending wallet's farm
///      (a wallet maps to at most one farm). A plain ERC-20 transfer straight to this
///      address also arrives, and is creditable from the token's own Transfer event; the
///      function exists so that the common path emits one unambiguous log.
///
///      **Withdrawals are operator-signed vouchers.** The game decides who may take what:
///      it applies the aged-harvest toll, the daily cap, the 48-hour delay and the risk
///      state (§11.1, §12) off-chain, and only then signs. A voucher carries the
///      recipient, the amount, a per-recipient nonce and an expiry, so it cannot be
///      replayed, reordered or held indefinitely. This is a *different signature* from the
///      one a player's wallet makes when requesting a withdrawal in the API: that proves
///      intent to the game, this proves authorisation to the chain.
///
///      **Pausing covers withdrawals only.** A guardian -- a 2-of-3 multisig -- can stop
///      the exit if a key leaks or the backend misbehaves, without trapping deposits or
///      touching the token. The threshold lives in the multisig, not here: this contract
///      holds one guardian address and lets the Safe supply the "2 of 3", which keeps the
///      signing policy changeable without redeploying custody.
contract FarmVault is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The token this vault custodies.
    IERC20 public immutable ecu;

    /// @notice Signs withdrawal vouchers. Rotatable by the guardian if a key is lost.
    address public operator;

    /// @notice The 2-of-3 multisig that may pause withdrawals and rotate the operator.
    address public guardian;

    /// @notice True while withdrawals are stopped. Deposits are never paused.
    bool public withdrawalsPaused;

    /// @notice Next expected voucher nonce for each recipient.
    mapping(address => uint256) public nonces;

    bytes32 public constant VOUCHER_TYPEHASH =
        keccak256("WithdrawalVoucher(address to,uint256 amount,uint256 nonce,uint256 expiry)");

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount, uint256 nonce);
    event OperatorChanged(address indexed previousOperator, address indexed newOperator);
    event GuardianChanged(address indexed previousGuardian, address indexed newGuardian);
    event WithdrawalsPaused(address indexed by);
    event WithdrawalsUnpaused(address indexed by);

    error ZeroAddress();
    error ZeroAmount();
    error NotGuardian();
    error Paused();
    error VoucherExpired(uint256 expiry);
    error WrongNonce(uint256 expected, uint256 given);
    error BadSignature();

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    /// @param ecu_ The ECU token.
    /// @param operator_ The backend key that signs withdrawal vouchers.
    /// @param guardian_ The 2-of-3 multisig that can pause withdrawals.
    constructor(IERC20 ecu_, address operator_, address guardian_) EIP712("e-Farm", "1") {
        if (address(ecu_) == address(0) || operator_ == address(0) || guardian_ == address(0)) {
            revert ZeroAddress();
        }
        ecu = ecu_;
        operator = operator_;
        guardian = guardian_;
    }

    // -----------------------------------------------------------------------
    // Deposits
    // -----------------------------------------------------------------------

    /// @notice Bridge ECU into the game. Requires an allowance for this contract.
    /// @dev Never paused: stopping the exit must not also trap the entrance, and a player
    ///      who has already approved should not have a transaction fail for a reason that
    ///      has nothing to do with them.
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        ecu.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    // -----------------------------------------------------------------------
    // Withdrawals
    // -----------------------------------------------------------------------

    /// @notice Take ECU out against a voucher the operator signed.
    /// @dev Anyone may submit the transaction -- a relayer, or the recipient -- because the
    ///      signature, not the sender, is the authority, and the tokens can only ever go to
    ///      the `to` the operator named.
    function withdraw(address to, uint256 amount, uint256 nonce, uint256 expiry, bytes calldata signature)
        external
        nonReentrant
    {
        if (withdrawalsPaused) revert Paused();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp > expiry) revert VoucherExpired(expiry);

        uint256 expected = nonces[to];
        if (nonce != expected) revert WrongNonce(expected, nonce);

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(VOUCHER_TYPEHASH, to, amount, nonce, expiry)));
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer != operator) revert BadSignature();

        // Spent before the transfer: the nonce is the replay guard, so it must move even
        // if the token does something surprising on the way out.
        nonces[to] = expected + 1;

        emit Withdrawn(to, amount, nonce);
        ecu.safeTransfer(to, amount);
    }

    /// @notice The digest a voucher must be signed over. For the backend and for testing.
    function voucherDigest(address to, uint256 amount, uint256 nonce, uint256 expiry) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(VOUCHER_TYPEHASH, to, amount, nonce, expiry)));
    }

    /// @notice The EIP-712 domain separator, so a client can rebuild it without guessing.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // -----------------------------------------------------------------------
    // Guardian
    // -----------------------------------------------------------------------

    function pauseWithdrawals() external onlyGuardian {
        withdrawalsPaused = true;
        emit WithdrawalsPaused(msg.sender);
    }

    function unpauseWithdrawals() external onlyGuardian {
        withdrawalsPaused = false;
        emit WithdrawalsUnpaused(msg.sender);
    }

    /// @notice Rotate the signing key, for a leak or a planned roll.
    /// @dev Vouchers signed by the old operator stop working immediately. Unspent nonces
    ///      are untouched, so a queue signed before a rotation must be reissued -- which is
    ///      the safe direction to fail in.
    function setOperator(address newOperator) external onlyGuardian {
        if (newOperator == address(0)) revert ZeroAddress();
        emit OperatorChanged(operator, newOperator);
        operator = newOperator;
    }

    /// @notice Hand the guardian role to another multisig.
    function setGuardian(address newGuardian) external onlyGuardian {
        if (newGuardian == address(0)) revert ZeroAddress();
        emit GuardianChanged(guardian, newGuardian);
        guardian = newGuardian;
    }
}
