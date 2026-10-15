# Integrating native ownership

## Royalty pools

A native royalty position holds `share::share::Share` alongside its registrations
and reward debt. Payout funds continue to use `Balance<Currency>`.

- Read supply and decimals from the issuance; never assume a global denomination.
- Audit reward arithmetic for the full `u64` supply range, including supplies
  larger than any fixed reward precision constant.
- Bind each pool to a genuine `Issuance` and retain its ID.
- Check a position's issuance ID before accepting its shares.
- Include issuance identity and payout currency in the pool's derivation.
- Return native shares when a position is fully unregistered.
- Preserve accumulator math, reward debt, carry accounting and custody controls.

Keep shares inside a position while it is registered. Before splitting or
recombining ownership, settle and unregister the position, or implement explicit
operations that preserve reward accounting. Exposing mutable shares in a
registered position could change its weight without updating the pool.

## Parent protocols

A protocol creates shares with `share::new` on a parent object it controls,
usually a scheme or license object dedicated to what the shares mean. Pass
explicit supply and decimals, then allocate the returned units. No per-issuance
share type parameter is needed.

`new` returns the `Issuance` unshared. Create any pools and register any stakes
that must exist before revenue can arrive, then call `share` in the same
transaction.

Verify that an issuance belongs to a parent by derivation:
`share::derive_address(parent_id) == object::id_address(issuance)`.
`parent_id(&Issuance)` is for clients navigating upward, and matches the
derivation.

Administrative capabilities must bind to and validate the relevant parent ID.
Shares for different issuances have the same Move type, so authorization and
pool membership checks must explicitly compare identities.

Native shares cannot use the framework's `Balance<T>` funds accumulator. To give
one party ownership in another's shares, use an appropriate owned wrapper and
receiving path, or a protected container. Do not expose raw mutable UID access
merely to route ownership. Routed positions must verify the issuance and
preserve their intended payout destination.
