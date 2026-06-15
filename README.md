# QNX DevSecOps Pipeline - VULNERABLE version

A GitLab CI/CD pipeline implementing **DevSecOps practices** for a
QNX Neutrino real-time embedded application.

## Overview

The pipeline cross-compiles a C application targeting **QNX Neutrino x86-64**,
deploys it to a QEMU-virtualised QNX target, runs automated tests over SSH,
and enforces a security gate before any merge is allowed.

## Pipeline Stages

| Stage    | Job                  | Description                                      |
|----------|----------------------|--------------------------------------------------|
| build    | `build`              | Cross-compile with `qcc` for QNX Neutrino x86-64 |
| test     | `test:qemu`          | Smoke + integration tests on live QEMU/QNX VM    |
| security | `security:cppcheck`  | Static analysis – blocks on any `error` finding  |
| security | `security:flawfinder`| SAST – blocks on Level ≥ 4 findings              |
| security | `security:secrets`   | Secret detection with gitleaks                   |
| security | `security:report`    | Aggregated security summary                      |

## Security Gates (Shift-Left)

- **cppcheck** — zero-error policy on `program.c`
- **flawfinder** — any CWE finding at Level ≥ 4 blocks the pipeline
- **gitleaks** — hardcoded credentials prevent merge

The `program.c` file is included **intentionally** to
demonstrate that all three gates fire correctly on real vulnerabilities
(CWE-798, CWE-120, CWE-134, CWE-78, CWE-190, CWE-415, CWE-788, CWE-476).

## Requirements

| Tool              | Purpose                        |
|-------------------|--------------------------------|
| QNX SDP 8 (`qcc`) | Cross-compiler                 |
| QEMU x86-64       | Virtualised QNX target         |
| cppcheck          | Static analysis                |
| flawfinder        | C/C++ SAST                     |
| gitleaks          | Secret / credential detection  |
| sshpass           | Non-interactive SSH in CI      |

## Repository Structure
├── program.c               # VULNERABLE program \
├── .gitlab-ci.yml          # Full DevSecOps pipeline definition \
├── scripts/ \
│   ├── qemu_start.sh       # Start QNX VM in daemon mode \
│   ├── qemu_stop.sh        # Graceful shutdown \
│   └── wait_for_ssh.sh     # Poll until SSH is reachable \
├── tests/ \
│   ├── smoke_test.sh       # Fast sanity checks (5 tests) \
│   └── integration_test.sh # Behavioural tests + JUnit XML (7 tests) \
└── docker-compose.yml      # GitLab CE instance

## Application

`program.c` is a **QNX Neutrino periodic-pulse timer demo** that:
- reads CPU count from `_syspage_ptr`
- creates an IPC channel with `ChannelCreate` / `ConnectAttach`
- arms a `CLOCK_MONOTONIC` timer to fire `SIGEV_PULSE` every 500 ms
- receives 5 pulses and prints timestamped output
- cleans up all resources on exit
