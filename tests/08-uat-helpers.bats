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

# ---------------------------------------------------------------------------
# assert_json_field
# ---------------------------------------------------------------------------

@test "assert_json_field extracts top-level string field" {
    output='{"name":"batsman","version":"1.2.0"}'
    run assert_json_field "name" "batsman"
    assert_success
}

@test "assert_json_field extracts nested field via dot-notation" {
    output='{"status":{"code":200,"msg":"ok"}}'
    run assert_json_field "status.code" "200"
    assert_success
}

@test "assert_json_field fails on value mismatch" {
    output='{"name":"batsman"}'
    run assert_json_field "name" "wrong"
    assert_failure
    assert_output --partial "expected 'wrong', got 'batsman'"
}

@test "assert_json_field fails for empty output" {
    output=''
    run assert_json_field "key" "val"
    assert_failure
    assert_output --partial "output is empty"
}

@test "assert_json_field fails for missing key" {
    output='{"name":"batsman"}'
    run assert_json_field "missing" "val"
    assert_failure
    assert_output --partial "failed to extract"
}

# ---------------------------------------------------------------------------
# assert_json_array_length
# ---------------------------------------------------------------------------

@test "assert_json_array_length checks top-level array" {
    output='[1,2,3]'
    run assert_json_array_length "" 3
    assert_success
}

@test "assert_json_array_length checks nested array" {
    output='{"items":[{"a":1},{"a":2}]}'
    run assert_json_array_length "items" 2
    assert_success
}

@test "assert_json_array_length fails on count mismatch" {
    output='[1,2,3]'
    run assert_json_array_length "" 5
    assert_failure
    assert_output --partial "expected length 5, got 3"
}

@test "assert_json_array_length fails for empty output" {
    output=''
    run assert_json_array_length "" 0
    assert_failure
    assert_output --partial "output is empty"
}

# ---------------------------------------------------------------------------
# assert_csv_row_count
# ---------------------------------------------------------------------------

@test "assert_csv_row_count counts data rows excluding header" {
    output=$'ip,service\n192.0.2.1,sshd\n192.0.2.2,dovecot'
    run assert_csv_row_count 2
    assert_success
}

@test "assert_csv_row_count fails on count mismatch" {
    output=$'ip,service\n192.0.2.1,sshd'
    run assert_csv_row_count 5
    assert_failure
    assert_output --partial "expected 5 data rows, got 1"
}

@test "assert_csv_row_count fails for empty output" {
    output=''
    run assert_csv_row_count 0
    assert_failure
    assert_output --partial "output is empty"
}

# ---------------------------------------------------------------------------
# assert_csv_header
# ---------------------------------------------------------------------------

@test "assert_csv_header passes when all columns present" {
    output=$'ip,service,count\n192.0.2.1,sshd,5'
    run assert_csv_header "ip" "service" "count"
    assert_success
}

@test "assert_csv_header fails for missing column" {
    output=$'ip,service,count\n192.0.2.1,sshd,5'
    run assert_csv_header "ip" "missing_col"
    assert_failure
    assert_output --partial "column 'missing_col' not found"
}

@test "assert_csv_header fails for empty output" {
    output=''
    run assert_csv_header "ip"
    assert_failure
    assert_output --partial "output is empty"
}

# ---------------------------------------------------------------------------
# assert_output_line_count
# ---------------------------------------------------------------------------

@test "assert_output_line_count exact match" {
    output=$'line1\nline2\nline3'
    run assert_output_line_count 3
    assert_success
}

@test "assert_output_line_count range match" {
    output=$'line1\nline2\nline3'
    run assert_output_line_count 2 5
    assert_success
}

@test "assert_output_line_count fails on exact mismatch" {
    output=$'line1\nline2'
    run assert_output_line_count 5
    assert_failure
    assert_output --partial "expected 5 lines, got 2"
}

@test "assert_output_line_count empty output passes for 0" {
    output=''
    run assert_output_line_count 0
    assert_success
}

