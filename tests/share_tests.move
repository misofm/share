#[test_only]
module share::share_tests;

use std::string::String;
use std::unit_test::{assert_eq, destroy};
use sui::coin::TreasuryCap;
use sui::coin_registry::{CoinRegistry, Currency};

use share::fixture::{Self, Fixture};
use share::share;

const SUPPLY: u64 = 100_000_000_000_000;

fun standard(registry: &mut CoinRegistry, ctx: &mut TxContext): (Currency<Fixture>, TreasuryCap<Fixture>) {
    fixture::locked(registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx)
}

/// Mints `Fixture` against the standard expectations with the given overrides.
fun mint_with<T>(
    mut currency: Currency<T>,
    treasury_cap: TreasuryCap<T>,
    module_name: vector<u8>,
    datatype_name: vector<u8>,
    description: String,
    icon_url: String,
    supply: u64,
    registry: CoinRegistry,
) {
    let shares = share::mint(
        &mut currency, treasury_cap, module_name, datatype_name, 6,
        b"Fixture".to_string(), b"FIX".to_string(), description, icon_url, supply,
    );
    assert_eq!(shares.value(), supply);
    assert!(currency.is_supply_fixed());
    assert_eq!(currency.total_supply(), option::some(supply));
    destroy(shares); destroy(currency); destroy(registry);
}

fun mint_standard<T>(currency: Currency<T>, treasury_cap: TreasuryCap<T>, registry: CoinRegistry) {
    mint_with(currency, treasury_cap, b"fixture", b"Fixture", b"".to_string(), b"".to_string(), SUPPLY, registry)
}

#[test]
fun mints_and_fixes_supply() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    mint_standard(currency, treasury_cap, registry);
}

#[test]
fun expected_description_and_icon_accepted() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(),
        b"About".to_string(), b"https://example.com/i.png".to_string(), ctx,
    );
    mint_with(
        currency, treasury_cap, b"fixture", b"Fixture",
        b"About".to_string(), b"https://example.com/i.png".to_string(), SUPPLY, registry,
    );
}

#[test]
fun max_supply_accepted() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    mint_with(currency, treasury_cap, b"fixture", b"Fixture", b"".to_string(), b"".to_string(), 0xFFFF_FFFF_FFFF_FFFF, registry);
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_datatype_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    mint_with(currency, treasury_cap, b"fixture", b"Other", b"".to_string(), b"".to_string(), SUPPLY, registry);
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_module_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    mint_with(currency, treasury_cap, b"other", b"Fixture", b"".to_string(), b"".to_string(), SUPPLY, registry);
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun one_time_witness_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::witness_named(&mut registry, ctx);
    mint_with(currency, treasury_cap, b"fixture", b"FIXTURE", b"".to_string(), b"".to_string(), SUPPLY, registry);
}

#[test, expected_failure(abort_code = share::ETreasuryMismatch)]
fun foreign_treasury_cap_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let mut other_registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    let (other_currency, other_treasury_cap) = standard(&mut other_registry, ctx);
    destroy(other_currency); destroy(other_registry); destroy(treasury_cap);
    mint_standard(currency, other_treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::ENotZeroSupply)]
fun minted_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, mut treasury_cap) = standard(&mut registry, ctx);
    destroy(treasury_cap.mint_balance(1));
    mint_standard(currency, treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::ERegulatedCurrency)]
fun regulated_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap, deny_cap) = fixture::regulated(&mut registry, ctx);
    destroy(deny_cap);
    mint_standard(currency, treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::EMetadataNotLocked)]
fun unlocked_metadata_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap, metadata_cap) = fixture::unlocked(&mut registry, ctx);
    destroy(metadata_cap);
    mint_standard(currency, treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::EInvalidDecimals)]
fun wrong_decimals_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::locked(
        &mut registry, 9, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    mint_standard(currency, treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::EInvalidName)]
fun wrong_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Other".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    mint_standard(currency, treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::EInvalidSymbol)]
fun wrong_symbol_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"OTHER".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    mint_standard(currency, treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::EInvalidDescription)]
fun wrong_description_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"About".to_string(), b"".to_string(), ctx,
    );
    mint_standard(currency, treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::EInvalidIconUrl)]
fun wrong_icon_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"https://example.com/i.png".to_string(), ctx,
    );
    mint_standard(currency, treasury_cap, registry);
}

#[test, expected_failure(abort_code = share::EZeroSupply)]
fun zero_supply_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    mint_with(currency, treasury_cap, b"fixture", b"Fixture", b"".to_string(), b"".to_string(), 0, registry);
}
