# VisualIdentity.md (VIMD)

A fixed-supply ERC-20 for the IdentityMD custom token launch. The deployable contract is
[`src/VIMDToken.sol`](src/VIMDToken.sol), Solidity identifier **`VIMDToken`**.

## Token behavior

| Parameter | Value |
| --- | --- |
| Name | `VisualIdentity.md` |
| Symbol | `VIMD` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| Native currency required | None; constructor is nonpayable |

The constructor mints the entire supply in one operation and emits one
`Transfer(address(0), deployer, supply)` event. There is no further minting, burning,
ownership, pausing, blacklisting, confiscation, fee, rebasing, or upgrade functionality.
The deployer has the same transfer and approval rights as any other holder.

The assumption for unspecified transfer rules is ordinary ERC-20 behavior, implemented
by the vendored OpenZeppelin Contracts v5.0.2 ERC20. Successful operations return `true`;
invalid operations revert with ERC-6093 custom errors. Transfers deliver the exact
requested amount. Zero-value transfers and self-transfers are supported; zero-address
senders, recipients, and approval spenders are rejected.

`approve` replaces the current allowance. `transferFrom` requires an allowance even if
the caller is the source account. Finite allowances decrease when spent;
`type(uint256).max` means unlimited allowance and is not decreased. Explicit approvals
emit `Approval`; this implementation does not emit `Approval` when `transferFrom`
decreases an allowance. Failed transfers leave balances and allowances unchanged.

## Build and test

Use Foundry with Solidity **0.8.26**, as pinned in [`foundry.toml`](foundry.toml).
All Solidity dependencies are included as ordinary files in `lib/`; no dependency
installation, RPC endpoint, environment secrets, or submodules are needed. An offline
machine needs Foundry and the pinned Solidity compiler preinstalled.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xcc54560cea388c175d7c1160aee98ebc27727833822c11f83a60df96e798dbc2 forge test
forge fmt --check
```

The configuration uses the Cancun EVM target, optimizer enabled with 200 runs, and
`bytecode_hash = "none"`. It enables neither FFI nor filesystem permissions. Tests use
local actors and isolated deployments; they do not read or change environment variables,
fork a chain, or depend on test order. The shell seed above controls Foundry's fuzzer.

[`test/VIMDToken.t.sol`](test/VIMDToken.t.sol) covers metadata, exact issuance and its
event, CREATE2 factory deployment, exact launch distribution transfers, pool-address
transfers in both directions, approvals, allowance consumption/revocation, unlimited
allowances, zero amounts, self-transfers, invalid addresses, insufficient balances and
allowances, rollback after failure, and unavailable mint/burn/admin entrypoints.
Seven fuzz tests each run 1,024 cases. A runtime opcode check rejects delegation and
destruction opcodes and checks the deployment size limit.

[`test/VIMDToken.invariant.t.sol`](test/VIMDToken.invariant.t.sol) runs 128 sequences of
64 actions over four actors. An independent ledger checks every balance and allowance,
total supply conservation, and that rejected transfers preserve state. The handler
exercises transfers, approvals, delegated transfers, and invalid delegated transfers.

The local launch tests exercise ERC-20 transfer boundaries. They do not deploy a real
Uniswap PoolManager or claim to execute swaps. The supplied protected checks also depend
on platform-owned launch contracts, a pool implementation, and resolved manifest values;
the network runs that integration harness separately.

## Deployment and launch responsibilities

Deploy **only `VIMDToken`**, directly from its compiled creation bytecode, with no
constructor arguments and no ETH. There are no application contracts or linked
libraries. Contracts under `test/` are local harnesses and are not launch artifacts.
Do not use a proxy: issuance takes place in the constructor.

The launch chain is Ethereum (chain ID 1). The IdentityMD factory is the immediate
deployer, so it receives all `10^27` units. An EOA deploying directly would receive the
entire supply instead; a deployment wrapper would receive it itself. The transaction
origin is never used. No particular factory address is hardcoded or required by the token.

The platform performs allocation and pool setup after construction. The supplied launch
terms are recorded here for handoff, not implemented as constructor transfers:

| Platform allocation | Share of total | VIMD |
| --- | --- | --- |
| Swarm distributor | 10% | 100,000,000 |
| Liquidity pool | 88% | 880,000,000 |
| Remainder recipient | 2% | 20,000,000 |

The remainder recipient is `0x6945df968a39edd0aa3f4b85f4949f6bf0f458f5`.
The launch's `economics.poolBps` is `8800` and `economics.initialMarketCapWei` is
`2500000000000000000000` (2,500 IMD at 18 decimals). The pair is IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, pool fee `12500` (1.25%), and tick spacing
`60`. The supplied provenance price is `79228162514264337593543950336`; the platform
derives the actual opening price from the launch economics and token ordering.

The separate manifest stage records these parameters and the token's exact minor-unit
supply. This project does not generate `launch.json`. Network operators are responsible
for final integration checks, manifest preparation, factory launch, allocation, and
explorer source verification with the pinned build settings. This project sends no
transactions and requires no wallet key.

## After launch

There are **no owner settings, initialization calls, or ongoing administrator duties**.
The launch operator should verify the deployed metadata, total supply, constructor mint
recipient, and subsequent distribution against the accepted manifest and transaction logs.
No party can repair a mistaken transfer by seizing tokens or changing the implementation.

Holders are responsible for recipient addresses and spender approvals. Use allowances
appropriate to the intended spend. Changing an existing nonzero allowance can race a
spender's pending transaction; revoke it and wait for confirmation before replacing it
when that matters. Unlimited approvals permit spending future balances until revoked.
The token invokes no recipient callbacks and provides no asset-recovery function:
tokens sent to this token contract or to another contract unable to return them may be
permanently inaccessible. Ordinary ETH sends are rejected.

## Security review and dependencies

The contract adds only the constructor and fixed supply constant to OpenZeppelin ERC20.
Review against the supplied security reference found no external calls in the token's
constructor or transfer paths, no privileged runtime entrypoints, no oracle or signature
dependency, and no proxy or delegation. Recipient code cannot reenter through a transfer
callback because none is made. Supply arithmetic is the exact integer product `10^9 * 10^18`.

Local validation used `forge build`, the unit/fuzz/invariant suite, and `forge fmt --check`.
Slither and Mythril were not run. This local review and test suite are not an independent
security audit; the platform's independent review and launch integration checks remain
release responsibilities.

Vendored versions, source commits, licenses, and integrity hashes are recorded in
[`DEPENDENCIES.md`](DEPENDENCIES.md) and [`dependencies.lock.json`](dependencies.lock.json).
