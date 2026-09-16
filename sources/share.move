// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Fixed-supply currency issuance for representing equity-like ownership stakes.
///
/// ### Usage:
///
/// 1. Create a package with a `share` module containing a `Share` type
/// 2. Create a currency with `sui::coin_registry::new_currency`
/// 3. Delete the metadata cap via `finalize_and_delete_metadata_cap`
/// 4. Call `share::share::initialize` with the currency and its canonical
///    treasury cap (the one created together with the currency)
/// 5. Distribute the returned balance to shareholders
module share::share;

use std::type_name::with_defining_ids;
use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::Currency;
use sui::event::emit;
use sui::object;

// === Constants ===

/// Fixed supply of 100,000,000.000000 tokens (6 decimal places).
const SUPPLY: u64 = 100_000_000_000_000;
/// Required number of decimal places.
const DECIMALS: u8 = 6;

/// Suffix that all valid share type names must end with.
const SHARE_TYPE: vector<u8> = b"::share::Share";

// === Errors ===

/// Currency already has non-zero supply.
const ENotZeroSupply: u64 = 0;
/// Currency's MetadataCap has not been deleted.
const EMetadataCapNotDeleted: u64 = 1;
/// Share type is invalid (must end with `::share::Share`).
const EInvalidShareType: u64 = 2;
/// Currency does not have 6 decimals.
const EInvalidDecimals: u64 = 3;
/// Currency is regulated (carries a `DenyCapV2`). Shares must be freeze-proof
/// equity, so a regulated share currency — whose issuer retains deny-list and
/// global-pause authority over holders forever — is rejected.
const ERegulatedCurrency: u64 = 4;
/// Treasury cap is not the canonical cap recorded on the currency at creation.
const ETreasuryCapMismatch: u64 = 5;

// === Events ===

public struct ShareInitializedEvent<phantom ShareType> has copy, drop {
    currency_id: address,
    treasury_cap_id: address,
    decimals: u8,
    supply: u64,
    fixed_supply: bool,
    metadata_cap_deleted: bool,
    regulated: bool,
}

// === Public Functions ===

/// Initializes a fixed-supply share token with 100,000,000.000000 supply.
/// Validates the currency configuration, mints the fixed supply,
/// and makes the supply immutable. Returns the full token balance.
///
/// The type parameter must be a `Share` type defined in a `share` module
/// (i.e. `<address>::share::Share`).
public fun initialize<Share>(
    currency: &mut Currency<Share>,
    mut treasury_cap: TreasuryCap<Share>,
): Balance<Share> {
    // Assert the share type, metadata lock, regulation and decimals, aborting
    // with the specific error code of the first failing check.
    share_config_error(currency).do!(|code| abort code);
    // Assert the presented treasury cap is the canonical cap recorded on the
    // currency at creation. `make_supply_fixed` fixes the supply with whatever
    // cap it is handed without checking, so bind it here: the supply is fixed
    // with the registry's own cap. This also rejects legacy-migrated
    // currencies as created (`treasury_cap_id: none`).
    assert!(
        currency.treasury_cap_id() == option::some(object::id(&treasury_cap)),
        ETreasuryCapMismatch,
    );
    // Assert the currency has no existing supply. Together with minting exactly
    // `SUPPLY` and fixing it below, this makes the result satisfy `is_share` by
    // construction, so no post-check is needed.
    assert!(treasury_cap.supply().value() == 0, ENotZeroSupply);

    // Capture identifiers before consuming the treasury cap below. These are
    // read-only observations used only to make the initialization event
    // self-contained for indexers.
    let currency_id = object::id_address(currency);
    let treasury_cap_id = object::id_address(&treasury_cap);

    // Mint the share balance.
    let balance = treasury_cap.mint_balance(SUPPLY);

    // Make the supply fixed.
    currency.make_supply_fixed(treasury_cap);

    emit(ShareInitializedEvent<Share> {
        currency_id,
        treasury_cap_id,
        decimals: DECIMALS,
        supply: SUPPLY,
        fixed_supply: currency.is_supply_fixed(),
        metadata_cap_deleted: currency.is_metadata_cap_deleted(),
        regulated: currency.is_regulated(),
    });

    balance
}

