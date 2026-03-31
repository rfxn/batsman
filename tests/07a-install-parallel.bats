#!/usr/bin/env bats
# 07a-install-parallel.bats — install-parallel.sh smoke tests via mock commands
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
# shellcheck disable=SC2154,SC2034

# These tests verify install-parallel.sh behavior without network access by
# substituting mock wget, curl, sha256sum, tar, and parallel commands via PATH.
# Tests that exercise the download/install path use a sandboxed PATH that
# excludes the real GNU parallel binary to prevent early-exit via the
# "already installed" guard.

setup() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR

    MOCK_BIN="$TEST_TMPDIR/mock-bin"
    CMD_LOG="$TEST_TMPDIR/cmd.log"
    MOCK_HASH="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    mkdir -p "$MOCK_BIN"
    touch "$CMD_LOG"
    export CMD_LOG MOCK_HASH

    # Resolve source path for install-parallel.sh
    if [[ -f /opt/batsman/scripts/install-parallel.sh ]]; then
        INSTALL_PARALLEL_SRC="/opt/batsman/scripts/install-parallel.sh"
    else
        INSTALL_PARALLEL_SRC="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/scripts/install-parallel.sh"
    fi

    # Create working copy for tests
    INSTALL_PARALLEL="$TEST_TMPDIR/install-parallel.sh"
    cp "$INSTALL_PARALLEL_SRC" "$INSTALL_PARALLEL"
    chmod +x "$INSTALL_PARALLEL"

    # Build a sandboxed PATH that includes essential system tools but NOT
    # the real GNU parallel. This lets us test the download/install path.
    SANDBOX_BIN="$TEST_TMPDIR/sandbox-bin"
    mkdir -p "$SANDBOX_BIN"
    # Symlink essential tools the script needs
    for tool in bash head awk mktemp rm mkdir chmod cp cat; do
        local real_path
        real_path="$(command -v "$tool" 2>/dev/null)" || true
        if [[ -n "$real_path" ]]; then
            ln -sf "$real_path" "$SANDBOX_BIN/$tool"
        fi
    done

    # Sandboxed PATH: mock bin first, then sandbox (no real parallel)
    SANDBOX_PATH="$MOCK_BIN:$SANDBOX_BIN"
    export SANDBOX_PATH

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

    # Mock tar: create src/parallel in extraction directory
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
    mkdir -p "$dest/src"
    cat > "$dest/src/parallel" << 'PSCRIPT'
#!/usr/bin/perl
print "GNU parallel mock\n";
PSCRIPT
    chmod +x "$dest/src/parallel"
fi
MOCK_EOF
    chmod +x "$MOCK_BIN/tar"

    # Mock perl: for the sandbox (perl must be found for download tests)
    ln -sf "$(command -v perl 2>/dev/null || echo /usr/bin/perl)" "$SANDBOX_BIN/perl"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ---------------------------------------------------------------------------
# Default version values
# ---------------------------------------------------------------------------

@test "install-parallel: default version is 20260322" {
    grep -q 'PARALLEL_VERSION:-20260322' "$INSTALL_PARALLEL_SRC"
}

@test "install-parallel: default SHA256 matches pinned version" {
    grep -q 'PARALLEL_SHA256:-764680e932f4d0d21cf0329bd9f9eed659895de16836001f6491533b822befe0' "$INSTALL_PARALLEL_SRC"
}

# ---------------------------------------------------------------------------
# Skip when already installed
# ---------------------------------------------------------------------------

@test "install-parallel: skips if parallel already on PATH" {
    # Create a mock parallel that is already installed
    cat > "$MOCK_BIN/parallel" << 'MOCK_EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then
    echo "GNU parallel 20260101"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_BIN/parallel"

    # Include mock parallel in sandbox so it is found
    ln -sf "$MOCK_BIN/parallel" "$SANDBOX_BIN/parallel"

    run env PATH="$SANDBOX_PATH" \
        PARALLEL_SHA256="$MOCK_HASH" \
        bash "$INSTALL_PARALLEL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    # Should NOT have downloaded anything
    [ ! -s "$CMD_LOG" ]
}

# ---------------------------------------------------------------------------
# Missing perl
# ---------------------------------------------------------------------------

@test "install-parallel: aborts if perl is not found" {
    # Remove perl from the sandbox so it is not found
    rm -f "$SANDBOX_BIN/perl"

    run env PATH="$SANDBOX_PATH" \
        PARALLEL_SHA256="$MOCK_HASH" \
        bash "$INSTALL_PARALLEL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"perl is required"* ]]
}

# ---------------------------------------------------------------------------
# SHA256 verification
# ---------------------------------------------------------------------------

