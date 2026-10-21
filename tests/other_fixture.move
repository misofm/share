// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A second module declaring a `Fixture` type, for the exact-module check.
#[test_only]
module share::other_fixture;

public struct Fixture has key { id: UID }
