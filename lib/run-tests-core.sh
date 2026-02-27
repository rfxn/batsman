#!/bin/bash
# batsman — run-tests-core.sh
# Parallel test orchestration engine (sourced library)
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
#
# This file is sourced by project run-tests.sh wrappers.
# Do not execute directly.
#
# Required variables (set before sourcing):
#   BATSMAN_PROJECT            Project name (image tag prefix, container naming)
#   BATSMAN_PROJECT_DIR        Project root (Docker build context)
#   BATSMAN_TESTS_DIR          Directory containing .bats files
#   BATSMAN_INFRA_DIR          Path to batsman submodule (tests/infra)
#   BATSMAN_CONTAINER_TEST_PATH  Test directory path inside container
#   BATSMAN_SUPPORTED_OS       Space-separated list of supported OS targets
#
# Optional variables:
#   BATSMAN_DOCKER_FLAGS       Extra docker run flags (e.g., "--privileged")
#   BATSMAN_DEFAULT_OS         Default OS when --os omitted (default: debian12)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: run-tests-core.sh must be sourced, not executed directly." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Internal state (set by batsman_parse_args)
# ---------------------------------------------------------------------------
_batsman_os=""
_batsman_parallel=0
_batsman_parallel_n=0
_batsman_formatter="tap"
_batsman_bats_args=()
_batsman_explicit_files=0
_batsman_image_tag=""

# ---------------------------------------------------------------------------
# batsman_usage — Print help text parameterized by project vars
# ---------------------------------------------------------------------------
batsman_usage() {
    cat <<EOF
Usage: $0 [--os OS] [--parallel [N]] [--filter PATTERN] [--formatter FMT] [--help] [BATS_ARGS...]

Options:
  --os OS           Target OS (default: ${BATSMAN_DEFAULT_OS:-debian12})
  --parallel [N]    Run test files in N parallel containers (default: nproc*2)
  --filter PATTERN  Filter tests by name (passed to bats --filter)
  --formatter FMT   BATS output formatter: tap (default), pretty
  --help            Show this help

Any remaining arguments are passed directly to bats.
Specific test file paths bypass parallel mode.

Supported OS targets:
  ${BATSMAN_SUPPORTED_OS:-debian12}
EOF
    exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# batsman_parse_args — Parse CLI arguments
# ---------------------------------------------------------------------------
batsman_parse_args() {
    _batsman_os="${BATSMAN_DEFAULT_OS:-debian12}"
    _batsman_parallel=0
    _batsman_parallel_n=0
    _batsman_formatter="tap"
    _batsman_bats_args=()
    _batsman_explicit_files=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --os)
                shift
                _batsman_os="$1"
                ;;
            --parallel)
                _batsman_parallel=1
                # Check if next arg is a number (optional N)
                if [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    _batsman_parallel_n="$2"
                    shift
                fi
                ;;
            --filter)
                shift
                _batsman_bats_args+=("--filter" "$1")
                ;;
            --formatter)
                shift
                _batsman_formatter="$1"
                ;;
            --help|-h)
                batsman_usage 0
                ;;
            *)
                _batsman_bats_args+=("$1")
                _batsman_explicit_files=1
                ;;
        esac
        shift
    done

    # Validate OS target
    local valid=0
    local os_entry
    for os_entry in $BATSMAN_SUPPORTED_OS; do
        if [ "$os_entry" = "$_batsman_os" ]; then
            valid=1
            break
        fi
    done
    if [ "$valid" -eq 0 ]; then
        echo "Unsupported OS: $_batsman_os" >&2
        echo "Supported: $BATSMAN_SUPPORTED_OS" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# batsman_build — Two-phase Docker build (base from infra, project from tests/)
