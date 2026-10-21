// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Canonical fixed-supply share coins. `mint` consumes the treasury cap, so a
/// currency can be minted only once.
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

// === Public Functions ===

/// `Share` must be exactly `<package>::<module_name>::<datatype_name>`. Checks abort
/// in the order documented in the README.
public fun mint<Share: key>(
    currency: &mut Currency<Share>,
    mut treasury_cap: TreasuryCap<Share>,
    module_name: vector<u8>,
    datatype_name: vector<u8>,
    decimals: u8,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
    supply: u64,
): Balance<Share> {
    assert!(supply > 0, EZeroSupply);
    assert!(is_type<Share>(module_name, datatype_name), EInvalidType);
    assert!(currency.is_metadata_cap_deleted(), EMetadataNotLocked);
    assert!(!currency.is_regulated(), ERegulatedCurrency);
    assert!(currency.decimals() == decimals, EInvalidDecimals);
    assert!(currency.name() == name, EInvalidName);
    assert!(currency.symbol() == symbol, EInvalidSymbol);
    assert!(currency.description() == description, EInvalidDescription);
    assert!(currency.icon_url() == icon_url, EInvalidIconUrl);
    assert!(
        currency.treasury_cap_id() == option::some(object::id(&treasury_cap)),
        ETreasuryMismatch,
    );
    assert!(treasury_cap.total_supply() == 0, ENotZeroSupply);

    let shares = treasury_cap.mint_balance(supply);
    currency.make_supply_fixed(treasury_cap);
    shares
}

// === Private Functions ===

/// True only for exactly `<address>::<module_name>::<datatype_name>`, which
/// excludes type arguments when `datatype_name` contains no `<`.
fun is_type<Share: key>(module_name: vector<u8>, datatype_name: vector<u8>): bool {
    let type_name = type_name::with_defining_ids<Share>();
    let mut expected = type_name.address_string().into_bytes();
    expected.append(b"::");
    expected.append(module_name);
    expected.append(b"::");
    expected.append(datatype_name);
    type_name.as_string() == &ascii::string(expected)
}

// === Test Functions ===

#[test_only]
public fun is_type_for_testing<Share: key>(
    module_name: vector<u8>,
    datatype_name: vector<u8>,
): bool {
    is_type<Share>(module_name, datatype_name)
}
