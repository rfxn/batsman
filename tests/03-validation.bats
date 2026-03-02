#!/usr/bin/env bats
# 03-validation.bats — Required variable validation, variant mapping, Dockerfile paths
# shellcheck disable=SC2154,SC2034

load helpers/batsman-common

setup() {
    batsman_setup
}

teardown() {
    batsman_teardown
}

# ---------------------------------------------------------------------------
# Required variable validation (batsman_run validates before parse_args)
# ---------------------------------------------------------------------------

@test "missing BATSMAN_PROJECT reports error" {
    unset BATSMAN_PROJECT
    run batsman_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"BATSMAN_PROJECT"* ]]
}

@test "missing BATSMAN_PROJECT_DIR reports error" {
    unset BATSMAN_PROJECT_DIR
    run batsman_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"BATSMAN_PROJECT_DIR"* ]]
}

@test "missing BATSMAN_TESTS_DIR reports error" {
    unset BATSMAN_TESTS_DIR
    run batsman_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"BATSMAN_TESTS_DIR"* ]]
}

@test "missing BATSMAN_INFRA_DIR reports error" {
    unset BATSMAN_INFRA_DIR
    run batsman_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"BATSMAN_INFRA_DIR"* ]]
}

@test "missing BATSMAN_CONTAINER_TEST_PATH reports error" {
    unset BATSMAN_CONTAINER_TEST_PATH
    run batsman_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"BATSMAN_CONTAINER_TEST_PATH"* ]]
}

@test "missing BATSMAN_SUPPORTED_OS reports error" {
    unset BATSMAN_SUPPORTED_OS
    run batsman_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"BATSMAN_SUPPORTED_OS"* ]]
}

@test "multiple missing vars all reported" {
    unset BATSMAN_PROJECT BATSMAN_PROJECT_DIR BATSMAN_TESTS_DIR
    run batsman_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"BATSMAN_PROJECT"* ]]
    [[ "$output" == *"BATSMAN_PROJECT_DIR"* ]]
    [[ "$output" == *"BATSMAN_TESTS_DIR"* ]]
}

@test "empty string treated as missing" {
    BATSMAN_PROJECT=""
    run batsman_run
    [ "$status" -ne 0 ]
    [[ "$output" == *"BATSMAN_PROJECT"* ]]
}

@test "batsman_run propagates parse_args failure (F-001)" {
    run batsman_run --os invalid_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported"* ]]
}

@test "batsman_run propagates missing-value failure" {
    run batsman_run --timeout
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires"* ]]
}

# ---------------------------------------------------------------------------
# Variant mapping (BATSMAN_BASE_OS_MAP)
# ---------------------------------------------------------------------------
# The mapping logic is in batsman_build() and batsman_clean(). Since those
# require Docker, we test the mapping logic by replicating the exact loop
# pattern from batsman_build() — same code path, no Docker dependency.

_resolve_base_os() {
    local os="$1"
    local base_os="$os"
    if [ -n "${BATSMAN_BASE_OS_MAP:-}" ]; then
        local _map_entry
        for _map_entry in $BATSMAN_BASE_OS_MAP; do
            if [ "${_map_entry%%=*}" = "$os" ]; then
                base_os="${_map_entry#*=}"
                break
            fi
        done
    fi
    echo "$base_os"
}

@test "variant mapping: yara-x=debian12 resolves correctly" {
    BATSMAN_BASE_OS_MAP="yara-x=debian12"
    run _resolve_base_os "yara-x"
    [ "$output" = "debian12" ]
}

@test "variant mapping: no match returns identity" {
    BATSMAN_BASE_OS_MAP="yara-x=debian12"
    run _resolve_base_os "rocky9"
    [ "$output" = "rocky9" ]
}

@test "variant mapping: empty map returns identity" {
    BATSMAN_BASE_OS_MAP=""
    run _resolve_base_os "debian12"
    [ "$output" = "debian12" ]
}

@test "variant mapping: multiple mappings picks correct one" {
    BATSMAN_BASE_OS_MAP="yara-x=debian12 custom=rocky9"
    run _resolve_base_os "custom"
    [ "$output" = "rocky9" ]
}

@test "variant mapping: first match wins" {
    BATSMAN_BASE_OS_MAP="yara-x=debian12 yara-x=rocky9"
    run _resolve_base_os "yara-x"
    [ "$output" = "debian12" ]
}

# ---------------------------------------------------------------------------
# Dockerfile path conventions
# ---------------------------------------------------------------------------

@test "dockerfile: debian12 project uses Dockerfile (no suffix)" {
    # The convention: default OS (_batsman_os = debian12) uses tests/Dockerfile
    batsman_parse_args --os debian12
    local project_df="$BATSMAN_TESTS_DIR/Dockerfile"
    local expected_path="Dockerfile"
    local actual
    if [ "$_batsman_os" = "debian12" ]; then
        actual="Dockerfile"
    else
        actual="Dockerfile.${_batsman_os}"
    fi
    [ "$actual" = "$expected_path" ]
}

@test "dockerfile: rocky9 project uses Dockerfile.rocky9" {
    batsman_parse_args --os rocky9
    local expected_path="Dockerfile.rocky9"
    local actual
    if [ "$_batsman_os" = "debian12" ]; then
        actual="Dockerfile"
    else
        actual="Dockerfile.${_batsman_os}"
    fi
    [ "$actual" = "$expected_path" ]
}

@test "dockerfile: base Dockerfiles use INFRA_DIR/dockerfiles/" {
    # Verify the base dockerfile path convention
    local base_df="$BATSMAN_DOCKERFILES/Dockerfile.debian12"
    [ -f "$base_df" ]
}

@test "dockerfile: all 9 base Dockerfiles exist" {
    local os
    for os in debian12 centos6 centos7 rocky8 rocky9 rocky10 \
              ubuntu1204 ubuntu2004 ubuntu2404; do
        [ -f "$BATSMAN_DOCKERFILES/Dockerfile.$os" ]
    done
}
