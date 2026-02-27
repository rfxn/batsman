#!/bin/bash
# batsman — run-tests-core.sh
# Parallel test orchestration engine (sourced library)
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
#
# This file is sourced by project run-tests.sh wrappers.
# Do not execute directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: run-tests-core.sh must be sourced, not executed directly." >&2
    exit 1
fi

# Stub — implemented in Phase 4
batsman_run() {
    echo "batsman_run: not yet implemented" >&2
    return 1
}
