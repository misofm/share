// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Canonical fixed-supply share coins.
///
/// `mint` checks a freshly registered currency against the caller's expected
/// type and metadata, mints the whole supply and fixes it by consuming the
/// treasury cap. Every coin that passes the same expectations is identical
/// apart from its package address, and a currency can be minted only once.
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
const ETreasuryMismatch: u64 = 1;
const ENotZeroSupply: u64 = 2;
const ERegulatedCurrency: u64 = 3;
const EMetadataNotLocked: u64 = 4;
const EInvalidDecimals: u64 = 5;
const EInvalidName: u64 = 6;
const EInvalidSymbol: u64 = 7;
const EInvalidDescription: u64 = 8;
const EInvalidIconUrl: u64 = 9;
const EZeroSupply: u64 = 10;

// === Public Functions ===

/// Mints the full fixed supply of `T`. Aborts unless `T` is exactly
/// `<package>::<module_name>::<datatype_name>` and not a one-time witness
/// name, the cap is the currency's treasury cap with nothing minted, the
/// currency is unregulated with its metadata cap deleted, and decimals, name,
/// symbol, description and icon URL equal the expected values.
public fun mint<T>(
    currency: &mut Currency<T>,
    mut treasury_cap: TreasuryCap<T>,
    module_name: vector<u8>,
    datatype_name: vector<u8>,
    decimals: u8,
    name: String,
    symbol: String,
    description: String,
    icon_url: String,
    supply: u64,
): Balance<T> {
    assert!(is_type<T>(module_name, datatype_name), EInvalidType);
    assert!(currency.treasury_cap_id() == option::some(object::id(&treasury_cap)), ETreasuryMismatch);
    assert!(treasury_cap.total_supply() == 0, ENotZeroSupply);
    assert!(!currency.is_regulated(), ERegulatedCurrency);
    assert!(currency.is_metadata_cap_deleted(), EMetadataNotLocked);
    assert!(currency.decimals() == decimals, EInvalidDecimals);
    assert!(currency.name() == name, EInvalidName);
    assert!(currency.symbol() == symbol, EInvalidSymbol);
    assert!(currency.description() == description, EInvalidDescription);
    assert!(currency.icon_url() == icon_url, EInvalidIconUrl);
    assert!(supply > 0, EZeroSupply);

    let shares = treasury_cap.mint_balance(supply);
    currency.make_supply_fixed(treasury_cap);
    shares
}

// === Private Functions ===

/// True only for exactly `<address>::<module_name>::<datatype_name>` with no
/// type arguments, where `datatype_name` isn't the module's one-time witness
/// name. Legacy coin constructors require a one-time witness, so the
/// currency was created through `coin_registry` and its regulation is known.
fun is_type<T>(module_name: vector<u8>, datatype_name: vector<u8>): bool {
    if (datatype_name == uppercase(module_name)) return false;
    let type_name = type_name::with_defining_ids<T>();
    if (type_name.is_primitive()) return false;
    let mut expected = type_name.address_string().into_bytes();
    expected.append(b"::");
    expected.append(module_name);
    expected.append(b"::");
    expected.append(datatype_name);
    type_name.as_string() == &ascii::string(expected)
}

fun uppercase(bytes: vector<u8>): vector<u8> {
    bytes.map!(|byte| if (byte >= 0x61 && byte <= 0x7a) byte - 0x20 else byte)
}
