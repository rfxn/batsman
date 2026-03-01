#!/bin/bash
# batsman-common.bash — shared BATS helper for batsman self-tests
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE

# Resolve library path — works inside container and locally
if [[ -f /opt/batsman/lib/run-tests-core.sh ]]; then
    BATSMAN_LIB="/opt/batsman/lib/run-tests-core.sh"
    BATSMAN_DOCKERFILES="/opt/batsman/dockerfiles"
else
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    BATSMAN_LIB="$PROJECT_ROOT/lib/run-tests-core.sh"
    BATSMAN_DOCKERFILES="$PROJECT_ROOT/dockerfiles"
fi
export BATSMAN_LIB BATSMAN_DOCKERFILES

# Load bats-support and bats-assert
if [[ -d /usr/local/lib/bats/bats-support ]]; then
    # shellcheck disable=SC1091
    source /usr/local/lib/bats/bats-support/load.bash
    # shellcheck disable=SC1091
    source /usr/local/lib/bats/bats-assert/load.bash
fi

# Source library under test
# shellcheck disable=SC1090
source "$BATSMAN_LIB"

batsman_setup() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    # Safe defaults for all required variables
    export BATSMAN_PROJECT="test-project"
    export BATSMAN_PROJECT_DIR="$TEST_TMPDIR/project"
    export BATSMAN_TESTS_DIR="$TEST_TMPDIR/tests"
    export BATSMAN_INFRA_DIR="$TEST_TMPDIR/infra"
    export BATSMAN_CONTAINER_TEST_PATH="/opt/tests"
    export BATSMAN_SUPPORTED_OS="debian12 rocky9 centos7"
    export BATSMAN_DEFAULT_OS="debian12"
    export BATSMAN_DOCKER_FLAGS=""
    export BATSMAN_BASE_OS_MAP=""
    export BATSMAN_TEST_TIMEOUT=""
    export BATSMAN_REPORT_DIR=""
    mkdir -p "$BATSMAN_PROJECT_DIR" "$BATSMAN_TESTS_DIR" "$BATSMAN_INFRA_DIR"
}

batsman_teardown() {
    rm -rf "$TEST_TMPDIR"
}
