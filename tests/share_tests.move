#[test_only]
module share::share_tests;

use std::string::String;
use std::unit_test::{assert_eq, destroy};
use sui::coin::TreasuryCap;
use sui::coin_registry::{CoinRegistry, Currency};
use share::fixture::{Self, Fixture, Generic};
use share::share::{Self, Spec};

const SUPPLY: u64 = 100_000_000_000_000;

fun spec_with(description: String, icon_url: String, supply: u64): Spec {
    share::spec(b"fixture", b"Fixture", 6, b"Fixture".to_string(), b"FIX".to_string(), description, icon_url, supply)
}

fun standard_spec(): Spec { spec_with(b"".to_string(), b"".to_string(), SUPPLY) }

fun standard(registry: &mut CoinRegistry, ctx: &mut TxContext): (Currency<Fixture>, TreasuryCap<Fixture>) {
    fixture::locked(registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx)
}

/// Mints against `spec` and checks the result is a share of it.
fun mint_and_check(
    mut currency: Currency<Fixture>,
    treasury_cap: TreasuryCap<Fixture>,
    spec: Spec,
    supply: u64,
    registry: CoinRegistry,
) {
    assert!(!share::is_share(&currency, &spec));
    let shares = share::mint(&mut currency, treasury_cap, &spec);
    assert_eq!(shares.value(), supply);
    assert!(currency.is_supply_fixed());
    assert!(share::is_share(&currency, &spec));
    destroy(shares); destroy(currency); destroy(registry);
}

// === mint ===

#[test]
fun mints_and_fixes_supply() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    mint_and_check(currency, treasury_cap, standard_spec(), SUPPLY, registry);
}

#[test]
fun max_supply_accepted() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    let max = 0xFFFF_FFFF_FFFF_FFFF;
    mint_and_check(currency, treasury_cap, spec_with(b"".to_string(), b"".to_string(), max), max, registry);
}

#[test]
fun expected_description_and_icon_accepted() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(),
        b"About".to_string(), b"https://example.com/i.png".to_string(), ctx,
    );
    let spec = spec_with(b"About".to_string(), b"https://example.com/i.png".to_string(), SUPPLY);
    let shares = share::mint(&mut currency, treasury_cap, &spec);
    assert!(share::is_share(&currency, &spec));
    destroy(shares); destroy(currency); destroy(registry);
}

/// Minting then burning back to zero leaves nothing outstanding, so `mint`
/// still produces exactly the spec's supply.
#[test]
fun mint_then_burn_is_benign() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, mut treasury_cap) = standard(&mut registry, ctx);
    let coin = treasury_cap.mint(5, ctx);
    treasury_cap.burn(coin);
    mint_and_check(currency, treasury_cap, standard_spec(), SUPPLY, registry);
}

#[test, expected_failure(abort_code = share::EZeroSupply)]
fun zero_supply_spec_rejected() {
    spec_with(b"".to_string(), b"".to_string(), 0);
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_datatype_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    let spec = share::spec(b"fixture", b"Other", 6, b"Fixture".to_string(), b"FIX".to_string(), b"".to_string(), b"".to_string(), SUPPLY);
    destroy(share::mint(&mut currency, treasury_cap, &spec));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidType)]
fun wrong_module_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    let spec = share::spec(b"other", b"Fixture", 6, b"Fixture".to_string(), b"FIX".to_string(), b"".to_string(), b"".to_string(), SUPPLY);
    destroy(share::mint(&mut currency, treasury_cap, &spec));
    abort
}

#[test]
fun generic_type_never_matches() {
    let spec = share::spec(b"fixture", b"Generic", 6, b"Fixture".to_string(), b"FIX".to_string(), b"".to_string(), b"".to_string(), SUPPLY);
    assert!(!share::is_type_for_testing<Generic<Fixture>>(&spec));
    assert!(share::is_type_for_testing<Fixture>(&standard_spec()));
}

#[test, expected_failure(abort_code = share::EMetadataNotLocked)]
fun unlocked_metadata_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap, metadata_cap) = fixture::unlocked(&mut registry, ctx);
    destroy(metadata_cap);
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
    abort
}

#[test, expected_failure(abort_code = share::ERegulatedCurrency)]
fun regulated_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap, deny_cap) = fixture::regulated(&mut registry, ctx);
    destroy(deny_cap);
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidDecimals)]
fun wrong_decimals_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 9, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidName)]
fun wrong_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Other".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidSymbol)]
fun wrong_symbol_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"OTHER".to_string(), b"Fixture".to_string(), b"".to_string(), b"".to_string(), ctx,
    );
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidDescription)]
fun wrong_description_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"About".to_string(), b"".to_string(), ctx,
    );
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
    abort
}

#[test, expected_failure(abort_code = share::EInvalidIconUrl)]
fun wrong_icon_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = fixture::locked(
        &mut registry, 6, b"FIX".to_string(), b"Fixture".to_string(), b"".to_string(), b"https://example.com/i.png".to_string(), ctx,
    );
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
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
    destroy(share::mint(&mut currency, other_treasury_cap, &standard_spec()));
    abort
}

#[test, expected_failure(abort_code = share::ENotZeroSupply)]
fun minted_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, mut treasury_cap) = standard(&mut registry, ctx);
    destroy(treasury_cap.mint_balance(1));
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
    abort
}

// === is_share ===

/// A minted share isn't a share of a spec with a different supply or metadata.
#[test]
fun is_share_requires_the_exact_spec() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (mut currency, treasury_cap) = standard(&mut registry, ctx);
    destroy(share::mint(&mut currency, treasury_cap, &standard_spec()));
    assert!(share::is_share(&currency, &standard_spec()));
    assert!(!share::is_share(&currency, &spec_with(b"".to_string(), b"".to_string(), SUPPLY + 1)));
    assert!(!share::is_share(&currency, &spec_with(b"About".to_string(), b"".to_string(), SUPPLY)));
    destroy(currency); destroy(registry);
}

/// A conforming currency whose supply was never fixed isn't a share.
#[test]
fun is_share_requires_fixed_supply() {
    let ctx = &mut tx_context::dummy();
    let mut registry = fixture::registry(ctx);
    let (currency, treasury_cap) = standard(&mut registry, ctx);
    assert!(!share::is_share(&currency, &standard_spec()));
    destroy(currency); destroy(treasury_cap); destroy(registry);
}
