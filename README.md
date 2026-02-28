# batsman — Shared BATS Test Infrastructure

[![Version](https://img.shields.io/github/v/tag/rfxn/batsman?label=version&sort=semver)](https://github.com/rfxn/batsman/releases)
[![License: GPL v2](https://img.shields.io/badge/license-GPLv2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
[![GitHub Issues](https://img.shields.io/github/issues/rfxn/batsman)](https://github.com/rfxn/batsman/issues)
[![Shell](https://img.shields.io/badge/shell-bash-green.svg)](https://www.gnu.org/software/bash/)
[![BATS](https://img.shields.io/badge/bats--core-1.13.0-orange.svg)](https://github.com/bats-core/bats-core)

Shared BATS test infrastructure for R-fx Networks projects.
Consumed as a git submodule at `tests/infra/` in each project.

Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>

## Quick Start

1. Add batsman as a submodule:
   ```bash
   cd your-project
   git submodule add https://github.com/rfxn/batsman.git tests/infra
   git submodule update --init --recursive
   ```

2. Create a project Dockerfile (`tests/Dockerfile`):
   ```dockerfile
   ARG BASE_IMAGE=myproject-base-debian12
   FROM ${BASE_IMAGE}
   RUN apt-get update && apt-get install -y --no-install-recommends your-packages
   COPY . /opt/project-src/
   RUN cd /opt/project-src && sh install.sh
   COPY tests/ /opt/tests/
   WORKDIR /opt/tests
   CMD ["bats", "--formatter", "tap", "/opt/tests/"]
   ```

3. Create `tests/run-tests.sh` (thin wrapper):
   ```bash
   #!/bin/bash
   set -e
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   BATSMAN_PROJECT="myproject"
   BATSMAN_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
   BATSMAN_TESTS_DIR="$SCRIPT_DIR"
   BATSMAN_INFRA_DIR="$SCRIPT_DIR/infra"
   BATSMAN_DEFAULT_OS="debian12"
   BATSMAN_CONTAINER_TEST_PATH="/opt/tests"
   BATSMAN_SUPPORTED_OS="debian12 centos7 rocky8 rocky9 ubuntu2004 ubuntu2404"
   source "$BATSMAN_INFRA_DIR/lib/run-tests-core.sh"
   batsman_run "$@"
   ```

4. Create `tests/Makefile`:
   ```makefile
   BATSMAN_OS_MODERN := debian12 rocky9 ubuntu2404
   BATSMAN_OS_LEGACY := centos7 rocky8 ubuntu2004
   BATSMAN_OS_DEEP   :=
   BATSMAN_OS_EXTRA  :=
   BATSMAN_OS_ALL    := $(BATSMAN_OS_MODERN) $(BATSMAN_OS_LEGACY) $(BATSMAN_OS_DEEP) $(BATSMAN_OS_EXTRA)
   BATSMAN_RUN_TESTS := ./run-tests.sh
   include infra/include/Makefile.tests
   ```

5. Run tests:
   ```bash
   make -C tests test
   ```

## How It Works

### Two-Phase Docker Build

batsman uses a two-phase Docker build to separate base OS infrastructure from
project-specific dependencies:

- **Phase 1 (base image):** Built from batsman's `dockerfiles/Dockerfile.<os>`.
  Installs system packages, common utilities, and BATS. Tagged as
  `<project>-base-<os>` (e.g., `apf-base-debian12`).

- **Phase 2 (project image):** Built from the project's own
  `tests/Dockerfile.<os>`. Uses `ARG BASE_IMAGE` / `FROM ${BASE_IMAGE}` to
  layer on project-specific packages, install the project, and copy test files.

This separation means base images are cached and shared across CI runs, while
project images rebuild only when project code changes.

### Parallel Test Orchestration

`lib/run-tests-core.sh` is a sourced library that provides:

- **Round-robin distribution:** `.bats` files are distributed across N Docker
  containers (default: `nproc * 2`). Each container runs a subset of tests
  independently.
- **TAP aggregation:** Output from all containers is collected and merged into
  a single TAP stream.
- **Named containers:** Each container gets a deterministic name
  (`<project>-test-<os>-<slot>`) for easy debugging. Containers are cleaned up
  on exit, including on `SIGINT`/`SIGTERM`.
- **Sequential fallback:** When `--parallel` is not passed, tests run in a
  single container.

### CI: Reusable Workflow

`.github/workflows/test.yml` is a reusable GitHub Actions workflow called via
`workflow_call`. It:

1. Checks out the project with `submodules: recursive`
2. Sets up Docker Buildx with the `docker-container` driver
3. Builds the base image with GHA cache (`type=gha`)
4. Builds the project image with plain `docker build` (sees the loaded base)
5. Runs tests in the project image

The hybrid approach (docker-container for cached base build, plain docker for
project build) works around limitations with `type=gha` cache on older Docker
versions.

## Supported OS Targets

batsman provides 9 base OS images spanning three tiers plus an extra tier:

| Target | Base Image | Package Manager | Tier | Notes |
|--------|-----------|-----------------|------|-------|
| debian12 | `debian:12-slim` | apt-get | Modern | Default target |
| rocky9 | `rockylinux:9-minimal` | microdnf | Modern | |
| ubuntu2404 | `ubuntu:24.04` | apt-get | Modern | |
| centos7 | `centos:7` | yum | Legacy | EOL, vault repos |
| rocky8 | `rockylinux:8-minimal` | microdnf | Legacy | |
| ubuntu2004 | `ubuntu:20.04` | apt-get | Legacy | |
| centos6 | `centos:6` | yum | Deep Legacy | EOL, vault repos, TLS fallback |
| ubuntu1204 | `ubuntu:12.04` | apt-get | Deep Legacy | EOL, old-releases repos, TLS fallback |
| rocky10 | `rockylinux:10` | dnf | Extra | |

## OS Tier Architecture

Tiers group OS targets by age and compatibility characteristics:

**Modern** — Current production targets. Full TLS support, modern package
managers, Bash 5.x. These run in CI by default for all projects.

**Legacy** — Older but still commonly deployed. EOL repositories may be needed
(CentOS 7 uses `vault.centos.org`). Bash 4.2+. These run in CI to catch
compatibility regressions.

**Deep Legacy** — CentOS 6 (Bash 4.1, kernel 2.6.32) and Ubuntu 12.04 (Bash
4.2). These define the portability floor:
- `wget` may not support TLS 1.2+ — `install-bats.sh` provides a TLS fallback
  mode using `curl -sSL -k` as primary with `wget --no-check-certificate` as
  secondary.
- EOL repositories: `vault.centos.org` for CentOS 6, `old-releases.ubuntu.com`
  for Ubuntu 12.04.
- No systemd — SysV init only.

**Extra** — Targets not included in CI by default. Available for manual testing
via `make -C tests test-<os>`. Rocky 10 is in this tier pending stable release.
Projects may also use Extra for non-OS variants (e.g., LMD's `yara-x` target).

### Package Manager Differences

| OS Family | Manager | Install Command | Notes |
|-----------|---------|----------------|-------|
| Debian/Ubuntu | apt-get | `apt-get install -y --no-install-recommends` | |
| CentOS 6/7 | yum | `yum install -y` | |
| Rocky 8/9 (minimal) | microdnf | `microdnf install -y` | No `--allowerasing` |
| Rocky 10 | dnf | `dnf install -y --allowerasing` | Full dnf |

**Note:** Rocky 8/9 minimal images ship `coreutils-single` which conflicts
with `coreutils` via `microdnf`. Omit `coreutils` from package lists on these
targets — `coreutils-single` provides equivalent commands.

## Integration Guide

### Project Dockerfile Pattern

Each OS needs a project Dockerfile. The default target (debian12) uses
`tests/Dockerfile`; others use `tests/Dockerfile.<os>`.

```dockerfile
ARG BASE_IMAGE=myproject-base-debian12
FROM ${BASE_IMAGE}

# Project-specific packages only — base utilities are in the base image
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables iproute2

# Install project
COPY . /opt/project-src/
RUN cd /opt/project-src && sh install.sh

# Copy tests
COPY tests/ /opt/tests/
WORKDIR /opt/tests
CMD ["bats", "--formatter", "tap", "/opt/tests/"]
```

For RHEL-family targets, use the appropriate package manager:
```dockerfile
# Rocky 8/9 (microdnf)
RUN microdnf install -y iproute && microdnf clean all

# Rocky 10 (dnf)
RUN dnf install -y --allowerasing iproute && dnf clean all

# CentOS 6/7 (yum)
RUN yum install -y iproute && yum clean all
```

### run-tests.sh Wrapper Pattern

The wrapper sets project-specific variables and sources the orchestration
engine. It should be ~20-30 lines.

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Required variables
BATSMAN_PROJECT="myproject"
BATSMAN_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATSMAN_TESTS_DIR="$SCRIPT_DIR"
BATSMAN_INFRA_DIR="$SCRIPT_DIR/infra"
BATSMAN_CONTAINER_TEST_PATH="/opt/tests"
BATSMAN_SUPPORTED_OS="debian12 centos6 centos7 rocky8 rocky9 rocky10 ubuntu1204 ubuntu2004 ubuntu2404"

# Optional variables
BATSMAN_DOCKER_FLAGS="--privileged"     # Only if needed (e.g., iptables tests)
BATSMAN_DEFAULT_OS="debian12"
BATSMAN_BASE_OS_MAP=""                  # e.g., "yara-x=debian12" for variants

source "$BATSMAN_INFRA_DIR/lib/run-tests-core.sh"
batsman_run "$@"
```

### Makefile Include Pattern

The project Makefile defines tier groupings and includes `Makefile.tests`:

```makefile
BATSMAN_OS_MODERN := debian12 rocky9 ubuntu2404
BATSMAN_OS_LEGACY := centos7 rocky8 ubuntu2004
BATSMAN_OS_DEEP   := centos6 ubuntu1204
BATSMAN_OS_EXTRA  := rocky10
BATSMAN_OS_ALL    := $(BATSMAN_OS_MODERN) $(BATSMAN_OS_LEGACY) $(BATSMAN_OS_DEEP) $(BATSMAN_OS_EXTRA)
BATSMAN_RUN_TESTS := ./run-tests.sh

include infra/include/Makefile.tests
```

### CI Workflow Caller Pattern

Projects call the reusable workflow from their own CI configuration:

```yaml
name: Tests
on:
  push:
    branches: [master, '2.*']
  pull_request:
    branches: [master]
jobs:
  test:
    uses: rfxn/batsman/.github/workflows/test.yml@v1.0.1
    with:
      project-name: myproject
      os-matrix: '["debian12","centos7","rocky8","rocky9","ubuntu2004","ubuntu2404"]'
      docker-run-flags: '--privileged'    # omit if not needed
```

## Configuration Reference

### install-bats.sh Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `BATS_VERSION` | `1.13.0` | bats-core version |
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
| `BATSMAN_BASE_OS_MAP` | no | Variant-to-base mappings (e.g. `"yara-x=debian12"`) |
| `BATSMAN_TEST_TIMEOUT` | no | Per-test timeout in seconds (passed as `BATS_TEST_TIMEOUT`) |

### Makefile.tests Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `BATSMAN_OS_MODERN` | yes | Modern tier OS list |
| `BATSMAN_OS_LEGACY` | yes | Legacy tier OS list |
| `BATSMAN_OS_DEEP` | no | Deep legacy tier OS list |
| `BATSMAN_OS_EXTRA` | no | Extra OS targets (e.g. rocky10, yara-x) |
| `BATSMAN_OS_ALL` | yes | Combined full OS list |
| `BATSMAN_RUN_TESTS` | yes | Path to project run-tests.sh |

### CI Workflow Inputs

| Input | Required | Default | Purpose |
|-------|----------|---------|---------|
| `project-name` | yes | — | Project name for image tags |
| `os-matrix` | yes | — | JSON array of OS targets |
| `docker-run-flags` | no | `""` | Extra docker run flags |
| `timeout` | no | `15` | Job timeout in minutes |
| `dockerfile-dir` | no | `tests` | Directory containing project Dockerfiles |

## Common Use Cases

### Make Targets

| Target | Description |
|--------|-------------|
| `test` | Default OS, parallel (default goal) |
| `test-serial` | Default OS, sequential (single container) |
| `test-verbose` | Default OS, pretty formatter (sequential) |
| `test-<os>` | Specific OS, parallel |
| `test-modern` | Modern tier, sequential across OS |
| `test-legacy` | Legacy tier, sequential across OS |
| `test-deep-legacy` | Deep legacy tier, sequential across OS |
| `test-all` | All tiers, sequential across OS |
| `test-modern-parallel` | Modern tier, parallel across OS |
| `test-legacy-parallel` | Legacy tier, parallel across OS |
| `test-deep-legacy-parallel` | Deep legacy tier, parallel across OS |
| `test-all-parallel` | All tiers, parallel across OS |

### Script CLI

```bash
# Run on default OS (parallel)
./tests/run-tests.sh --parallel

# Run on a specific OS
./tests/run-tests.sh --os rocky9 --parallel

# Filter tests by name
./tests/run-tests.sh --filter "install" --parallel

# Run a specific .bats file
./tests/run-tests.sh /opt/tests/01-install.bats

# Custom parallelism level
./tests/run-tests.sh --parallel 4

# Pretty output (sequential only)
./tests/run-tests.sh --formatter pretty

# Per-test timeout (30 seconds)
./tests/run-tests.sh --timeout 30 --parallel

# Stop on first failure
./tests/run-tests.sh --abort --parallel

# Show batsman version
./tests/run-tests.sh --version
```

## Using batsman in Your Own Project

batsman can be used by any Bash project that needs cross-OS BATS testing.

### Requirements

- Docker (with BuildKit support)
- GNU Make
- Bash 4.1+
- Git (for submodule)

### Minimal Standalone Example

For a project with a single OS target and no special requirements:

**`tests/Dockerfile`:**
```dockerfile
ARG BASE_IMAGE=mylib-base-debian12
FROM ${BASE_IMAGE}
COPY . /opt/src/
COPY tests/ /opt/tests/
WORKDIR /opt/tests
CMD ["bats", "--formatter", "tap", "/opt/tests/"]
```

**`tests/run-tests.sh`:**
```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATSMAN_PROJECT="mylib"
BATSMAN_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATSMAN_TESTS_DIR="$SCRIPT_DIR"
BATSMAN_INFRA_DIR="$SCRIPT_DIR/infra"
BATSMAN_CONTAINER_TEST_PATH="/opt/tests"
BATSMAN_SUPPORTED_OS="debian12"
source "$BATSMAN_INFRA_DIR/lib/run-tests-core.sh"
batsman_run "$@"
```

**`tests/Makefile`:**
```makefile
BATSMAN_OS_MODERN := debian12
BATSMAN_OS_LEGACY :=
BATSMAN_OS_DEEP   :=
BATSMAN_OS_EXTRA  :=
BATSMAN_OS_ALL    := $(BATSMAN_OS_MODERN)
BATSMAN_RUN_TESTS := ./run-tests.sh
include infra/include/Makefile.tests
```

Then `make -C tests test` builds the base image, builds the project image,
and runs your BATS tests.

### Customization

- **`BATSMAN_DOCKER_FLAGS`** — Set to `--privileged` if your tests need
  iptables, kernel modules, or network namespaces. Leave empty otherwise.
- **`BATSMAN_BASE_OS_MAP`** — Map variant names to base OS images. For example,
  `"yara-x=debian12"` means the `yara-x` variant reuses the `debian12` base
  image but has its own project Dockerfile (`tests/Dockerfile.yara-x`).
- **Tier groupings** — Adjust `BATSMAN_OS_MODERN`, `BATSMAN_OS_LEGACY`, etc.
  to match your project's support matrix.
- **TLS fallback** — Deep legacy Dockerfiles set `TLS_FALLBACK=2` in the
  `install-bats.sh` invocation to handle systems where `wget` cannot connect
  to GitHub over TLS 1.2+.

### Pinning to a Release Tag

Pin the submodule to a specific tag for reproducibility:

```bash
cd tests/infra
git fetch --tags
git checkout v1.0.1
cd ../..
git add tests/infra
git commit -m "Pin batsman submodule to v1.0.1"
```

In CI workflow callers, reference the same tag:
```yaml
uses: rfxn/batsman/.github/workflows/test.yml@v1.0.1
```

## Consumer Projects

| Project | Docker Flags | Container Test Path | OS Targets | Notable | Repository |
|---------|-------------|--------------------|-----------:|---------|------------|
| APF | `--privileged` | `/opt/tests` | 9 | iptables/netfilter tests | [rfxn/apf](https://github.com/rfxn/apf) |
| BFD | (none) | `/opt/bfd/tests` | 9 | Non-standard test path | [rfxn/bfd](https://github.com/rfxn/bfd) |
| LMD | (none) | `/opt/tests` | 9 + yara-x | BATSMAN_BASE_OS_MAP for yara-x variant | [rfxn/lmd](https://github.com/rfxn/lmd) |
| tlog_lib | (none) | `/opt/tlog_lib/tests` | 9 | Zero project packages needed | [rfxn/tlog_lib](https://github.com/rfxn/tlog_lib) |

## License

GNU General Public License v2 — see LICENSE.
