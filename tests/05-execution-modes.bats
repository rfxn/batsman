#!/usr/bin/env bats
# 05-execution-modes.bats — Execution mode function tests (direct, sequential, parallel)
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
# shellcheck disable=SC2154,SC2034

load helpers/batsman-common

setup() {
    batsman_setup
    DOCKER_LOG="$TEST_TMPDIR/docker.log"
    DOCKER_EXIT_CODE=0
    DOCKER_TAP_OUTPUT=""
    export DOCKER_LOG DOCKER_EXIT_CODE DOCKER_TAP_OUTPUT

    # Docker stub: logs arguments to file, outputs TAP for 'run' subcommand
    # shellcheck disable=SC2317
    docker() {
        echo "$*" >> "$DOCKER_LOG"
        case "$1" in
            run)
                if [ -n "${DOCKER_TAP_OUTPUT:-}" ]; then
                    printf '%s\n' "$DOCKER_TAP_OUTPUT"
                else
                    echo "ok 1 stub test"
                fi
                return "${DOCKER_EXIT_CODE:-0}"
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f docker

    # Execution state defaults (normally set by batsman_parse_args + batsman_build)
    _batsman_os="debian12"
    _batsman_formatter="tap"
    _batsman_bats_args=()
    _batsman_explicit_files=0
    _batsman_test_timeout=""
    _batsman_report_dir=""
    _batsman_image_tag="test-project-test-debian12"
    _batsman_parallel=0
    _batsman_parallel_n=0
    _batsman_abort=0
    _batsman_clean=0
}

teardown() {
    batsman_teardown
}

# ---------------------------------------------------------------------------
# batsman_run_direct
# ---------------------------------------------------------------------------

@test "direct: docker run with correct image and formatter" {
    _batsman_bats_args=("test1.bats")
    run batsman_run_direct
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"test-project-test-debian12"* ]]
    [[ "$logged" == *"--formatter tap"* ]]
    [[ "$logged" == *"test1.bats"* ]]
}

@test "direct: passes timeout env when set" {
    _batsman_test_timeout="30"
    _batsman_bats_args=("test1.bats")
    run batsman_run_direct
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"-e BATS_TEST_TIMEOUT=30"* ]]
}

@test "direct: report volume mount when report-dir set" {
    _batsman_report_dir="$TEST_TMPDIR/reports"
    _batsman_bats_args=("test1.bats")
    run batsman_run_direct
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"-v "* ]]
    [[ "$logged" == *":/reports"* ]]
    [[ "$logged" == *"--report-formatter junit"* ]]
}

@test "direct: no timeout env when unset" {
    _batsman_test_timeout=""
    _batsman_bats_args=("test1.bats")
    run batsman_run_direct
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" != *"BATS_TEST_TIMEOUT"* ]]
}

# ---------------------------------------------------------------------------
# batsman_run_sequential
# ---------------------------------------------------------------------------

@test "sequential: includes BATSMAN_CONTAINER_TEST_PATH" {
    run batsman_run_sequential
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"/opt/tests"* ]]
}

@test "sequential: bats_args placed before test path" {
    _batsman_bats_args=("--filter" "mytest")
    run batsman_run_sequential
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"--filter mytest"* ]]
    [[ "$logged" == *"/opt/tests"* ]]
    # Verify order: filter keyword before test path
    local filter_pos path_pos
    filter_pos=$(echo "$logged" | grep -ob "filter" | head -1 | cut -d: -f1)
    path_pos=$(echo "$logged" | grep -ob "/opt/tests" | head -1 | cut -d: -f1)
    [ "$filter_pos" -lt "$path_pos" ]
}

@test "sequential: no bats_args branch runs correctly" {
    _batsman_bats_args=()
    run batsman_run_sequential
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"test-project-test-debian12"* ]]
    [[ "$logged" == *"/opt/tests"* ]]
    [[ "$logged" != *"--filter"* ]]
}

# ---------------------------------------------------------------------------
# batsman_run_parallel
# ---------------------------------------------------------------------------

@test "parallel: zero test files returns error" {
    _batsman_parallel_n=2
    run batsman_run_parallel
    [ "$status" -ne 0 ]
    [[ "$output" == *"No test files"* ]]
}

@test "parallel: named containers with correct pattern" {
    _batsman_parallel_n=2
    touch "$BATSMAN_TESTS_DIR/01-a.bats" "$BATSMAN_TESTS_DIR/02-b.bats"
    run batsman_run_parallel
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"--name test-project-debian12-"*"-g0"* ]]
    [[ "$logged" == *"--name test-project-debian12-"*"-g1"* ]]
}

@test "parallel: creates per-group report subdirectories" {
    _batsman_parallel_n=2
    _batsman_report_dir="$TEST_TMPDIR/reports"
    touch "$BATSMAN_TESTS_DIR/01-a.bats" "$BATSMAN_TESTS_DIR/02-b.bats"
    run batsman_run_parallel
    [ "$status" -eq 0 ]
    [ -d "$TEST_TMPDIR/reports/group-0" ]
    [ -d "$TEST_TMPDIR/reports/group-1" ]
}

@test "parallel: failed docker returns non-zero exit" {
    _batsman_parallel_n=1
    touch "$BATSMAN_TESTS_DIR/01-a.bats"
    DOCKER_EXIT_CODE=1
    run batsman_run_parallel
    [ "$status" -ne 0 ]
}

@test "parallel: TAP counting tallies ok/not-ok lines" {
    _batsman_parallel_n=2
    touch "$BATSMAN_TESTS_DIR/01-a.bats" "$BATSMAN_TESTS_DIR/02-b.bats"
    DOCKER_TAP_OUTPUT="ok 1 test one
not ok 2 test two
ok 3 test three"
    run batsman_run_parallel
    [ "$status" -eq 0 ]
    # 2 groups x (2 ok + 1 not-ok) = 6 tests, 2 failed
    [[ "$output" == *"6 tests"* ]]
    [[ "$output" == *"2 failed"* ]]
}
