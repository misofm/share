# unconfirmedlabs/share

Fixed-supply ownership scoped to a parent object, for Sui Move. Native ownership
requires no currency, per-issuance token package or global registry.

The package contains only `share::share`, so MusicOS and eventOS can depend on
it alone.

## Create an issuance

```move
// 100 million shares displayed with 6 decimal places.
let (issuance, shares) = share::new(&mut scheme.id, 100_000_000_000_000, 6);
// Create pools or register stakes here, then:
issuance.share();
```

The parent is the object that gives the shares their meaning, usually a
scheme or license object owned by the integrating protocol. The caller supplies
its actual `&mut UID`, and the parent's defining module must authorize that
access. The `Issuance` is a derived object of the parent under `IssuanceKey()`,
so each parent has at most one issuance, and the permanent derived claim
prevents repeat creation. There is no global registry and no shared object on
the creation path.

`new` returns the issuance unshared, so the caller can use it (for example to
create a royalty pool) before sharing it. `Issuance` has only `key`, so the
creating transaction must call `share`.

`Issuance` records `parent_id` (so clients can go from a share back to its
parent without an indexer), immutable `supply` and immutable `decimals`.
`Share` contains an issuance ID and a `u64` quantity, with **only `store`**: no
UID, duplication or implicit destruction. Applications hold shares inside their
own wrappers or royalty positions. The issuance contains no token type or
conversion configuration.

Prefer a dedicated scheme object as the parent over a widely used object such
as a musicos `Composition` or `Recording`. A parent has one issuance slot, so
using a shared identity object as the parent would give its first user that
slot permanently.

## API

| Function | Result |
|---|---|
| `new(&mut UID, supply: u64, decimals: u8)` | Unshared `Issuance` and the full initial `Share` |
| `share(Issuance)` | Shares the issuance; required in the creating transaction |
| `derive_address(parent_id)` | Predicted issuance address, not proof of existence |
| `parent_id(&Issuance)` | Parent `ID` |
| `issuance_id(&Share)` | Ownership issuance `ID` |
| `value(&Share)` | Units held |
| `supply(&Issuance)` | Fixed total base units for this issuance |
| `decimals(&Issuance)` | Display precision for this issuance |
| `zero(&Issuance)` | Zero units for that issuance |
| `split(&mut Share, amount)` | Removes and returns that amount |
| `join(&mut Share, Share)` | Consumes another value; returns new total |
| `join_vec(&mut Share, vector<Share>)` | Consumes all supplied values |
| `withdraw_all(&mut Share)` | Returns everything, leaving zero |
| `destroy_zero(Share)` | Consumes only a zero value |

Supply is a positive `u64`: `1` through `18_446_744_073_709_551_615`, inclusive.
Decimals accept the full `u8` range (`0` through `255`), matching Sui currency
creation. These are display metadata; initialization never computes a power of
ten or multiplies supply by a decimal scale. Supply is already in base units.
The native ownership fraction is `value / issuance.supply()`; decimals do not
affect that ratio. There is no package-wide supply or decimal default.

Operations follow Sui Balance conventions. Joining checks issuance identity at
runtime, including zero values. Splitting zero or the full balance is supported.
Empty vector joins are no-ops. Checked arithmetic and transaction atomicity
protect failed operations. Splits and joins touch no shared objects.

`IssuanceCreatedEvent` records the issuance and parent identities plus supply
(`u64`) and decimals (`u8`). There is no holder enumeration requirement.

## Conservation and integration

Native ownership units are created only by `new`. There is no
public or package-private reconstruction/mint interface, nonzero burn or issuer
clawback in this package. Every native unit, including units held by adapters,
remains part of the fixed supply. Integrations can use the public API without
being approved by the parent or this package.

Royalty positions hold native shares alongside reward debt and registration
state. Payout funds continue to use `Balance<Currency>`. Existing coin-based
royalty pools require adaptation; see [INTEGRATION.md](INTEGRATION.md).

## Build and test

```sh
sui move build
sui move test
```

Licensed under Apache-2.0.
