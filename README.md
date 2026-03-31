# batsman

<p align="center">
  <a href="https://github.com/rfxn/batsman/actions/workflows/self-test.yml"><img src="https://github.com/rfxn/batsman/actions/workflows/self-test.yml/badge.svg?style=flat-square" alt="CI"></a>
  <a href="CHANGELOG"><img src="https://img.shields.io/badge/version-1.4.0-blue.svg?style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL_v2-green.svg?style=flat-square" alt="License"></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/shell-bash-4EAA25.svg?style=flat-square" alt="Shell"></a>
  <a href="https://github.com/bats-core/bats-core"><img src="https://img.shields.io/badge/bats--core-1.13.0-orange.svg?style=flat-square" alt="BATS"></a>
</p>

**BATS test infrastructure for rfxn projects** -- Docker-based multi-OS
test execution with parallel orchestration and Makefile integration.

> (C) 2002-2026, R-fx Networks <proj@rfxn.com>
> Licensed under GNU GPL v2

## Quick Start

```bash
# 1. Add batsman as a submodule
cd your-project
git submodule add https://github.com/rfxn/batsman.git tests/infra
git submodule update --init --recursive

# 2. Create tests/Dockerfile (see Integration Guide for templates)
# 3. Create tests/run-tests.sh and tests/Makefile (see Integration Guide)

# 4. Run tests on the default OS (debian12)
make -C tests test

# 5. Verify a specific OS target
make -C tests test-rocky9
```

## 1. Introduction

batsman is the shared BATS test infrastructure for all R-fx Networks
projects. It provides base OS Docker images, a parallel test orchestration
engine, a parameterized Makefile include, and a reusable GitHub Actions
CI workflow. Consumer projects add batsman as a git submodule at
`tests/infra/` and source its library to run tests across multiple OS
targets.

### 1.1 Supported Systems

batsman provides 9 base OS images spanning three tiers plus an extra tier.

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

### 1.2 Requirements

- Docker (with BuildKit support)
- GNU Make
- Bash 4.1+
- Git (for submodule)

### 1.3 Project Structure

```
dockerfiles/Dockerfile.<os>       # 9 base OS images
include/Makefile.tests            # Parameterized Make include for consumers
lib/run-tests-core.sh             # Parallel test orchestration engine
lib/uat-helpers.bash              # UAT assertion helper library
scripts/install-bats.sh           # BATS installer for Docker images
scripts/file-groups.sh            # Round-robin file distributor for CI matrix
scripts/install-parallel.sh       # GNU parallel installer for deep legacy OS
.github/workflows/test.yml        # Reusable CI workflow (consumers call this)
.github/workflows/self-test.yml   # batsman self-test CI
tests/                            # batsman self-tests
```

## 2. Installation

Add batsman as a git submodule pinned to a release tag.

```bash
cd your-project
git submodule add https://github.com/rfxn/batsman.git tests/infra
cd tests/infra
git fetch --tags
git checkout v1.4.0
cd ../..
git add tests/infra
git commit -m "Pin batsman submodule to v1.4.0"
```

### 2.1 Upgrading

Update the submodule to a new tag and update CI workflow references.

```bash
cd tests/infra
git fetch origin --tags --force
git checkout v1.4.0
cd ../..
git add tests/infra
git commit -m "Pin batsman submodule to v1.4.0"
```

In CI workflow callers, update the tag reference:

```yaml
uses: rfxn/batsman/.github/workflows/test.yml@v1.4.0
```

