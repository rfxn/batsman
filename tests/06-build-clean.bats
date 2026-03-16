#!/usr/bin/env bats
# 06-build-clean.bats — Build, clean, and routing integration tests
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
# shellcheck disable=SC2154,SC2034

load helpers/batsman-common

setup() {
    batsman_setup
    DOCKER_LOG="$TEST_TMPDIR/docker.log"
    DOCKER_EXIT_CODE=0
    DOCKER_TAP_OUTPUT=""
    DOCKER_IMAGES_OUTPUT=""
    export DOCKER_LOG DOCKER_EXIT_CODE DOCKER_TAP_OUTPUT DOCKER_IMAGES_OUTPUT

    # Docker stub: logs all subcommands, returns configurable output
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
            images)
                if [ -n "${DOCKER_IMAGES_OUTPUT:-}" ]; then
                    printf '%s\n' "$DOCKER_IMAGES_OUTPUT"
                fi
                return 0
                ;;
        esac
        return 0
    }
    export -f docker

    # Create mock Dockerfiles for build tests
    mkdir -p "$BATSMAN_INFRA_DIR/dockerfiles"
    touch "$BATSMAN_INFRA_DIR/dockerfiles/Dockerfile.debian12"
    touch "$BATSMAN_INFRA_DIR/dockerfiles/Dockerfile.rocky9"
    touch "$BATSMAN_TESTS_DIR/Dockerfile"
    touch "$BATSMAN_TESTS_DIR/Dockerfile.rocky9"

    # Execution state defaults (normally set by batsman_parse_args)
    _batsman_os="debian12"
    _batsman_formatter="tap"
    _batsman_bats_args=()
    _batsman_explicit_files=0
    _batsman_test_timeout=""
    _batsman_report_dir=""
    _batsman_image_tag=""
    _batsman_parallel=0
    _batsman_parallel_n=0
    _batsman_abort=0
    _batsman_clean=0
    _batsman_done=0
}

teardown() {
    batsman_teardown
}

# ---------------------------------------------------------------------------
# batsman_build — Dockerfile resolution and image tagging (F-021)
# ---------------------------------------------------------------------------

@test "build: base image built with correct Dockerfile and tag" {
    batsman_build
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"build -f $BATSMAN_INFRA_DIR/dockerfiles/Dockerfile.debian12"* ]]
    [[ "$logged" == *"-t test-project-base-debian12"* ]]
}

@test "build: project image built with correct tag" {
    batsman_build
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"-t test-project-test-debian12"* ]]
}

@test "build: debian12 project uses Dockerfile without OS suffix" {
    _batsman_os="debian12"
    batsman_build
    local project_build
    project_build=$(grep "build.*--build-arg" "$DOCKER_LOG")
    [[ "$project_build" == *"-f $BATSMAN_TESTS_DIR/Dockerfile -t"* ]]
}

@test "build: non-debian12 project uses Dockerfile.OS" {
    _batsman_os="rocky9"
    batsman_build
    local project_build
    project_build=$(grep "build.*--build-arg" "$DOCKER_LOG")
    [[ "$project_build" == *"-f $BATSMAN_TESTS_DIR/Dockerfile.rocky9"* ]]
}

@test "build: missing base Dockerfile returns error" {
    rm "$BATSMAN_INFRA_DIR/dockerfiles/Dockerfile.debian12"
    run batsman_build
    [ "$status" -ne 0 ]
    [[ "$output" == *"base Dockerfile not found"* ]]
}

@test "build: missing project Dockerfile returns error" {
    _batsman_os="rocky9"
    rm "$BATSMAN_TESTS_DIR/Dockerfile.rocky9"
    run batsman_build
    [ "$status" -ne 0 ]
    [[ "$output" == *"project Dockerfile not found"* ]]
}

@test "build: sets _batsman_image_tag" {
    batsman_build
    [ "$_batsman_image_tag" = "test-project-test-debian12" ]
}

@test "build: variant mapping resolves base OS" {
    BATSMAN_BASE_OS_MAP="custom-variant=debian12"
    BATSMAN_SUPPORTED_OS="debian12 rocky9 centos7 custom-variant"
    _batsman_os="custom-variant"
    touch "$BATSMAN_TESTS_DIR/Dockerfile.custom-variant"
    batsman_build
    local logged
    logged=$(cat "$DOCKER_LOG")
    # Base image should use debian12 Dockerfile (mapped), not custom-variant
    [[ "$logged" == *"Dockerfile.debian12"* ]]
    [[ "$logged" == *"-t test-project-base-debian12"* ]]
}

