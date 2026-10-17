# unconfirmedlabs/share

Canonical fixed-supply share coins for Sui Move.

A share coin is an ordinary `Coin<T>` whose type, metadata and supply are pinned
by the protocol that uses it. `share::mint` checks a freshly registered currency
against the caller's expectations, mints the whole supply and fixes it. Coins
minted against the same expectations are identical apart from their package
address. MusicOS uses it for composition and recording shares.

## Mint

```move
let shares: Balance<T> = share::mint(
    &mut currency,
    treasury_cap,
    b"composition_share",          // expected module
    b"CompositionShare",           // expected datatype
    6,                             // decimals
    b"Composition Share".to_string(),
    b"CSHARE".to_string(),
    b"".to_string(),               // description
    b"".to_string(),               // icon URL
    100_000_000_000_000,           // supply in base units
);
```

`mint` aborts unless:

- `T` is exactly `<package>::<module>::<datatype>`, with no type arguments, and
  the datatype isn't the module's one-time witness name. Legacy coin constructors
  need a one-time witness, so the currency came from `coin_registry` and its
  regulation status is known.
- The treasury cap is the currency's, with nothing minted yet.
- The currency is unregulated and its metadata cap is deleted.
- Decimals, name, symbol, description and icon URL equal the expected values.
- Supply is positive.

It then mints `supply` and consumes the treasury cap with
`coin_registry::make_supply_fixed`, so the currency can be minted only once and
its supply never changes.

## Creating a conforming currency

`coin_registry::new_currency<T>` must be called from `T`'s own module, so each
share type lives in a small package of its own. Register the currency with the
expected metadata, delete the metadata cap (`finalize_and_delete_metadata_cap`)
and pass the treasury cap to the protocol that calls `mint`.

## Build and test

```sh
sui move build
sui move test
```

Licensed under Apache-2.0.
