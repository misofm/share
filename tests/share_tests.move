// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Tests for `share::initialize` — the economic root of the ecosystem: every
/// share supply (100M tokens, 6 decimals, permanently fixed) passes through it,
/// and the `::share::Share` type-suffix gate decides what counts as a share
/// type. Covers the happy path, all four abort gates, and the suffix matrix.
#[test_only]
module share::share_tests;

use share::legacyotw;
use share::myshare;
use share::notshare;
use share::share::{Self, Share, Shares, MyShare, ShareInitializedEvent};
use std::unit_test::{assert_eq, destroy};

/// 100,000,000.000000 tokens at 6 decimals — must match share::SUPPLY.
const SUPPLY: u64 = 100_000_000_000_000;

// Error codes from share.move
const ENotZeroSupply: u64 = 0;
const EMetadataCapNotDeleted: u64 = 1;
const EInvalidShareType: u64 = 2;
const EInvalidDecimals: u64 = 3;
const ERegulatedCurrency: u64 = 4;
const ETreasuryCapMismatch: u64 = 5;

#[test]
fun initialize_mints_fixed_supply() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    let currency_id = sui::object::id_address(&currency);
    let treasury_cap_id = sui::object::id_address(&treasury_cap);
    currency.set_description(&metadata_cap, b"A distinct description".to_string());
    currency.set_icon_url(&metadata_cap, b"https://example.com/icon.png".to_string());
    currency.delete_metadata_cap(metadata_cap);

    let balance = share::initialize<Share>(&mut currency, treasury_cap);

    // The full fixed supply is returned, and the supply is permanently fixed
    // (the treasury cap was consumed by make_supply_fixed).
    assert_eq!(balance.value(), SUPPLY);
    assert!(currency.is_supply_fixed());
    assert_eq!(currency.total_supply(), option::some(SUPPLY));
    let events = sui::event::events_by_type<ShareInitializedEvent<Share>>();
    assert_eq!(events.length(), 1);
    let (
        event_currency_id,
        event_treasury_cap_id,
        event_decimals,
        event_supply,
        event_fixed_supply,
        event_metadata_cap_deleted,
        event_regulated,
    ) = share::initialized_event_fields(&events[0]);
    assert_eq!(event_currency_id, currency_id);
    assert_eq!(event_treasury_cap_id, treasury_cap_id);
    assert_eq!(event_decimals, 6);
    assert_eq!(event_supply, SUPPLY);
    assert!(event_fixed_supply);
    assert!(event_metadata_cap_deleted);
    assert!(!event_regulated);
    assert_eq!(sui::bcs::to_bytes(&events[0]).length(), 76);
    assert_eq!(currency.description().into_bytes(), b"A distinct description");
    assert_eq!(currency.icon_url().into_bytes(), b"https://example.com/icon.png");
    assert_eq!(sui::event::events_by_type<ShareInitializedEvent<Shares>>().length(), 0);

    destroy(balance);
    destroy(currency);
}

// === Abort gates ===

#[test, expected_failure(abort_code = EMetadataCapNotDeleted, location = share)]
fun initialize_rejects_undeleted_metadata_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);

    let balance = share::initialize<Share>(&mut currency, treasury_cap);

    destroy(balance);
    destroy(currency);
    destroy(metadata_cap);
    abort
}

#[test, expected_failure(abort_code = ERegulatedCurrency, location = share)]
fun initialize_rejects_regulated_currency() {
    let ctx = &mut tx_context::dummy();
    // A share currency that is valid in every other respect (6 decimals,
    // metadata cap deleted, zero supply, correct type) but was made regulated:
    // its issuer holds a live DenyCapV2 and could freeze holders forever.
    let (mut currency, treasury_cap, metadata_cap, deny_cap) =
        share::new_regulated_share_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);

    let balance = share::initialize<Share>(&mut currency, treasury_cap);

    destroy(balance);
    destroy(currency);
    destroy(deny_cap);
    abort
}

#[test, expected_failure(abort_code = EInvalidDecimals, location = share)]
fun initialize_rejects_wrong_decimals() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(9, ctx);
    currency.delete_metadata_cap(metadata_cap);

    let balance = share::initialize<Share>(&mut currency, treasury_cap);

    destroy(balance);
    destroy(currency);
    abort
}

#[test, expected_failure(abort_code = ENotZeroSupply, location = share)]
fun initialize_rejects_existing_supply() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, mut treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);

    // Pre-mint a single unit: the supply is no longer zero.
    let coin = sui::coin::mint(&mut treasury_cap, 1, ctx);
    let balance = share::initialize<Share>(&mut currency, treasury_cap);

    destroy(coin);
    destroy(balance);
    destroy(currency);
    abort
}