# ---------------------------------------------------------------------------
# batsman_clean — Image cleanup modes (F-020)
# ---------------------------------------------------------------------------

@test "clean: no args removes current OS test and base images" {
    _batsman_os="debian12"
    batsman_clean
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"rmi test-project-test-debian12"* ]]
    [[ "$logged" == *"rmi test-project-base-debian12"* ]]
}

@test "clean --all: removes test images then base images" {
    DOCKER_IMAGES_OUTPUT="test-project-test-debian12:latest
test-project-test-rocky9:latest
test-project-base-debian12:latest
test-project-base-rocky9:latest
unrelated-image:latest"
    batsman_clean --all
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"rmi test-project-test-debian12:latest"* ]]
    [[ "$logged" == *"rmi test-project-test-rocky9:latest"* ]]
    [[ "$logged" == *"rmi test-project-base-debian12:latest"* ]]
    [[ "$logged" == *"rmi test-project-base-rocky9:latest"* ]]
    # Unrelated image should NOT be removed
    [[ "$logged" != *"rmi unrelated-image"* ]]
}

@test "clean --dangling-only: prune only, no image removal" {
    batsman_clean --dangling-only
    local logged
    logged=$(cat "$DOCKER_LOG")
    [[ "$logged" == *"image prune -f"* ]]
    # Should NOT have rmi calls
    [[ "$logged" != *"rmi"* ]]
}

@test "clean: unknown option returns error" {
    run batsman_clean --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "clean: variant mapping resolves base OS for cleanup" {
    BATSMAN_BASE_OS_MAP="custom-variant=debian12"
    _batsman_os="custom-variant"
    batsman_clean
    local logged
    logged=$(cat "$DOCKER_LOG")
    # Test image uses the variant name
    [[ "$logged" == *"rmi test-project-test-custom-variant"* ]]
    # Base image uses the resolved OS
    [[ "$logged" == *"rmi test-project-base-debian12"* ]]
}

# ---------------------------------------------------------------------------
# batsman_run — Routing logic (F-047)
# ---------------------------------------------------------------------------

@test "run: explicit file routes to direct mode" {
    run batsman_run /opt/tests/01-test.bats
    [ "$status" -eq 0 ]
    local run_cmd
    run_cmd=$(grep "^run " "$DOCKER_LOG")
    # Direct mode passes the file path through
    [[ "$run_cmd" == *"/opt/tests/01-test.bats"* ]]
    # No --name (parallel uses named containers)
    [[ "$run_cmd" != *"--name"* ]]
}

@test "run: --parallel routes to parallel mode" {
    touch "$BATSMAN_TESTS_DIR/01-test.bats" "$BATSMAN_TESTS_DIR/02-test.bats"
    run batsman_run --parallel 2
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    # Parallel mode uses named containers
    [[ "$logged" == *"--name test-project-debian12-"* ]]
}

@test "run: default routes to sequential mode" {
    run batsman_run
    [ "$status" -eq 0 ]
    local run_cmd
    run_cmd=$(grep "^run " "$DOCKER_LOG")
    # Sequential mode includes container test path
    [[ "$run_cmd" == *"/opt/tests"* ]]
    # No --name (only parallel uses named containers)
    [[ "$run_cmd" != *"--name"* ]]
}

@test "run: --help skips build and test" {
    run batsman_run --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    # No docker calls — log file should not exist
    [ ! -f "$DOCKER_LOG" ]
}

@test "run: --version skips build and test" {
    run batsman_run --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"batsman"* ]]
    # No docker calls — log file should not exist
    [ ! -f "$DOCKER_LOG" ]
}

@test "run: --clean invokes cleanup after test" {
    run batsman_run --clean
    [ "$status" -eq 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    # Should have rmi calls from batsman_clean()
    [[ "$logged" == *"rmi test-project-test-debian12"* ]]
    [[ "$logged" == *"rmi test-project-base-debian12"* ]]
}

@test "run: --clean preserves non-zero exit code on test failure" {
    DOCKER_EXIT_CODE=1
    run batsman_run --clean
    [ "$status" -ne 0 ]
    local logged
    logged=$(cat "$DOCKER_LOG")
    # Cleanup still ran despite failure
    [[ "$logged" == *"rmi test-project-test-debian12"* ]]
    [[ "$logged" == *"rmi test-project-base-debian12"* ]]
}
