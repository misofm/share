// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Fixed-supply ownership scoped to a parent object.
module share::share;

// === Imports ===

use sui::derived_object;
use sui::event;

// === Errors ===

const ENotEnough: u64 = 0;
const EIssuanceMismatch: u64 = 1;
const ENonZero: u64 = 2;
const EEmptySupply: u64 = 3;

// === Structs ===

/// Permanent ownership identity, derived from its parent. Neither deletion nor
/// mutable UID access is exposed.
public struct Issuance has key {
    id: UID,
    /// The parent this issuance is derived from, for navigating back up.
    parent_id: ID,
    supply: u64,
    decimals: u8,
}

/// Linear ownership units. Applications provide custody and revenue accounting.
public struct Share has store {
    issuance_id: ID,
    value: u64,
}

/// Derivation key: one issuance per parent.
public struct IssuanceKey() has copy, drop, store;

// === Events ===

public struct IssuanceCreatedEvent has copy, drop {
    issuance_id: ID,
    parent_id: ID,
    supply: u64,
    decimals: u8,
}

// === Public Functions ===

/// Creates the parent's issuance and its full supply. Parent UID access is the
/// authorization boundary; the parent's defining module must gate it. The
/// derived claim is permanent, so a parent has at most one issuance. Supply is
/// positive and in base units; decimals are display metadata.
///
/// The issuance is returned unshared so the caller can create pools or
/// register stakes first. It is key-only, so the same transaction must `share` it.
public fun new(parent: &mut UID, supply: u64, decimals: u8): (Issuance, Share) {
    assert!(supply > 0, EEmptySupply);
    let issuance = Issuance {
        id: derived_object::claim(parent, IssuanceKey()),
        parent_id: parent.to_inner(),
        supply,
        decimals,
    };
    let issuance_id = object::id(&issuance);
    event::emit(IssuanceCreatedEvent {
        issuance_id,
        parent_id: issuance.parent_id,
        supply,
        decimals,
    });
    (issuance, Share { issuance_id, value: supply })
}

public fun share(self: Issuance) {
    transfer::share_object(self);
}

public fun zero(issuance: &Issuance): Share {
    Share { issuance_id: object::id(issuance), value: 0 }
}

/// Like Balance::join: consumes one value and returns the new total.
public fun join(self: &mut Share, share: Share): u64 {
    let Share { issuance_id, value } = share;
    assert!(self.issuance_id == issuance_id, EIssuanceMismatch);
    self.value = self.value + value;
    self.value
}

public fun join_vec(self: &mut Share, shares: vector<Share>) {
    shares.do!(|share| { self.join(share); });
}

public fun split(self: &mut Share, amount: u64): Share {
    assert!(self.value >= amount, ENotEnough);
    self.value = self.value - amount;
    Share { issuance_id: self.issuance_id, value: amount }
}

public fun withdraw_all(self: &mut Share): Share {
    let amount = self.value;
    self.split(amount)
}

public fun destroy_zero(self: Share) {
    let Share { issuance_id: _, value } = self;
    assert!(value == 0, ENonZero);
}

// === View Functions ===

/// The issuance address for a parent. Computes an address, not evidence that
/// the issuance exists.
public fun derive_address(parent_id: ID): address {
    derived_object::derive_address(parent_id, IssuanceKey())
}

public fun parent_id(self: &Issuance): ID { self.parent_id }
public fun issuance_id(self: &Share): ID { self.issuance_id }
public fun value(self: &Share): u64 { self.value }
/// Immutable total base units.
public fun supply(self: &Issuance): u64 { self.supply }

/// Immutable display precision.
public fun decimals(self: &Issuance): u8 { self.decimals }

// === Test Functions ===

/// Builds a bounded share fixture for tests that focus on downstream custody
/// and accounting. Production shares come only from `new`.
#[test_only]
public fun create_for_testing(issuance: &Issuance, value: u64): Share {
    assert!(value <= issuance.supply(), ENotEnough);
    Share { issuance_id: object::id(issuance), value }
}

/// Builds a fixture when the tested package stores only the issuance
/// ID. This bypasses authentic issuance and supply conservation; tests using
/// it do not prove either property. Use real issuance/split for integration.
#[test_only]
public fun create_for_testing_from_id(issuance_id: ID, value: u64): Share {
    Share { issuance_id, value }
}
