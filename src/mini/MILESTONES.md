# mini milestones

mini is the canonical XNull compiler. The second-engine and bootstrap paths
were removed on 2026-11-20. Git history keeps the old records; this file
records the mini-only line.

## 2026-11-20 · mini-only cut

- Removed `src/compiler`, `src/bootstrap`, the engine selector, project/build
  CLI paths, and the old differential test scripts.
- `xnull` now exposes only mini build/run/check/version/clean/doctor.
- XDK T0 gates are mini-only: `xdk.sh`, `m10_parity`, `resources.sh`.
- `src/mini/tests/m8.sh` keeps single-file CLI/JSON/exit-code tests.
- `src/mini/build.sh` self-hosts from `bin/mini.c`/`bin/mini`; one compiler.

## 2026-11-18 · mini 0.2.0 / M9-CUT

- mini became the default compiler.
- Self-host fixed point and the 200M performance curve were recorded.
- Legacy remained selectable at that time; that option is now gone.

## 2026-11-18 · Mini 0.3.0 / M10-T0

- XDK-first T0 scenarios: bytes, text, math, time, io, fs, sys, tasks, sync,
  log, config, cli.
- `m10_parity` and `m10_perf` established the XDK floor.
