#!/bin/bash
# batsman self-test wrapper — consumes itself
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Variables consumed by sourced run-tests-core.sh
# shellcheck disable=SC2034
BATSMAN_PROJECT="batsman"
BATSMAN_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC2034
BATSMAN_TESTS_DIR="$SCRIPT_DIR"
BATSMAN_INFRA_DIR="$BATSMAN_PROJECT_DIR"          # self-bootstrap: infra IS the project
# shellcheck disable=SC2034
BATSMAN_DOCKER_FLAGS=""
# shellcheck disable=SC2034
BATSMAN_DEFAULT_OS="debian12"
# shellcheck disable=SC2034
BATSMAN_CONTAINER_TEST_PATH="/opt/tests"
# shellcheck disable=SC2034
BATSMAN_SUPPORTED_OS="debian12"

# shellcheck disable=SC1090,SC1091
source "$BATSMAN_INFRA_DIR/lib/run-tests-core.sh"
batsman_run "$@"
