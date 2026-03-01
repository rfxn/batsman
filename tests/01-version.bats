#!/usr/bin/env bats
# 01-version.bats — Version, source guard, and --help/--version tests

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

@test "BATSMAN_VERSION matches expected 1.0.2" {
    [ "$BATSMAN_VERSION" = "1.0.2" ]
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

# ---------------------------------------------------------------------------
# Dockerfile inventory
# ---------------------------------------------------------------------------

@test "all 9 base Dockerfiles exist" {
    local os
    for os in debian12 centos6 centos7 rocky8 rocky9 rocky10 \
              ubuntu1204 ubuntu2004 ubuntu2404; do
        [ -f "$BATSMAN_DOCKERFILES/Dockerfile.$os" ]
    done
}
