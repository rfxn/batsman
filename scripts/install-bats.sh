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
#   BATS_VERSION          bats-core version       (default: 1.11.0)
#   BATS_SUPPORT_VERSION  bats-support version    (default: 0.3.0)
#   BATS_ASSERT_VERSION   bats-assert version     (default: 2.1.0)
#   TLS_FALLBACK          TLS download strategy   (default: 0)
#     0 = standard wget (modern distros)
#     1 = wget --no-check-certificate, curl -sSL -k fallback (CentOS 6)
#     2 = curl -sSL -k primary, wget --no-check-certificate fallback (Ubuntu 12.04)

set -e

BATS_VERSION="${BATS_VERSION:-1.11.0}"
BATS_SUPPORT_VERSION="${BATS_SUPPORT_VERSION:-0.3.0}"
BATS_ASSERT_VERSION="${BATS_ASSERT_VERSION:-2.1.0}"
TLS_FALLBACK="${TLS_FALLBACK:-0}"

BATS_INSTALL_PREFIX="/usr/local"
BATS_LIB_DIR="/usr/local/lib/bats"

GITHUB_BASE="https://github.com/bats-core"

# fetch_tarball URL DEST_DIR
#   Downloads and extracts a GitHub release tarball into DEST_DIR.
#   Respects TLS_FALLBACK for EOL distros with outdated certificates.
fetch_tarball() {
    local url="$1"
    local dest="$2"

    mkdir -p "$dest"

    case "$TLS_FALLBACK" in
        0)
            wget -qO- "$url" | tar xz -C "$dest" --strip-components=1
            ;;
        1)
            # CentOS 6: wget --no-check-certificate primary, curl fallback
            (wget --no-check-certificate -qO- "$url" || \
             curl -sSL -k "$url") | tar xz -C "$dest" --strip-components=1
            ;;
        2)
            # Ubuntu 12.04: curl primary, wget --no-check-certificate fallback
            (curl -sSL -k "$url" || \
             wget --no-check-certificate -qO- "$url") | tar xz -C "$dest" --strip-components=1
            ;;
        *)
            echo "install-bats.sh: unknown TLS_FALLBACK value: $TLS_FALLBACK" >&2
            exit 1
            ;;
    esac
}

echo "Installing bats-core ${BATS_VERSION}..."
BATS_TMPDIR="$(mktemp -d)"
fetch_tarball "${GITHUB_BASE}/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz" "$BATS_TMPDIR"
"$BATS_TMPDIR/install.sh" "$BATS_INSTALL_PREFIX"
rm -rf "$BATS_TMPDIR"

echo "Installing bats-support ${BATS_SUPPORT_VERSION}..."
fetch_tarball \
    "${GITHUB_BASE}/bats-support/archive/refs/tags/v${BATS_SUPPORT_VERSION}.tar.gz" \
    "${BATS_LIB_DIR}/bats-support"

echo "Installing bats-assert ${BATS_ASSERT_VERSION}..."
fetch_tarball \
    "${GITHUB_BASE}/bats-assert/archive/refs/tags/v${BATS_ASSERT_VERSION}.tar.gz" \
    "${BATS_LIB_DIR}/bats-assert"

echo "BATS installation complete: bats-core=${BATS_VERSION} bats-support=${BATS_SUPPORT_VERSION} bats-assert=${BATS_ASSERT_VERSION}"
