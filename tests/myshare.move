// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A type whose MODULE name merely ends in `share` (`::myshare::Share`) for
/// testing the share type-suffix gate: the suffix starts with `::`, so the
/// module must be exactly `share`. Has its own currency helper because
/// `coin_registry::new_currency<T>` must be called from T's defining module.
#[test_only]
module share::myshare;

use sui::coin::TreasuryCap;
use sui::coin_registry::{Self, Currency, MetadataCap};

public struct Share has key { id: UID }

public fun new_currency_for_testing(
    ctx: &mut TxContext,
): (Currency<Share>, TreasuryCap<Share>, MetadataCap<Share>) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (initializer, treasury_cap) = coin_registry::new_currency<Share>(
        &mut registry,
        6,
        b"MSHR".to_string(),
        b"My Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    std::unit_test::destroy(registry);
    (currency, treasury_cap, metadata_cap)
}
