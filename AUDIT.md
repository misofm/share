# Security Audit — `share`

Audited at `4cdd365fedf2d4b924a50eb20d266319391186f9` (2026-10-21). Package `share`, module `share::share`; framework dependency `sui::coin_registry`, `sui::coin`, `sui::balance` at `719fb2960ccfbf9f4d33041f8ea5146d30671696`.

## What it does

One function, `mint<Share: key>` (`sources/share.move:31`), checks a freshly registered `Currency<Share>` against protocol-supplied type names, metadata and supply, mints the whole supply as a `Balance<Share>` and fixes the supply by consuming the `TreasuryCap`. There is no burn, no admin, no state. See [README](./README.md).

## Trust model

- **Issuer** (holder of `TreasuryCap<Share>`): the only party that can call `mint` for a type, and only once. Must have created the currency with `coin_registry::new_currency` from `Share`'s own module and deleted the metadata cap first.
- **Caller protocol** (e.g. `miso_music`): supplies the expected module name, datatype name, decimals, symbol, name, description, icon URL and supply as constants. `mint`'s guarantee is only as strong as those constants; the package does not know what a "correct" share is.
- **Nobody** can mint a second time, change supply, metadata or regulation after `mint`, or obtain another `TreasuryCap<Share>` for a `key` type.

## Findings

**SH-1 · Info · Accepted** — `is_type` accepts a generic instantiation when the caller spells the type arguments into `datatype_name` (`sources/share.move:65-73`). Probe: `is_type<Generic<Fixture>>(b"fixture", b"Generic<<addr>::fixture::Fixture>")` returns true. The README states this; protocols must pass a plain datatype name.

**SH-2 · Info · Accepted** — The expected metadata and supply are untyped arguments; a caller that derives them from user input instead of constants gets no protection from `mint`. Documented as a caller responsibility.

## Checked, no finding

- **Single mint per type.** `ENotZeroSupply` (`:56`) requires nothing outstanding; `make_supply_fixed` (`:59`) moves the cap into `SupplyState::Fixed`, from which no framework path recovers a `Supply` or `TreasuryCap` (`coin_registry.move`: `make_supply_fixed` aborts `EInvariantViolation` on a second call; `burn_balance` requires `BurnOnly`). Mint-then-burn-to-zero before `mint` is harmless (test `mint_then_burn_is_benign`).
- **Only one `TreasuryCap<Share>` can exist.** `coin::new_treasury_cap` is `public(package)`; `coin::create_currency*` and `coin_registry::new_currency_with_otw` need `T: drop`; `balance::create_supply` needs `T: drop`. A `key` struct cannot have `drop` (UID lacks `drop`; verified with a probe struct that fails to compile). So `ETreasuryMismatch` (`:52-55`) is defense in depth, as the README says.
- **Only one `Currency<Share>` can exist** for a `key` type: `new_currency` derives its ID from the registry with `CurrencyKey<T>` and aborts `ECurrencyAlreadyExists` on repeat; the OTW and legacy-migration constructors are excluded by the `key` bound.
- **`new_currency` must be called from `Share`'s module.** Enforced by the Sui verifier at compile time (`ESC02010 invalid coin creation call`; probe from a sibling module fails to build). Together with the `is_type` check this pins the coin to `<package>::<module>::<datatype>`.
- **Metadata is frozen after `mint`.** `is_metadata_cap_deleted` (`:45`) is terminal: `claim_metadata_cap` aborts when the state is `Claimed` or `Deleted`, every `set_*` needs a `&MetadataCap`, and `update_from_legacy_metadata` aborts for claimed/deleted. Decimals have no setter.
- **Regulation is frozen after `mint`.** `is_regulated` (`:46`) false means no `DenyCapV2<Share>` exists: the only constructors are `CurrencyInitializer::make_regulated` (sets `Regulated` before `finalize`) and the `T: drop` legacy flows; `migrate_regulated_state_by_cap` therefore has nothing to be called with. `new_currency` sets `Unregulated`, never `Unknown`.
- **Money.** Exactly `supply` is minted (`increase_supply` allows `value <= u64::MAX - 0`; `max_supply_accepted` test); the full balance is returned to the caller; nothing is retained or sent; no rounding or dust.
- **Type-name parsing.** `with_defining_ids` gives a stable address across upgrades; the expected string is built from that address, so only module and datatype names are caller-controlled. Separator injection and empty names cannot match (tests `injected_separator_never_matches`, `empty_names_never_match`).
- **Abort order and reachability.** Codes 0–10 are each reachable and tested in the README's order; `EZeroSupply` (`:43`) precedes all other checks.
- **Object lifecycle.** The package defines no objects; `Currency` is a shared framework object taken by `&mut`; the cap is consumed; the returned `Balance` has `store` only.
- **Limits.** One command, no events, no dynamic fields.

## Operational requirements

- Create each share type in its own module, register with `coin_registry::new_currency`, `finalize_and_delete_metadata_cap`, then hand the `TreasuryCap` to the protocol that calls `mint`. Do not call `make_regulated`.
- The caller of `mint` receives the full supply; the issuer must keep the cap until the protocol mints.
- Protocols must pass the type names and metadata as constants, with no type arguments in `datatype_name`.

## Verification

- `sui move test --coverage`: 22/22 passed; `sui move coverage summary`: 100.00% for `share::share`.
- `sui move build -e mainnet` and `sui move build -e testnet`: both succeed with framework `719fb2960ccfbf9f4d33041f8ea5146d30671696` (Move.lock).
- Throwaway probes (not committed): generic type-name match (SH-1); `key + drop` struct rejected by the compiler; `new_currency` on a foreign type rejected by the verifier.
