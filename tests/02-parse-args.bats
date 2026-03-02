#!/usr/bin/env bats
# 02-parse-args.bats — CLI argument parsing tests (highest-value coverage)
# shellcheck disable=SC2154,SC2034

load helpers/batsman-common

setup() {
    batsman_setup
}

teardown() {
    batsman_teardown
}

# ---------------------------------------------------------------------------
# Defaults (no arguments)
# ---------------------------------------------------------------------------

@test "defaults: no args sets _batsman_os to BATSMAN_DEFAULT_OS" {
    batsman_parse_args
    [ "$_batsman_os" = "$BATSMAN_DEFAULT_OS" ]
}

@test "defaults: no args sets _batsman_parallel=0" {
    batsman_parse_args
    [ "$_batsman_parallel" -eq 0 ]
}

@test "defaults: no args sets _batsman_formatter=tap" {
    batsman_parse_args
    [ "$_batsman_formatter" = "tap" ]
}

@test "defaults: no args sets empty bats_args" {
    batsman_parse_args
    [ "${#_batsman_bats_args[@]}" -eq 0 ]
}

@test "defaults: state resets on repeated calls" {
    batsman_parse_args --parallel --os rocky9
    batsman_parse_args
    [ "$_batsman_parallel" -eq 0 ]
    [ "$_batsman_os" = "debian12" ]
}

@test "defaults: unset BATSMAN_DEFAULT_OS falls back to debian12" {
    unset BATSMAN_DEFAULT_OS
    batsman_parse_args
    [ "$_batsman_os" = "debian12" ]
}

# ---------------------------------------------------------------------------
# --os
# ---------------------------------------------------------------------------

@test "--os sets _batsman_os" {
    batsman_parse_args --os rocky9
    [ "$_batsman_os" = "rocky9" ]
}

@test "--os overrides default" {
    BATSMAN_DEFAULT_OS="centos7"
    batsman_parse_args --os debian12
    [ "$_batsman_os" = "debian12" ]
}

@test "--os with invalid OS returns error" {
    run batsman_parse_args --os invalid_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported"* ]]
}

@test "--os invalid shows supported list" {
    run batsman_parse_args --os bogus
    [[ "$output" == *"Supported:"* ]]
}

# ---------------------------------------------------------------------------
# --parallel
# ---------------------------------------------------------------------------

@test "--parallel sets flag" {
    batsman_parse_args --parallel
    [ "$_batsman_parallel" -eq 1 ]
}

@test "--parallel N sets explicit count" {
    batsman_parse_args --parallel 4
    [ "$_batsman_parallel" -eq 1 ]
    [ "$_batsman_parallel_n" -eq 4 ]
}

@test "--parallel without N defaults to 0 (auto)" {
    batsman_parse_args --parallel
    [ "$_batsman_parallel_n" -eq 0 ]
}

@test "--parallel does not consume non-numeric next arg" {
    batsman_parse_args --parallel --formatter pretty
    [ "$_batsman_parallel" -eq 1 ]
    [ "$_batsman_parallel_n" -eq 0 ]
    [ "$_batsman_formatter" = "pretty" ]
}

# ---------------------------------------------------------------------------
# --filter / --filter-tags
# ---------------------------------------------------------------------------

@test "--filter passes through to bats_args" {
    batsman_parse_args --filter "test_name"
    [ "${_batsman_bats_args[0]}" = "--filter" ]
    [ "${_batsman_bats_args[1]}" = "test_name" ]
}

@test "--filter-tags passes through to bats_args" {
    batsman_parse_args --filter-tags "smoke"
    [ "${_batsman_bats_args[0]}" = "--filter-tags" ]
    [ "${_batsman_bats_args[1]}" = "smoke" ]
}

@test "--filter-tags negation passes through" {
    batsman_parse_args --filter-tags '!slow'
    [ "${_batsman_bats_args[1]}" = "!slow" ]
}

@test "multiple --filter-tags accumulate" {
    batsman_parse_args --filter-tags "smoke" --filter-tags "fast"
    [ "${#_batsman_bats_args[@]}" -eq 4 ]
    [ "${_batsman_bats_args[0]}" = "--filter-tags" ]
    [ "${_batsman_bats_args[1]}" = "smoke" ]
    [ "${_batsman_bats_args[2]}" = "--filter-tags" ]
    [ "${_batsman_bats_args[3]}" = "fast" ]
}

@test "--filter and --filter-tags combined" {
    batsman_parse_args --filter "install" --filter-tags "smoke"
    [ "${#_batsman_bats_args[@]}" -eq 4 ]
    [ "${_batsman_bats_args[0]}" = "--filter" ]
    [ "${_batsman_bats_args[2]}" = "--filter-tags" ]
}