# ---------------------------------------------------------------------------
batsman_build() {
    local base_dockerfile="$BATSMAN_INFRA_DIR/dockerfiles/Dockerfile.${_batsman_os}"
    local base_tag="${BATSMAN_PROJECT}-base-${_batsman_os}"

    # Phase 1: Build base image from batsman Dockerfiles
    if [ ! -f "$base_dockerfile" ]; then
        echo "Error: base Dockerfile not found: $base_dockerfile" >&2
        return 1
    fi
    echo "=== Building base image (${_batsman_os}) ==="
    docker build -f "$base_dockerfile" -t "$base_tag" "$BATSMAN_INFRA_DIR"

    # Phase 2: Build project image FROM base
    local project_dockerfile
    if [ "$_batsman_os" = "debian12" ]; then
        project_dockerfile="$BATSMAN_TESTS_DIR/Dockerfile"
    else
        project_dockerfile="$BATSMAN_TESTS_DIR/Dockerfile.${_batsman_os}"
    fi

    if [ ! -f "$project_dockerfile" ]; then
        echo "Error: project Dockerfile not found: $project_dockerfile" >&2
        return 1
    fi

    _batsman_image_tag="${BATSMAN_PROJECT}-test-${_batsman_os}"
    echo "=== Building project image (${BATSMAN_PROJECT}/${_batsman_os}) ==="
    docker build --build-arg "BASE_IMAGE=$base_tag" \
        -f "$project_dockerfile" -t "$_batsman_image_tag" "$BATSMAN_PROJECT_DIR"
}

# ---------------------------------------------------------------------------
# batsman_run_direct — Run explicit test file paths (no parallel)
# ---------------------------------------------------------------------------
batsman_run_direct() {
    echo "=== Running tests: ${_batsman_os} ==="
    # shellcheck disable=SC2086
    docker run --rm ${BATSMAN_DOCKER_FLAGS:-} "$_batsman_image_tag" \
        bats --formatter "$_batsman_formatter" "${_batsman_bats_args[@]}"
}

