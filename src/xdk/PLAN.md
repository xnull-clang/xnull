# XDK-first reverse development plan

**Milestone:** Mini 0.3.0 / M10-T0
**Start:** 2026-11-18
**Rule:** XDK is the product. Runtime is the substrate. The compiler is a means.

This plan replaces the compiler-first planning sequence. The old Mini 1.0 /
M9-CUT plan is archived at
[`../mini/archive/2026-11-18-m9cut/`](../mini/archive/2026-11-18-m9cut/).

## 1. Development direction

Every capability starts from a bottom-layer XDK requirement, not from a
compiler feature wish list:

```text
XDK package contract
  → runtime primitive / ABI
  → FFI contract
  → compiler/language support only where required
  → XDK scenario + legacy oracle differential
  → regression and performance evidence
```

No compiler-only feature is added without an XDK package scenario that needs
it. No XDK source package is filled with an empty implementation. No runtime
primitive is "completed" without a consumer and a test.

The T0 package/file/API design baseline is
[`../../docs/设计08-T0核心包详细设计方案-v1.0.0.md`](../../docs/设计08-T0核心包详细设计方案-v1.0.0.md):
one package per stage, with per-file interfaces, contracts, scenarios, and
recorded gaps.

The `legacy` engine is used as an oracle wherever it has the capability. When
legacy itself is incomplete, the specification and runtime ABI are the oracle,
and the gap is recorded explicitly.

## 2. Reverse loop for every slice

1. Pick one T0 package/API from the matrix.
2. Write the smallest executable XDK scenario, including expected stdout,
   stderr, exit code, and error path.
3. Run the scenario through `legacy` and capture behavior/generated calls.
4. Inspect the runtime ABI and existing XDK source to derive the minimal
   implementation.
5. Implement the runtime primitive and XDK wrapper.
6. Add the smallest compiler/language support needed by the scenario.
7. Add a differential regression and update the matrix.
8. Commit code + scenario + regression together; otherwise the slice is not
   complete.

## 3. T0 package matrix

Status is deliberately explicit; `missing` means no claim of support.

| Package | Current state | Next reverse target |
| --- | --- | --- |
| `xdk.errors` | base scenario passing in mini (`tests/xdk_errors.x`) | wrap/mapErr/report error paths |
| `xdk.runtime` | diagnose/exit/clock base scenario passing (`tests/xdk_runtime.x`) | exit-code and clock boundary scenario |
| `xdk.meta` | version/platform base scenario passing (`tests/xdk_meta.x`) | build/target matrix scenario |
| `xdk.bytes` | UTF-8/hex/concat/slice/compare/endian, bit ops, ByteBuffer, ByteReader/ByteWriter verified mini + legacy (`tests/xdk_bytes*.x`) | streaming buffers and mutation/error edge cases |
| `xdk.text` | base and `text/full` verified mini + legacy (`tests/xdk_text*.x`) | UTF-16/format/regex edge cases |
| `xdk.math` | base scenario verified (`tests/xdk_math.x`) | Int128 and numeric edge scenarios |
| `xdk.time` | base scenario verified (`tests/xdk_time.x`) | Instant/DateTime/timezone scenario |
| `xdk.io` | in-memory Reader/Writer verified mini + legacy (`tests/xdk_io.x`); legacy `readBytes` return gap remains | file/network/terminal streams |
| `xdk.fs` | text exists/read/write verified mini + legacy (`tests/xdk_fs.x`) | Path/atomic write/full File/Dir |
| `xdk.sys` | File/Dir/Process plus complete `Resource.x` (exists/size/read/text/list + Context cancellation) verified in base and full modes (`tests/resources*.sh`); remaining File/Dir edges pending | resource-context parity in `m10_parity`; dir/path edges |
| `xdk.tasks` | Task/TaskGroup/Context spawn/join/close/cancel and join deadline verified mini only (`tests/xdk_tasks.x`, `tests/xdk_cancel.x`); legacy task adapter prototype gap | result propagation into group errors; legacy parity |
| `xdk.sync` | AtomicInt/Bool load/store/cas and AtomicRef verified mini + legacy; Mutex<T> + withLock verified mini + legacy; Channel<Int> send/receive/close verified mini only | typed channel elements; Channel legacy parity |
| `xdk.collections` | `[:]` map literals verified mini + legacy (`tests/xdk_collections.x`); generic algorithms `sortBy`/`dedup`/`find` verified mini over Int/String (`tests/xdk_collections_algo.x`); `groupByInt` still blocked on `Map<Int, ...>` runtime | Map/Set runtime + groupByInt; legacy generic function typedefs |
| `xdk.log` | Level thresholds, Logger names, debug/info/warn/error, stdout sink verified mini + legacy (`tests/xdk_log.x`) | fields and pluggable sinks |
| `xdk.config` | profile/key snapshot, overrides, env allowlist verified mini + legacy (`tests/xdk_config.x`) | file/codec loading, profiles |
| `xdk.cli` | Args length/flag/value/positionals, usage and exit-code mapping verified mini (`tests/xdk_cli.x`); legacy String element read gap | subcommands and help rendering |