@test "install-parallel: SHA256 mismatch aborts with error" {
    run env PATH="$SANDBOX_PATH" \
        MOCK_SHA256="0000000000000000000000000000000000000000000000000000000000000bad" \
        PARALLEL_SHA256="$MOCK_HASH" \
        bash "$INSTALL_PARALLEL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SHA256 checksum mismatch"* ]]
}

# ---------------------------------------------------------------------------
# TLS fallback routing
# ---------------------------------------------------------------------------

@test "install-parallel: TLS_FALLBACK=0 uses wget" {
    run env PATH="$SANDBOX_PATH" \
        TLS_FALLBACK=0 \
        PARALLEL_SHA256="$MOCK_HASH" \
        bash "$INSTALL_PARALLEL"
    [ "$status" -eq 0 ]
    local cmds
    cmds=$(cat "$CMD_LOG")
    [[ "$cmds" == *"wget --timeout=60 -qO"* ]]
    [[ "$cmds" != *"--no-check-certificate"* ]]
    [[ "$cmds" != *"curl"* ]]
}

@test "install-parallel: TLS_FALLBACK=1 uses wget --no-check-certificate" {
    run env PATH="$SANDBOX_PATH" \
        TLS_FALLBACK=1 \
        PARALLEL_SHA256="$MOCK_HASH" \
        bash "$INSTALL_PARALLEL"
    [ "$status" -eq 0 ]
    local cmds
    cmds=$(cat "$CMD_LOG")
    [[ "$cmds" == *"wget --no-check-certificate --timeout=60"* ]]
}

@test "install-parallel: TLS_FALLBACK=2 uses curl primary" {
    run env PATH="$SANDBOX_PATH" \
        TLS_FALLBACK=2 \
        PARALLEL_SHA256="$MOCK_HASH" \
        bash "$INSTALL_PARALLEL"
    [ "$status" -eq 0 ]
    local cmds
    cmds=$(cat "$CMD_LOG")
    [[ "$cmds" == *"curl --connect-timeout 30 --max-time 120"* ]]
}

@test "install-parallel: unknown TLS_FALLBACK aborts with error" {
    run env PATH="$SANDBOX_PATH" \
        TLS_FALLBACK=9 \
        PARALLEL_SHA256="$MOCK_HASH" \
        bash "$INSTALL_PARALLEL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown TLS_FALLBACK"* ]]
}

# ---------------------------------------------------------------------------
# Successful install flow
# ---------------------------------------------------------------------------

@test "install-parallel: successful install prints completion message" {
    run env PATH="$SANDBOX_PATH" \
        PARALLEL_SHA256="$MOCK_HASH" \
        bash "$INSTALL_PARALLEL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing GNU parallel"* ]]
    [[ "$output" == *"installed"* ]]
}

# ---------------------------------------------------------------------------
# Dockerfile integration
# ---------------------------------------------------------------------------

@test "install-parallel: Dockerfile.centos6 includes perl and bzip2 packages" {
    local dockerfile
    if [[ -f /opt/batsman/dockerfiles/Dockerfile.centos6 ]]; then
        dockerfile="/opt/batsman/dockerfiles/Dockerfile.centos6"
    else
        dockerfile="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/dockerfiles/Dockerfile.centos6"
    fi
    grep -q 'perl' "$dockerfile"
    grep -q 'bzip2' "$dockerfile"
}

@test "install-parallel: Dockerfile.centos6 has install-parallel.sh step" {
    local dockerfile
    if [[ -f /opt/batsman/dockerfiles/Dockerfile.centos6 ]]; then
        dockerfile="/opt/batsman/dockerfiles/Dockerfile.centos6"
    else
        dockerfile="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/dockerfiles/Dockerfile.centos6"
    fi
    grep -q 'COPY scripts/install-parallel.sh' "$dockerfile"
    grep -q 'TLS_FALLBACK=1 bash /tmp/install-parallel.sh' "$dockerfile"
}

@test "install-parallel: Dockerfile.ubuntu1204 includes bzip2 package" {
    local dockerfile
    if [[ -f /opt/batsman/dockerfiles/Dockerfile.ubuntu1204 ]]; then
        dockerfile="/opt/batsman/dockerfiles/Dockerfile.ubuntu1204"
    else
        dockerfile="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/dockerfiles/Dockerfile.ubuntu1204"
    fi
    grep -q 'bzip2' "$dockerfile"
}

@test "install-parallel: Dockerfile.ubuntu1204 has install-parallel.sh step" {
    local dockerfile
    if [[ -f /opt/batsman/dockerfiles/Dockerfile.ubuntu1204 ]]; then
        dockerfile="/opt/batsman/dockerfiles/Dockerfile.ubuntu1204"
    else
        dockerfile="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/dockerfiles/Dockerfile.ubuntu1204"
    fi
    grep -q 'COPY scripts/install-parallel.sh' "$dockerfile"
    grep -q 'TLS_FALLBACK=2 bash /tmp/install-parallel.sh' "$dockerfile"
}