# ---------------------------------------------------------------------------
# batsman_run_sequential — Single container, all tests
# ---------------------------------------------------------------------------
batsman_run_sequential() {
    echo "=== Running tests: ${_batsman_os} ==="
    if [ ${#_batsman_bats_args[@]} -gt 0 ]; then
        # bats_args may contain --filter; append test path
        # shellcheck disable=SC2086
        docker run --rm ${BATSMAN_DOCKER_FLAGS:-} "$_batsman_image_tag" \
            bats --formatter "$_batsman_formatter" \
            "${_batsman_bats_args[@]}" "$BATSMAN_CONTAINER_TEST_PATH"
    else
        # shellcheck disable=SC2086
        docker run --rm ${BATSMAN_DOCKER_FLAGS:-} "$_batsman_image_tag" \
            bats --formatter "$_batsman_formatter" "$BATSMAN_CONTAINER_TEST_PATH"
    fi
}

# ---------------------------------------------------------------------------
# batsman_run_parallel — Round-robin into N groups, TAP aggregation
# ---------------------------------------------------------------------------
batsman_run_parallel() {
    # Determine number of parallel groups
    local num_groups
    if [ "$_batsman_parallel_n" -gt 0 ]; then
        num_groups="$_batsman_parallel_n"
    else
        num_groups=$(( $(nproc) * 2 ))
        [ "$num_groups" -lt 1 ] && num_groups=1
    fi

    # Discover test files (sorted by name — numbered convention ensures order)
    local test_files=()
    local f
    while IFS= read -r f; do
        test_files+=("$f")
    done < <(find "$BATSMAN_TESTS_DIR" -maxdepth 1 -name '[0-9]*.bats' -print | sort)

    local num_files=${#test_files[@]}
    if [ "$num_files" -eq 0 ]; then
        echo "No test files found in $BATSMAN_TESTS_DIR" >&2
        return 1
    fi

    # Cap groups at number of files
    [ "$num_groups" -gt "$num_files" ] && num_groups="$num_files"

    # Round-robin distribute files into groups
    local -a group_files
    local i
    for i in $(seq 0 $(( num_groups - 1 ))); do
        group_files[i]=""
    done

    local group fname container_path
    for i in $(seq 0 $(( num_files - 1 ))); do
        group=$(( i % num_groups ))
        fname="$(basename "${test_files[$i]}")"
        container_path="${BATSMAN_CONTAINER_TEST_PATH}/$fname"
        if [ -z "${group_files[group]}" ]; then
            group_files[group]="$container_path"
        else
            group_files[group]="${group_files[group]} $container_path"
        fi
    done

    # Create temp dir for output
    local tmpdir_par
    tmpdir_par="$(mktemp -d)"
    local run_id="$$"

    # Cleanup trap: remove named containers and temp dir on interrupt/exit
    _batsman_cleanup() {
        for i in $(seq 0 $(( num_groups - 1 ))); do
            docker rm -f "${BATSMAN_PROJECT}-${_batsman_os}-${run_id}-g${i}" >/dev/null 2>&1 || true
        done
        rm -rf "$tmpdir_par"
    }
    trap _batsman_cleanup EXIT INT TERM

    echo "=== Running tests: ${_batsman_os} (parallel: ${num_groups} groups, ${num_files} files) ==="
    local start_time=$SECONDS

    # Launch named containers in parallel
    local -a pids
    for i in $(seq 0 $(( num_groups - 1 ))); do
        # shellcheck disable=SC2086
        docker run --rm ${BATSMAN_DOCKER_FLAGS:-} \
            --name "${BATSMAN_PROJECT}-${_batsman_os}-${run_id}-g${i}" \
            "$_batsman_image_tag" \
            bats --formatter tap "${_batsman_bats_args[@]}" ${group_files[$i]} \
            > "$tmpdir_par/group-$i.tap" 2>&1 &
        pids+=($!)
    done

    # Wait for all containers, collect exit codes
    local failed_groups=0
    local -a exit_codes
    for i in $(seq 0 $(( num_groups - 1 ))); do
        if wait "${pids[$i]}"; then
            exit_codes[i]=0
        else
            exit_codes[i]=1
            failed_groups=$(( failed_groups + 1 ))
        fi
    done

    local elapsed=$(( SECONDS - start_time ))

    # Display output with group headers
    local total_tests=0
    local total_pass=0
    local total_fail=0
    local short_names status name line
    for i in $(seq 0 $(( num_groups - 1 ))); do
        # Build short file list for header
        short_names=""
        # shellcheck disable=SC2086
        for f in ${group_files[$i]}; do
            name="$(basename "$f" .bats)"
            if [ -z "$short_names" ]; then
                short_names="$name"
            else
                short_names="$short_names $name"
            fi
        done

        status="PASS"
        [ "${exit_codes[$i]}" -ne 0 ] && status="FAIL"

        echo ""
        echo "=== Group $((i+1))/$num_groups [$status]: $short_names ==="
        cat "$tmpdir_par/group-$i.tap"

        # Count tests from TAP output
        while IFS= read -r line; do
            case "$line" in
                ok\ *)
                    total_tests=$(( total_tests + 1 ))
                    total_pass=$(( total_pass + 1 ))
                    ;;
                not\ ok\ *)
                    total_tests=$(( total_tests + 1 ))
                    total_fail=$(( total_fail + 1 ))
                    ;;
            esac
        done < "$tmpdir_par/group-$i.tap"
    done

    echo ""
    local passed_groups=$(( num_groups - failed_groups ))
    echo "=== Results: $passed_groups/$num_groups groups passed ($total_tests tests, $total_fail failed) in ${elapsed}s ==="

    # Cleanup is handled by trap; reset it
    trap - EXIT INT TERM
    _batsman_cleanup

    [ "$failed_groups" -gt 0 ] && return 1
    return 0
}

# ---------------------------------------------------------------------------
# batsman_run — Main entry point: parse → build → execute
# ---------------------------------------------------------------------------
batsman_run() {
    # Validate required variables
    local missing=0
    local var
    for var in BATSMAN_PROJECT BATSMAN_PROJECT_DIR BATSMAN_TESTS_DIR \
               BATSMAN_INFRA_DIR BATSMAN_CONTAINER_TEST_PATH BATSMAN_SUPPORTED_OS; do
        if [ -z "${!var:-}" ]; then
            echo "Error: required variable $var is not set" >&2
            missing=1
        fi
    done
    [ "$missing" -eq 1 ] && return 1

    batsman_parse_args "$@"
    batsman_build

    if [ "$_batsman_explicit_files" -eq 1 ]; then
        batsman_run_direct
    elif [ "$_batsman_parallel" -eq 0 ]; then
        batsman_run_sequential
    else
        batsman_run_parallel
    fi
}
