# batsman — Shared BATS Test Infrastructure

Shared BATS test infrastructure for R-fx Networks projects (APF, BFD, LMD).
Consumed as a git submodule at `tests/infra/` in each project.

Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>

## What It Provides

- **scripts/install-bats.sh** — Single BATS installer used by all Dockerfiles,
  with TLS fallback support for EOL distros (CentOS 6, Ubuntu 12.04)
- **dockerfiles/** — Base OS images (9 targets) with common utilities and BATS
  pre-installed. Projects layer project-specific packages on top.
- **lib/run-tests-core.sh** — Parallel test orchestration engine (sourced library).
  Round-robin file distribution, TAP aggregation, named container cleanup.
- **include/Makefile.tests** — Parameterized GNU Make include generating per-OS,
  tier-grouped, and cross-OS parallel targets.
- **.github/workflows/test.yml** — Reusable GitHub Actions workflow via
  `workflow_call` for CI matrix testing.

## Integration

Add batsman as a submodule in each project:

```bash
cd your-project
git submodule add https://github.com/rfxn/batsman.git tests/infra
git submodule update --init --recursive
```

### Project Dockerfile (layers on base image)

```dockerfile
ARG BASE_IMAGE=batsman-base-debian12
FROM ${BASE_IMAGE}

# Project-specific packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables iproute2 ipset ...

# Copy source, install, configure
COPY . /opt/project-src/
RUN cd /opt/project-src && sh install.sh && ...
COPY tests/ /opt/tests/
WORKDIR /opt/tests
CMD ["bats", "--formatter", "tap", "/opt/tests/"]
```

### Project run-tests.sh (thin wrapper)

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BATSMAN_PROJECT="myproject"
BATSMAN_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATSMAN_TESTS_DIR="$SCRIPT_DIR"
BATSMAN_INFRA_DIR="$SCRIPT_DIR/infra"
BATSMAN_DOCKER_FLAGS="--privileged"
BATSMAN_DEFAULT_OS="debian12"
BATSMAN_CONTAINER_TEST_PATH="/opt/tests"
BATSMAN_SUPPORTED_OS="debian12 centos6 centos7 rocky8 rocky9 rocky10 ubuntu1204 ubuntu2004 ubuntu2404"

source "$BATSMAN_INFRA_DIR/lib/run-tests-core.sh"
batsman_run "$@"
```

### Project Makefile (variable definitions + include)

```makefile
BATSMAN_OS_MODERN := debian12 rocky9 ubuntu2404
BATSMAN_OS_LEGACY := centos7 rocky8 ubuntu2004
BATSMAN_OS_DEEP   := centos6 ubuntu1204
BATSMAN_OS_EXTRA  :=
BATSMAN_OS_ALL    := $(BATSMAN_OS_MODERN) $(BATSMAN_OS_LEGACY) $(BATSMAN_OS_DEEP) $(BATSMAN_OS_EXTRA)
BATSMAN_RUN_TESTS := ./run-tests.sh

include infra/include/Makefile.tests
```

### Project CI workflow (caller)

```yaml
name: Project Tests
on:
  push:
    branches: [master, '2.*']
  pull_request:
    branches: [master]
jobs:
  test:
    uses: rfxn/batsman/.github/workflows/test.yml@v1
    with:
      project-name: myproject
      os-matrix: '["debian12","rocky9","ubuntu2404"]'
      docker-run-flags: '--privileged'
```

## Configuration Reference

### install-bats.sh Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `BATS_VERSION` | `1.11.0` | bats-core version |
| `BATS_SUPPORT_VERSION` | `0.3.0` | bats-support version |
| `BATS_ASSERT_VERSION` | `2.1.0` | bats-assert version |
| `TLS_FALLBACK` | `0` | TLS mode: 0=standard wget, 1=wget --no-check-certificate with curl fallback, 2=curl primary with wget fallback |

### run-tests-core.sh Configuration Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `BATSMAN_PROJECT` | yes | Image tag prefix, container naming |
| `BATSMAN_PROJECT_DIR` | yes | Docker build context root |
| `BATSMAN_TESTS_DIR` | yes | Directory containing .bats files |
| `BATSMAN_INFRA_DIR` | yes | Path to batsman submodule |
| `BATSMAN_DOCKER_FLAGS` | no | Extra docker run flags (e.g. `--privileged`) |
| `BATSMAN_DEFAULT_OS` | no | Default OS when --os omitted (default: debian12) |
| `BATSMAN_CONTAINER_TEST_PATH` | yes | Test directory path inside container |
| `BATSMAN_SUPPORTED_OS` | yes | Space-separated list of supported OS targets |
| `BATSMAN_BASE_OS_MAP` | no | Variant→base mappings (e.g. `"yara-x=debian12"`) |

### Makefile.tests Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `BATSMAN_OS_MODERN` | yes | Modern tier OS list |
| `BATSMAN_OS_LEGACY` | yes | Legacy tier OS list |
| `BATSMAN_OS_DEEP` | no | Deep legacy tier OS list |
| `BATSMAN_OS_EXTRA` | no | Extra OS targets (e.g. yara-x) |
| `BATSMAN_OS_ALL` | yes | Combined full OS list |
| `BATSMAN_RUN_TESTS` | yes | Path to project run-tests.sh |

## Supported OS Targets

| Target | Base Image | Package Manager | Notes |
|--------|-----------|-----------------|-------|
| debian12 | debian:12-slim | apt-get | Default target |
| centos6 | centos:6 | yum | EOL, vault repos, TLS fallback |
| centos7 | centos:7 | yum | EOL, vault repos |
| rocky8 | rockylinux:8-minimal | microdnf | |
| rocky9 | rockylinux:9-minimal | microdnf | |
| rocky10 | rockylinux:10 | dnf | |
| ubuntu1204 | ubuntu:12.04 | apt-get | EOL, old-releases repos, TLS fallback |
| ubuntu2004 | ubuntu:20.04 | apt-get | |
| ubuntu2404 | ubuntu:24.04 | apt-get | |

## License

GNU General Public License v2 — see LICENSE.