// === Public View Functions ===

/// Returns whether `currency` is a valid share: its type is
/// `<address>::share::Share`, its metadata cap is deleted, it is not
/// regulated, it has 6 decimals, and its supply is permanently fixed at
/// 100,000,000.000000 tokens. This is the complete property set `initialize`
/// establishes, read back from the currency, so downstream packages can gate
/// on it. It returns `true` for any currency with that shape, including one
/// that reached it without `initialize`; such a currency is economically
/// identical (only the `ShareInitializedEvent` is missing). The canonical
/// treasury-cap check `initialize` performs needs no counterpart here: a fixed
/// supply means the treasury cap was consumed, and a fixed supply cannot burn.
public fun is_share<Share>(currency: &Currency<Share>): bool {
    // Supply first: two cheap reads that reject most non-share currencies.
    currency.is_supply_fixed() &&
        currency.total_supply() == option::some(SUPPLY) &&
        share_config_error(currency).is_none()
}

// === Private Functions ===

/// Returns the error code of the first failing configuration check shared by
/// `initialize` and `is_share`, or `none` if every check passes. Keeping every
/// check here means the two functions cannot drift apart, and each call runs
/// each check once.
fun share_config_error<Share>(currency: &Currency<Share>): Option<u64> {
    // The type must be `<address>::share::Share`.
    if (!has_share_type_name<Share>()) return option::some(EInvalidShareType);
    // The MetadataCap must be deleted, so currency metadata can never change.
    if (!currency.is_metadata_cap_deleted()) return option::some(EMetadataCapNotDeleted);
    // The currency must not be regulated. A regulated currency has a live
    // `DenyCapV2` whose holder can deny-list or globally pause holders forever;
    // shares are meant to be freeze-proof fixed-supply equity. The
    // `RegulatedState::Unknown` fail-open case of `is_regulated()` only arises
    // for legacy-migrated currencies, and none can exist for a share type:
    // every legacy constructor is OTW-gated, and `::share::Share` is never a
    // one-time witness.
    if (currency.is_regulated()) return option::some(ERegulatedCurrency);
    // The currency must have 6 decimals.
    if (currency.decimals() != DECIMALS) return option::some(EInvalidDecimals);
    option::none()
}

/// Whether the type name ends with `::share::Share`. The suffix includes the
/// leading `::`, so the module must be exactly `share`, and it ends the string,
/// so the struct must be exactly `Share` with no type parameters.
fun has_share_type_name<Share>(): bool {
    let type_name = with_defining_ids<Share>();
    // Borrow the name bytes in place rather than serializing a copy.
    let bytes = type_name.as_string().as_bytes();
    let suffix = SHARE_TYPE;
    let bytes_len = bytes.length();
    let suffix_len = suffix.length();
    // Primitive type names (e.g. `u64`) are shorter than the suffix.
    if (bytes_len < suffix_len) return false;
    let offset = bytes_len - suffix_len;
    let mut i = 0;
    while (i < suffix_len) {
        if (bytes[offset + i] != suffix[i]) return false;
        i = i + 1;
    };
    true
}

// === Test Only ===

#[test_only]
use sui::coin_registry::{Self, MetadataCap};

/// A qualifying share type: `<addr>::share::Share`. Lives in this module
/// because the suffix gate requires module `share`, struct `Share`, and
/// `coin_registry::new_currency<T>` must be called from T's defining module.
#[test_only]
public struct Share has key { id: UID }

/// A NON-qualifying type in the right module with the wrong struct name —
/// `::share::Shares` shifts the suffix window one byte and must be rejected.
#[test_only]
public struct Shares has key { id: UID }

