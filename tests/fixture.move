// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Test currencies; `coin_registry::new_currency` must be called from the type's own module.
#[test_only]
module share::fixture;

use std::string::String;
use sui::coin::{TreasuryCap, DenyCapV2};
use sui::coin_registry::{Self, Currency, CoinRegistry, MetadataCap};

public struct Fixture has key { id: UID }
public struct Generic<phantom Inner> has key { id: UID }

/// The dummy context's sender is the system address.
public fun registry(ctx: &mut TxContext): CoinRegistry {
    coin_registry::create_coin_data_registry_for_testing(ctx)
}

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
        registry,
        decimals,
        symbol,
        name,
        description,
        icon_url,
        ctx,
    );
    let (mut currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(
        initializer,
        ctx,
    );
    currency.delete_metadata_cap(metadata_cap);
    (currency, treasury_cap)
}

public fun unlocked(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<Fixture>, TreasuryCap<Fixture>, MetadataCap<Fixture>) {
    let (initializer, treasury_cap) = coin_registry::new_currency<Fixture>(
        registry,
        6,
        b"FIX".to_string(),
        b"Fixture".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    (currency, treasury_cap, metadata_cap)
}

public fun regulated(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<Fixture>, TreasuryCap<Fixture>, DenyCapV2<Fixture>) {
    let (mut initializer, treasury_cap) = coin_registry::new_currency<Fixture>(
        registry,
        6,
        b"FIX".to_string(),
        b"Fixture".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let deny_cap = initializer.make_regulated(false, ctx);
    let (mut currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(
        initializer,
        ctx,
    );
    currency.delete_metadata_cap(metadata_cap);
    (currency, treasury_cap, deny_cap)
}
