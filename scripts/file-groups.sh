#!/usr/bin/env bash
# batsman — file-groups.sh
# Round-robin file distribution + base-OS resolution for CI matrix expansion
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
#
# Discovers numbered .bats files in a test directory, distributes them
# round-robin into N groups, and outputs a GitHub Actions strategy.matrix
# JSON object crossing os-matrix x groups, with each entry carrying a
# resolved base_os derived from BATSMAN_BASE_OS_MAP.
#
# Output shape (always an include array; never the simple {"os":[...]} form):
#   num-groups <= 1 → [{"os":"X","base_os":"Y"},...]
#                     (group/files omitted so matrix.group stays falsy)
#   num-groups >  1 → [{"os":"X","base_os":"Y","group":N,"files":"..."},...]
#
# Filename charset: only files matching ^[0-9][a-zA-Z0-9._-]*\.bats$ are
# accepted — protects downstream JSON construction and unquoted shell
# expansion (workflow `$TEST_TARGET`, in-container `bats <files>`) from
# space/quote/metachar injection. Non-conforming filenames cause exit 2.
#
# Usage:
#   file-groups.sh <test-source-dir> <num-groups> <container-test-path> \
#                  <os-matrix-json> [base-os-map]
#
# Arguments:
#   test-source-dir     Host path containing [0-9]*.bats files
#   num-groups          Number of groups to distribute into (capped at file count)
#   container-test-path Container-side path prefix for file paths in output
#   os-matrix-json      JSON array of OS targets, e.g. '["debian12","rocky9"]'
#   base-os-map         (optional) Space-separated key=value variant→base
#                       mappings, e.g. "yara-x=debian12 modsec=rocky9".
#                       Identity is applied for any OS without a mapping.
#
# Exit codes:
#   0  Success
#   1  Invalid arguments or no test directory
#   2  Filename charset violation (non-portable .bats filename detected)

set -eo pipefail

test_source_dir="$1"
num_groups="$2"
container_test_path="$3"
os_matrix_json="$4"
base_os_map="${5:-}"

if [ -z "$test_source_dir" ] || [ -z "$num_groups" ] || [ -z "$container_test_path" ] || [ -z "$os_matrix_json" ]; then
    echo "Usage: file-groups.sh <test-source-dir> <num-groups> <container-test-path> <os-matrix-json> [base-os-map]" >&2
    exit 1
fi

if ! [[ "$num_groups" =~ ^[0-9]+$ ]]; then
    echo "file-groups.sh: num-groups must be a non-negative integer, got '$num_groups'" >&2
    exit 1
fi

if [ ! -d "$test_source_dir" ]; then
    echo "file-groups.sh: directory not found: $test_source_dir" >&2
    exit 1
fi

# Filename charset: numbered prefix + portable chars only
fname_pattern='^[0-9][a-zA-Z0-9._-]*\.bats$'

# Validate base-os-map entries up-front (charset symmetric with os_pattern).
# `for entry in $var` IFS-splits on whitespace, so any space inside a value
# would silently corrupt parsing — fail closed instead of yielding wrong
# build targets downstream.
map_entry_pattern='^[a-zA-Z0-9._-]+=[a-zA-Z0-9._-]+$'
for _entry in $base_os_map; do
    if ! [[ "$_entry" =~ $map_entry_pattern ]]; then
        echo "file-groups.sh: base-os-map entry '$_entry' violates charset $map_entry_pattern" >&2
        exit 2
    fi
done
unset _entry

# Resolve variant OS to base via space-separated key=value map (identity fallback)
_resolve_base_os() {
    local os="$1"
    local entry
    for entry in $base_os_map; do
        if [ "${entry%%=*}" = "$os" ]; then
            printf '%s\n' "${entry#*=}"
            return 0
        fi
    done
    printf '%s\n' "$os"
}

# Discover test files (sorted by name — numbered convention ensures order)
files=()
while IFS= read -r f; do
    fname="$(basename "$f")"
    if ! [[ "$fname" =~ $fname_pattern ]]; then
        echo "file-groups.sh: filename '$fname' violates charset $fname_pattern — refusing to emit unsafe matrix" >&2
        exit 2
    fi
    files+=("$fname")
done < <(find "$test_source_dir" -maxdepth 1 -name '[0-9]*.bats' -print | sort)

num_files=${#files[@]}

# Parse os-matrix JSON: strip brackets/quotes, split by comma
# Expects JSON array of simple strings without spaces — no jq dependency required
os_list=$(echo "$os_matrix_json" | tr -d '[]" ' | tr ',' ' ')

# OS-name validation (defense for the unquoted matrix.os usage downstream)
os_pattern='^[a-zA-Z0-9._-]+$'
for os in $os_list; do
    if ! [[ "$os" =~ $os_pattern ]]; then
        echo "file-groups.sh: os name '$os' violates charset $os_pattern" >&2
        exit 2
    fi
done

# Emit per-OS include array with no group/files keys (preserves matrix.group
# falsy semantics for concurrency/artifact-name expressions). Used by both
# the no-files short-circuit and the num_groups<=1 path.
_emit_os_only_include() {
    local first=1 os base_os
    printf '{"include":['
    for os in $os_list; do
        [ "$first" -eq 0 ] && printf ','
        base_os="$(_resolve_base_os "$os")"
        printf '{"os":"%s","base_os":"%s"}' "$os" "$base_os"
        first=0
    done
    printf ']}\n'
}

# No files: emit per-OS only (no group/files keys)
if [ "$num_files" -eq 0 ]; then
    _emit_os_only_include
    exit 0
fi

# Cap groups at file count (no empty jobs)
[ "$num_groups" -gt "$num_files" ] && num_groups="$num_files"

# num-groups <= 1: emit per-OS only (matrix.group stays falsy)
if [ "$num_groups" -le 1 ]; then
    _emit_os_only_include
    exit 0
fi

# num-groups > 1: round-robin distribute files into groups
group_files=()
for (( i=0; i<num_groups; i++ )); do
    group_files[i]=""
done

for (( i=0; i<num_files; i++ )); do
    group=$(( i % num_groups ))
    path="${container_test_path}/${files[$i]}"
    if [ -z "${group_files[group]}" ]; then
        group_files[group]="$path"
    else
        group_files[group]="${group_files[group]} $path"
    fi
done

# Build GHA matrix JSON: os x group cross-product, each entry with base_os
printf '{"include":['
first=1
for os in $os_list; do
    base_os="$(_resolve_base_os "$os")"
    for (( g=0; g<num_groups; g++ )); do
        [ "$first" -eq 0 ] && printf ','
        printf '{"os":"%s","base_os":"%s","group":%d,"files":"%s"}' \
            "$os" "$base_os" "$((g+1))" "${group_files[g]}"
        first=0
    done
done
printf ']}\n'