#[test, expected_failure(abort_code = ETreasuryCapMismatch, location = share)]
fun initialize_rejects_non_canonical_treasury_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);

    // A second, forged cap for the same type: a valid `TreasuryCap<Share>`,
    // but not the cap the registry recorded at currency creation.
    let forged_cap = sui::coin::create_treasury_cap_for_testing<Share>(ctx);
    let balance = share::initialize<Share>(&mut currency, forged_cap);

    destroy(treasury_cap);
    destroy(balance);
    destroy(currency);
    abort
}

/// Proves the framework property the canonical-cap assert relies on to reject
/// legacy-migrated currencies: as migrated, they carry NO recorded treasury
/// cap ID. (`set_treasury_cap_id` can fill it later — but only with a real
/// `TreasuryCap<T>`, and no legacy cap of a share type can ever exist, since
/// every legacy constructor is OTW-gated and `::share::Share` is never a
/// one-time witness.) Also documents the fail-open gap being closed: such a
/// currency's regulated state is `Unknown`, which `is_regulated()` reads as
/// unregulated.
#[test]
#[allow(deprecated_usage)]
fun migrated_legacy_currency_carries_no_recorded_cap() {
    let ctx = &mut tx_context::dummy();
    let mut registry = sui::coin_registry::create_coin_data_registry_for_testing(ctx);
    let (treasury_cap, metadata) = sui::coin::create_currency(
        legacyotw::new_for_testing(),
        6,
        b"LEG",
        b"Legacy",
        b"",
        option::none(),
        ctx,
    );
    let currency = sui::coin_registry::migrate_legacy_metadata_for_testing(
        &mut registry,
        &metadata,
        ctx,
    );

    // The fail-open gap: a migrated currency reads as unregulated...
    assert!(!currency.is_regulated());
    // ...but as migrated carries no recorded treasury cap, so `initialize`'s
    // canonical-cap assert rejects it (the ID could only be filled later via
    // `set_treasury_cap_id` with a real `TreasuryCap<T>` — impossible for
    // share types, whose legacy caps can never exist).
    assert!(currency.treasury_cap_id().is_none());

    destroy(treasury_cap);
    destroy(metadata);
    destroy(currency);
    destroy(registry);
}

// === Type-suffix gate ===

#[test, expected_failure(abort_code = EInvalidShareType, location = share)]
fun initialize_rejects_wrong_module_name() {
    let ctx = &mut tx_context::dummy();
    // `::notshare::Share` — right struct name, wrong module.
    let (mut currency, treasury_cap, metadata_cap) = notshare::new_currency_for_testing(ctx);

    let balance = share::initialize<notshare::Share>(&mut currency, treasury_cap);

    destroy(balance);
    destroy(currency);
    destroy(metadata_cap);
    abort
}

#[test, expected_failure(abort_code = EInvalidShareType, location = share)]
fun initialize_rejects_wrong_struct_name() {
    let ctx = &mut tx_context::dummy();
    // `::share::Shares` — right module, struct name shifts the suffix window
    // by one byte. Catches any "ends with Share" sloppiness in the matcher.
    let (mut currency, treasury_cap, metadata_cap) = share::new_shares_currency_for_testing(ctx);

    let balance = share::initialize<Shares>(&mut currency, treasury_cap);

    destroy(balance);
    destroy(currency);
    destroy(metadata_cap);
    abort
}

// === is_share ===

/// Mint the exact share supply and fix it without going through `initialize`.
fun fix_supply_for_testing<T>(
    currency: &mut sui::coin_registry::Currency<T>,
    mut treasury_cap: sui::coin::TreasuryCap<T>,
    amount: u64,
): sui::balance::Balance<T> {
    let balance = treasury_cap.mint_balance(amount);
    currency.make_supply_fixed(treasury_cap);
    balance
}

#[test]
fun is_share_true_after_initialize() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = share::initialize<Share>(&mut currency, treasury_cap);

    assert!(share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_before_initialize() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);

    // Supply is still controlled by the treasury cap (not fixed).
    assert!(!share::is_share(&currency));

    destroy(treasury_cap);
    destroy(currency);
}

#[test]
fun is_share_true_for_share_shaped_currency_without_initialize() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    // Economically identical to an initialized share, so it qualifies.
    assert!(share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_for_wrong_module_name() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) = notshare::new_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_for_wrong_struct_name() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) = share::new_shares_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_when_metadata_cap_not_deleted() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
    destroy(metadata_cap);
}

#[test]
fun is_share_false_for_regulated_currency() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap, deny_cap) =
        share::new_regulated_share_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
    destroy(deny_cap);
}

#[test]
fun is_share_false_for_wrong_decimals() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(9, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_for_wrong_fixed_supply() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY + 1);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_for_burn_only_supply() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, mut treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = treasury_cap.mint_balance(SUPPLY);
    currency.make_supply_burn_only(treasury_cap);

    // Burn-only supply can shrink below the fixed share supply.
    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

