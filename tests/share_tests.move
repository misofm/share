#[test_only]
module share::share_tests;

use std::string::String;
use std::unit_test::{assert_eq, destroy};
use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::{CoinRegistry, Currency};
use share::fixture::{Self, Fixture, Generic};
use share::share;

const SUPPLY: u64 = 100_000_000_000_000;

/// Mints with the standard type and name, and the given description, icon
/// and supply.
fun mint_with(
    currency: &mut Currency<Fixture>,
    treasury_cap: TreasuryCap<Fixture>,
    description: String,
    icon_url: String,
    supply: u64,
): Balance<Fixture> {
    share::mint(
        currency, treasury_cap, b"fixture", b"Fixture", 6, b"Fixture".to_string(), b"FIX".to_string(),
        description, icon_url, supply,
    )
}

/// Mints with the standard expectations.
fun mint_standard(currency: &mut Currency<Fixture>, treasury_cap: TreasuryCap<Fixture>): Balance<Fixture> {
    mint_with(currency, treasury_cap, b"".to_string(), b"".to_string(), SUPPLY)
}

fun standard(registry: &mut CoinRegistry, ctx: &mut TxContext): (Currency<Fixture>, TreasuryCap<Fixture>) {
    fixture::locked(registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx)
}

/// Mints `supply` and checks it is minted and fixed.
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
    destroy(shares); destroy(currency); destroy(registry);
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
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(),
        b"About".to_string(), b"https://example.com/i.png".to_string(), ctx,
    );
    let shares = mint_with(&mut currency, treasury_cap, b"About".to_string(), b"https://example.com/i.png".to_string(), SUPPLY);
    assert_eq!(shares.value(), SUPPLY);
    destroy(shares); destroy(currency); destroy(registry);
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
    destroy(share::mint(
        &mut currency, treasury_cap, b"fixture", b"Other", 6, b"Fixture".to_string(), b"FIX".to_string(),
        b"".to_string(), b"".to_string(), SUPPLY,
    ));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_module_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    destroy(share::mint(
        &mut currency, treasury_cap, b"other", b"Fixture", 6, b"Fixture".to_string(), b"FIX".to_string(),
        b"".to_string(), b"".to_string(), SUPPLY,
    ));
    abort
}

#[test]
fun generic_type_never_matches() {
    assert!(!share::is_type_for_testing<Generic<Fixture>>(b"fixture", b"Generic"));
    assert!(share::is_type_for_testing<Fixture>(b"fixture", b"Fixture"));
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
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 9, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidName)]
fun wrong_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Other".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidSymbol)]
fun wrong_symbol_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"OTHER".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidDescription)]
fun wrong_description_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"About".to_string(), b"".to_string(), ctx,
    );
    destroy(mint_standard(&mut currency, treasury_cap));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidIconUrl)]
fun wrong_icon_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"https://example.com/i.png".to_string(), ctx,
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
    destroy(other_currency); destroy(other_registry); destroy(treasury_cap);
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
