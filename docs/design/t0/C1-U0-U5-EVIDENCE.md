# C1 evidence and U0–U5 user journeys

| Item | Value |
| --- | --- |
| Base commit | `77e95ae3` (three reference programs PASS) |
| Machine | Darwin 25.5.0 x86_64, Apple clang 17.0.0 (clang-1700.6.3.2) |
| Date | 2026-11-21 |
| Reviewer | 待签 |

## A1. API manifest

Generated from `src/ffi/capabilities.tsv` and the package design headers by
`src/toolchain/gen_api_manifest.py`; no symbol is hand-added.

```text
python3 src/toolchain/gen_api_manifest.py
api manifest: 14 packages
src/ffi/api-manifest.tsv
```

## R0. Reproducible bootstrap

Commands, run twice:

```sh
src/runtime/build_rt.sh --lib
src/mini/tests/selfhost.sh
```

Observed:

```text
run1 rt=b5c54590e4db7e83e8c819fb3ea356d67d62777b4f9e633a6894fe7e9566fc13 selfhost=mini selfhost: PASS
run2 rt=b5c54590e4db7e83e8c819fb3ea356d67d62777b4f9e633a6894fe7e9566fc13 selfhost=mini selfhost: PASS
cc: Apple clang version 17.0.0 (clang-1700.6.3.2)
uname: Darwin 25.5.0 x86_64
load: 5.76 4.48 4.48
```

The runtime library hash and selfhost result are identical across both runs;
there is no differing segment to locate.

## R4. Package signatures

`AUDIT.md` §3.6 is a per-package ledger with Reviewer `待签` and the actual gate
command for each package. No package is self-signed.

## R9 / U4. Reference performance load

`src/mini/tests/m10_perf.sh` was run five times; each run is a full 25M/50M/
100M/200M compile+run cycle. 200M results:

```text
0.693, 0.651, 0.649, 0.670, 0.634
median = 0.651s
baseline = 0.733s
ratio = 0.888x
```

Budgets and observed for the 200M point:

| Budget | Limit | Observed |
| --- | --- | --- |
| 200M run | ≤ 0.880s (1.2× baseline) | 0.651s median |
| compile | ≤ 5s | 2.10s (200M source, `xnull build`) |
| run RSS | ≤ 16 MiB | 0.59 MiB |
| compile RSS | ≤ 128 MiB | 41.42 MiB |

The full `m10_perf.sh` wall time is about 15.3s per run because it compiles and
runs four points; that is separate from the 200M compile/run budget above.

## U0. Install from local artifact

Built a temporary release tarball (not committed) from `src/cli`,
`src/toolchain`, `src/mini/bin/mini`, `src/runtime`, `src/xdk`, `src/ffi`:

```text
/tmp/c1_u0/xnull-1.0.0.tar.gz
sha256 7c9d711d09820c9d8a37898934ce449dc86693b66a758a071d7f00a09ef18772
```

Extracted to `/tmp/c1_u0/prefix`; `doctor` and hello output:

```text
mini: /tmp/c1_u0/prefix/src/mini/bin/mini
runtime: /tmp/c1_u0/prefix/src/runtime
cc: /usr/bin/cc
python3: /Users/vjs/.local/bin/python3
ffi projection: ok
engine: mini
hello from installed xnull
```

`doctor` exit 0, hello exit 0.

## U1. Multi-file project

Project: `/tmp/c1_u1/project`, copied from
`src/mini/tests/ref/project` (`xnull.project`, `main.x`, `model.x`,
`report.x`; entry imports `model` and `report`).

```text
xnull check /tmp/c1_u1/project        # sema ok, exit 0
xnull build /tmp/c1_u1/project -o ... # exit 0
/tmp/c1_u1/app                        # alpha=2 / 6
```

After editing `main.x` to use count 3 and rebuilding:

```text
alpha=3
6
```

`xnull run /tmp/c1_u1/project` also prints `alpha=3 / 6`. This is a full
rebuild on change; there is no incremental object cache, and the docs do not
claim one.

## U2. Injected failure

Changed `line(item)` to `line(missing)` in the project.

```text
xnull check --json: exit 1
{"ok":false,...,"code":"SEM-001","message":"undefined symbol: missing",
 "line":6,"column":16,...}
xnull run: exit 1
/tmp/c1_u2/project/src/main/x/main.x:6:16: [SEM-001] undefined symbol: missing
```

The error code and source location are sufficient to locate the failure. There
is no task dump API in the 1.0 surface; U2 uses the diagnostic/error-code path.

## U3. 0.x upgrade

Guide: `docs/design/t0/MIGRATION-0.x-to-1.0.md`.
Sample: `src/mini/tests/ref/migration_sample.x`; output
`[INFO] migration: ready version=1.0`.

**Explicit incomplete item:** no installable 0.x artifact exists in this
workspace, so the migration was validated by source patterns and a compilable
1.0 sample, not by an in-place install/upgrade. This is the only unfinished U3
item.

## U5. Non-author trial

An independent subagent was given only `README.md` and the T0 package docs
(`00-overview`, `14-log`, `15-config`, `16-cli`), with no source access. It
created `/tmp/c1_u5_user` (`xnull.project`, `app.x`, `util.x`, `report.x`).

Result: **PASS**. `check` printed `sema ok`; `build` and `run` both exited 0
with identical deterministic output (including log lines and sum `55`).

Documentation gaps reported and action taken:

1. `xnull.project` format was unspecified → README now shows a minimal
   manifest example.
2. Relative `build`/`run`/`check` paths failed with a misleading empty-input
   error → `resolve_entry` now canonicalizes relative files/directories to
   absolute paths.
3. Import/module semantics were under-specified → README now states
   same-directory `import model` and dotted subdirectory imports.
4. Core syntax was not in the allowed doc set → README now links S1–S5.
5. `Args` flags need leading `--` (`"--verbose"`, not `"verbose"`) → documented
   in `16-cli.md`.
6. `xnull check` on a config-importing project failed with a phantom
   `fsErrorRaw` while `run` succeeded → `cmd_check` now passes the same
   projected `--project-file` as build/run; the trial project checks cleanly.

After the fixes, `/tmp/c1_u5_user` was rechecked with `xnull check .` and a
relative build from the project directory; both pass.

## C1 reference programs

`src/mini/tests/ref.sh` builds and runs:

- `ref/cli_tool.x` → `cli_help.out`, `cli_run.out`, `cli_missing.out`
- `ref/concurrent.x` → `concurrent.out`
- `ref/ffi_bytes.x` → `ffi_bytes.out`
- `ref/project` → `project.out`
- `ref/migration_sample.x` → `migration_sample.out`

All pass. Gap found and fixed: `Bytes.toString` used `rt_string_from_c`
(strlen) and evaluated its receiver twice; `xn_bytes_to_string` now takes the
Bytes pointer once and honors `xrt_bytes_len`. The pipe/`readStdoutAll()` and
FileSource paths exercised this and are green.