# ---------------------------------------------------------------------------
# --formatter
# ---------------------------------------------------------------------------

@test "--formatter sets value" {
    batsman_parse_args --formatter pretty
    [ "$_batsman_formatter" = "pretty" ]
}

@test "--formatter default is tap" {
    batsman_parse_args
    [ "$_batsman_formatter" = "tap" ]
}

# ---------------------------------------------------------------------------
# --timeout
# ---------------------------------------------------------------------------

@test "--timeout sets value" {
    batsman_parse_args --timeout 30
    [ "$_batsman_test_timeout" = "30" ]
}

@test "--timeout CLI overrides env var" {
    BATSMAN_TEST_TIMEOUT="60"
    batsman_parse_args --timeout 30
    [ "$_batsman_test_timeout" = "30" ]
}

@test "--timeout env used when no CLI" {
    BATSMAN_TEST_TIMEOUT="60"
    batsman_parse_args
    [ "$_batsman_test_timeout" = "60" ]
}

@test "--timeout empty when neither CLI nor env" {
    unset BATSMAN_TEST_TIMEOUT
    batsman_parse_args
    [ -z "$_batsman_test_timeout" ]
}

# ---------------------------------------------------------------------------
# --report-dir
# ---------------------------------------------------------------------------

@test "--report-dir sets value" {
    batsman_parse_args --report-dir /tmp/reports
    [ "$_batsman_report_dir" = "/tmp/reports" ]
}

@test "--report-dir CLI overrides env var" {
    BATSMAN_REPORT_DIR="/env/reports"
    batsman_parse_args --report-dir /cli/reports
    [ "$_batsman_report_dir" = "/cli/reports" ]
}

@test "--report-dir env used when no CLI" {
    BATSMAN_REPORT_DIR="/env/reports"
    batsman_parse_args
    [ "$_batsman_report_dir" = "/env/reports" ]
}

@test "--report-dir empty when neither CLI nor env" {
    unset BATSMAN_REPORT_DIR
    batsman_parse_args
    [ -z "$_batsman_report_dir" ]
}

# ---------------------------------------------------------------------------
# --abort
# ---------------------------------------------------------------------------

@test "--abort sets flag" {
    batsman_parse_args --abort
    [ "$_batsman_abort" -eq 1 ]
}

@test "--abort prepends to bats_args" {
    batsman_parse_args --abort
    [ "${_batsman_bats_args[0]}" = "--abort" ]
}

@test "--abort prepend order with existing filter" {
    batsman_parse_args --filter "test_name" --abort
    # --abort should be first in bats_args (prepended)
    [ "${_batsman_bats_args[0]}" = "--abort" ]
    [ "${_batsman_bats_args[1]}" = "--filter" ]
    [ "${_batsman_bats_args[2]}" = "test_name" ]
}

# ---------------------------------------------------------------------------
# --clean
# ---------------------------------------------------------------------------