// === Check order ===
// `initialize` runs the four configuration checks (type name, metadata cap,
// regulated, decimals) before the canonical-treasury-cap and zero-supply
// checks. This order is intentional: the configuration checks are shared with
// `is_share`, and a caller presenting the wrong cap learns about a misconfigured
// currency first. These tests pin which code wins when both fail.

#[test, expected_failure(abort_code = ERegulatedCurrency, location = share)]
fun initialize_reports_regulated_before_treasury_cap_mismatch() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap, deny_cap) =
        share::new_regulated_share_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);
    let forged_cap = sui::coin::create_treasury_cap_for_testing<Share>(ctx);

    let balance = share::initialize<Share>(&mut currency, forged_cap);

    destroy(treasury_cap);
    destroy(balance);
    destroy(currency);
    destroy(deny_cap);
    abort
}

#[test, expected_failure(abort_code = EInvalidDecimals, location = share)]
fun initialize_reports_wrong_decimals_before_treasury_cap_mismatch() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(9, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let forged_cap = sui::coin::create_treasury_cap_for_testing<Share>(ctx);

    let balance = share::initialize<Share>(&mut currency, forged_cap);

    destroy(treasury_cap);
    destroy(balance);
    destroy(currency);
    abort
}

// === Type-suffix gate: near misses ===

#[test, expected_failure(abort_code = EInvalidShareType, location = share)]
fun initialize_rejects_module_name_ending_in_share() {
    let ctx = &mut tx_context::dummy();
    // `::myshare::Share` — the suffix starts with `::`, so a module name that
    // merely ends in `share` must not match.
    let (mut currency, treasury_cap, metadata_cap) = myshare::new_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);

    let balance = share::initialize<myshare::Share>(&mut currency, treasury_cap);

    destroy(balance);
    destroy(currency);
    abort
}

#[test, expected_failure(abort_code = EInvalidShareType, location = share)]
fun initialize_rejects_struct_name_ending_in_share() {
    let ctx = &mut tx_context::dummy();
    // `::share::MyShare` — right module, struct name merely ends in `Share`.
    let (mut currency, treasury_cap, metadata_cap) = share::new_myshare_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);

    let balance = share::initialize<MyShare>(&mut currency, treasury_cap);

    destroy(balance);
    destroy(currency);
    abort
}

/// A legacy (`sui::coin`) currency migrated into the registry, presented with
/// its real legacy treasury cap, cap ID filled in and metadata cap deleted: the
/// type name still fails, so neither the `Unknown` regulated state nor the
/// migrated cap ID is ever consulted.
#[test, expected_failure(abort_code = EInvalidShareType, location = share)]
#[allow(deprecated_usage)]
fun initialize_rejects_legacy_migrated_currency() {
    let ctx = &mut tx_context::dummy();
    let mut registry = sui::coin_registry::create_coin_data_registry_for_testing(ctx);
    let (treasury_cap, metadata) = sui::coin::create_currency(
        legacyotw::new_for_testing(),
        6,
        b"LEG",
        b"Legacy",
        b"",
        option::none(),
        ctx,
    );
    let mut currency = sui::coin_registry::migrate_legacy_metadata_for_testing(
        &mut registry,
        &metadata,
        ctx,
    );
    currency.set_treasury_cap_id(&treasury_cap);
    let metadata_cap = currency.claim_metadata_cap(&treasury_cap, ctx);
    currency.delete_metadata_cap(metadata_cap);

    let balance = share::initialize<legacyotw::LEGACYOTW>(&mut currency, treasury_cap);

    destroy(balance);
    destroy(currency);
    destroy(metadata);
    destroy(registry);
    abort
}

/// The name check on types that can never carry a `Currency`, reached through
/// the test-only wrapper: names shorter than the 14-byte suffix (primitives,
/// short vectors) hit the length guard and return `false` instead of
/// underflowing; generic names end in `>` and never match. A generic
/// `share::Share<T>` cannot be declared in this package (the non-generic
/// `Share` occupies the name in this module), so generics are represented by
/// wrappers of `Share`.
#[test]
fun has_share_type_name_false_for_short_and_generic_names() {
    assert!(share::has_share_type_name_for_testing<Share>());
    // Shorter than the suffix: 3, 4, 7, 10 and 12 bytes.
    assert!(!share::has_share_type_name_for_testing<u64>());
    assert!(!share::has_share_type_name_for_testing<bool>());
    assert!(!share::has_share_type_name_for_testing<address>());
    assert!(!share::has_share_type_name_for_testing<vector<u8>>());
    assert!(!share::has_share_type_name_for_testing<vector<u256>>());
    // Long enough, no match.
    assert!(!share::has_share_type_name_for_testing<vector<address>>());
    // Generic names end in `>`.
    assert!(!share::has_share_type_name_for_testing<vector<Share>>());
    assert!(!share::has_share_type_name_for_testing<Option<Share>>());
    assert!(!share::has_share_type_name_for_testing<sui::coin::Coin<Share>>());
    assert!(!share::has_share_type_name_for_testing<ShareInitializedEvent<Share>>());
    // Near misses with a currency-capable type.
    assert!(!share::has_share_type_name_for_testing<Shares>());
    assert!(!share::has_share_type_name_for_testing<MyShare>());
    assert!(!share::has_share_type_name_for_testing<myshare::Share>());
    assert!(!share::has_share_type_name_for_testing<notshare::Share>());
}

