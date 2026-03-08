#!/bin/bash
# batsman — uat-helpers.bash
# Shared UAT assertion and utility library for BATS-based UAT scenarios
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
#
# Sourced by UAT .bats files via: load '../infra/lib/uat-helpers'
#
# Provides:
#   uat_setup                    — Initialize output capture directory
#   uat_capture SCENARIO CMD...  — Run command, capture output to named log
#   uat_log MSG                  — Append timestamped message to session log
#   assert_valid_json            — Validate $output is parseable JSON
#   assert_valid_csv [COLS]      — Validate CSV structure and column consistency
#   assert_empty_state_message   — Verify non-blank "no data" message
#   assert_no_banner_corruption FMT — Verify structured output is clean
#   _uat_json_extract KEY [MODE] — Shared JSON dot-notation traversal (internal)
#   assert_json_field KEY EXP    — Assert JSON field value (dot-notation)
#   assert_json_array_length K N — Assert JSON array length at key
#   assert_csv_row_count COUNT   — Assert CSV data rows (excluding header)
#   assert_csv_header COLS...    — Assert CSV header contains columns
#   assert_output_line_count M [N] — Assert output line count (exact or range)
#   assert_file_perms FILE OCTAL — Assert file permission matches
#   assert_process_running PAT   — Assert process matching pattern exists
#   assert_process_not_running P — Assert no process matching pattern
#   uat_wait_for_condition CMD T — Poll command until success or timeout
#   uat_wait_for_file FILE T     — Wait for file to exist and be non-empty
#   uat_wait_for_log FILE PAT T  — Wait for pattern to appear in log
#   uat_cleanup_processes PAT    — Kill matching processes, wait for exit
#
# All functions are bash 4.1+ safe (no declare -A, no ${var,,}).

# ---------------------------------------------------------------------------
# Setup / Output Capture
# ---------------------------------------------------------------------------

# uat_setup — Create output capture directory and session log
# Call from setup_file() in each UAT .bats file
uat_setup() {
    export UAT_OUTPUT_DIR="${UAT_OUTPUT_DIR:-/tmp/uat-output}"
    mkdir -p "$UAT_OUTPUT_DIR"
    uat_log "UAT session started"
}

# uat_capture SCENARIO_NAME COMMAND [ARGS...]
# Run a command via BATS 'run', capture full output to a named log file.
# Sets $output and $status for subsequent BATS assertions.
#
# Usage:
#   uat_capture "ban-lifecycle" bfd -b 192.0.2.1 sshd
#   assert_success
#   assert_output --partial "192.0.2.1"
# shellcheck disable=SC2154  # $output and $status set by BATS 'run'
uat_capture() {
    local scenario="$1"
    shift
    local logfile="${UAT_OUTPUT_DIR}/${scenario}.log"

    run "$@"

    {
        echo "=== CMD: $* ==="
        echo "$output"
        echo "EXIT_CODE: $status"
        echo "==="
    } >> "$logfile"
}

