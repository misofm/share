/// Test currencies. `coin_registry::new_currency` must be called from the
/// type's own module; each test builds its own registry.
#[test_only]
module share::fixture;

use std::string::String;
use sui::coin::{TreasuryCap, DenyCapV2};
use sui::coin_registry::{Self, Currency, CoinRegistry, MetadataCap};

/// The expected type in most tests: `share::fixture::Fixture`.
public struct Fixture has key { id: UID }
/// A generic type, for the exact-name check.
public struct Generic<phantom X> has key { id: UID }

/// A registry for one test; the dummy context's sender is the system address.
public fun registry(ctx: &mut TxContext): CoinRegistry {
    coin_registry::create_coin_data_registry_for_testing(ctx)
}

/// `Fixture` with the given metadata and its metadata cap deleted.
public fun locked(
    registry: &mut CoinRegistry,
    decimals: u8,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
    ctx: &mut TxContext,
): (Currency<Fixture>, TreasuryCap<Fixture>) {
    let (initializer, treasury_cap) = coin_registry::new_currency<Fixture>(
        registry, decimals, symbol, name, description, icon_url, ctx,
    );
    let (mut currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    currency.delete_metadata_cap(metadata_cap);
    (currency, treasury_cap)
}

/// `Fixture` with the standard test metadata, metadata cap kept.
public fun unlocked(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<Fixture>, TreasuryCap<Fixture>, MetadataCap<Fixture>) {
    let (initializer, treasury_cap) = coin_registry::new_currency<Fixture>(
        registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    (currency, treasury_cap, metadata_cap)
}

/// Regulated `Fixture` with the standard test metadata.
public fun regulated(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<Fixture>, TreasuryCap<Fixture>, DenyCapV2<Fixture>) {
    let (mut initializer, treasury_cap) = coin_registry::new_currency<Fixture>(
        registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    let deny_cap = initializer.make_regulated(false, ctx);
    let (mut currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    currency.delete_metadata_cap(metadata_cap);
    (currency, treasury_cap, deny_cap)
}
