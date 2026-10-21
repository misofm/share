// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module share::share_tests;

use std::string::String;
use std::unit_test::{assert_eq, destroy};
use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::{CoinRegistry, Currency};
use share::fixture::{Self, Fixture, Generic};
use share::other_fixture;
use share::share;

const SUPPLY: u64 = 100_000_000_000_000;
const ICON_URL: vector<u8> = b"https://example.com/i.png";

fun mint_with(
    currency: &mut Currency<Fixture>,
    treasury_cap: TreasuryCap<Fixture>,
    description: String,
    icon_url: String,
    supply: u64,
): Balance<Fixture> {
    share::mint(
        currency,
        treasury_cap,
        b"fixture",
        b"Fixture",
        6,
        b"FIX".to_string(),
        b"Fixture".to_string(),
        description,
        icon_url,
        supply,
    )
}

fun mint_standard(
    currency: &mut Currency<Fixture>,
    treasury_cap: TreasuryCap<Fixture>,
): Balance<Fixture> {
    mint_with(currency, treasury_cap, b"".to_string(), b"".to_string(), SUPPLY)
}

fun mint_named(
    currency: &mut Currency<Fixture>,
    treasury_cap: TreasuryCap<Fixture>,
    module_name: vector<u8>,
    datatype_name: vector<u8>,
): Balance<Fixture> {
    share::mint(
        currency,
        treasury_cap,
        module_name,
        datatype_name,
        6,
        b"FIX".to_string(),
        b"Fixture".to_string(),
        b"".to_string(),
        b"".to_string(),
        SUPPLY,
    )
}

fun standard(
    registry: &mut CoinRegistry,
    ctx: &mut TxContext,
): (Currency<Fixture>, TreasuryCap<Fixture>) {
    locked_with(registry, 6, b"FIX", b"Fixture", b"", b"", ctx)
}

fun locked_with(
    registry: &mut CoinRegistry,
    decimals: u8,
    symbol: vector<u8>,
    name: vector<u8>,
    description: vector<u8>,
    icon_url: vector<u8>,
    ctx: &mut TxContext,
): (Currency<Fixture>, TreasuryCap<Fixture>) {
    fixture::locked(
        registry,
        decimals,
        symbol.to_string(),
        name.to_string(),
        description.to_string(),
        icon_url.to_string(),
        ctx,
    )
}

fun mint_and_check(
    mut currency: Currency<Fixture>,
    treasury_cap: TreasuryCap<Fixture>,
    supply: u64,
    registry: CoinRegistry,
) {
    let shares = mint_with(&mut currency, treasury_cap, b"".to_string(), b"".to_string(), supply);
    assert_eq!(shares.value(), supply);
    assert!(currency.is_supply_fixed());
    assert_eq!(currency.total_supply(), option::some(supply));
    destroy(shares);
    destroy(currency);
    destroy(registry);
}

// === mint ===

#[test]
fun mints_and_fixes_supply() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    mint_and_check(currency, treasury_cap, SUPPLY, registry);
}

#[test]
fun supply_of_one_accepted() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    mint_and_check(currency, treasury_cap, 1, registry);
}

#[test]
fun max_supply_accepted() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    let max = 0xFFFF_FFFF_FFFF_FFFF;
    mint_and_check(currency, treasury_cap, max, registry);
}

#[test]
fun expected_description_and_icon_accepted() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = locked_with(
        &mut registry,
        6,
        b"FIX",
        b"Fixture",
        b"About",
        ICON_URL,
        ctx,
    );
    let shares = mint_with(
        &mut currency,
        treasury_cap,
        b"About".to_string(),
        ICON_URL.to_string(),
        SUPPLY,
    );
    assert_eq!(shares.value(), SUPPLY);
    destroy(shares);
    destroy(currency);
    destroy(registry);
}

