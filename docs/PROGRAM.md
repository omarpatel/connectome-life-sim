# The Instar program

`program/programs/instar` is the Anchor 0.31 program for the experimental
world ledger: creature identity and ancestry as Metaplex Core assets, test
balances and transfers, and an engine state hash committed each epoch.
The simulation runs off-chain in `services/world`; this program does not run
neurons or establish that a simulation is biologically accurate.

This port is for local validators and devnet only. The original deployment,
its accounts and its transaction history are excluded. No deployment status
or production readiness is claimed. All ledger quantities described below
are protocol mechanics, not historical balances, earnings or valuations.

Configure the program identity consistently in the Rust declaration,
Anchor configuration, generated IDL, service configuration and browser pin
before integration. A public program identifier is not a signer: deployment
and initialization additionally require authorized local signing material.
Never copy an old deployment identity or publish private keys.

## Design rule

Every balance the program holds has a withdrawal path that exists from
deployment and does not depend on any off-chain process being alive. If the
operator key were destroyed this instant and nobody ever ran the world again,
each lamport can still be got out, by someone, without anyone's permission:

| balance          | exit                                                                 |
| ---------------- | -------------------------------------------------------------------- |
| creature vault   | `reclaim_vault` by its keeper once the world is winding down         |
| credit           | `withdraw` by its owner, at any time                                 |
| metabolism, pool | `withdraw_treasury` by the operator; `sweep_to_recovery` by anyone in wind-down |
| anything left    | `escheat` to `recovery`, 180 days after `begin_wind_down` landed   |
| account rent     | `close_record`, `close_credit`, `close_world` to `recovery`, after escheat |

Wind-down is declared by the operator, or by anyone once the operator has been
silent for 90 days, so an abandoned world escheats at day 270 at the earliest.
Every operator instruction refreshes the heartbeat, so a world that is being
run never opens these doors.

## Development ledger accounting

All lamports live on the `World` PDA itself. Lamports come in through a CPI
`system_program::transfer` from the payer (`buy`, `buy_listed`, `fund`) and go
out by debiting the World account and crediting any writable recipient
(`withdraw`, `withdraw_treasury`, `sweep_to_recovery`, `escheat`), so a payout
can never be refused.

Solvency invariant, asserted at the end of every instruction that moves
lamports or ledger balances:

    world.lamports - rent_exempt(World) >= metabolism + pool + total_vaults + total_credit

`total_vaults` and `total_credit` are running totals kept on `World` because a
transaction cannot read every creature; each instruction that changes a vault
or a credit moves the same amount through the total. The integration suite
checks totals against the sum of creature and credit accounts after each flow.

## Accounts

`World`, seeds `["world"]`, one per program:

| field                 | type     |                                                             |
| --------------------- | -------- | ----------------------------------------------------------- |
| operator              | Pubkey   | the crank: registers births, settles deaths, posts epochs   |
| pending_operator      | Pubkey   | two-step hand-over                                          |
| recovery              | Pubkey   | where an abandoned world's money goes; set at init, changeable by `set_recovery` until wind-down begins, fixed after |
| collection            | Pubkey   | the Core collection every fly's asset belongs to; set at init |
| next_id               | u64      | the next fly id the engine may register                   |
| total_alive           | u64      | flies not DEAD                                             |
| last_epoch, last_epoch_tick, last_state_hash | u64, u64, [u8;32] | the last epoch commitment  |
| metabolism            | u64      | treasury that sets carrying capacity                        |
| pool                  | u64      | treasury that pays living flies every eighth epoch         |
| total_vaults          | u64      | sum of every creature vault                                 |
| total_credit          | u64      | sum of every credit                                         |
| last_operator_action  | i64      | unix time of the last operator instruction                  |
| wind_down, wind_down_at | bool, i64 | one-way                                                  |
| escheated             | bool     | set by `escheat`; opens the close instructions              |
| closed_records        | u64      | Creature PDAs closed by `close_record`                      |
| credits_open          | u64      | Credit PDAs in existence                                    |
| bump                  | u8       |                                                             |

`Creature`, seeds `["creature", id as u64 LE]`, closed only by `close_record`
after escheat:

