#!/usr/bin/env bats
# 09-file-groups.bats — File-group distribution and JSON output tests
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
# shellcheck disable=SC2154,SC2034

load helpers/batsman-common

setup() {
    batsman_setup
    FILE_GROUPS="$BATSMAN_SCRIPTS/file-groups.sh"
    MOCK_DIR="$TEST_TMPDIR/bats-files"
    mkdir -p "$MOCK_DIR"
}

teardown() {
    batsman_teardown
}

# ---------------------------------------------------------------------------
# Helper: create numbered .bats files
# ---------------------------------------------------------------------------
_create_files() {
    local dir="$1"
    shift
    local name
    for name in "$@"; do
        touch "$dir/$name"
    done
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "file-groups: missing arguments prints usage and exits 1" {
    run bash "$FILE_GROUPS"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "file-groups: nonexistent directory exits 1" {
    run bash "$FILE_GROUPS" "/no/such/dir" 2 "/opt/tests" '["debian12"]'
    [ "$status" -eq 1 ]
    [[ "$output" == *"directory not found"* ]]
}

# ---------------------------------------------------------------------------
# Empty and minimal cases
# ---------------------------------------------------------------------------

@test "file-groups: empty directory still emits per-OS include (no group/files keys)" {
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12","rocky9"]'
    [ "$status" -eq 0 ]
    # 0 files → no group/files fields, but include array still has one entry per OS
    [[ "$output" == *'"os":"debian12"'* ]]
    [[ "$output" == *'"os":"rocky9"'* ]]
    [[ "$output" == *'"base_os":"debian12"'* ]]
    [[ "$output" != *'"group"'* ]]
    [[ "$output" != *'"files"'* ]]
}

@test "file-groups: single file caps to 1 group; group/files keys omitted (matrix.group falsy)" {
    _create_files "$MOCK_DIR" 01-only.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 4 "/opt/tests" '["debian12"]'
    [ "$status" -eq 0 ]
    # 1 file → cap at 1 group. num_groups<=1 path emits no group/files
    # so matrix.group stays falsy in concurrency / artifact-name expressions.
    local count
    count=$(echo "$output" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['include']))")
    [ "$count" -eq 1 ]
    [[ "$output" != *'"group"'* ]]
    [[ "$output" != *'"files"'* ]]
    [[ "$output" == *'"base_os":"debian12"'* ]]
}

@test "file-groups: num-groups=1 omits group/files (preserves v1.4.0 default-shape semantics)" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats 03-c.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 1 "/opt/tests" '["debian12"]'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"group"'* ]]
    [[ "$output" != *'"files"'* ]]
    [[ "$output" == *'"base_os":"debian12"'* ]]
}

# ---------------------------------------------------------------------------
# Round-robin distribution
# ---------------------------------------------------------------------------

@test "file-groups: 4 files / 2 groups distributes 2+2" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12"]'
    [ "$status" -eq 0 ]
    # Group 1: files 0,2 (01-a, 03-c); Group 2: files 1,3 (02-b, 04-d)
    local g1_files g2_files
    g1_files=$(echo "$output" | python3 -c "
import sys, json
for e in json.load(sys.stdin)['include']:
    if e['group'] == 1: print(e['files'])
")
    g2_files=$(echo "$output" | python3 -c "
import sys, json
for e in json.load(sys.stdin)['include']:
    if e['group'] == 2: print(e['files'])
")
    [[ "$g1_files" == *"01-a.bats"* ]]
    [[ "$g1_files" == *"03-c.bats"* ]]
    [[ "$g2_files" == *"02-b.bats"* ]]
    [[ "$g2_files" == *"04-d.bats"* ]]
}

@test "file-groups: 5 files / 3 groups distributes 2+2+1" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats 05-e.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 3 "/opt/tests" '["debian12"]'
    [ "$status" -eq 0 ]
    local g1_count g2_count g3_count
    g1_count=$(echo "$output" | python3 -c "
import sys, json
for e in json.load(sys.stdin)['include']:
    if e['group'] == 1: print(len(e['files'].split()))
")
    g2_count=$(echo "$output" | python3 -c "
import sys, json
for e in json.load(sys.stdin)['include']:
    if e['group'] == 2: print(len(e['files'].split()))
")
    g3_count=$(echo "$output" | python3 -c "
import sys, json
for e in json.load(sys.stdin)['include']:
    if e['group'] == 3: print(len(e['files'].split()))
")
    [ "$g1_count" -eq 2 ]
    [ "$g2_count" -eq 2 ]
    [ "$g3_count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Group capping
# ---------------------------------------------------------------------------

@test "file-groups: groups capped at file count" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 10 "/opt/tests" '["debian12"]'
    [ "$status" -eq 0 ]
    # 2 files -> cap at 2 groups; 1 OS = 2 entries
    local count
    count=$(echo "$output" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['include']))")
    [ "$count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# OS x group cross-product
# ---------------------------------------------------------------------------

@test "file-groups: 2 OS x 2 groups produces 4 matrix entries" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12","rocky9"]'
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['include']))")
    [ "$count" -eq 4 ]
    # Verify both OS appear
    [[ "$output" == *'"os":"debian12"'* ]]
    [[ "$output" == *'"os":"rocky9"'* ]]
}

@test "file-groups: 3 OS x 3 groups produces 9 matrix entries" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats 03-c.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 3 "/opt/tests" '["debian12","rocky9","centos7"]'
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['include']))")
    [ "$count" -eq 9 ]
}

