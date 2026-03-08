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
