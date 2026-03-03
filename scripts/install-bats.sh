#!/bin/bash
# batsman — install-bats.sh
# Shared BATS installer for all project Dockerfiles
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2 — see LICENSE
#
# Usage in Dockerfile:
#   COPY scripts/install-bats.sh /tmp/install-bats.sh
#   RUN TLS_FALLBACK=0 bash /tmp/install-bats.sh && rm -f /tmp/install-bats.sh
#
# Environment variables:
#   BATS_VERSION          bats-core version       (default: 1.13.0)
#   BATS_SUPPORT_VERSION  bats-support version    (default: 0.3.0)
#   BATS_ASSERT_VERSION   bats-assert version     (default: 2.1.0)
#   BATS_CORE_SHA256      SHA256 for bats-core tarball    (default: matches pinned version)
#   BATS_SUPPORT_SHA256   SHA256 for bats-support tarball (default: matches pinned version)
#   BATS_ASSERT_SHA256    SHA256 for bats-assert tarball  (default: matches pinned version)
#   TLS_FALLBACK          TLS download strategy   (default: 0)
#     0 = standard wget (modern distros)
#     1 = wget --no-check-certificate, curl -sSL -k fallback (CentOS 6)
#     2 = curl -sSL -k primary, wget --no-check-certificate fallback (Ubuntu 12.04)

set -eo pipefail

BATS_VERSION="${BATS_VERSION:-1.13.0}"
BATS_SUPPORT_VERSION="${BATS_SUPPORT_VERSION:-0.3.0}"
BATS_ASSERT_VERSION="${BATS_ASSERT_VERSION:-2.1.0}"
TLS_FALLBACK="${TLS_FALLBACK:-0}"

# SHA256 checksums for pinned tarball versions
# Update these when changing BATS_VERSION, BATS_SUPPORT_VERSION, or BATS_ASSERT_VERSION
BATS_CORE_SHA256="${BATS_CORE_SHA256:-a85e12b8828271a152b338ca8109aa23493b57950987c8e6dff97ba492772ff3}"
BATS_SUPPORT_SHA256="${BATS_SUPPORT_SHA256:-7815237aafeb42ddcc1b8c698fc5808026d33317d8701d5ec2396e9634e2918f}"
BATS_ASSERT_SHA256="${BATS_ASSERT_SHA256:-98ca3b685f8b8993e48ec057565e6e2abcc541034ed5b0e81f191505682037fd}"

BATS_INSTALL_PREFIX="/usr/local"
BATS_LIB_DIR="/usr/local/lib/bats"

GITHUB_BASE="https://github.com/bats-core"

# fetch_tarball URL DEST_DIR EXPECTED_SHA256
#   Downloads a GitHub release tarball to a temp file, verifies its SHA256
#   checksum, and extracts into DEST_DIR.
#   Respects TLS_FALLBACK for EOL distros with outdated certificates.
#   File-based download avoids partial-data corruption in fallback modes:
#   partial output is cleaned before the fallback attempt begins.
fetch_tarball() {
    local url="$1"
    local dest="$2"
    local expected_sha256="$3"
    local tarball
    tarball="$(mktemp "${TMPDIR:-/tmp}/bats-download.XXXXXX")"

    mkdir -p "$dest"

    case "$TLS_FALLBACK" in
        0)
            wget --timeout=60 -qO "$tarball" "$url"
            ;;
        1)
            # CentOS 6: wget --no-check-certificate primary, curl fallback
            wget --no-check-certificate --timeout=60 -qO "$tarball" "$url" || {
                rm -f "$tarball"
                curl --connect-timeout 30 --max-time 120 -sSL -k -o "$tarball" "$url"
            }
            ;;
        2)
            # Ubuntu 12.04: curl primary, wget --no-check-certificate fallback
            curl --connect-timeout 30 --max-time 120 -sSL -k -o "$tarball" "$url" || {
                rm -f "$tarball"
                wget --no-check-certificate --timeout=60 -qO "$tarball" "$url"
            }
            ;;
        *)
            rm -f "$tarball"
            echo "install-bats.sh: unknown TLS_FALLBACK value: $TLS_FALLBACK" >&2
            exit 1
            ;;
    esac

    local actual_sha256
    actual_sha256="$(sha256sum "$tarball" | awk '{print $1}')"
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        echo "install-bats.sh: SHA256 checksum mismatch for $url" >&2
        echo "  expected: $expected_sha256" >&2
        echo "  actual:   $actual_sha256" >&2
        rm -f "$tarball"
        exit 1
    fi

    tar xz -C "$dest" --strip-components=1 < "$tarball"
    rm -f "$tarball"
}

echo "Installing bats-core ${BATS_VERSION}..."
BATS_TMPDIR="$(mktemp -d)"
fetch_tarball "${GITHUB_BASE}/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz" "$BATS_TMPDIR" "$BATS_CORE_SHA256"
"$BATS_TMPDIR/install.sh" "$BATS_INSTALL_PREFIX"
rm -rf "$BATS_TMPDIR"

echo "Installing bats-support ${BATS_SUPPORT_VERSION}..."
fetch_tarball \
    "${GITHUB_BASE}/bats-support/archive/refs/tags/v${BATS_SUPPORT_VERSION}.tar.gz" \
    "${BATS_LIB_DIR}/bats-support" \
    "$BATS_SUPPORT_SHA256"

echo "Installing bats-assert ${BATS_ASSERT_VERSION}..."
fetch_tarball \
    "${GITHUB_BASE}/bats-assert/archive/refs/tags/v${BATS_ASSERT_VERSION}.tar.gz" \
    "${BATS_LIB_DIR}/bats-assert" \
    "$BATS_ASSERT_SHA256"

echo "BATS installation complete: bats-core=${BATS_VERSION} bats-support=${BATS_SUPPORT_VERSION} bats-assert=${BATS_ASSERT_VERSION}"
