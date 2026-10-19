# misofm/share

Canonical fixed-supply share coins for Sui Move.

A share coin is an ordinary `Coin<T>` whose type, metadata and supply are pinned
by the protocol that uses it. `mint` checks a freshly registered currency against
the protocol's expected values, mints the whole supply and fixes it. Coins minted
with the same values are identical apart from their package address. MusicOS uses
this for composition and recording shares, and treats a work object as proof that
its coin passed `mint`.

## Usage

```move
let shares: Balance<T> = share::mint(
    &mut currency,
    treasury_cap,
    b"composition_share",          // module
    b"CompositionShare",           // datatype
    6,                             // decimals
    b"Composition Share".to_string(),
    b"CSHARE".to_string(),
    b"".to_string(),               // description
    b"".to_string(),               // icon URL
    100_000_000_000_000,           // supply in base units
);
```

## Guarantees

`mint<T: key>` aborts unless, in this order:

| Check | Error |
|---|---|
| The supply is positive | `EZeroSupply` |
| `T` is exactly `<package>::<module>::<datatype>`, with no type arguments | `EInvalidType` |
| The metadata cap is deleted | `EMetadataNotLocked` |
| The currency is unregulated | `ERegulatedCurrency` |
| Decimals, name, symbol, description and icon URL equal the expected values | `EInvalidDecimals` … `EInvalidIconUrl` |
| The treasury cap is the one recorded on the currency | `ETreasuryMismatch` |
| Nothing is minted | `ENotZeroSupply` |

`mint` then mints the supply and consumes the treasury cap with
`coin_registry::make_supply_fixed`, so the currency can be minted only once and
its supply never changes. Minting then burning back to zero beforehand is
harmless: nothing is outstanding.

The `key` bound excludes legacy coins. Legacy constructors need a one-time
witness, which has only `drop`, so every accepted currency came from
`coin_registry::new_currency` and its regulation status is never `Unknown`. A
legacy regulated currency, migrated and with its treasury cap recorded, would
otherwise pass every other check while its deny cap stays live.

The caller of `mint` receives the full supply, so issuers should keep the
treasury cap until they mint.

## Creating a conforming currency

`coin_registry::new_currency<T>` must be called from `T`'s own module, so each
share type lives in a small package of its own. Register the currency with the
expected metadata, delete the metadata cap (`finalize_and_delete_metadata_cap`)
and pass the treasury cap to the protocol that calls `mint`.

## Framework assumptions

Re-verify on framework changes: `new_currency` can only be called from `T`'s
module and once per type; one-time witnesses have only `drop`;
`make_supply_fixed` accepts any cap of the right type, hence the treasury cap
check.

## Build and test

```sh
sui move build
sui move test
```

Licensed under Apache-2.0.