// === is_share: near-miss names and edge supplies ===

#[test]
fun is_share_false_for_module_name_ending_in_share() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) = myshare::new_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_for_struct_name_ending_in_share() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) = share::new_myshare_currency_for_testing(ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_for_fixed_supply_of_zero() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);
    // `make_supply_fixed` on a `Currency` accepts an empty supply.
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, 0);

    assert!(currency.is_supply_fixed());
    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_for_fixed_supply_one_below() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY - 1);

    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

/// The prior generation's 10 million whole shares is no longer admissible.
#[test]
fun is_share_false_for_previous_generation_supply() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, 10_000_000_000_000);

    assert!(currency.is_supply_fixed());
    assert!(!share::is_share(&currency));
    destroy(balance);
    destroy(currency);
}

#[test]
fun is_share_false_when_metadata_cap_unclaimed() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap) = share::new_share_currency_unclaimed_for_testing(ctx);
    assert!(!currency.is_metadata_cap_claimed());
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);

    // Unclaimed is not deleted: the cap could still be claimed and used.
    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}

/// Supply fixed while the metadata cap is still live: not a share until the
/// cap is deleted, a share afterwards. `initialize` refuses this order (code
/// `EMetadataCapNotDeleted`), but the end state is identical, so `is_share`
/// accepts it — as documented on the function.
#[test]
fun is_share_true_once_metadata_cap_deleted_after_fixing_supply() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);
    assert!(!share::is_share(&currency));

    currency.set_name(&metadata_cap, b"Renamed".to_string());
    currency.delete_metadata_cap(metadata_cap);

    assert!(share::is_share(&currency));
    destroy(balance);
    destroy(currency);
}

/// A legacy-migrated currency has `regulated: Unknown` (which `is_regulated`
/// reads as unregulated), `supply: Unknown` and `treasury_cap_id: none`.
/// `is_share` must return `false` without aborting on any of those reads —
/// both as migrated and after being shaped like a share in every respect but
/// its type name.
#[test]
#[allow(deprecated_usage)]
fun is_share_false_for_legacy_migrated_currency() {
    let ctx = &mut tx_context::dummy();
    let mut registry = sui::coin_registry::create_coin_data_registry_for_testing(ctx);
    let (treasury_cap, metadata) = sui::coin::create_currency(
        legacyotw::new_for_testing(),
        6,
        b"LEG",
        b"Legacy",
        b"",
        option::none(),
        ctx,
    );
    let mut currency = sui::coin_registry::migrate_legacy_metadata_for_testing(
        &mut registry,
        &metadata,
        ctx,
    );
    assert!(!currency.is_regulated());
    assert!(!share::is_share(&currency));

    currency.set_treasury_cap_id(&treasury_cap);
    let metadata_cap = currency.claim_metadata_cap(&treasury_cap, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = fix_supply_for_testing(&mut currency, treasury_cap, SUPPLY);
    assert!(currency.total_supply() == option::some(SUPPLY));
    assert!(currency.is_metadata_cap_deleted());

    // Only the type name stands between the fail-open `Unknown` state and `true`.
    assert!(!share::is_share(&currency));

    destroy(balance);
    destroy(currency);
    destroy(metadata);
    destroy(registry);
}

/// After `initialize` nothing on the currency can change a checked property:
/// no treasury cap, no metadata cap, no deny cap remain.
#[test]
fun is_share_stays_true_after_initialize() {
    let ctx = &mut tx_context::dummy();
    let (mut currency, treasury_cap, metadata_cap) =
        share::new_share_currency_for_testing(6, ctx);
    currency.delete_metadata_cap(metadata_cap);
    let balance = share::initialize<Share>(&mut currency, treasury_cap);

    assert!(share::is_share(&currency));
    assert!(currency.metadata_cap_id().is_none());
    assert!(currency.deny_cap_id().is_none());
    assert!(currency.treasury_cap_id().is_some());
    assert!(share::is_share(&currency));

    destroy(balance);
    destroy(currency);
}
