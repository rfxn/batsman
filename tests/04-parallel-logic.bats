#!/usr/bin/env bats
# 04-parallel-logic.bats — Parallel distribution and file discovery tests
# shellcheck disable=SC2154,SC2034

load helpers/batsman-common

setup() {
    batsman_setup
    # Create a mock tests directory for file discovery
    MOCK_TESTS_DIR="$TEST_TMPDIR/mock-tests"
    mkdir -p "$MOCK_TESTS_DIR"
}

teardown() {
    batsman_teardown
}

# ---------------------------------------------------------------------------
# Helper: create numbered .bats files
# ---------------------------------------------------------------------------
_create_bats_files() {
    local dir="$1"
    shift
    local name
    for name in "$@"; do
        touch "$dir/$name"
    done
}

# ---------------------------------------------------------------------------
# Helper: replicate round-robin distribution from batsman_run_parallel()
# This is the exact algorithm from the production code.
# ---------------------------------------------------------------------------
_round_robin() {
    local test_dir="$1"
    local num_groups="$2"

    # Discover files (same find|sort as production)
    local test_files=()
    local f
    while IFS= read -r f; do
        test_files+=("$f")
    done < <(find "$test_dir" -maxdepth 1 -name '[0-9]*.bats' -print | sort)

    local num_files=${#test_files[@]}
    [ "$num_files" -eq 0 ] && return 0

    # Cap groups
    [ "$num_groups" -gt "$num_files" ] && num_groups="$num_files"

    # Round-robin
    local -a group_files
    local i
    for i in $(seq 0 $(( num_groups - 1 ))); do
        group_files[i]=""
    done

    local group fname
    for i in $(seq 0 $(( num_files - 1 ))); do
        group=$(( i % num_groups ))
        fname="$(basename "${test_files[$i]}")"
        if [ -z "${group_files[group]}" ]; then
            group_files[group]="$fname"
        else
            group_files[group]="${group_files[group]} $fname"
        fi
    done

    # Output: one line per group
    for i in $(seq 0 $(( num_groups - 1 ))); do
        echo "${group_files[$i]}"
    done
}

# ---------------------------------------------------------------------------
# Group count
# ---------------------------------------------------------------------------

@test "parallel: explicit N sets group count" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats
    run _round_robin "$MOCK_TESTS_DIR" 2
    [ "$status" -eq 0 ]
    # 2 groups expected
    local line_count
    line_count=$(echo "$output" | wc -l)
    [ "$line_count" -eq 2 ]
}

@test "parallel: groups capped at number of files" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-a.bats 02-b.bats
    run _round_robin "$MOCK_TESTS_DIR" 10
    [ "$status" -eq 0 ]
    # Only 2 files → cap at 2 groups
    local line_count
    line_count=$(echo "$output" | wc -l)
    [ "$line_count" -eq 2 ]
}

@test "parallel: single file caps to 1 group" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-a.bats
    run _round_robin "$MOCK_TESTS_DIR" 4
    [ "$status" -eq 0 ]
    local line_count
    line_count=$(echo "$output" | wc -l)
    [ "$line_count" -eq 1 ]
}

@test "parallel: fewer groups than files leaves groups uncapped" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats
    run _round_robin "$MOCK_TESTS_DIR" 3
    [ "$status" -eq 0 ]
    local line_count
    line_count=$(echo "$output" | wc -l)
    [ "$line_count" -eq 3 ]
}

# ---------------------------------------------------------------------------
# Round-robin distribution
# ---------------------------------------------------------------------------

@test "round-robin: 4 files / 2 groups → 2+2" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats
    run _round_robin "$MOCK_TESTS_DIR" 2
    [ "$status" -eq 0 ]
    local -a lines
    mapfile -t lines <<< "$output"
    # Group 0: files 0,2 → 01-a 03-c
    [[ "${lines[0]}" == *"01-a.bats"* ]]
    [[ "${lines[0]}" == *"03-c.bats"* ]]
    # Group 1: files 1,3 → 02-b 04-d
    [[ "${lines[1]}" == *"02-b.bats"* ]]
    [[ "${lines[1]}" == *"04-d.bats"* ]]
}

@test "round-robin: 5 files / 3 groups → 2+2+1" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats 05-e.bats
    run _round_robin "$MOCK_TESTS_DIR" 3
    [ "$status" -eq 0 ]
    local -a lines
    mapfile -t lines <<< "$output"
    # Group 0: 01-a 04-d (indices 0,3)
    local g0_count g1_count g2_count
    g0_count=$(echo "${lines[0]}" | wc -w)
    g1_count=$(echo "${lines[1]}" | wc -w)
    g2_count=$(echo "${lines[2]}" | wc -w)
    [ "$g0_count" -eq 2 ]
    [ "$g1_count" -eq 2 ]
    [ "$g2_count" -eq 1 ]
}

@test "round-robin: 7 files / 3 groups → 3+2+2" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats \
        05-e.bats 06-f.bats 07-g.bats
    run _round_robin "$MOCK_TESTS_DIR" 3
    [ "$status" -eq 0 ]
    local -a lines
    mapfile -t lines <<< "$output"
    local g0_count g1_count g2_count
    g0_count=$(echo "${lines[0]}" | wc -w)
    g1_count=$(echo "${lines[1]}" | wc -w)
    g2_count=$(echo "${lines[2]}" | wc -w)
    [ "$g0_count" -eq 3 ]
    [ "$g1_count" -eq 2 ]
    [ "$g2_count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

@test "file discovery: finds numbered .bats files" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-first.bats 02-second.bats 03-third.bats
    local count
    count=$(find "$MOCK_TESTS_DIR" -maxdepth 1 -name '[0-9]*.bats' -print | wc -l)
    [ "$count" -eq 3 ]
}

@test "file discovery: ignores non-numbered files" {
    _create_bats_files "$MOCK_TESTS_DIR" 01-first.bats helpers.bats setup.bash
    local count
    count=$(find "$MOCK_TESTS_DIR" -maxdepth 1 -name '[0-9]*.bats' -print | wc -l)
    [ "$count" -eq 1 ]
}

@test "file discovery: files sorted in order" {
    _create_bats_files "$MOCK_TESTS_DIR" 03-third.bats 01-first.bats 02-second.bats
    local -a found
    while IFS= read -r f; do
        found+=("$(basename "$f")")
    done < <(find "$MOCK_TESTS_DIR" -maxdepth 1 -name '[0-9]*.bats' -print | sort)
    [ "${found[0]}" = "01-first.bats" ]
    [ "${found[1]}" = "02-second.bats" ]
    [ "${found[2]}" = "03-third.bats" ]
}

@test "file discovery: empty directory returns 0 files" {
    local empty_dir="$TEST_TMPDIR/empty"
    mkdir -p "$empty_dir"
    local count
    count=$(find "$empty_dir" -maxdepth 1 -name '[0-9]*.bats' -print | wc -l)
    [ "$count" -eq 0 ]
}