| field             | type     |                                                        |
| ----------------- | -------- | ------------------------------------------------------ |
| id                | u64      |                                                        |
| parent_id         | u64      | `u64::MAX` for a founder                               |
| generation        | u32      |                                                        |
| birth_tick, death_tick | u64 |                                                        |
| genome_hash       | [u8;32]  | the engine's genome digest at birth                    |
| asset             | Pubkey   | the fly's Core asset; kept after the burn as record  |
| listed_by         | Pubkey   | who listed the fly for resale; default when not listed |
| listed_at         | i64      | when; a listing expires LISTING_MAX_AGE later          |
| vault             | u64      | lamports the fly holds, backed by World              |
| sale_price        | u64      | OFFERED: opening price (`offer_price` gives the current one); OWNED: resale price, 0 = not listed |
| status            | u8       | 1 OFFERED, 2 OWNED, 3 WILD, 4 DEAD (0 never on chain)  |
| pending_cull, cull_requested_at | bool, i64 |                                         |
| bump              | u8       |                                                        |

`last_state_hash` and `genome_hash` are zero-padded 64-bit digests, not
32-byte hashes: bytes 0..23 are zero and bytes 24..31 hold the engine's u64
(`state_hash()` at the epoch tick, `creature_genome_hash(slot)` at birth) in
big-endian order. The journal, the site and `/api/journal` carry only the
16-hex-character u64 form, so a third party checking the chain against a
replayed engine compares the last 8 bytes of the account field to that value.

`Credit`, seeds `["credit", owner]`: `owner`, `amount`, `bump`. Created with
`init_if_needed` by whichever instruction first owes the owner something
(`buy_listed`, `settle_death`, `force_settle_cull`, `reclaim_vault`); the
transaction's signer pays its rent and the world counts it in `credits_open`.
Closed only by `close_credit` after escheat.

## The fly as an NFT

Who keeps a fly is not a field of `Creature`: it is the `owner` of the
fly's Metaplex Core asset (`mpl-core` 0.11 with the `anchor` feature).
The Core program identifier is defined by the dependency and integration
configuration, not by a historical deployment record in this document.
Ownership can change through a native Core transfer; the Instar program
has no `transfer` instruction.

`init_world` creates the collection (`CreateCollectionV2`, name `Instar`,
`collection_uri`) with the World PDA as update authority; the collection
account is a fresh keypair the client signs for and `World.collection`
records it. `register_birth` creates the asset (`CreateV2`, name
`Instar #<id>`, `uri`, again a fresh client-signed keypair recorded in
`Creature.asset`), owned by the World PDA, in the collection, with four
plugins whose authority is the World PDA, the three permanent ones being
addable only at creation:

| plugin | what the program does with it |
| --- | --- |
| `PermanentTransferDelegate` | `buy_listed` moves the asset from the seller to the buyer |
| `PermanentFreezeDelegate` | `request_cull` freezes the asset; a frozen asset cannot be transferred, so a fly awaiting its cull cannot leave the cage |
| `PermanentBurnDelegate` | `settle_death`, `force_settle_cull` and `reclaim_vault` burn the asset; the burn goes through a freeze |
| `Attributes` | `generation`, `parent` (id, or `founder`), `birth_tick`, `genome` (the 16-hex-character digest) for wallets to show |

`buy` moves the asset from the World PDA (signing as owner) to the buyer.
Every instruction that takes the asset checks `asset == creature.asset` and
that Core owns the account (`AssetMismatch`), and the collection against
`World.collection` (`WrongCollection`). Ownership checks read the asset's
`owner` at execution time: `list`, `request_cull` and `reclaim_vault` require
the signer to be that owner (`NotOwner`); `unlist` accepts the owner or
`listed_by`; the keeper paid by `settle_death` and `force_settle_cull` is the
owner at settlement, and their `keeper_credit` PDA is checked against it
(a WILD or OFFERED fly is owned by the World PDA and has no keeper).

The keeper share is a pull payment keyed by that owner: it lands in the
Credit PDA of whatever account holds the asset when the death is settled, and
`withdraw` needs that account's signature. An asset sitting in a
marketplace escrow, or sent to any address that cannot sign, forfeits its
keeper share to a credit nobody can draw (until escheat). Keep a fly in a
wallet you sign with; list it through `list`, from that wallet, rather than
on an external marketplace, if you want its death share.