# uat_log MSG — Append timestamped message to session log
uat_log() {
    local msg="$1"
    local logfile="${UAT_OUTPUT_DIR:-/tmp/uat-output}/uat-session.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$logfile"
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

# assert_valid_json — Validate that $output is parseable JSON
# Uses python3 -m json.tool (available in all modern containers)
assert_valid_json() {
    if [ -z "$output" ]; then
        echo "assert_valid_json: output is empty" >&2
        return 1
    fi
    if ! echo "$output" | python3 -m json.tool > /dev/null 2>&1; then
        echo "assert_valid_json: invalid JSON output:" >&2
        echo "$output" | head -5 >&2
        return 1
    fi
}

# assert_valid_csv [EXPECTED_COLS] — Validate CSV structure
# Checks: non-empty, header row present, consistent column count across rows.
# If EXPECTED_COLS is provided, verifies header has that many columns.
assert_valid_csv() {
    local expected_cols="${1:-}"

    if [ -z "$output" ]; then
        echo "assert_valid_csv: output is empty" >&2
        return 1
    fi

    local header
    header="$(echo "$output" | head -1)"
    local header_cols
    header_cols="$(echo "$header" | awk -F',' '{print NF}')"

    if [ -n "$expected_cols" ] && [ "$header_cols" -ne "$expected_cols" ]; then
        echo "assert_valid_csv: expected $expected_cols columns, got $header_cols" >&2
        echo "Header: $header" >&2
        return 1
    fi

    # Check all data rows have same column count as header
    local bad_rows
    bad_rows="$(echo "$output" | awk -F',' -v hc="$header_cols" 'NR>1 && NF!=hc && NF>0 {print NR": "NF" cols (expected "hc")"}')"
    if [ -n "$bad_rows" ]; then
        echo "assert_valid_csv: inconsistent column counts:" >&2
        echo "$bad_rows" >&2
        return 1
    fi
}

# assert_empty_state_message — Verify "no data" output is a clear message
# Fails if output is completely empty (should have a descriptive message like
# "No active bans" instead of blank output or headers with zero data rows).
assert_empty_state_message() {
    if [ -z "$output" ]; then
        echo "assert_empty_state_message: output is blank — expected a descriptive 'no data' message" >&2
        return 1
    fi
}

# assert_no_banner_corruption FORMAT — Verify structured output is clean
# FORMAT: "json" or "csv"
# Checks that version banners or log prefixes haven't bled into structured output.
assert_no_banner_corruption() {
    local format="$1"

    if [ -z "$output" ]; then
        echo "assert_no_banner_corruption: output is empty" >&2
        return 1
    fi

    case "$format" in
        json)
            # First non-whitespace character should be [ or {
            local first_char
            first_char="$(echo "$output" | grep -oE '^\S' | head -1)"
            if [ "$first_char" != "[" ] && [ "$first_char" != "{" ]; then
                echo "assert_no_banner_corruption: JSON starts with '$first_char' — banner corruption?" >&2
                echo "First line: $(echo "$output" | head -1)" >&2
                return 1
            fi
            ;;
        csv)
            # First line should not contain a timestamp-like prefix (e.g., "Mar  7 12:00")
            local first_line
            first_line="$(echo "$output" | head -1)"
            local ts_pat='^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9]'
            if [[ "$first_line" =~ $ts_pat ]]; then
                echo "assert_no_banner_corruption: CSV has timestamp prefix — banner corruption?" >&2
                echo "First line: $first_line" >&2
                return 1
            fi
            ;;
        *)
            echo "assert_no_banner_corruption: unknown format '$format' (expected 'json' or 'csv')" >&2
            return 1
            ;;
    esac
}

# _uat_json_extract KEY [MODE] — Extract a value from JSON $output via dot-notation
# Traverses nested objects/arrays using python3 -c. Shared by assert_json_field
# and assert_json_array_length.
# KEY: dot-separated path (e.g., "status.code", "items.0.name").
#      Use "" for the top-level value (returns data as-is).
# MODE: "value" (default) — print the traversed value
#       "len"  — print len() of the traversed value (must be a list)
# Returns 0 on success, 1 on extraction/type failure.
_uat_json_extract() {
    local key="$1"
    local mode="${2:-value}"

    echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
key = '${key}'
if key == '':
    val = data
else:
    keys = key.split('.')
    val = data
    for k in keys:
        if isinstance(val, list):
            val = val[int(k)]
        else:
            val = val[k]
mode = '${mode}'
if mode == 'len':
    if not isinstance(val, list):
        print('NOT_ARRAY', file=sys.stderr)
        sys.exit(1)
    print(len(val))
else:
    print(val)
" 2>&1
}

# assert_json_field KEY EXPECTED — Assert a JSON field value matches expected
# KEY supports dot-notation for nested fields (e.g., "status.code").
# Operates on $output (set by BATS 'run' or direct assignment).
# Uses _uat_json_extract for JSON parsing.
assert_json_field() {
    local key="$1"
    local expected="$2"

    if [ -z "$output" ]; then
        echo "assert_json_field: output is empty" >&2
        return 1
    fi

    local actual
    actual="$(_uat_json_extract "$key" "value")" || {
        echo "assert_json_field: failed to extract key '$key' from JSON" >&2
        echo "Python error: $actual" >&2
        echo "Output was: $(echo "$output" | head -3)" >&2
        return 1
    }

    if [ "$actual" != "$expected" ]; then
        echo "assert_json_field: key '$key' expected '$expected', got '$actual'" >&2
        return 1
    fi
}

