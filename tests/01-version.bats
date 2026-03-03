#!/usr/bin/env bats
# 01-version.bats — Version, source guard, and --help/--version tests
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE

load helpers/batsman-common

setup() {
    batsman_setup
}

teardown() {
    batsman_teardown
}

# ---------------------------------------------------------------------------
# BATSMAN_VERSION variable
# ---------------------------------------------------------------------------

@test "BATSMAN_VERSION is set and non-empty" {
    [ -n "$BATSMAN_VERSION" ]
}

@test "BATSMAN_VERSION matches X.Y.Z format" {
    local pattern='^[0-9]+\.[0-9]+\.[0-9]+$'
    [[ "$BATSMAN_VERSION" =~ $pattern ]]
}

@test "BATSMAN_VERSION matches source file declaration" {
    local src_version
    src_version=$(grep -E '^BATSMAN_VERSION=' "$BATSMAN_LIB" | head -1 | \
        sed 's/^BATSMAN_VERSION="//' | sed 's/"$//')
    [ -n "$src_version" ]
    [ "$BATSMAN_VERSION" = "$src_version" ]
}

# ---------------------------------------------------------------------------
# Source guard
# ---------------------------------------------------------------------------

@test "library sources successfully from BATS" {
    # All public functions should exist after sourcing
    local fn
    for fn in batsman_usage batsman_parse_args batsman_build \
              batsman_clean batsman_run_direct batsman_run_sequential \
              batsman_run_parallel batsman_run; do
        [ "$(type -t "$fn")" = "function" ]
    done
}

@test "direct execution fails with error message" {
    run bash "$BATSMAN_LIB"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be sourced"* ]]
}

# ---------------------------------------------------------------------------
# --version
# ---------------------------------------------------------------------------

@test "--version outputs version string and exits 0" {
    run batsman_parse_args --version
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "--version output starts with 'batsman'" {
    run batsman_parse_args --version
    [[ "$output" == batsman* ]]
}

@test "--version sets _batsman_done flag and returns (no exit)" {
    _batsman_done=0
    batsman_parse_args --version
    [ "$_batsman_done" -eq 1 ]
}

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

@test "--help exits 0 with usage text" {
    run batsman_parse_args --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "--help shows supported OS targets" {
    run batsman_parse_args --help
    [[ "$output" == *"debian12"* ]]
}

@test "--help sets _batsman_done flag and returns (no exit)" {
    _batsman_done=0
    batsman_parse_args --help
    [ "$_batsman_done" -eq 1 ]
}
