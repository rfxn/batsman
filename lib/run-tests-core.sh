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
#   BATSMAN_BASE_OS_MAP        Variant→base OS mappings (e.g., "yara-x=debian12")
#   BATSMAN_TEST_TIMEOUT       Per-test timeout in seconds (passed as BATS_TEST_TIMEOUT)
#   BATSMAN_REPORT_DIR         Host directory for JUnit XML reports (passed as --report-dir)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: run-tests-core.sh must be sourced, not executed directly." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
BATSMAN_VERSION="1.1.0"

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
_batsman_test_timeout=""
_batsman_abort=0
_batsman_report_dir=""
_batsman_clean=0
_batsman_done=0

# ---------------------------------------------------------------------------
# batsman_usage — Print help text parameterized by project vars
# ---------------------------------------------------------------------------
batsman_usage() {
    cat <<EOF
batsman $BATSMAN_VERSION — test orchestration engine

Usage: $0 [OPTIONS] [BATS_ARGS...]

Options:
  --os OS           Target OS (default: ${BATSMAN_DEFAULT_OS:-debian12})
  --parallel [N]    Run test files in N parallel containers (default: nproc;
                    0 = auto-detect). Forces tap formatter for aggregation.
  --filter PATTERN  Filter tests by name (passed to bats --filter)
  --filter-tags TAG Filter tests by tag (comma-separated, ! to negate)
  --formatter FMT   BATS output formatter: tap (default), pretty
                    Ignored in --parallel mode (tap required for aggregation)
  --timeout SECS    Per-test timeout in seconds (overrides BATSMAN_TEST_TIMEOUT)
  --abort           Stop on first test failure (requires BATS 1.13.0+)
  --report-dir DIR  Write JUnit XML reports to DIR (overrides BATSMAN_REPORT_DIR)
  --clean           Remove project images for the target OS after test run
  --version         Show batsman version and exit
  --help, -h        Show this help

Any remaining arguments are passed directly to bats.
Specific test file paths bypass parallel mode.
In parallel mode, --abort applies per-group (each container aborts independently).
JUnit reports: sequential/direct produce DIR/report.xml; parallel produces
DIR/group-N/report.xml per group.

Supported OS targets:
  ${BATSMAN_SUPPORTED_OS:-debian12}
EOF
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
    _batsman_test_timeout=""
    _batsman_abort=0
    _batsman_report_dir=""
    _batsman_clean=0
    _batsman_done=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --os)
                if [ $# -lt 2 ]; then
                    echo "Error: --os requires a value" >&2
                    return 1
                fi
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
                if [ $# -lt 2 ]; then
                    echo "Error: --filter requires a value" >&2
                    return 1
                fi
                shift
                _batsman_bats_args+=("--filter" "$1")
                ;;
            --filter-tags)
                if [ $# -lt 2 ]; then
                    echo "Error: --filter-tags requires a value" >&2
                    return 1
                fi
                shift
                _batsman_bats_args+=("--filter-tags" "$1")
                ;;
            --formatter)
                if [ $# -lt 2 ]; then
                    echo "Error: --formatter requires a value" >&2
                    return 1
                fi
                shift
                _batsman_formatter="$1"
                ;;
            --timeout)
                if [ $# -lt 2 ]; then
                    echo "Error: --timeout requires a value" >&2
                    return 1
                fi
                shift
                _batsman_test_timeout="$1"
                ;;
            --abort)
                _batsman_abort=1
                ;;
            --report-dir)
                if [ $# -lt 2 ]; then
                    echo "Error: --report-dir requires a value" >&2
                    return 1
                fi
                shift
                _batsman_report_dir="$1"
                ;;
            --clean)
                _batsman_clean=1
                ;;
            --version)
                echo "batsman $BATSMAN_VERSION"
                _batsman_done=1
                return 0
                ;;
            --help|-h)
                batsman_usage
                _batsman_done=1
                return 0
                ;;
            --)
                shift
                while [ $# -gt 0 ]; do
                    _batsman_bats_args+=("$1")
                    _batsman_explicit_files=1
                    shift
                done
                break
                ;;
            *)
                if [[ "$1" == --* ]]; then
                    echo "Warning: unknown option '$1' -- passing to bats" >&2
                    _batsman_bats_args+=("$1")
                else
                    _batsman_bats_args+=("$1")
                    _batsman_explicit_files=1
                fi
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

    # Resolve test timeout: CLI --timeout takes precedence over env var
    if [ -z "$_batsman_test_timeout" ] && [ -n "${BATSMAN_TEST_TIMEOUT:-}" ]; then
        _batsman_test_timeout="$BATSMAN_TEST_TIMEOUT"
    fi

    # Resolve report dir: CLI --report-dir takes precedence over env var
    if [ -z "$_batsman_report_dir" ] && [ -n "${BATSMAN_REPORT_DIR:-}" ]; then
        _batsman_report_dir="$BATSMAN_REPORT_DIR"
    fi

    # Validate timeout is a positive integer (covers both CLI and env var)
    if [ -n "$_batsman_test_timeout" ]; then
        local _num_pat='^[0-9]+$'
        if ! [[ "$_batsman_test_timeout" =~ $_num_pat ]]; then
            echo "Error: timeout must be a positive integer, got '$_batsman_test_timeout'" >&2
            return 1
        fi
    fi

    # Prepend --abort to bats args if requested
    if [ "$_batsman_abort" -eq 1 ]; then
        _batsman_bats_args=("--abort" "${_batsman_bats_args[@]}")
    fi
}