@test "--clean sets flag" {
    batsman_parse_args --clean
    [ "$_batsman_clean" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Explicit files (unknown args)
# ---------------------------------------------------------------------------

@test "file path sets explicit_files=1" {
    batsman_parse_args /opt/tests/01-test.bats
    [ "$_batsman_explicit_files" -eq 1 ]
    [ "${_batsman_bats_args[0]}" = "/opt/tests/01-test.bats" ]
}

@test "mixed flags and file paths" {
    batsman_parse_args --formatter pretty /opt/tests/01-test.bats
    [ "$_batsman_formatter" = "pretty" ]
    [ "$_batsman_explicit_files" -eq 1 ]
    [ "${_batsman_bats_args[0]}" = "/opt/tests/01-test.bats" ]
}

@test "unknown --flag passes to bats_args without setting explicit_files" {
    batsman_parse_args --unknown-flag 2>/dev/null
    [ "$_batsman_explicit_files" -eq 0 ]
    [ "${_batsman_bats_args[0]}" = "--unknown-flag" ]
}

@test "unknown --flag emits warning" {
    run batsman_parse_args --unknown-flag
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning"*"--unknown-flag"* ]]
}

@test "unknown --flag does not break other flags" {
    batsman_parse_args --parallel --unknown-bats-opt 2>/dev/null
    [ "$_batsman_parallel" -eq 1 ]
    [ "${_batsman_bats_args[0]}" = "--unknown-bats-opt" ]
    [ "$_batsman_explicit_files" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Missing value guards (F-002)
# ---------------------------------------------------------------------------

@test "--os without value returns error" {
    run batsman_parse_args --os
    [ "$status" -ne 0 ]
    [[ "$output" == *"--os"*"requires"* ]]
}

@test "--filter without value returns error" {
    run batsman_parse_args --filter
    [ "$status" -ne 0 ]
    [[ "$output" == *"--filter"*"requires"* ]]
}

@test "--filter-tags without value returns error" {
    run batsman_parse_args --filter-tags
    [ "$status" -ne 0 ]
    [[ "$output" == *"--filter-tags"*"requires"* ]]
}

@test "--formatter without value returns error" {
    run batsman_parse_args --formatter
    [ "$status" -ne 0 ]
    [[ "$output" == *"--formatter"*"requires"* ]]
}

@test "--timeout without value returns error" {
    run batsman_parse_args --timeout
    [ "$status" -ne 0 ]
    [[ "$output" == *"--timeout"*"requires"* ]]
}

@test "--report-dir without value returns error" {
    run batsman_parse_args --report-dir
    [ "$status" -ne 0 ]
    [[ "$output" == *"--report-dir"*"requires"* ]]
}

@test "--os at end of args is caught (not consumed by bottom shift)" {
    run batsman_parse_args --parallel --os
    [ "$status" -ne 0 ]
    [[ "$output" == *"--os"*"requires"* ]]
}

# ---------------------------------------------------------------------------
# Timeout numeric validation (F-004)
# ---------------------------------------------------------------------------

@test "--timeout with non-numeric value returns error" {
    run batsman_parse_args --timeout abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "--timeout with flag-like value returns error" {
    run batsman_parse_args --timeout --parallel
    [ "$status" -ne 0 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "--timeout 0 is accepted" {
    batsman_parse_args --timeout 0
    [ "$_batsman_test_timeout" = "0" ]
}

@test "BATSMAN_TEST_TIMEOUT env with non-numeric value returns error" {
    BATSMAN_TEST_TIMEOUT="abc"
    run batsman_parse_args
    [ "$status" -ne 0 ]
    [[ "$output" == *"positive integer"* ]]
}

# ---------------------------------------------------------------------------
# End-of-options (--)
# ---------------------------------------------------------------------------

@test "-- passes remaining args as file paths" {
    batsman_parse_args -- /opt/tests/01-test.bats
    [ "$_batsman_explicit_files" -eq 1 ]
    [ "${_batsman_bats_args[0]}" = "/opt/tests/01-test.bats" ]
}

@test "-- with no remaining args is harmless" {
    batsman_parse_args --
    [ "$_batsman_explicit_files" -eq 0 ]
    [ "${#_batsman_bats_args[@]}" -eq 0 ]
}

@test "-- prevents flag-like args from being parsed as options" {
    batsman_parse_args -- --not-a-flag
    [ "$_batsman_explicit_files" -eq 1 ]
    [ "${_batsman_bats_args[0]}" = "--not-a-flag" ]
    [ "$_batsman_parallel" -eq 0 ]
}

@test "flags before -- are parsed, args after are operands" {
    batsman_parse_args --parallel -- /opt/tests/01-test.bats
    [ "$_batsman_parallel" -eq 1 ]
    [ "$_batsman_explicit_files" -eq 1 ]
    [ "${_batsman_bats_args[0]}" = "/opt/tests/01-test.bats" ]
}

# ---------------------------------------------------------------------------
# Combined flags
# ---------------------------------------------------------------------------

@test "all flags combined correctly" {
    batsman_parse_args --os rocky9 --parallel 4 --formatter pretty \
        --timeout 30 --abort --clean --filter "install" \
        --filter-tags "smoke" --report-dir /tmp/reports
    [ "$_batsman_os" = "rocky9" ]
    [ "$_batsman_parallel" -eq 1 ]
    [ "$_batsman_parallel_n" -eq 4 ]
    [ "$_batsman_formatter" = "pretty" ]
    [ "$_batsman_test_timeout" = "30" ]
    [ "$_batsman_abort" -eq 1 ]
    [ "$_batsman_clean" -eq 1 ]
    [ "$_batsman_report_dir" = "/tmp/reports" ]
    # bats_args: --abort (prepended), --filter install, --filter-tags smoke
    [ "${_batsman_bats_args[0]}" = "--abort" ]
    [ "${_batsman_bats_args[1]}" = "--filter" ]
    [ "${_batsman_bats_args[2]}" = "install" ]
    [ "${_batsman_bats_args[3]}" = "--filter-tags" ]
    [ "${_batsman_bats_args[4]}" = "smoke" ]
}