# assert_json_array_length KEY COUNT — Assert JSON array length at given key
# KEY is the field name containing an array. Use "" for top-level array.
# Operates on $output. Uses _uat_json_extract for JSON traversal.
assert_json_array_length() {
    local key="$1"
    local expected_count="$2"

    if [ -z "$output" ]; then
        echo "assert_json_array_length: output is empty" >&2
        return 1
    fi

    local actual_count
    actual_count="$(_uat_json_extract "$key" "len")" || {
        echo "assert_json_array_length: failed to get array length for key '$key'" >&2
        echo "Output was: $(echo "$output" | head -3)" >&2
        return 1
    }

    if [ "$actual_count" != "$expected_count" ]; then
        echo "assert_json_array_length: key '$key' expected length $expected_count, got $actual_count" >&2
        return 1
    fi
}

# assert_csv_row_count COUNT — Assert CSV data row count (excluding header)
# Operates on $output.
assert_csv_row_count() {
    local expected_count="$1"

    if [ -z "$output" ]; then
        echo "assert_csv_row_count: output is empty" >&2
        return 1
    fi

    # Count non-empty lines excluding header (line 1)
    local actual_count
    # grep -c returns exit 1 when no lines match — fallback to 0; stderr suppressed for clean output
    actual_count="$(echo "$output" | tail -n +2 | grep -c '.' 2>/dev/null)" || actual_count=0

    if [ "$actual_count" -ne "$expected_count" ]; then
        echo "assert_csv_row_count: expected $expected_count data rows, got $actual_count" >&2
        return 1
    fi
}

# assert_csv_header COLS... — Assert CSV header contains expected column names
# Each argument is a column name that must appear in the first line.
# Operates on $output.
assert_csv_header() {
    if [ -z "$output" ]; then
        echo "assert_csv_header: output is empty" >&2
        return 1
    fi

    local header
    header="$(echo "$output" | head -1)"
    local col
    for col in "$@"; do
        # Check if column name appears as a complete CSV field
        # Match: start-of-line or comma, then the column name, then comma or end-of-line
        local col_pat="(^|,)${col}(,|$)"
        if ! [[ "$header" =~ $col_pat ]]; then
            echo "assert_csv_header: column '$col' not found in header: $header" >&2
            return 1
        fi
    done
}

# assert_output_line_count MIN [MAX] — Assert output line count within range
# If only MIN is given, asserts exact count. If MAX is given, asserts MIN <= count <= MAX.
# Operates on $output.
assert_output_line_count() {
    local min_count="$1"
    local max_count="${2:-}"

    if [ -z "$output" ]; then
        # Empty output = 0 lines
        if [ "$min_count" -gt 0 ]; then
            echo "assert_output_line_count: output is empty, expected at least $min_count lines" >&2
            return 1
        fi
        return 0
    fi

    local actual_count
    actual_count="$(echo "$output" | wc -l)"
    # Trim whitespace from wc output (some implementations pad)
    actual_count="${actual_count## }"
    actual_count="${actual_count%% }"

    if [ -z "$max_count" ]; then
        # Exact match
        if [ "$actual_count" -ne "$min_count" ]; then
            echo "assert_output_line_count: expected $min_count lines, got $actual_count" >&2
            return 1
        fi
    else
        # Range check
        if [ "$actual_count" -lt "$min_count" ] || [ "$actual_count" -gt "$max_count" ]; then
            echo "assert_output_line_count: expected $min_count-$max_count lines, got $actual_count" >&2
            return 1
        fi
    fi
}

# assert_file_perms FILE OCTAL — Assert file permission matches
# Uses stat -c '%a' (GNU Linux only — all target OS are Linux).
assert_file_perms() {
    local file="$1"
    local expected_perms="$2"

    if [ ! -e "$file" ]; then
        echo "assert_file_perms: file does not exist: $file" >&2
        return 1
    fi

    local actual_perms
    actual_perms="$(stat -c '%a' "$file")"

    if [ "$actual_perms" != "$expected_perms" ]; then
        echo "assert_file_perms: $file expected perms $expected_perms, got $actual_perms" >&2
        return 1
    fi
}

