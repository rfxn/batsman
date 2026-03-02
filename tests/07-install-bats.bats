#!/usr/bin/env bats
# 07-install-bats.bats — install-bats.sh smoke tests via mock commands
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
# shellcheck disable=SC2154,SC2034

# These tests verify install-bats.sh behavior without network access by
# substituting mock wget, curl, sha256sum, and tar commands via PATH.
# The script is run with overridden install paths to avoid modifying the
# real BATS installation in the test container.

setup() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR

    MOCK_BIN="$TEST_TMPDIR/mock-bin"
    CMD_LOG="$TEST_TMPDIR/cmd.log"
    MOCK_INSTALL_PREFIX="$TEST_TMPDIR/install"
    MOCK_LIB_DIR="$TEST_TMPDIR/install/lib/bats"
    MOCK_HASH="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    mkdir -p "$MOCK_BIN" "$MOCK_INSTALL_PREFIX" "$MOCK_LIB_DIR"
    touch "$CMD_LOG"
    export CMD_LOG MOCK_HASH

    # Resolve source path for install-bats.sh
    if [[ -f /opt/batsman/scripts/install-bats.sh ]]; then
        INSTALL_BATS_SRC="/opt/batsman/scripts/install-bats.sh"
    else
        INSTALL_BATS_SRC="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/scripts/install-bats.sh"
    fi

    # Create modified copy with temp install paths (avoids overwriting
    # the real BATS installation in the container)
    INSTALL_BATS="$TEST_TMPDIR/install-bats.sh"
    sed \
        -e "s|BATS_INSTALL_PREFIX=\"/usr/local\"|BATS_INSTALL_PREFIX=\"$MOCK_INSTALL_PREFIX\"|" \
        -e "s|BATS_LIB_DIR=\"/usr/local/lib/bats\"|BATS_LIB_DIR=\"$MOCK_LIB_DIR\"|" \
        "$INSTALL_BATS_SRC" > "$INSTALL_BATS"
    chmod +x "$INSTALL_BATS"

    # --- Mock commands ---

    # Mock wget: write dummy content to -qO output file
    cat > "$MOCK_BIN/wget" << 'MOCK_EOF'
#!/bin/bash
echo "wget $*" >> "$CMD_LOG"
prev=""
for arg in "$@"; do
    if [ "$prev" = "-qO" ]; then
        echo "mock-tarball-content" > "$arg"
        exit 0
    fi
    prev="$arg"
done
exit 0
MOCK_EOF
    chmod +x "$MOCK_BIN/wget"

    # Mock curl: write dummy content to -o output file
    cat > "$MOCK_BIN/curl" << 'MOCK_EOF'
#!/bin/bash
echo "curl $*" >> "$CMD_LOG"
i=1
while [ "$i" -le "$#" ]; do
    eval "arg=\${$i}"
    if [ "$arg" = "-o" ]; then
        next=$((i + 1))
        eval "outfile=\${$next}"
        echo "mock-tarball-content" > "$outfile"
        exit 0
    fi
    i=$((i + 1))
done
exit 0
MOCK_EOF
    chmod +x "$MOCK_BIN/curl"

    # Mock sha256sum: output configurable hash
    cat > "$MOCK_BIN/sha256sum" << 'MOCK_EOF'
#!/bin/bash
echo "${MOCK_SHA256:-$MOCK_HASH}  $1"
MOCK_EOF
    chmod +x "$MOCK_BIN/sha256sum"

    # Mock tar: create install.sh and load.bash in destination dir
    cat > "$MOCK_BIN/tar" << 'MOCK_EOF'
#!/bin/bash
echo "tar $*" >> "$CMD_LOG"
prev=""
for arg in "$@"; do
    if [ "$prev" = "-C" ]; then
        dest="$arg"
        break
    fi
    prev="$arg"
done
if [ -n "${dest:-}" ] && [ -d "$dest" ]; then
    cat > "$dest/install.sh" << 'INST'
#!/bin/bash
echo "Mock bats install to $1"
mkdir -p "$1/bin"
INST
    chmod +x "$dest/install.sh"
    touch "$dest/load.bash"
fi
MOCK_EOF
    chmod +x "$MOCK_BIN/tar"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ---------------------------------------------------------------------------
# Default version values
# ---------------------------------------------------------------------------

