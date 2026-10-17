// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Canonical fixed-supply share coins.
///
/// A `Spec` states what a protocol's share coin must be: its exact type,
/// metadata and supply. `mint` checks a freshly registered currency against
/// the spec, mints the whole supply and fixes it by consuming the treasury
/// cap, so a currency can be minted only once. `is_share` reads the same
/// properties back, so downstream packages can gate on any minted share.
module share::share;

// === Imports ===

use std::ascii;
use std::string::String;
use std::type_name;
use sui::balance::Balance;
use sui::coin::TreasuryCap;
use sui::coin_registry::Currency;

// === Errors ===

const EInvalidType: u64 = 0;
const EMetadataNotLocked: u64 = 1;
const ERegulatedCurrency: u64 = 2;
const EInvalidDecimals: u64 = 3;
const EInvalidName: u64 = 4;
const EInvalidSymbol: u64 = 5;
const EInvalidDescription: u64 = 6;
const EInvalidIconUrl: u64 = 7;
const ETreasuryMismatch: u64 = 8;
const ENotZeroSupply: u64 = 9;
const EZeroSupply: u64 = 10;

// === Structs ===

/// The required type and metadata of a share coin, and its fixed supply in
/// base units.
public struct Spec has copy, drop, store {
    module_name: vector<u8>,
    datatype_name: vector<u8>,
    decimals: u8,
    name: String,
    symbol: String,
    description: String,
    icon_url: String,
    supply: u64,
}

// === Public Functions ===

/// A spec for `<package>::<module_name>::<datatype_name>` coins. Aborts with
/// `EZeroSupply` unless `supply` is positive.
public fun spec(
    module_name: vector<u8>,
    datatype_name: vector<u8>,
    decimals: u8,
    name: String,
    symbol: String,
    description: String,
    icon_url: String,
    supply: u64,
): Spec {
    assert!(supply > 0, EZeroSupply);
    Spec { module_name, datatype_name, decimals, name, symbol, description, icon_url, supply }
}

/// Mints the spec's full supply of `T` and fixes it. Aborts with the first
/// failing `is_share` property, `ETreasuryMismatch` unless the cap is the
/// currency's own, or `ENotZeroSupply` if anything is already minted.
public fun mint<T: key>(
    currency: &mut Currency<T>,
    mut treasury_cap: TreasuryCap<T>,
    spec: &Spec,
): Balance<T> {
    let error = spec_error(currency, spec);
    if (error.is_some()) abort error.destroy_some();
    assert!(currency.treasury_cap_id() == option::some(object::id(&treasury_cap)), ETreasuryMismatch);
    assert!(treasury_cap.total_supply() == 0, ENotZeroSupply);

    let shares = treasury_cap.mint_balance(spec.supply);
    currency.make_supply_fixed(treasury_cap);
    shares
}

// === View Functions ===

/// Whether `currency` is a share coin of `spec`: exact type, metadata locked
/// and equal to the spec, unregulated, and supply fixed at the spec's supply.
/// A fixed supply means the treasury cap is gone, so no further minting.
public fun is_share<T: key>(currency: &Currency<T>, spec: &Spec): bool {
    currency.is_supply_fixed() &&
        currency.total_supply() == option::some(spec.supply) &&
        spec_error(currency, spec).is_none()
}

// === Private Functions ===

/// The first failing property shared by `mint` and `is_share`, or `none`.
/// `T: key` excludes legacy coins: their constructors need a one-time
/// witness, which has only `drop`, so the currency came from `coin_registry`
/// and `is_regulated` is never `Unknown`.
fun spec_error<T: key>(currency: &Currency<T>, spec: &Spec): Option<u64> {
    if (!is_type<T>(spec)) return option::some(EInvalidType);
    if (!currency.is_metadata_cap_deleted()) return option::some(EMetadataNotLocked);
    if (currency.is_regulated()) return option::some(ERegulatedCurrency);
    if (currency.decimals() != spec.decimals) return option::some(EInvalidDecimals);
    if (currency.name() != spec.name) return option::some(EInvalidName);
    if (currency.symbol() != spec.symbol) return option::some(EInvalidSymbol);
    if (currency.description() != spec.description) return option::some(EInvalidDescription);
    if (currency.icon_url() != spec.icon_url) return option::some(EInvalidIconUrl);
    option::none()
}

/// True only for exactly `<address>::<module_name>::<datatype_name>`, with no
/// type arguments.
fun is_type<T: key>(spec: &Spec): bool {
    let type_name = type_name::with_defining_ids<T>();
    let mut expected = type_name.address_string().into_bytes();
    expected.append(b"::");
    expected.append(spec.module_name);
    expected.append(b"::");
    expected.append(spec.datatype_name);
    type_name.as_string() == &ascii::string(expected)
}

// === Test Functions ===

#[test_only]
public fun is_type_for_testing<T: key>(spec: &Spec): bool { is_type<T>(spec) }
