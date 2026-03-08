#!/usr/bin/env bats
# 08-uat-helpers.bats — Self-tests for UAT helper library
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE

load helpers/batsman-common

setup() {
    batsman_setup
    export UAT_OUTPUT_DIR="$TEST_TMPDIR/uat-output"
    # Resolve via same path as batsman-common.bash (handles container vs local)
    # shellcheck disable=SC1090
    source "${BATSMAN_LIB%/*}/uat-helpers.bash"
}

teardown() {
    batsman_teardown
}

# ---------------------------------------------------------------------------
# uat_setup
# ---------------------------------------------------------------------------

@test "uat_setup creates output directory" {
    [ ! -d "$UAT_OUTPUT_DIR" ]
    uat_setup
    [ -d "$UAT_OUTPUT_DIR" ]
}

@test "uat_setup creates session log" {
    uat_setup
    [ -f "$UAT_OUTPUT_DIR/uat-session.log" ]
}

@test "uat_setup session log contains start message" {
    uat_setup
    grep -q "UAT session started" "$UAT_OUTPUT_DIR/uat-session.log"
}

@test "uat_setup is idempotent" {
    uat_setup
    uat_setup
    [ -d "$UAT_OUTPUT_DIR" ]
    local count
    count=$(grep -c "UAT session started" "$UAT_OUTPUT_DIR/uat-session.log")
    [ "$count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# uat_capture
# ---------------------------------------------------------------------------

@test "uat_capture sets output and status from command" {
    uat_setup
    uat_capture "test-scenario" echo "hello world"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "uat_capture writes command marker to log" {
    uat_setup
    uat_capture "test-scenario" echo "hello"
    grep -q "=== CMD: echo hello ===" "$UAT_OUTPUT_DIR/test-scenario.log"
}

@test "uat_capture writes output to log" {
    uat_setup
    uat_capture "test-scenario" echo "test output line"
    grep -q "test output line" "$UAT_OUTPUT_DIR/test-scenario.log"
}

@test "uat_capture writes exit code to log" {
    uat_setup
    uat_capture "test-scenario" echo "ok"
    grep -q "EXIT_CODE: 0" "$UAT_OUTPUT_DIR/test-scenario.log"
}

@test "uat_capture captures failing commands" {
    uat_setup
    uat_capture "fail-scenario" false
    [ "$status" -ne 0 ]
    grep -q "EXIT_CODE: 1" "$UAT_OUTPUT_DIR/fail-scenario.log"
}

@test "uat_capture appends to same scenario log" {
    uat_setup
    uat_capture "multi" echo "first"
    uat_capture "multi" echo "second"
    local count
    count=$(grep -c "=== CMD:" "$UAT_OUTPUT_DIR/multi.log")
    [ "$count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# uat_log
# ---------------------------------------------------------------------------

@test "uat_log appends timestamped message" {
    uat_setup
    uat_log "test message"
    grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] test message$' \
        "$UAT_OUTPUT_DIR/uat-session.log"
}

# ---------------------------------------------------------------------------
# assert_valid_json
# ---------------------------------------------------------------------------

@test "assert_valid_json passes for valid JSON array" {
    output='[{"key":"value"}]'
    run assert_valid_json
    assert_success
}

@test "assert_valid_json passes for empty JSON array" {
    output='[]'
    run assert_valid_json
    assert_success
}

@test "assert_valid_json passes for JSON object" {
    output='{"key":"value"}'
    run assert_valid_json
    assert_success
}

@test "assert_valid_json fails for invalid JSON" {
    output='not json at all'
    run assert_valid_json
    assert_failure
    assert_output --partial "invalid JSON"
}

@test "assert_valid_json fails for empty output" {
    output=''
    run assert_valid_json
    assert_failure
    assert_output --partial "output is empty"
}

# ---------------------------------------------------------------------------
# assert_valid_csv
# ---------------------------------------------------------------------------

@test "assert_valid_csv passes for consistent CSV" {
    output=$'ip,service,count\n192.0.2.1,sshd,5\n192.0.2.2,dovecot,3'
    run assert_valid_csv
    assert_success
}

@test "assert_valid_csv passes with expected column count" {
    output=$'ip,service,count\n192.0.2.1,sshd,5'
    run assert_valid_csv 3
    assert_success
}

@test "assert_valid_csv fails for wrong column count" {
    output=$'ip,service,count\n192.0.2.1,sshd,5'
    run assert_valid_csv 5
    assert_failure
    assert_output --partial "expected 5 columns, got 3"
}

@test "assert_valid_csv fails for inconsistent rows" {
    output=$'ip,service,count\n192.0.2.1,sshd\n192.0.2.2,dovecot,3'
    run assert_valid_csv
    assert_failure
    assert_output --partial "inconsistent column counts"
}

@test "assert_valid_csv fails for empty output" {
    output=''
    run assert_valid_csv
    assert_failure
    assert_output --partial "output is empty"
}

# ---------------------------------------------------------------------------
# assert_empty_state_message
# ---------------------------------------------------------------------------

@test "assert_empty_state_message passes for descriptive message" {
    output='No active bans.'
    run assert_empty_state_message
    assert_success
}

@test "assert_empty_state_message fails for blank output" {
    output=''
    run assert_empty_state_message
    assert_failure
    assert_output --partial "output is blank"
}

# ---------------------------------------------------------------------------
# assert_no_banner_corruption
# ---------------------------------------------------------------------------

@test "assert_no_banner_corruption json passes for clean JSON" {
    output='[{"ip":"192.0.2.1"}]'
    run assert_no_banner_corruption json
    assert_success
}

@test "assert_no_banner_corruption json fails for banner prefix" {
    output=$'BFD version 2.0.1\n[{"ip":"192.0.2.1"}]'
    run assert_no_banner_corruption json
    assert_failure
    assert_output --partial "banner corruption"
}

@test "assert_no_banner_corruption csv passes for clean CSV" {
    output=$'ip,service,count\n192.0.2.1,sshd,5'
    run assert_no_banner_corruption csv
    assert_success
}

@test "assert_no_banner_corruption csv fails for timestamp prefix" {
    output=$'Mar  7 12:00:00 BFD version 2.0.1\nip,service,count'
    run assert_no_banner_corruption csv
    assert_failure
    assert_output --partial "banner corruption"
}

@test "assert_no_banner_corruption fails for unknown format" {
    output='some output'
    run assert_no_banner_corruption xml
    assert_failure
    assert_output --partial "unknown format"
}

@test "assert_no_banner_corruption fails for empty output" {
    output=''
    run assert_no_banner_corruption json
    assert_failure
    assert_output --partial "output is empty"
}