/// A NON-qualifying type in the right module whose struct name merely ends in
/// `Share` — `::share::MyShare` — must be rejected (the suffix starts with
/// `::`, so the struct must be exactly `Share`).
#[test_only]
public struct MyShare has key { id: UID }

/// Test-only window onto the private name check, so the length guard and
/// generic names can be exercised for types that can never have a `Currency`.
#[test_only]
public fun has_share_type_name_for_testing<T>(): bool { has_share_type_name<T>() }

/// Registered `Currency<Share>` + treasury + metadata cap with the given
/// decimals (callers pass 6 for valid setups, anything else to test the
/// decimals gate). Metadata cap deletion is left to the caller.
#[test_only]
public fun new_share_currency_for_testing(
    decimals: u8,
    ctx: &mut TxContext,
): (Currency<Share>, TreasuryCap<Share>, MetadataCap<Share>) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (initializer, treasury_cap) = coin_registry::new_currency<Share>(
        &mut registry,
        decimals,
        b"SHR".to_string(),
        b"Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    std::unit_test::destroy(registry);
    (currency, treasury_cap, metadata_cap)
}

#[test_only]
public fun new_shares_currency_for_testing(
    ctx: &mut TxContext,
): (Currency<Shares>, TreasuryCap<Shares>, MetadataCap<Shares>) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (initializer, treasury_cap) = coin_registry::new_currency<Shares>(
        &mut registry,
        6,
        b"SHRS".to_string(),
        b"Shares".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    std::unit_test::destroy(registry);
    (currency, treasury_cap, metadata_cap)
}

#[test_only]
public fun new_myshare_currency_for_testing(
    ctx: &mut TxContext,
): (Currency<MyShare>, TreasuryCap<MyShare>, MetadataCap<MyShare>) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (initializer, treasury_cap) = coin_registry::new_currency<MyShare>(
        &mut registry,
        6,
        b"MYSHR".to_string(),
        b"MyShare".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    std::unit_test::destroy(registry);
    (currency, treasury_cap, metadata_cap)
}

/// A `Currency<Share>` (6 decimals) whose `MetadataCap` was never claimed —
/// `metadata_cap_id` is `Unclaimed`, which is not `Deleted`.
#[test_only]
public fun new_share_currency_unclaimed_for_testing(
    ctx: &mut TxContext,
): (Currency<Share>, TreasuryCap<Share>) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (initializer, treasury_cap) = coin_registry::new_currency<Share>(
        &mut registry,
        DECIMALS,
        b"SHR".to_string(),
        b"Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let currency = coin_registry::unwrap_for_testing(initializer);
    std::unit_test::destroy(registry);
    (currency, treasury_cap)
}

/// A valid-in-every-other-way `Currency<Share>` that was made **regulated**
/// (carries a live `DenyCapV2<Share>`) before finalizing. Used to prove that
/// `initialize` rejects regulated share currencies — the deny cap is returned
/// so the test can dispose of it.
#[test_only]
public fun new_regulated_share_currency_for_testing(
    ctx: &mut TxContext,
): (
    Currency<Share>,
    TreasuryCap<Share>,
    MetadataCap<Share>,
    sui::coin::DenyCapV2<Share>,
) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (mut initializer, treasury_cap) = coin_registry::new_currency<Share>(
        &mut registry,
        DECIMALS,
        b"SHR".to_string(),
        b"Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    let deny_cap = coin_registry::make_regulated(&mut initializer, false, ctx);
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing(initializer, ctx);
    std::unit_test::destroy(registry);
    (currency, treasury_cap, metadata_cap, deny_cap)
}

#[test_only]
public fun initialized_event_fields<ShareType>(
    event: &ShareInitializedEvent<ShareType>,
): (
    address,
    address,
    u8,
    u64,
    bool,
    bool,
    bool,
) {
    (
        event.currency_id,
        event.treasury_cap_id,
        event.decimals,
        event.supply,
        event.fixed_supply,
        event.metadata_cap_deleted,
        event.regulated,
    )
}
