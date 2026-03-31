#!/usr/bin/env bash
# batsman — file-groups.sh
# Round-robin file distribution for CI file-group splitting
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
#
# Discovers numbered .bats files in a test directory, distributes them
# round-robin into N groups, and outputs a GitHub Actions strategy.matrix
# JSON object crossing os-matrix x groups.
#
# Usage:
#   file-groups.sh <test-source-dir> <num-groups> <container-test-path> <os-matrix-json>
#
# Arguments:
#   test-source-dir     Host path containing [0-9]*.bats files
#   num-groups          Number of groups to distribute into (capped at file count)
#   container-test-path Container-side path prefix for file paths in output
#   os-matrix-json      JSON array of OS targets, e.g. '["debian12","rocky9"]'
#
# Output (stdout):
#   {"include":[{"os":"debian12","group":1,"files":"/opt/tests/01-a.bats /opt/tests/05-e.bats"},...]}}
#
# Exit codes:
#   0  Success
#   1  Invalid arguments or no test directory

set -eo pipefail

test_source_dir="$1"
num_groups="$2"
container_test_path="$3"
os_matrix_json="$4"

if [ -z "$test_source_dir" ] || [ -z "$num_groups" ] || [ -z "$container_test_path" ] || [ -z "$os_matrix_json" ]; then
    echo "Usage: file-groups.sh <test-source-dir> <num-groups> <container-test-path> <os-matrix-json>" >&2
    exit 1
fi

if [ ! -d "$test_source_dir" ]; then
    echo "file-groups.sh: directory not found: $test_source_dir" >&2
    exit 1
fi

# Discover test files (sorted by name — numbered convention ensures order)
files=()
while IFS= read -r f; do
    files+=("$(basename "$f")")
done < <(find "$test_source_dir" -maxdepth 1 -name '[0-9]*.bats' -print | sort)

num_files=${#files[@]}
if [ "$num_files" -eq 0 ]; then
    echo '{"include":[]}'
    exit 0
fi

# Cap groups at file count (no empty jobs)
[ "$num_groups" -gt "$num_files" ] && num_groups="$num_files"

# Round-robin distribute files into groups
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

# Parse os-matrix JSON: strip brackets/quotes, split by comma
# Expects JSON array of simple strings without spaces — no jq dependency required
os_list=$(echo "$os_matrix_json" | tr -d '[]" ' | tr ',' ' ')

# Build GHA matrix JSON: os x group cross-product
printf '{"include":['
first=1
for os in $os_list; do
    for (( g=0; g<num_groups; g++ )); do
        [ "$first" -eq 0 ] && printf ','
        printf '{"os":"%s","group":%d,"files":"%s"}' "$os" "$((g+1))" "${group_files[g]}"
        first=0
    done
done
printf ']}\n'