# ---------------------------------------------------------------------------
# _batsman_resolve_base_os — Resolve variant OS to base OS via BATSMAN_BASE_OS_MAP
#
# Usage: _batsman_resolve_base_os <os_name>
# Outputs the resolved base OS name (identity if no mapping found).
# ---------------------------------------------------------------------------
_batsman_resolve_base_os() {
    local os="$1"
    local base_os="$os"
    if [ -n "${BATSMAN_BASE_OS_MAP:-}" ]; then
        local _map_entry
        for _map_entry in $BATSMAN_BASE_OS_MAP; do
            if [ "${_map_entry%%=*}" = "$os" ]; then
                base_os="${_map_entry#*=}"
                break
            fi
        done
    fi
    echo "$base_os"
}

# ---------------------------------------------------------------------------
# batsman_build — Two-phase Docker build (base from infra, project from tests/)
# ---------------------------------------------------------------------------
batsman_build() {
    # Resolve variant OS to base (e.g., yara-x -> debian12)
    local base_os
    base_os="$(_batsman_resolve_base_os "$_batsman_os")"

    local base_dockerfile="$BATSMAN_INFRA_DIR/dockerfiles/Dockerfile.${base_os}"
    local base_tag="${BATSMAN_PROJECT}-base-${base_os}"

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

    # Prune dangling images left by tag replacement (always safe, silent)
    docker image prune -f >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# batsman_clean — Remove project Docker images
#
# Modes:
#   (no args)        Remove base + test images for current OS, prune dangling
#   --all            Remove ALL base + test images for this project, prune dangling
#   --dangling-only  Prune dangling images only
# ---------------------------------------------------------------------------
# shellcheck disable=SC2120
batsman_clean() {
    local mode="current"
    if [ $# -gt 0 ]; then
        case "$1" in
            --all)          mode="all" ;;
            --dangling-only) mode="dangling" ;;
            *)
                echo "batsman_clean: unknown option: $1" >&2
                return 1
                ;;
        esac
    fi

    if [ "$mode" = "dangling" ]; then
        echo "=== Pruning dangling images ==="
        docker image prune -f
        return 0
    fi

    if [ "$mode" = "all" ]; then
        echo "=== Removing all ${BATSMAN_PROJECT} images ==="
        local img
        # Remove test images first (depend on base), then base images
        for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | \
                     grep -E "^${BATSMAN_PROJECT}-test-" 2>/dev/null); do
            echo "  Removing $img"
            docker rmi "$img" 2>/dev/null || true
        done
        for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | \
                     grep -E "^${BATSMAN_PROJECT}-base-" 2>/dev/null); do
            echo "  Removing $img"
            docker rmi "$img" 2>/dev/null || true
        done
    else
        echo "=== Removing ${BATSMAN_PROJECT} images for ${_batsman_os} ==="
        local test_img="${BATSMAN_PROJECT}-test-${_batsman_os}"
        local base_os
        base_os="$(_batsman_resolve_base_os "$_batsman_os")"
        local base_img="${BATSMAN_PROJECT}-base-${base_os}"

        echo "  Removing $test_img"
        docker rmi "$test_img" 2>/dev/null || true
        echo "  Removing $base_img"
        docker rmi "$base_img" 2>/dev/null || true
    fi

    # Prune dangling images after removal
    docker image prune -f >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# batsman_run_direct — Run explicit test file paths (no parallel)