# ---------------------------------------------------------------------------
# JSON structure validation
# ---------------------------------------------------------------------------

@test "file-groups: output is valid JSON" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12"]'
    [ "$status" -eq 0 ]
    echo "$output" | python3 -m json.tool > /dev/null
}

@test "file-groups: each entry has os, group, and files keys" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12"]'
    [ "$status" -eq 0 ]
    local valid
    valid=$(echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)['include']
ok = all('os' in e and 'group' in e and 'files' in e for e in data)
print('yes' if ok else 'no')
")
    [ "$valid" = "yes" ]
}

# ---------------------------------------------------------------------------
# Container path construction
# ---------------------------------------------------------------------------

@test "file-groups: files use container-test-path prefix (num-groups>1)" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/custom/path" '["debian12"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"/custom/path/01-a.bats"* ]]
    [[ "$output" == *"/custom/path/02-b.bats"* ]]
}

# ---------------------------------------------------------------------------
# File discovery (only numbered files)
# ---------------------------------------------------------------------------

@test "file-groups: ignores non-numbered files" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats helpers.bats setup.bash
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12"]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"01-a.bats"* ]]
    [[ "$output" == *"02-b.bats"* ]]
    [[ "$output" != *"helpers.bats"* ]]
    [[ "$output" != *"setup.bash"* ]]
}

# ---------------------------------------------------------------------------
# Filename charset validation (M3+M4 — security/regression hardening)
# ---------------------------------------------------------------------------

@test "file-groups: rejects filename with space (exit 2)" {
    _create_files "$MOCK_DIR" 01-ok.bats
    touch "$MOCK_DIR/02-bad name.bats"
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12"]'
    [ "$status" -eq 2 ]
    [[ "$output" == *"violates charset"* ]]
}

@test "file-groups: rejects filename with double-quote (JSON-injection guard)" {
    _create_files "$MOCK_DIR" 01-ok.bats
    touch "$MOCK_DIR/02-bad\"name.bats"
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12"]'
    [ "$status" -eq 2 ]
    [[ "$output" == *"violates charset"* ]]
}

@test "file-groups: rejects filename with command-substitution (shell-injection guard)" {
    _create_files "$MOCK_DIR" 01-ok.bats
    touch "$MOCK_DIR/02-bad\$(rm).bats"
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12"]'
    [ "$status" -eq 2 ]
}

@test "file-groups: non-integer num-groups exits 1" {
    _create_files "$MOCK_DIR" 01-a.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" "abc" "/opt/tests" '["debian12"]'
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-negative integer"* ]]
}

@test "file-groups: rejects malformed os name in os-matrix (charset guard)" {
    _create_files "$MOCK_DIR" 01-a.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12","bad;rm"]'
    [ "$status" -eq 2 ]
    [[ "$output" == *"os name"* ]]
}

# ---------------------------------------------------------------------------
# base-os-map (M2 — CI variant resolution)
# ---------------------------------------------------------------------------

@test "file-groups: identity base_os when base-os-map empty" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["debian12","rocky9"]'
    [ "$status" -eq 0 ]
    # base_os == os when no mapping
    [[ "$output" == *'"os":"debian12","base_os":"debian12"'* ]]
    [[ "$output" == *'"os":"rocky9","base_os":"rocky9"'* ]]
}

@test "file-groups: variant resolves to base via base-os-map" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["yara-x","debian12"]' "yara-x=debian12"
    [ "$status" -eq 0 ]
    # yara-x maps to debian12; debian12 stays identity
    [[ "$output" == *'"os":"yara-x","base_os":"debian12"'* ]]
    [[ "$output" == *'"os":"debian12","base_os":"debian12"'* ]]
}

@test "file-groups: multi-mapping base-os-map resolves each variant independently" {
    _create_files "$MOCK_DIR" 01-a.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 1 "/opt/tests" '["yara-x","modsec","centos7"]' \
        "yara-x=debian12 modsec=rocky9"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"os":"yara-x","base_os":"debian12"'* ]]
    [[ "$output" == *'"os":"modsec","base_os":"rocky9"'* ]]
    [[ "$output" == *'"os":"centos7","base_os":"centos7"'* ]]
}

@test "file-groups: rejects base-os-map entry with space-in-value (charset gate)" {
    _create_files "$MOCK_DIR" 01-a.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 1 "/opt/tests" '["debian12"]' "yara-x=debian 12"
    [ "$status" -eq 2 ]
    [[ "$output" == *"violates charset"* ]]
}

@test "file-groups: rejects base-os-map entry without = separator" {
    _create_files "$MOCK_DIR" 01-a.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 1 "/opt/tests" '["debian12"]' "yara-x"
    [ "$status" -eq 2 ]
    [[ "$output" == *"violates charset"* ]]
}

@test "file-groups: base_os present in num-groups>1 entries too" {
    _create_files "$MOCK_DIR" 01-a.bats 02-b.bats 03-c.bats 04-d.bats
    run bash "$FILE_GROUPS" "$MOCK_DIR" 2 "/opt/tests" '["yara-x"]' "yara-x=debian12"
    [ "$status" -eq 0 ]
    # Both groups for yara-x carry base_os=debian12
    local count
    count=$(echo "$output" | python3 -c "
import sys, json
m = json.load(sys.stdin)['include']
print(sum(1 for e in m if e.get('base_os') == 'debian12' and 'group' in e))
")
    [ "$count" -eq 2 ]
}
