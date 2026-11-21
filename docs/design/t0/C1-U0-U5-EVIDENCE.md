# C1 evidence and U0–U5 user journeys

| Item | Value |
| --- | --- |
| Base commit | `77e95ae3` (three reference programs PASS) |
| Machine | Darwin 25.5.0 x86_64, Apple clang 17.0.0 (clang-1700.6.3.2) |
| Date | 2026-11-21 |
| Reviewer | 待签 |

## A1. API manifest

Generated from `src/ffi/capabilities.tsv` and package/source evidence by
`src/toolchain/gen_api_manifest.py`; no symbol is hand-added. One row per
public symbol, with signature and stability.

```text
python3 src/toolchain/gen_api_manifest.py
api manifest: 114 symbols / 14 packages
src/ffi/api-manifest.tsv
xdk/ffi/api-manifest.tsv
```

`ByteBuffer` has its own row pointing at `xdk_bytes_extra.x` and
`xdk_bytes_strict.x`; `dumpTasks` points at `ref/u2_task_dump.x`.

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

## U0. Reproducible install

`src/toolchain/release.sh` builds a deterministic tarball (fixed
`SOURCE_DATE_EPOCH=1700000000`, sorted entries, fixed mtime/uid/gid, gzip mtime).
It writes `xnull-1.0.0.tar.gz`, its `.sha256`, and `VERSION`.

Two independent runs:

```text
run1 sha256 9395415af43d1de03fc39c5943c05e6e4f7c76f2b7d4d03d507656662b190f63
run2 sha256 9395415af43d1de03fc39c5943c05e6e4f7c76f2b7d4d03d507656662b190f63
cmp: identical
```

Installed from that tarball into `/tmp/c1_u0_release/prefix/xnull-1.0.0`:

```text
doctor exit 0:
mini: .../xnull-1.0.0/src/mini/bin/mini
runtime: .../xnull-1.0.0/src/runtime
cc: /usr/bin/cc
python3: /Users/vjs/.local/bin/python3
ffi projection: ok
engine: mini
hello exit 0: hello from released xnull
```

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

## U2. Injected failure and task dump

Compile failure in the project (`line(item)` → `line(missing)`):

```text
xnull check --json: exit 1
{"ok":false,...,"code":"SEM-001","message":"undefined symbol: missing",
 "line":6,"column":16,...}
xnull run: exit 1
/tmp/c1_u2/project/src/main/x/main.x:6:16: [SEM-001] undefined symbol: missing
```

Runtime diagnostic surface: `xdk.runtime.dumpTasks()` writes task
live/spawned/settled/carrier counters to stderr. The U2 probe
`src/mini/tests/ref/u2_task_dump.x` (run with `XNULL_CARRIERS=1`) prints:

```text
stdout:
true
1
stderr:
tasks: live=1 spawned=1 settled=0 carrier=1
tasks: live=0 spawned=1 settled=1 carrier=1
```

The first dump locates the blocked task; after `cancel`/`join`, the second
shows it settled. `ref.sh` diffs both streams.

## U3. 0.x upgrade

Worktree: `../XNull-mini-0.3.0` at tag `mini-v0.3.0` (commit `a36d123b`).

Official build attempt:

```text
./src/mini/build.sh -> exit 2
libxnrt.a: built and cached
shasum: .../src/bootstrap/bin/xn-s4: No such file or directory
xnull: bootstrap tool missing; run src/bootstrap/build.sh
```

The tag has no bootstrap artifact, so the official 0.3.0 build cannot run on
this machine. Per the fallback rule, a minimal substitute artifact was built
from the tag's own `src/mini/main.x` using the 1.0 mini as the seed compiler,
then linked with the tag runtime:

```text
artifact: /tmp/u3/xnull-0.3.0.tar.gz
sha256 45f2897d4e739c06e1eee3f3b816d89fc393d1d5c8643f0a8373d0039023f19b
installed version: mini 0.3.0
```

0.3.0 on `/tmp/u3/project` (single entry + `model.x`):

```text
mini 0.3.0
before=1
```

1.0 upgrade of the same project per `MIGRATION-0.x-to-1.0.md`: added
`xnull.project`, kept `model.x`, added `xdk.log` + `Logger.withField`.

```text
xnull check: sema ok, exit 0
xnull build: exit 0
run:
before=1
[INFO] u3: ready stage=upgraded
```

U3 is PASS with the documented substitute artifact; the missing official
bootstrap is recorded above rather than hidden.

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