@test "default versions: bats-core 1.13.0, support 0.3.0, assert 2.1.0" {
    grep -q 'BATS_VERSION:-1.13.0' "$INSTALL_BATS_SRC"
    grep -q 'BATS_SUPPORT_VERSION:-0.3.0' "$INSTALL_BATS_SRC"
    grep -q 'BATS_ASSERT_VERSION:-2.1.0' "$INSTALL_BATS_SRC"
}

# ---------------------------------------------------------------------------
# SHA256 verification
# ---------------------------------------------------------------------------

@test "SHA256 mismatch aborts with error" {
    run env PATH="$MOCK_BIN:$PATH" \
        MOCK_SHA256="0000000000000000000000000000000000000000000000000000000000000bad" \
        BATS_CORE_SHA256="$MOCK_HASH" \
        BATS_SUPPORT_SHA256="$MOCK_HASH" \
        BATS_ASSERT_SHA256="$MOCK_HASH" \
        bash "$INSTALL_BATS"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SHA256 checksum mismatch"* ]]
}

# ---------------------------------------------------------------------------
# TLS fallback routing
# ---------------------------------------------------------------------------

@test "TLS_FALLBACK=0 uses wget" {
    run env PATH="$MOCK_BIN:$PATH" \
        TLS_FALLBACK=0 \
        BATS_CORE_SHA256="$MOCK_HASH" \
        BATS_SUPPORT_SHA256="$MOCK_HASH" \
        BATS_ASSERT_SHA256="$MOCK_HASH" \
        bash "$INSTALL_BATS"
    [ "$status" -eq 0 ]
    local cmds
    cmds=$(cat "$CMD_LOG")
    [[ "$cmds" == *"wget --timeout=60 -qO"* ]]
    # Standard mode: no --no-check-certificate, no curl
    [[ "$cmds" != *"--no-check-certificate"* ]]
    [[ "$cmds" != *"curl"* ]]
}

@test "TLS_FALLBACK=1 uses wget --no-check-certificate" {
    run env PATH="$MOCK_BIN:$PATH" \
        TLS_FALLBACK=1 \
        BATS_CORE_SHA256="$MOCK_HASH" \
        BATS_SUPPORT_SHA256="$MOCK_HASH" \
        BATS_ASSERT_SHA256="$MOCK_HASH" \
        bash "$INSTALL_BATS"
    [ "$status" -eq 0 ]
    local cmds
    cmds=$(cat "$CMD_LOG")
    [[ "$cmds" == *"wget --no-check-certificate --timeout=60"* ]]
}

@test "TLS_FALLBACK=2 uses curl primary" {
    run env PATH="$MOCK_BIN:$PATH" \
        TLS_FALLBACK=2 \
        BATS_CORE_SHA256="$MOCK_HASH" \
        BATS_SUPPORT_SHA256="$MOCK_HASH" \
        BATS_ASSERT_SHA256="$MOCK_HASH" \
        bash "$INSTALL_BATS"
    [ "$status" -eq 0 ]
    local cmds
    cmds=$(cat "$CMD_LOG")
    [[ "$cmds" == *"curl --connect-timeout 30 --max-time 120"* ]]
}

@test "unknown TLS_FALLBACK aborts with error" {
    run env PATH="$MOCK_BIN:$PATH" \
        TLS_FALLBACK=9 \
        BATS_CORE_SHA256="$MOCK_HASH" \
        BATS_SUPPORT_SHA256="$MOCK_HASH" \
        BATS_ASSERT_SHA256="$MOCK_HASH" \
        bash "$INSTALL_BATS"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown TLS_FALLBACK"* ]]
}

# ---------------------------------------------------------------------------
# Successful install flow
# ---------------------------------------------------------------------------

@test "successful install completes all three libraries" {
    run env PATH="$MOCK_BIN:$PATH" \
        BATS_CORE_SHA256="$MOCK_HASH" \
        BATS_SUPPORT_SHA256="$MOCK_HASH" \
        BATS_ASSERT_SHA256="$MOCK_HASH" \
        bash "$INSTALL_BATS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing bats-core"* ]]
    [[ "$output" == *"Installing bats-support"* ]]
    [[ "$output" == *"Installing bats-assert"* ]]
    [[ "$output" == *"BATS installation complete"* ]]
}