# ---------------------------------------------------------------------------
batsman_run_direct() {
    local timeout_env=""
    [ -n "$_batsman_test_timeout" ] && timeout_env="-e BATS_TEST_TIMEOUT=$_batsman_test_timeout"

    local report_mount="" report_args=""
    if [ -n "$_batsman_report_dir" ]; then
        mkdir -p "$_batsman_report_dir"
        report_mount="-v $(cd "$_batsman_report_dir" && pwd):/reports"
        report_args="--report-formatter junit --output /reports"
    fi

    echo "=== Running tests: ${_batsman_os} ==="
    # shellcheck disable=SC2086
    docker run --rm ${BATSMAN_DOCKER_FLAGS:-} $timeout_env $report_mount \
        "$_batsman_image_tag" \
        bats --formatter "$_batsman_formatter" $report_args "${_batsman_bats_args[@]}"
}

# ---------------------------------------------------------------------------
# batsman_run_sequential — Single container, all tests
# ---------------------------------------------------------------------------
batsman_run_sequential() {
    local timeout_env=""
    [ -n "$_batsman_test_timeout" ] && timeout_env="-e BATS_TEST_TIMEOUT=$_batsman_test_timeout"

    local report_mount="" report_args=""
    if [ -n "$_batsman_report_dir" ]; then
        mkdir -p "$_batsman_report_dir"
        report_mount="-v $(cd "$_batsman_report_dir" && pwd):/reports"
        report_args="--report-formatter junit --output /reports"
    fi

    echo "=== Running tests: ${_batsman_os} ==="
    if [ ${#_batsman_bats_args[@]} -gt 0 ]; then
        # bats_args may contain --filter; append test path
        # shellcheck disable=SC2086
        docker run --rm ${BATSMAN_DOCKER_FLAGS:-} $timeout_env $report_mount \
            "$_batsman_image_tag" \
            bats --formatter "$_batsman_formatter" $report_args \
            "${_batsman_bats_args[@]}" "$BATSMAN_CONTAINER_TEST_PATH"
    else
        # shellcheck disable=SC2086
        docker run --rm ${BATSMAN_DOCKER_FLAGS:-} $timeout_env $report_mount \
            "$_batsman_image_tag" \
            bats --formatter "$_batsman_formatter" $report_args \
            "$BATSMAN_CONTAINER_TEST_PATH"
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
        num_groups=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
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

    local timeout_env=""
    [ -n "$_batsman_test_timeout" ] && timeout_env="-e BATS_TEST_TIMEOUT=$_batsman_test_timeout"

    # Per-group report volume mounts (parallel produces group-N subdirectories)
    local report_mount_base="" report_args=""
    if [ -n "$_batsman_report_dir" ]; then
        mkdir -p "$_batsman_report_dir"
        report_mount_base="$(cd "$_batsman_report_dir" && pwd)"
        report_args="--report-formatter junit --output /reports"
    fi

    echo "=== Running tests: ${_batsman_os} (parallel: ${num_groups} groups, ${num_files} files) ==="
    local start_time=$SECONDS

    # Launch named containers in parallel
    local -a pids
    for i in $(seq 0 $(( num_groups - 1 ))); do
        local report_mount=""
        if [ -n "$report_mount_base" ]; then
            mkdir -p "${report_mount_base}/group-${i}"
            report_mount="-v ${report_mount_base}/group-${i}:/reports"
        fi
        # shellcheck disable=SC2086
        docker run --rm ${BATSMAN_DOCKER_FLAGS:-} $timeout_env $report_mount \
            --name "${BATSMAN_PROJECT}-${_batsman_os}-${run_id}-g${i}" \
            "$_batsman_image_tag" \
            bats --formatter tap $report_args \
            "${_batsman_bats_args[@]}" ${group_files[$i]} \
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

    batsman_parse_args "$@" || return $?
    [ "$_batsman_done" -eq 1 ] && return 0
    batsman_build || return $?

    local test_rc=0
    if [ "$_batsman_explicit_files" -eq 1 ]; then
        batsman_run_direct || test_rc=$?
    elif [ "$_batsman_parallel" -eq 0 ]; then
        batsman_run_sequential || test_rc=$?
    else
        batsman_run_parallel || test_rc=$?
    fi

    if [ "$_batsman_clean" -eq 1 ]; then
        batsman_clean
    fi

    return "$test_rc"
}