# ---------------------------------------------------------------------------
# assert_file_perms
# ---------------------------------------------------------------------------

@test "assert_file_perms passes for matching permissions" {
    local testfile="$TEST_TMPDIR/perms-test"
    echo "data" > "$testfile"
    chmod 640 "$testfile"
    run assert_file_perms "$testfile" "640"
    assert_success
}

@test "assert_file_perms fails for wrong permissions" {
    local testfile="$TEST_TMPDIR/perms-test2"
    echo "data" > "$testfile"
    chmod 755 "$testfile"
    run assert_file_perms "$testfile" "640"
    assert_failure
    assert_output --partial "expected perms 640, got 755"
}

@test "assert_file_perms fails for nonexistent file" {
    run assert_file_perms "/nonexistent/file" "640"
    assert_failure
    assert_output --partial "does not exist"
}

# ---------------------------------------------------------------------------
# assert_process_running / assert_process_not_running
# ---------------------------------------------------------------------------

@test "assert_process_running passes for running process" {
    # sleep runs as a background process for this test
    sleep 60 &
    local pid=$!
    run assert_process_running "sleep 60"
    kill "$pid" 2>/dev/null || true  # cleanup — process may have already exited
    wait "$pid" 2>/dev/null || true  # reap — wait may fail if already reaped
    assert_success
}

@test "assert_process_not_running passes when no match" {
    run assert_process_not_running "nonexistent_process_pattern_xyz_12345"
    assert_success
}

# ---------------------------------------------------------------------------
# uat_wait_for_condition
# ---------------------------------------------------------------------------

@test "uat_wait_for_condition returns immediately on success" {
    run uat_wait_for_condition "true" 5
    assert_success
}

@test "uat_wait_for_condition times out on persistent failure" {
    export UAT_POLL_INTERVAL=0.1
    run uat_wait_for_condition "false" 1
    assert_failure
    assert_output --partial "timed out"
}

# ---------------------------------------------------------------------------
# uat_wait_for_file
# ---------------------------------------------------------------------------

@test "uat_wait_for_file returns immediately for existing file" {
    local testfile="$TEST_TMPDIR/wait-file-test"
    echo "content" > "$testfile"
    run uat_wait_for_file "$testfile" 5
    assert_success
}

@test "uat_wait_for_file times out for missing file" {
    export UAT_POLL_INTERVAL=0.1
    run uat_wait_for_file "$TEST_TMPDIR/does-not-exist" 1
    assert_failure
    assert_output --partial "timed out"
}

# ---------------------------------------------------------------------------
# uat_wait_for_log
# ---------------------------------------------------------------------------

@test "uat_wait_for_log finds pattern in existing log" {
    local logfile="$TEST_TMPDIR/wait-log-test.log"
    echo "startup complete" > "$logfile"
    run uat_wait_for_log "$logfile" "startup complete" 5
    assert_success
}

@test "uat_wait_for_log times out when pattern absent" {
    local logfile="$TEST_TMPDIR/wait-log-miss.log"
    echo "other content" > "$logfile"
    export UAT_POLL_INTERVAL=0.1
    run uat_wait_for_log "$logfile" "will never appear" 1
    assert_failure
    assert_output --partial "timed out"
}

# ---------------------------------------------------------------------------
# uat_cleanup_processes
# ---------------------------------------------------------------------------

@test "uat_cleanup_processes kills matching process" {
    sleep 120 &
    local pid=$!
    # Verify it started
    kill -0 "$pid" 2>/dev/null
    run uat_cleanup_processes "sleep 120"
    assert_success
    # Verify the process was actually killed
    run kill -0 "$pid"
    assert_failure
    wait "$pid" 2>/dev/null || true  # reap zombie — may fail if already reaped
}

@test "uat_cleanup_processes tolerates no matching processes" {
    run uat_cleanup_processes "nonexistent_process_pattern_xyz_99999"
    assert_success
}