A listing is only good while the asset is still in the lister's hands, and
for LISTING_MAX_AGE after it was made. `list` records `listed_by` and
`listed_at`; `buy_listed` requires `asset.owner == listed_by` and
`now - listed_at <= LISTING_MAX_AGE`, and pays `listed_by`'s credit, so a
fly moved with a native transfer since it was listed is `NotForSale`
until the new owner lists it themselves (or clears the stale listing with
`unlist`), and a listing that outlives the timer is `NotForSale` until it is
made again. The program cannot see a native transfer, so without the timer
a listing voided by the asset leaving `listed_by`'s hands would come back
to life the moment the asset returned there, at a price consented to for a
fly that has since kept earning.

Core does not delete a burned asset: it leaves a one-byte `Uninitialized`
stub behind, still owned by Core, and refunds the rest of the rent to the
payer. `Creature.asset` keeps pointing at it as the record of which asset
the fly was; the rent of a birth goes back to whoever settles the death.

A keeper can burn an unfrozen asset from their wallet, as they can any Core
asset they own; the record does not see it. The fly stays alive on chain
until the engine kills it, but nobody owns the stub: `list`, `request_cull`
and `reclaim_vault` load it as `WrongStatus`. `settle_death` alone accepts
the stub (its `asset` is an unchecked account pinned to `creature.asset`
and Core's ownership, read by hand): a burned asset means no keeper, the
keeper share goes to metabolism as for a fly the World held, `keeper_credit`
must be absent, and there is nothing to burn. `force_settle_cull` and
`reclaim_vault` keep the strict load: a fly awaiting its cull is frozen
and Core refuses its owner's burn, so no cull ever meets a stub; and a
reclaim needs the owner's signature, which a burned asset has nobody to
give. The vault of a fly whose keeper burned it is settled by the operator
like any death, and in an abandoned world it waits for escheat.

A keeper can also send the asset back to the World PDA with a plain
transfer. The fly is then OWNED with the cage as owner, nothing a keeper
can sign for; `open_offer` accepts it (OWNED and `asset.owner == World PDA`,
the listing cleared) so the operator can put it up for sale again as if
newborn. The service never does this on its own: it is operator tooling.

Local validators preload Core from `program/deps/mpl_core.so`, generated by
`bash scripts/dump-mpl-core.sh` from devnet by default. The binary is not
distributed with this source port; the SDK supplies its program identifier.

## Instructions

Operator instructions require `world.operator` as signer and set
`last_operator_action`. `id` arguments name the creature PDA. "keeper" below
is the asset's current owner; instructions that touch the asset also take
`asset`, `collection` and `mpl_core_program`.

| instruction | signer | effect |
| --- | --- | --- |
| `init_world(recovery, collection_uri)` | the program's upgrade authority (pays rent, becomes operator) | creates World and the Core collection (`collection` is a fresh keypair signer); the signer must be the upgrade authority named by the program-data account (`program`, `program_data` accounts), so nobody can claim the singleton PDA ahead of the deployer; `recovery` must be set and must not be the operator |
| `set_recovery(new)` | operator | not in wind-down; never the operator |
| `transfer_operator(new)` / `accept_operator()` | operator / pending | two-step; neither may make the recovery address the operator |
| `heartbeat()` | operator | refreshes `last_operator_action` |
| `post_epoch(epoch, tick, hash)` | operator | `epoch == last_epoch + 1`, `tick > last_epoch_tick` |
| `register_birth(id, parent_id, generation, birth_tick, genome_hash, uri)` | operator (pays rent) | `id == next_id`; WILD; creates the Core asset (`asset` is a fresh keypair signer) owned by the World PDA; not in wind-down |
| `open_offer(id, price)` | operator | WILD, or OWNED with the asset back in the World PDA's hands (a keeper sent it to the cage natively), to OFFERED at opening price `price` > 0; clears any listing and stamps `listed_at` as the offer's start; not in wind-down |
| `buy(id, price)` | buyer | OFFERED and the asset still the World PDA's; the current price is `offer_price(sale_price, listed_at, now)` (holds OFFER_HOLD_SECS = 5 min, then falls over OFFER_DECAY_SECS = 20 min to OFFER_FLOOR_BPS = 25%; flat when `listed_at` is 0) and `price` must be at least it, the buyer being charged the current price; the `parent` account is required whenever `parent_id` is set; 60% vault, 15% metabolism, 15% pool, 10% to the parent's vault if the parent is OWNED, else pool; the asset moves to the buyer, OWNED; not in wind-down |
| `list(id, price)` | keeper | OWNED and no pending cull; price > 0; records `listed_by` and `listed_at` |
| `unlist(id)` | keeper or `listed_by` | clears the listing |
| `buy_listed(id, price)` | buyer | `sale_price > 0`, the asset still `listed_by`'s and the listing younger than LISTING_MAX_AGE, else NotForSale; 90% to `listed_by`'s credit (`seller_credit`, derived from the record), 5% metabolism, 5% pool; the vault travels with the fly; the asset moves to the buyer through the transfer delegate; refused for a pending cull and in wind-down |
| `reward_many(amounts)` | operator | creatures in `remaining_accounts`, one per amount; pool to vaults; DEAD skipped; not in wind-down |
| `settle_death(id, cause, tick, heir_count)` | operator | first `heir_count` of `remaining_accounts` are heirs: each must be alive and the fly's own offspring (`parent_id == id`), passed in strictly increasing id order. With `pending_cull`, whatever the cause: 85% keeper credit, 15% metabolism. In wind-down: the whole vault to the keeper credit (no keeper: metabolism), nothing to heirs or treasuries. Otherwise 40% heirs in equal shares (dust to pool; no heirs: to metabolism), 35% metabolism, 15% pool, 10% keeper credit (no keeper: metabolism). `keeper_credit` is an optional account, required when the fly has a keeper; burns the asset. An asset the keeper already burned natively is accepted: no keeper, `keeper_credit` absent, nothing burned. A fly already DEAD fails WrongStatus |
| `request_cull(id)` | keeper | OWNED; clears the listing, freezes the asset, starts CULL_TIMEOUT |
| `force_settle_cull(id)` | anyone | after CULL_TIMEOUT: 85% keeper credit, 15% metabolism; burns the asset |
| `withdraw()` | credit owner | credit to owner's account |
| `withdraw_treasury(m, p)` | operator | to any account; `u64::MAX` takes the whole pot, 0 takes none of it |
| `fund(amount, pool_bps)` | anyone | `pool_bps` to pool, the rest to metabolism; not in wind-down |
| `begin_wind_down()` | operator, or anyone after ABANDONED_AFTER | one-way |
| `reclaim_vault(id)` | keeper | wind-down: vault to credit, asset burned, fly DEAD |
| `sweep_to_recovery()` | anyone | wind-down: metabolism + pool to `recovery` |
| `escheat()` | anyone | wind-down + ESCHEAT_AFTER: everything above rent to `recovery`; ledger zeroed, later claims fail Insolvent |
| `close_record(id)` | anyone | escheated: closes the Creature PDA to `recovery`, any status; the asset is untouched; `closed_records += 1` |
| `close_credit()` | anyone | escheated: closes the `credit` account passed (any owner's) to `recovery`; `credits_open -= 1` |
| `close_world()` | anyone | escheated, `closed_records == next_id`, `credits_open == 0`: closes the World PDA to `recovery` |

Splits are integer basis points; the last share of each split takes the
rounding remainder so the parts always sum to the whole.

Once `wind_down` is set nothing new enters the world: births, offers, sales,
rewards and funding are refused with `WindingDown`. The ledger is being
emptied, and fresh lamports would only back stale claims.

Errors: `NotOperator`, `NotOwner`, `WrongStatus`, `WrongId`, `NotForSale`,
`WrongPrice`, `Insolvent`, `NotWindingDown`, `NotAbandoned`, `TooEarly`,
`EpochNotMonotonic`, `NothingToWithdraw`, `WindingDown`, `RecoveryIsOperator`,
`AssetMismatch`, `WrongCollection`, `NotEscheated`, `RecordsStillOpen`.

## The end of the world

`escheat` empties the ledger; what is left on chain afterwards is rent: one
`Creature` per fly ever born, one `Credit` per address ever owed
something, and the `World` itself. Three permissionless instructions return
it, all to `recovery` and all only once `world.escheated` is set (before
that the records back money and closing one is refused with `NotEscheated`):

1. `close_record(id)` for every id below `next_id`, in any order and any
   status. The Core asset is not touched: a kept fly's asset stays with
   its keeper as a collectible, a dead one's is already a burned stub.
   `closed_records` counts them.
2. `close_credit()` for every `Credit` account (found by program-account
   scan on the Credit discriminator; `credits_open` says how many exist,
   counting every path that creates one, `reclaim_vault` included).
   No signature: after escheat a credit is empty and backs nothing.
3. `close_world()`, refused with `RecordsStillOpen` until
   `closed_records == next_id` and `credits_open == 0`. The collection is a
   Core account owned by Core, not by this program; it stays, with the
   World PDA, which no longer exists, as its update authority.

Each step is irreversible and returns the closed account's rent;
`escheat` is idempotent and a second call changes no balances. Program
deployment accounts and their upgrade authority are separate from this
application ledger.

## Timers

| constant         | default  | `short-timers` feature |
| ---------------- | -------- | ---------------------- |
| ABANDONED_AFTER  | 90 days  | 4 s                    |
| ESCHEAT_AFTER    | 180 days | 4 s                    |
| CULL_TIMEOUT     | 7 days   | 3 s                    |
| LISTING_MAX_AGE  | 30 days  | 6 s                    |

`Clock::unix_timestamp` is the clock. The integration suite uses the
`short-timers` feature and waits for those shortened intervals.
`scripts/build-program.sh test` builds the short-timer artifact for the suite
and restores the default-timer build afterwards. Feature markers beside the
artifact distinguish an in-progress build from a completed one; use a
consistent artifact and generated IDL for each local integration.

## Build and integration prerequisites

Use a compatible Rust, Solana/Agave and Anchor toolchain. The program targets
Anchor 0.31; the retained build wrapper uses `cargo build-sbf --arch v3`
for the artifact and `anchor idl build` for the IDL. Match the sBPF version
to your local validator or devnet toolchain.

The integration suite (`program/tests/instar.ts`) uses Node's native ESM
TypeScript stripping and needs Node >= 22.18. Install the program's Node
dependencies in `program/` separately from the root application dependencies.
Provider configuration must point at the intended local validator or devnet
and signing material controlled by the developer. Machine-specific wrapper
paths from the original environment are not setup prerequisites.

The simulation-only WASM build in the root README does not build or deploy
this program. Program integration additionally needs a configured program
identity, a locally built artifact and IDL, Metaplex Core available on the
chosen validator, and an initialized World with a matching operator.

The suite covers, in the order of one world's life: the collection at init,
a birth minting the asset to the World PDA with its attributes, primary sale
splits and the asset moving to the buyer, price protection, resale through
the transfer delegate and the travelling vault, an unlisted fly not for
sale, withdraw, the ancestry royalty (live, dead and wrong parent), batched
rewards that skip the dead, inheritance with dust and the burn, wild deaths
burned from the World PDA, culls (requested, with the freeze, and not), a
native Core transfer voiding the old listing and making the new owner the
keeper, a keeper's native burn settling with no keeper share, a listing
expiring after LISTING_MAX_AGE, a fly sent back to the cage re-offered and
bought again, epoch monotonicity, operator-only access, treasury withdrawal
and funding, operator hand-over, recovery address rules, a stranger failing
to wind down a running world, self-service culls after the timeout, the
heartbeat keeping a world alive, a keeper recovering (and burning) their
fly with the operator gone forever, treasuries reaching only the recovery
address, the world emptying to exactly the one vault nobody reclaimed, that
vault escheating after the timer, every record staying readable, and then
the end of the world: nothing closes before escheat, every record (the
unclaimed keeper's included, whose asset stays theirs) and every credit
closes to recovery for exactly its rent, `close_world` refuses while any
is open and then returns the World's rent, leaving the collection behind.
Solvency is asserted after every flow. Assets are read with
`@metaplex-foundation/mpl-core` over umi; the native transfer and burn are
the SDK's `transferV1` and `burnV1`.

## Localnet and devnet integration

The service defaults to localnet. Use an explicitly configured local RPC
endpoint or devnet; this port does not support production operation.
The validator must contain the matching Instar program and Metaplex Core.
`init_world` must be signed by the program's upgrade authority and creates
the World and its collection. Its recovery account must be distinct from
the operator. Configure public metadata URLs appropriate to the development
environment rather than any original deployment URL.

`PROGRAM_ID` selects the configured program;
`INSTAR_OPERATOR_KEYPAIR` identifies locally managed signing material.
The world process needs that operator to match the initialized World.
Keep signing material outside source control. This document intentionally
contains no deploy commands, original addresses, transaction signatures,
funding records or recovery runbook for the original installation.
