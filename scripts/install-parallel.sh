#!/usr/bin/env bash
# batsman — install-parallel.sh
# Install GNU parallel for BATS --jobs support on deep legacy OS
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
#
# Usage in Dockerfile:
#   COPY scripts/install-parallel.sh /tmp/install-parallel.sh
#   RUN TLS_FALLBACK=1 bash /tmp/install-parallel.sh && rm -f /tmp/install-parallel.sh
#
# Environment variables:
#   PARALLEL_VERSION   GNU parallel version   (default: YYYYMMDD — set at release)
#   PARALLEL_SHA256    SHA256 checksum         (default: matches pinned version)
#   TLS_FALLBACK       TLS download strategy   (same as install-bats.sh)
#     0 = standard wget (modern distros)
#     1 = wget --no-check-certificate, curl -k fallback (CentOS 6)
#     2 = curl -k primary, wget --no-check-certificate fallback (Ubuntu 12.04)

set -eo pipefail

PARALLEL_VERSION="${PARALLEL_VERSION:-20260322}"
PARALLEL_SHA256="${PARALLEL_SHA256:-764680e932f4d0d21cf0329bd9f9eed659895de16836001f6491533b822befe0}"
TLS_FALLBACK="${TLS_FALLBACK:-0}"

# Skip if parallel is already installed (e.g., via package manager on modern images)
if command -v parallel >/dev/null 2>&1; then  # safe: early exit when already present
    echo "GNU parallel already installed: $(parallel --version 2>&1 | head -1)"
    exit 0
fi

# Verify perl is available (parallel is a Perl script)
if ! command -v perl >/dev/null 2>&1; then  # safe: perl required for GNU parallel
    echo "install-parallel.sh: perl is required but not found" >&2
    exit 1
fi

URL="https://ftp.gnu.org/gnu/parallel/parallel-${PARALLEL_VERSION}.tar.bz2"
TARBALL="$(mktemp "${TMPDIR:-/tmp}/parallel-download.XXXXXX")"

echo "Installing GNU parallel ${PARALLEL_VERSION}..."

case "$TLS_FALLBACK" in
    0)
        wget --timeout=60 -qO "$TARBALL" "$URL"
        ;;
    1)
        # CentOS 6: wget --no-check-certificate primary, curl fallback
        wget --no-check-certificate --timeout=60 -qO "$TARBALL" "$URL" || {
            rm -f "$TARBALL"
            curl --connect-timeout 30 --max-time 120 -sSL -k -o "$TARBALL" "$URL"
        }
        ;;
    2)
        # Ubuntu 12.04: curl primary, wget --no-check-certificate fallback
        curl --connect-timeout 30 --max-time 120 -sSL -k -o "$TARBALL" "$URL" || {
            rm -f "$TARBALL"
            wget --no-check-certificate --timeout=60 -qO "$TARBALL" "$URL"
        }
        ;;
    *)
        rm -f "$TARBALL"
        echo "install-parallel.sh: unknown TLS_FALLBACK value: $TLS_FALLBACK" >&2
        exit 1
        ;;
esac

# Verify SHA256 checksum
ACTUAL_SHA256="$(sha256sum "$TARBALL" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$PARALLEL_SHA256" ]; then
    echo "install-parallel.sh: SHA256 checksum mismatch for parallel-${PARALLEL_VERSION}.tar.bz2" >&2
    echo "  expected: $PARALLEL_SHA256" >&2
    echo "  actual:   $ACTUAL_SHA256" >&2
    rm -f "$TARBALL"
    exit 1
fi

# Extract and install the parallel Perl script
TMPDIR_P="$(mktemp -d)"
tar xjf "$TARBALL" -C "$TMPDIR_P" --strip-components=1
cp "$TMPDIR_P/src/parallel" /usr/local/bin/parallel
chmod +x /usr/local/bin/parallel
rm -rf "$TMPDIR_P" "$TARBALL"

echo "GNU parallel ${PARALLEL_VERSION} installed"