Cross-cutting XDK slice: complete `Sys Resource.x` + `Context` with
`xdk.io.resource`/`xdk.resource`, tested in both base and full Sys modes.

## 4. Waves

### XDK-W0 — contract and probe baseline — DONE (2026-11-18)

- Lock runtime ABI surface for bytes, resource, tasks, sync, file/dir.
- Build probe scenarios and record legacy/unknown status.
- Record known reverse findings, not fake pass results.
- Exit: matrix has no unowned package and every target has a scenario name.
- Evidence: every package row above names its probe scenario; no package is
  unowned.

### XDK-W1 — runtime base: bytes, IO, FS — DONE (2026-11-19)

- `xdk.bytes`: Bytes/ByteBuffer operations, endian/hex, mutation errors.
- `xdk.io`: Reader/Writer/stream minimal surface.
- `xdk.fs`: path/file/dir/atomic write, base/full Sys bridging.
- Exit: byte/IO/FS scenarios run through mini and legacy where supported.
- Evidence: `src/mini/tests/xdk.sh` passes; bytes, io, and fs scenarios are
  differential (mini vs legacy) except where a legacy gap is recorded.
- Closed scope: core bytes, in-memory Reader/Writer, text exists/read/write.
  Streaming, path, atomic write, and full File/Dir remain in the matrix.

### XDK-W2 — concurrency: tasks and sync — DONE (2026-11-19)

Ordered slices; each slice is code + scenario + regression + commit:

1. **S2-1 `Mutex<T>`** — data-with-lock, scoped access, no bare lock/unlock
   (S5 §6.1). Runtime entry points already exist:
   `xrt_mutex_new`, `xrt_mutex_with_lock`.
   Scenario: `tests/xdk_mutex.x`, mini + legacy differential. **Done**: two
   `withLock` calls mutate the guarded object; both engines print
   `true/true/3`.
2. **S2-2 `Task` / `TaskGroup` / `Context`** — spawn/join/cancel/close with
   first-error mapping. Runtime entry points already exist:
   `xrt_task_group_*`, `xrt_task_join*`, `xrt_context_*`.
   Scenario: `tests/xdk_tasks.x`. **Done (mini)**: Ok/Err joins, group
   first-error mapping on `close`, and context cancellation after close.
   Legacy emits `xn_task_body_*` without adapter prototypes, so the
   differential stays open and is recorded below.
3. **S2-3 Channel completion** — close/drain semantics and cancellation on
   `send`/`receive`. **Done (mini)**: `tests/xdk_channel.x` now covers
   `send`/`receive`, close, post-close `send` failure, and post-close
   `receive` failure. Runtime close discards queued elements; drain means
   observing the closed terminal state. The legacy `Result<void, ...>` gap
   remains open (`xn_Result_void_CancelledError` typedef missing).
4. **S2-4 cancellation and timeout** — context cancel during a blocked
   channel operation and a task join deadline. **Done (mini)**:
   `tests/xdk_cancel.x` cancels a group while a task blocks in `receive`,
   then times out a `joinDeadline` and cancels the task to completion.
- Compiler types only as required by these scenarios.
- Exit: `xdk.tasks`/`xdk.sync` are no longer empty skeletons, and every W2
  scenario is covered by `tests/xdk.sh`.
- Evidence: `src/mini/tests/xdk.sh` passes with four new scenarios;
  `xdk_mutex.x` is differential, `xdk_tasks.x`/`xdk_cancel.x`/
  `xdk_channel.x` are mini-only against recorded legacy gaps.

### XDK-W3 — Sys resource and context — DONE (2026-11-19)

- Load complete `Resource.x` and Context subunits with `xdk.sys`.
- Resource exists/read/count + missing/context-cancel paths.
- Exit: resource project and base/full parity tests.
- **Done**: full Sys mode now loads `io/resource/Resource.x`; base mode keeps
  the lightweight `resourceExists`/`readResourceText`/`resourceCount`
  compatibility surface. `tests/resources.sh` covers the base project, the
  complete full project (mini + legacy differential), and a mini-only
  cancelled-context project.