See the [Migration Guide](#8-migration-guide) for version-specific
upgrade notes.

### 2.2 Key Files

| File | Purpose |
|------|---------|
| `lib/run-tests-core.sh` | Parallel test orchestration engine (sourced by consumer wrappers) |
| `lib/uat-helpers.bash` | UAT assertion helper library (sourced by UAT test files) |
| `include/Makefile.tests` | Parameterized GNU Make include with per-OS and tier targets |
| `scripts/install-bats.sh` | BATS installer with TLS fallback for legacy OS images |
| `scripts/file-groups.sh` | Round-robin file distributor for CI matrix splitting |
| `scripts/install-parallel.sh` | GNU parallel installer for deep legacy OS images |
| `dockerfiles/Dockerfile.<os>` | Base Docker images for each supported OS target |
| `.github/workflows/test.yml` | Reusable GitHub Actions CI workflow |

## 3. Configuration

batsman is configured entirely through shell variables set in the
consumer project's `run-tests.sh` wrapper and `Makefile`. There are
no configuration files to edit.

### 3.1 Orchestration Variables

Variables set in `tests/run-tests.sh` before sourcing `run-tests-core.sh`.

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `BATSMAN_PROJECT` | yes | -- | Image tag prefix and container naming |
| `BATSMAN_PROJECT_DIR` | yes | -- | Docker build context root |
| `BATSMAN_TESTS_DIR` | yes | -- | Directory containing `.bats` files |
| `BATSMAN_INFRA_DIR` | yes | -- | Path to batsman submodule |
| `BATSMAN_CONTAINER_TEST_PATH` | yes | -- | Test directory path inside container |
| `BATSMAN_SUPPORTED_OS` | yes | -- | Space-separated list of supported OS targets |
| `BATSMAN_DOCKER_FLAGS` | no | `""` | Extra `docker run` flags (e.g., `--privileged`) |
| `BATSMAN_DEFAULT_OS` | no | `debian12` | Default OS when `--os` omitted |
| `BATSMAN_BASE_OS_MAP` | no | `""` | Variant-to-base mappings (e.g., `"yara-x=debian12"`) |
| `BATSMAN_TEST_TIMEOUT` | no | -- | Per-test timeout in seconds (overridden by `--timeout`) |
| `BATSMAN_REPORT_DIR` | no | -- | Host directory for JUnit XML reports (overridden by `--report-dir`) |

### 3.2 Makefile Variables

Variables set in `tests/Makefile` before `include infra/include/Makefile.tests`.

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `BATSMAN_OS_MODERN` | yes | -- | Modern tier OS list |
| `BATSMAN_OS_LEGACY` | yes | -- | Legacy tier OS list |
| `BATSMAN_OS_DEEP` | no | -- | Deep legacy tier OS list |
| `BATSMAN_OS_EXTRA` | no | -- | Extra OS targets (e.g., rocky10, yara-x) |
| `BATSMAN_OS_ALL` | yes | -- | Combined full OS list |
| `BATSMAN_RUN_TESTS` | yes | -- | Path to project `run-tests.sh` |
| `BATSMAN_PROJECT` | no | -- | Project name for image tags (required for `clean` targets) |
| `PARALLEL_JOBS` | no | `nproc` | Cross-OS parallel job count for `xargs -P` |

### 3.3 BATS Installer Variables

Variables set in Dockerfiles or passed as build args to `install-bats.sh`.

| Variable | Default | Purpose |
|----------|---------|---------|
| `BATS_VERSION` | `1.13.0` | bats-core version |
| `BATS_SUPPORT_VERSION` | `0.3.0` | bats-support version |
| `BATS_ASSERT_VERSION` | `2.1.0` | bats-assert version |
| `BATS_CORE_SHA256` | *(matches pinned version)* | SHA256 checksum for bats-core tarball |
| `BATS_SUPPORT_SHA256` | *(matches pinned version)* | SHA256 checksum for bats-support tarball |
| `BATS_ASSERT_SHA256` | *(matches pinned version)* | SHA256 checksum for bats-assert tarball |
| `TLS_FALLBACK` | `0` | TLS mode: 0=standard wget, 1=wget `--no-check-certificate` with curl fallback, 2=curl primary with wget fallback |

### 3.4 CI Workflow Inputs

Inputs for the reusable workflow (`.github/workflows/test.yml`).

| Input | Required | Default | Purpose |
|-------|----------|---------|---------|
| `project-name` | yes | -- | Project name for image tags |
| `os-matrix` | yes | -- | JSON array of OS targets |
| `docker-run-flags` | no | `""` | Extra docker run flags |
| `timeout` | no | `15` | Job timeout in minutes |
| `dockerfile-dir` | no | `tests` | Directory containing project Dockerfiles |
| `concurrency-group` | no | `""` | Concurrency group prefix |
| `test-path` | no | `/opt/tests` | Test directory path inside container |
| `parallel-jobs` | no | `0` | BATS parallel jobs via `--jobs N` (0 = serial) |
| `file-groups` | no | `1` | Split test files into N groups per OS (multi-container parallelism) |
| `reports` | no | `true` | Generate JUnit XML reports and upload as artifacts |

## 4. Usage

batsman provides three interfaces: a shell library (`batsman_run`),
Make targets, and a reusable CI workflow. All three use the same
underlying orchestration engine.

### 4.1 Script CLI

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

# Filter tests by tag
./tests/run-tests.sh --filter-tags "smoke" --parallel

# Stop on first failure
./tests/run-tests.sh --abort --parallel

# Generate JUnit XML reports
./tests/run-tests.sh --report-dir /tmp/reports --parallel

# Clean up project images after test run
./tests/run-tests.sh --os rocky9 --clean --parallel

# Show batsman version
./tests/run-tests.sh --version
```

### 4.2 Make Targets

| Target | Description |
|--------|-------------|
| `test` | Default OS, parallel (default goal) |
| `test-serial` | Default OS, sequential (single container) |
| `test-verbose` | Default OS, pretty formatter (sequential) |
| `test-report` | Default OS, parallel, JUnit XML in `reports/` |
| `test-<os>` | Specific OS, parallel |
| `test-modern` | Modern tier, sequential across OS |
| `test-legacy` | Legacy tier, sequential across OS |
| `test-deep-legacy` | Deep legacy tier, sequential across OS |
| `test-all` | All tiers, sequential across OS |
| `test-modern-parallel` | Modern tier, parallel across OS |
| `test-legacy-parallel` | Legacy tier, parallel across OS |
| `test-deep-legacy-parallel` | Deep legacy tier, parallel across OS |
| `test-all-parallel` | All tiers, parallel across OS |
| `clean` | Remove all images for current project |
| `clean-all` | Remove all batsman project images across all projects |
| `clean-dangling` | Prune dangling images only (always safe) |

### 4.3 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed (or `--help`/`--version` displayed) |
| 1 | Test failures, build errors, missing variables, or invalid arguments |

## 5. Docker Build

batsman uses a two-phase Docker build to separate base OS infrastructure
from project-specific dependencies.

### 5.1 Build Phases

- **Phase 1 (base image):** Built from batsman's `dockerfiles/Dockerfile.<os>`.
  Installs system packages, common utilities, and BATS. Tagged as
  `<project>-base-<os>` (e.g., `apf-base-debian12`).

- **Phase 2 (project image):** Built from the project's own
  `tests/Dockerfile.<os>`. Uses `ARG BASE_IMAGE` / `FROM ${BASE_IMAGE}` to
  layer on project-specific packages, install the project, and copy test files.

Base images are cached and shared across CI runs. Project images rebuild
only when project code changes.

### 5.2 Image Lifecycle

Docker images accumulate across test runs. batsman provides opt-in cleanup:

- **Auto-prune:** After every build, dangling images (orphaned by tag
  replacement) are automatically pruned. This is silent and always safe.
- **`--clean` flag:** Removes the base and test images for the target OS after
  the test run completes. Test exit codes are preserved.
- **`batsman_clean()`:** Public function with three modes: no args (current OS),
  `--all` (all project images), `--dangling-only`.
- **Makefile targets:** `clean` (current project), `clean-all` (all batsman
  projects), `clean-dangling` (dangling only).

### 5.3 Package Managers

| OS Family | Manager | Install Command | Notes |
|-----------|---------|----------------|-------|
| Debian/Ubuntu | apt-get | `apt-get install -y --no-install-recommends` | |
| CentOS 6/7 | yum | `yum install -y` | |
| Rocky 8/9 (minimal) | microdnf | `microdnf install -y` | No `--allowerasing` |
| Rocky 10 | dnf | `dnf install -y --allowerasing` | Full dnf |

Rocky 8/9 minimal images ship `coreutils-single` which conflicts with
`coreutils` via `microdnf`. Omit `coreutils` from package lists on these
targets.

## 6. Test Orchestration

The orchestration engine distributes test files across parallel Docker
containers and aggregates the results.

### 6.1 Parallel Execution

- `.bats` files are distributed round-robin across N Docker containers
  (default: `nproc`).
- Each container runs a subset of tests independently.
- TAP output from all containers is collected and merged into a single stream.
- Each container gets a deterministic name (`<project>-<os>-<pid>-g<N>`)
  for debugging. Containers are cleaned up on exit, including on
  `SIGINT`/`SIGTERM`.

### 6.2 Formatter Restriction

Parallel mode forces `tap` formatter for TAP stream aggregation. The
`--formatter` option applies only to sequential and direct modes. Use
`make test-verbose` (sequential) for pretty-formatted output.

### 6.3 OS Tier Architecture

**Modern** -- Current production targets. Full TLS support, modern package
managers, Bash 5.x. Run in CI by default.

**Legacy** -- Older but still commonly deployed. EOL repositories may be
needed (CentOS 7 uses `vault.centos.org`). Bash 4.2+.

**Deep Legacy** -- CentOS 6 (Bash 4.1, kernel 2.6.32) and Ubuntu 12.04
(Bash 4.2). These define the portability floor. `install-bats.sh` provides
TLS fallback modes for systems where `wget` cannot connect to GitHub over
TLS 1.2+. SHA256 checksums verify download integrity regardless of TLS mode.

**Extra** -- Targets not included in CI by default. Available for manual
testing via `make -C tests test-<os>`. Projects may also use Extra for
non-OS variants (e.g., LMD's `yara-x` target).

## 7. Integration Guide

Consumer projects need three files to integrate with batsman: a Dockerfile,
a `run-tests.sh` wrapper, and a Makefile.

### 7.1 Project Dockerfile

Each OS needs a project Dockerfile. The default target (debian12) uses
`tests/Dockerfile`; others use `tests/Dockerfile.<os>`.

```dockerfile
ARG BASE_IMAGE=myproject-base-debian12
FROM ${BASE_IMAGE}

# Project-specific packages only -- base utilities are in the base image
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

### 7.2 run-tests.sh Wrapper

The wrapper sets project-specific variables and sources the orchestration
engine.

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

### 7.3 Makefile Include

The project Makefile defines tier groupings and includes `Makefile.tests`.

```makefile
BATSMAN_OS_MODERN := debian12 rocky9 ubuntu2404
BATSMAN_OS_LEGACY := centos7 rocky8 ubuntu2004
BATSMAN_OS_DEEP   := centos6 ubuntu1204
BATSMAN_OS_EXTRA  := rocky10
BATSMAN_OS_ALL    := $(BATSMAN_OS_MODERN) $(BATSMAN_OS_LEGACY) $(BATSMAN_OS_DEEP) $(BATSMAN_OS_EXTRA)
BATSMAN_RUN_TESTS := ./run-tests.sh
BATSMAN_PROJECT   := myproject

include infra/include/Makefile.tests
```

### 7.4 CI Workflow Caller

Projects call the reusable workflow from their own CI configuration.

```yaml
name: Tests
on:
  push:
    branches: [master, '2.*']
  pull_request:
    branches: [master]
jobs:
  test:
    uses: rfxn/batsman/.github/workflows/test.yml@v1.4.0
    with:
      project-name: myproject
      os-matrix: '["debian12","centos7","rocky8","rocky9","ubuntu2004","ubuntu2404"]'
      docker-run-flags: '--privileged'    # omit if not needed
      parallel-jobs: 4                    # BATS --jobs 4 (omit for serial)
```

### 7.5 Minimal Example

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
BATSMAN_PROJECT   := mylib
include infra/include/Makefile.tests
```

Then `make -C tests test` builds the base image, builds the project image,
and runs your BATS tests.

### 7.6 Pinning to a Release

Pin the submodule to a specific tag for reproducibility:

```bash
cd tests/infra
git fetch --tags
git checkout v1.4.0
cd ../..
git add tests/infra
git commit -m "Pin batsman submodule to v1.4.0"
```

In CI workflow callers, reference the same tag:
```yaml
uses: rfxn/batsman/.github/workflows/test.yml@v1.4.0
```

## 8. Migration Guide

Upgrade notes for consumer projects. Newest version first.

### 8.1 Upgrading to v1.4.0

### File-Group Splitting

The `file-groups` input splits test files across multiple GHA matrix jobs
for multi-container parallelism. Each group runs in an isolated container
with its own state — ideal for test suites where files share kernel or
system resources (iptables, cgroups).

```yaml
uses: rfxn/batsman/.github/workflows/test.yml@v1.4.0
with:
  project-name: apf
  os-matrix: '["debian12","rocky9"]'
  docker-run-flags: '--privileged'
  file-groups: 4
```

With 8 OS targets and `file-groups: 4`, this produces 32 parallel jobs.
Each group gets a round-robin subset of `[0-9]*.bats` files sorted by name.

| Setting | Behavior |
|---------|----------|
| `file-groups: 1` (default) | All files in one job per OS (current behavior) |
| `file-groups: N` | N groups per OS, round-robin file distribution |
| `file-groups` > file count | Capped at file count (no empty jobs) |

`file-groups` and `parallel-jobs` are orthogonal:
- `file-groups` splits across GHA jobs (separate containers)
- `parallel-jobs` runs files in parallel within a container
- A consumer can use both if their tests support concurrent execution

**Deep legacy support:** All 9 base Docker images now include GNU
`parallel`. CentOS 6 and Ubuntu 12.04 install it via a standalone Perl
script (`scripts/install-parallel.sh`) with SHA256 verification.

### 8.2 Upgrading to v1.3.0

**CI parallel test execution (opt-in)**

The reusable workflow now accepts a `parallel-jobs` input that passes
`--jobs N` to BATS, running test files in parallel within each matrix
job. Default is `0` (serial) — no behavior change unless you opt in.

To enable, add `parallel-jobs` to your workflow caller:

```yaml
uses: rfxn/batsman/.github/workflows/test.yml@v1.3.0
with:
  parallel-jobs: 4    # recommended for GHA standard runners
```

BATS `--jobs` requires GNU `parallel` inside the container and test
files that are independent (no cross-file state sharing). Tests within
each file still run sequentially. `setup_file`/`teardown_file` scoping
is preserved. Deep legacy images (centos6, ubuntu1204) lack `parallel`
and fall back to serial execution automatically with a CI warning.

### 8.3 Upgrading to v1.0.3

**SHA256 checksum verification (transparent)**

`install-bats.sh` now verifies SHA256 checksums for all three downloaded
tarballs (bats-core, bats-support, bats-assert) after download and before
extraction. This is transparent for standard usage. If you override
`BATS_VERSION`, `BATS_SUPPORT_VERSION`, or `BATS_ASSERT_VERSION`, you
must also set the corresponding SHA256 variables.

**Default parallelism reduced**

Default parallel container count changed from `nproc*2` to `nproc` for
both intra-OS containers and cross-OS parallel jobs. To restore the
previous behavior:

```bash
# Intra-OS: override via CLI
./tests/run-tests.sh --parallel $(($(nproc) * 2))

# Cross-OS: override via Make variable
make -C tests test-all-parallel PARALLEL_JOBS=$(($(nproc) * 2))
```

**CLI argument parsing stricter**

Flags that require a value (`--os`, `--filter`, `--filter-tags`,
`--formatter`, `--timeout`, `--report-dir`) now error when the trailing
argument is missing. `--timeout` rejects non-numeric values. Unknown
`--flags` emit a warning instead of silently routing to direct mode.

### 8.4 Upgrading to v1.0.2

**BATS 1.13.0 run-variable unset -- BREAKING CHANGE**

BATS was upgraded from 1.11.0 to 1.13.0. Starting with BATS 1.12.0, the
`run` command unsets `$output`, `$lines`, `$stderr`, and `$stderr_lines`
at the start of each invocation. Tests that rely on stale values from a
previous `run` call will silently produce incorrect results.

**Broken pattern:**
```bash
@test "example" {
    run some_command
    run another_command
    # BUG: $output now contains only another_command's output
    assert_output --partial "from some_command"  # FAILS
}
```

**Fixed pattern:**
```bash
@test "example" {
    run some_command
    local first_output="$output"
    run another_command
    assert_output --partial "from another_command"
    [[ "$first_output" == *"from some_command"* ]]
}
```

**New CLI options available**

v1.0.2 added `--timeout`, `--abort`, `--filter-tags`, `--report-dir`,
`--clean`, and `--version`.

**CI workflow changes**

The reusable workflow gained `test-path`, `reports`, and
`concurrency-group` inputs. JUnit XML reports are uploaded as artifacts
with 14-day retention.

### 8.5 Upgrading to v1.0.1

**Variant mapping (new capability)**

v1.0.1 introduced `BATSMAN_BASE_OS_MAP` for mapping non-OS variant names
to base OS images (e.g., `"yara-x=debian12"`). No action required unless
you want to use this feature.

**Makefile include and CI workflow introduced**

v1.0.1 added `include/Makefile.tests` and `.github/workflows/test.yml`.
Projects upgrading from v1.0.0 need to create a `tests/Makefile` and CI
workflow caller.

## 9. UAT Framework

batsman supports a separate UAT (User Acceptance Testing) layer alongside
unit and integration tests. UAT scenarios test multi-step workflows,
output quality, and cross-view consistency.

### 9.1 How It Works

- UAT scenarios live in `tests/uat/` as standard BATS files.
- They are invisible to `make test` (the parallel runner uses `maxdepth 1`).
- Run with `make uat` or `make uat-verbose`.
- Uses the same Docker images as unit tests -- no separate build.
- Shared assertion helpers via `lib/uat-helpers.bash`.

### 9.2 Directory Structure

```
tests/
├── infra/                    # batsman submodule
├── helpers/
│   └── uat-myproject.bash    # Project-specific UAT helpers
├── uat/                      # UAT scenario files
│   ├── 01-workflow-a.bats
│   └── 02-workflow-b.bats
├── 01-unit-tests.bats        # Unit tests (run by make test)
└── Makefile
```

### 9.3 Available Helpers

JSON assertion helpers (`assert_valid_json`, `assert_json_field`,
`assert_json_array_length`) require `python3` in the container. batsman
base images do not install python3 -- add it to your project Dockerfile
if using these helpers.

| Function | Purpose |
|----------|---------|
| `uat_setup` | Create output capture directory and session log |
| `uat_capture SCENARIO CMD...` | Run command, capture output to named log |
| `uat_log MSG` | Append timestamped message to session log |
| `assert_valid_json` | Validate `$output` is parseable JSON |
| `assert_valid_csv [COLS]` | Validate CSV structure and column consistency |
| `assert_empty_state_message` | Verify non-blank "no data" message |
| `assert_no_banner_corruption FMT` | Verify structured output has no version banner |
| `assert_json_field KEY EXPECTED` | Assert JSON field value with dot-notation |
| `assert_json_array_length KEY COUNT` | Assert JSON array length at a given key path |
| `assert_csv_row_count COUNT` | Assert CSV data row count (excluding header) |
| `assert_csv_header COLS...` | Assert CSV header contains expected column names |
| `assert_output_line_count MIN [MAX]` | Assert output line count (exact or range) |
| `assert_file_perms FILE OCTAL` | Assert file permission matches expected octal |
| `assert_process_running PATTERN` | Assert process matching pattern exists |
| `assert_process_not_running PATTERN` | Assert no process matching pattern exists |
| `uat_wait_for_condition CMD TIMEOUT` | Poll command until success or timeout |
| `uat_wait_for_file FILE TIMEOUT` | Wait for file to exist and be non-empty |
| `uat_wait_for_log FILE PATTERN TIMEOUT` | Wait for pattern to appear in log file |
| `uat_cleanup_processes PATTERN` | Kill matching processes with SIGKILL fallback |

### 9.4 Running UAT

```bash
# All UAT scenarios (default OS)
make -C tests uat

# Verbose output
make -C tests uat-verbose

# Specific category via BATS tags
./tests/run-tests.sh --filter-tags "uat:ban-lifecycle" -- /opt/tests/uat/

# Specific file
./tests/run-tests.sh -- /opt/tests/uat/01-workflow-a.bats
```

### 9.5 Tag Convention

- Tag all UAT tests with `uat` for universal filtering.
- Add category sub-tags: `uat:ban-lifecycle`, `uat:output-quality`, etc.
- Syntax: `# bats test_tags=uat,uat:category-name`

## 10. Consumer Projects

Projects currently using batsman as their test infrastructure.

| Project | Docker Flags | Test Path | OS Targets | Notable | Repository |
|---------|-------------|-----------|-----------|---------|------------|
| APF | `--privileged` | `/opt/tests` | 9 | iptables/netfilter tests | [rfxn/apf](https://github.com/rfxn/apf) |
| BFD | (none) | `/opt/tests` | 9 | | [rfxn/bfd](https://github.com/rfxn/bfd) |
| LMD | (none) | `/opt/tests` | 9 + yara-x | BATSMAN_BASE_OS_MAP for yara-x variant | [rfxn/lmd](https://github.com/rfxn/lmd) |
| tlog_lib | (none) | `/opt/tests` | 9 | Zero project packages needed | [rfxn/tlog_lib](https://github.com/rfxn/tlog_lib) |

## License

GNU General Public License v2 -- see [LICENSE](LICENSE).

## Support

- **Issues:** [github.com/rfxn/batsman/issues](https://github.com/rfxn/batsman/issues)
- **Email:** proj@rfxn.com
- **Web:** [rfxn.com](https://www.rfxn.com)