/// Minting then burning back to zero leaves nothing outstanding, so `mint`
/// still produces exactly the requested supply.
#[test]
fun mint_then_burn_is_benign() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, mut treasury_cap) = standard(&mut registry, ctx);
    let coin = treasury_cap.mint(5, ctx);
    treasury_cap.burn(coin);
    mint_and_check(currency, treasury_cap, SUPPLY, registry);
}

#[test, expected_failure(abort_code = share::EZeroSupply)]
fun zero_supply_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    destroy(mint_with(&mut currency, treasury_cap, b"".to_string(), b"".to_string(), 0));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_datatype_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    destroy(mint_named(&mut currency, treasury_cap, b"fixture", b"Other"));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_module_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    destroy(mint_named(&mut currency, treasury_cap, b"other", b"Fixture"));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun swapped_names_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    destroy(mint_named(&mut currency, treasury_cap, b"Fixture", b"fixture"));
    abort
}

#[test]
fun generic_type_never_matches() {
    assert!(!share::is_type_for_testing<Generic<Fixture>>(b"fixture", b"Generic"));
    assert!(share::is_type_for_testing<Fixture>(b"fixture", b"Fixture"));
}

#[test]
fun injected_separator_never_matches() {
    assert!(!share::is_type_for_testing<Fixture>(b"fixture::Fixture", b""));
    assert!(!share::is_type_for_testing<Fixture>(b"", b"fixture::Fixture"));
    assert!(!share::is_type_for_testing<Fixture>(b"fixture::fixture", b"Fixture"));
    assert!(!share::is_type_for_testing<Fixture>(b"fixture", b"Fixture::Fixture"));
}

#[test]
fun empty_names_never_match() {
    assert!(!share::is_type_for_testing<Fixture>(b"", b"Fixture"));
    assert!(!share::is_type_for_testing<Fixture>(b"fixture", b""));
    assert!(!share::is_type_for_testing<Fixture>(b"", b""));
}

#[test]
fun same_datatype_in_other_module_never_matches() {
    assert!(!share::is_type_for_testing<other_fixture::Fixture>(b"fixture", b"Fixture"));
    assert!(share::is_type_for_testing<other_fixture::Fixture>(b"other_fixture", b"Fixture"));
    assert!(!share::is_type_for_testing<Fixture>(b"other_fixture", b"Fixture"));
}

#[test, expected_failure(abort_code = share::EMetadataNotLocked)]
fun unlocked_metadata_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap, metadata_cap) = fixture::unlocked(&mut registry, ctx);
    destroy(metadata_cap);
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::ERegulatedCurrency)]
fun regulated_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap, deny_cap) = fixture::regulated(&mut registry, ctx);
    destroy(deny_cap);
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidDecimals)]
fun wrong_decimals_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = locked_with(
        &mut registry,
        9,
        b"FIX",
        b"Fixture",
        b"",
        b"",
        ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidName)]
fun wrong_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = locked_with(
        &mut registry,
        6,
        b"FIX",
        b"Other",
        b"",
        b"",
        ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidSymbol)]
fun wrong_symbol_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = locked_with(
        &mut registry,
        6,
        b"OTHER",
        b"Fixture",
        b"",
        b"",
        ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidDescription)]
fun wrong_description_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = locked_with(
        &mut registry,
        6,
        b"FIX",
        b"Fixture",
        b"About",
        b"",
        ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidIconUrl)]
fun wrong_icon_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = locked_with(
        &mut registry,
        6,
        b"FIX",
        b"Fixture",
        b"",
        ICON_URL,
        ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::ETreasuryMismatch)]
fun foreign_treasury_cap_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let mut other_registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    let (other_currency, other_treasury_cap) = standard(&mut other_registry, ctx);
    destroy(other_currency);
    destroy(other_registry);
    destroy(treasury_cap);
    destroy(mint_standard(&mut currency, other_treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::ENotZeroSupply)]
fun minted_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, mut treasury_cap) = standard(&mut registry, ctx);
    destroy(treasury_cap.mint_balance(1));
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}