- Complete surface: `resourceExists`, `resourceSize` (`Int?`),
  `readResource(Context, String)`, `readResourceText(Context, String)`,
  `listResources(Context, String)`. Missing paths, invalid paths (`..`,
  absolute), corrupt UTF-8, and cancelled contexts return the specified
  `ErrorKind`.
- `readResourceText` returns `String`; the obsolete `Text` class no longer
  exists, so the subunit was aligned with the runtime/bridge contract.
- Compiler deltas required by the scenario: full-mode Resource loading,
  `null` assignability for handle/reference parameters, `Int?` printing, and
  `Bytes` method typing in the CGen method table.

### XDK-W4 — collections and generic boundaries — DONE (2026-11-19)

- Empty Map/container literal and contextual type inference (XDK need).
- Generic function-type parameters only where collections require them.
- Collections algorithms and legacy differential.
- Exit: `xdk.collections` scenario compiles and runs on mini.
- **Done (mini)**: generic specialization infers type parameters from
  `List<T>` arguments, monomorphizes `sortBy`/`dedup`/`find`, and clones
  typed function parameters (`Bool(T,T)`, `Bool(T)`, `Int(T)`). Scenarios
  cover Int and String lists in `tests/xdk_collections_algo.x`.
- Compiler deltas: scope-aware inference of local/parameter types in Mono,
  `List<T>` element extraction, top-level comma splitting for parameter
  type lists (`Bool(Int,Int)`), and generic call rewriting.
- Open gaps: `groupByInt` needs `Map<Int,List<T>>` runtime support; legacy
  emits `xn_fn_*` typedefs without declaring them and is therefore not
  differential for generic algorithms. Array literals must still bind to a
  local before use (no expression-level `ArrayLit`).

### XDK-W5 — higher T0: log, config, CLI — DONE (2026-11-19)

- Implement each package against already-proven XDK/runtime primitives.
- No new compiler feature unless its XDK scenario requires one.
- Exit: one runnable package scenario each.
- **Done**: `xdk.log` (`Level`, `Logger`, thresholded
  debug/info/warn/error), `xdk.config` (`Config` profile/key snapshot,
  overrides, env allowlist), and `xdk.cli` (`Args` length/flag/value/
  positionals, `usage`, `exitCodeFor`).
- Scenarios: `tests/xdk_log.x` and `tests/xdk_config.x` are differential
  (mini + legacy); `tests/xdk_cli.x` builds a binary and runs it with
  arguments on mini.
- No new compiler features were required; the packages use existing
  String/List/class/FFI primitives. Package paths were registered in the
  mini loader, package resolver, and legacy bundle.
- Open gap: the legacy oracle miscompiles String element reads through
  `Args.value`; the CLI differential is therefore open and recorded.

### XDK-W6 — T0 conformance and performance — DONE (2026-11-19)

- Add `m10_parity.sh`: all T0 packages, base/full modes.
- Keep M9-PAR 47/47 and 26 regressions green.
- Update the 200M performance curve; reject >20% regressions.
- Exit: full T0 matrix diff=0, performance evidence recorded.
- **Done**: `tests/m10_parity.sh` covers 19 differential file scenarios
  (mini vs legacy in base and full), 5 mini-only scenarios with base/full
  parity, the CLI argv scenario, and the resource base/full/cancel projects.
- `tests/m10_perf.sh` measures 25M/50M/100M/200M. Current 200M is 0.727s
  against the 0.2.0 baseline of 0.733s (0.992x); the 1.2x gate rejects
  regressions above 0.880s.
- The 0.3.0 curve is recorded at
  `docs/assets/mini-200m-runtime-20261119.svg`; mini and legacy stay within
  1.001x at 200M.

### XDK-W7 — release — DONE (2026-11-19)

- `mini 0.3.0`, milestone record, README, RESUME, tag.
- Legacy remains selectable; deletion/default changes need separate approval.
- **Done**: `mini --version` reports `mini 0.3.0`; `MILESTONES.md` records
  `mini-v0.3.0`; English and Chinese READMEs link the 0.3.0 curve; RESUME
  marks W0–W7 closed. Tag created after the release commit.

## 5. Compiler dependency queue

Compiler work is allowed only after its XDK trigger exists:

| XDK trigger | Required compiler/runtime work |
| --- | --- |
| `xdk.sync` Mutex/Channel | `Mutex<T>` type + scoped `withLock` lowering; Channel close/cancel; legacy `Result<void, ...>` gap |
| `xdk.tasks` Task/TaskGroup/Context | task types, cancellation/result mapping |
| `xdk.collections` empty Map | parser/checker/CGen support for `{}` with contextual element types |
| collections generic algorithms | typed function parameters/generic function values |
| resource/context | Result/companion, Context and resource FFI |
| log/config/cli | only package source/adapters over existing text/time/sys/fs |

If a compiler change cannot name its XDK scenario, it stays out of the current
wave.

## 6. Acceptance gates

- Every T0 package has source, a runnable scenario, and an explicit status.
- `m10_parity.sh` covers all T0 packages in base/full modes with stdout,
  stderr, and exit-code equality.
- Existing M9-PAR 47/47, 26 regressions, selfhost, and m8 remain green.
- Runtime ABI probes cover bytes, resource, tasks, sync, file/dir.
- Performance: no >20% regression against the `mini 0.2.0` 200M baseline.
- No empty package, no unimplemented scenario marked PASS.
- Legacy remains available; deletion or default changes require approval.

## 7. Known reverse findings

- `xdk.sync` probe: AtomicInt/AtomicBool construction, `load`/`store`/`cas`,
  and `AtomicRef` now run in both mini and legacy. `Mutex<T>` and
  `withLock` run in mini and legacy (`tests/xdk_mutex.x`). `Channel<Int>`
  runs on mini only: legacy has a `Result<void, ...>` codegen gap
  (`xn_Result_void_CancelledError` typedef missing) that blocks the
  differential. Runtime `channel_close` discards queued elements, so
  post-close `receive` observes the closed terminal state rather than
  draining values.
- `xdk.tasks` probe: Task/TaskGroup/Context now run on mini
  (`tests/xdk_tasks.x`) including Ok/Err joins and group first-error
  mapping. `tests/xdk_cancel.x` proves cancellation of a blocked channel
  operation and `joinDeadline` timeout without consuming the result. The
  legacy oracle emits `xn_task_body_*` without adapter prototypes, so the
  task differential stays open.
- `xdk.sys` probe: base mode keeps the compatibility resource surface; full
  mode now loads `io/resource/Resource.x` so the complete resource API
  (exists/size/read/text/list) runs in mini and legacy with the same output.
  Context cancellation is verified on mini with `Context.background()` and
  `cancel()`; legacy has no `Context.background` builtin and is not claimed
  for the cancelled path.
- `xdk.collections` probe: `import xdk.collections` and
  `Map<String, Int> m = [:]` run in both mini and legacy. Generic algorithms
  now monomorphize on mini (`sortBy`, `dedup`, `find` over Int and String);
  `groupByInt` is blocked by the missing `Map<Int, ...>` runtime, and legacy
  generic algorithms miss `xn_fn_*` typedefs. Both gaps are recorded.
- `xdk.io` probe: the legacy `readBytes` return path still differs from the
  mini path and is recorded as an open gap, not silently excluded.
- `xdk.log`/`xdk.config`/`xdk.cli` probe: log and config are differential;
  CLI argument values compile on mini, while legacy misreads String elements
  from `List<String>.get` in this path.
- M7-F1 Result/companion and closure lifetime remain open boundaries.

## 8. Current next action

XDK-W0 through XDK-W7 are closed and `mini 0.3.0` is released. The next
work is the T0 package-by-package hardening defined in
[`../../docs/设计08-T0核心包详细设计方案-v1.0.0.md`](../../docs/设计08-T0核心包详细设计方案-v1.0.0.md):
execute stages T0-01 … T0-16 in dependency order, one package per stage.

Each stage must land the package file layout/API, a runnable scenario, a
regression, and an explicit mini/legacy differential or recorded gap. The
existing W6 matrix (`m10_parity.sh`) and performance gate remain the floor.
Legacy stays selectable; deletion or default changes require separate
approval.

Release baseline:

```sh
./src/mini/tests/xdk.sh
./src/mini/tests/resources.sh
./src/mini/tests/m10_parity.sh
./src/mini/tests/m10_perf.sh
./src/mini/tests/m9_parity.sh
./src/mini/tests/selfhost.sh
```

`m9_parity` (47/47), the 26 regressions, `selfhost`, `m8`, and the W6
matrix are the floor. Do not spend a wave building compiler machinery
before its XDK scenario exists.