# assert_process_running PATTERN — Assert process matching pattern exists
# Uses pgrep (available on all target OS: CentOS 6+ procps-ng).
assert_process_running() {
    local pattern="$1"

    if ! pgrep -f "$pattern" > /dev/null 2>&1; then
        echo "assert_process_running: no process matching '$pattern'" >&2
        return 1
    fi
}

# assert_process_not_running PATTERN — Assert no process matching pattern
# Uses pgrep (available on all target OS: CentOS 6+ procps-ng).
assert_process_not_running() {
    local pattern="$1"

    if pgrep -f "$pattern" > /dev/null 2>&1; then
        echo "assert_process_not_running: process matching '$pattern' is still running" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Wait / Poll Utilities
# ---------------------------------------------------------------------------

# uat_wait_for_condition CMD TIMEOUT_SEC — Poll command until success or timeout
# Polls at UAT_POLL_INTERVAL (default 0.5s). Returns 0 on success, 1 on timeout.
# CMD is evaluated via eval (pass a quoted command string).
uat_wait_for_condition() {
    local cmd="$1"
    local timeout_sec="$2"
    local interval="${UAT_POLL_INTERVAL:-0.5}"
    local start_time="$SECONDS"
    local deadline=$(( start_time + timeout_sec ))

    while true; do
        if eval "$cmd" > /dev/null 2>&1; then
            return 0
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "uat_wait_for_condition: timed out after ${timeout_sec}s waiting for: $cmd" >&2
            return 1
        fi
        sleep "$interval"
    done
}

# uat_wait_for_file FILE TIMEOUT_SEC — Wait for file to exist and be non-empty
# Polls at UAT_POLL_INTERVAL (default 0.5s). Returns 0 on success, 1 on timeout.
uat_wait_for_file() {
    local file="$1"
    local timeout_sec="$2"
    local interval="${UAT_POLL_INTERVAL:-0.5}"
    local start_time="$SECONDS"
    local deadline=$(( start_time + timeout_sec ))

    while true; do
        if [ -s "$file" ]; then
            return 0
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "uat_wait_for_file: timed out after ${timeout_sec}s waiting for: $file" >&2
            return 1
        fi
        sleep "$interval"
    done
}

# uat_wait_for_log FILE PATTERN TIMEOUT_SEC — Wait for pattern to appear in log
# Polls at UAT_POLL_INTERVAL (default 0.5s). Returns 0 on success, 1 on timeout.
uat_wait_for_log() {
    local file="$1"
    local pattern="$2"
    local timeout_sec="$3"
    local interval="${UAT_POLL_INTERVAL:-0.5}"
    local start_time="$SECONDS"
    local deadline=$(( start_time + timeout_sec ))

    while true; do
        if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then
            return 0
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "uat_wait_for_log: timed out after ${timeout_sec}s waiting for '$pattern' in $file" >&2
            return 1
        fi
        sleep "$interval"
    done
}

# uat_cleanup_processes PATTERN — Kill matching processes, wait for exit
# Uses pkill (available on all target OS: CentOS 6+ procps-ng).
# Tolerates already-dead processes (pkill exit 1 = no match is not an error).
# Waits up to 5 seconds for processes to exit before sending SIGKILL.
uat_cleanup_processes() {
    local pattern="$1"
    local graceful_timeout=5
    local start_time="$SECONDS"
    local deadline=$(( start_time + graceful_timeout ))

    # Send SIGTERM; exit code 1 = no matching process (not an error)
    pkill -f "$pattern" 2>/dev/null || true  # pkill rc=1 means no match — safe to ignore

    # Wait for processes to exit
    while pgrep -f "$pattern" > /dev/null 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            # Force kill after graceful timeout
            pkill -9 -f "$pattern" 2>/dev/null || true  # SIGKILL; rc=1 = already dead — safe
            break
        fi
        sleep 0.2
    done
}
