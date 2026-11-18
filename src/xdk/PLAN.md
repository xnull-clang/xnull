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

| Package | Current state | First reverse target |
| --- | --- | --- |
| `xdk.errors` | base surface | error/wrap/mapErr scenario |
| `xdk.runtime` | base surface | diagnose/exit/clock scenario |
| `xdk.meta` | base surface | version/platform/build scenario |
| `xdk.bytes` | UTF-8/hex/concat/slice/compare/endian, bit ops, ByteBuffer, ByteReader/ByteWriter added | bit API edge cases and streaming buffers |
| `xdk.text` | `text/full` | UTF/format/regex/parse scenario |
| `xdk.math` | base surface | numeric/Int128 scenario |
| `xdk.time` | base surface | Instant/DateTime/timezone scenario |
| `xdk.io` | minimal in-memory Reader/Writer added; legacy `readBytes` return gap; file/network/terminal streams pending | stream + legacy gap scenario |
| `xdk.fs` | minimal text exists/read/write added over base Sys; path/atomic-write/full File/Dir pending | path/atomic-write scenario |
| `xdk.sys` | partial File/Dir/Process | Env/platform/resource/context scenario |
| `xdk.tasks` | empty skeleton | TaskGroup/Context scenario |
| `xdk.sync` | AtomicInt/Bool load/store/cas, AtomicRef, Channel<Int> mini path added; legacy Channel Result gap; Mutex/tasks pending | Mutex/tasks scenario |
| `xdk.collections` | source exists; `[:]` + import now works; generic function types still block full source | Map/Set/List scenario; generic function values |
| `xdk.log` | missing package source | Logger/Level/sink scenario |
| `xdk.config` | missing package source | Config snapshot/env allowlist scenario |
| `xdk.cli` | missing package source | Args/Command/exit-code scenario |

Cross-cutting XDK slice: complete `Sys Resource.x` + `Context` with
`xdk.io.resource`/`xdk.resource`, tested in both base and full Sys modes.

## 4. Waves

### XDK-W0 — contract and probe baseline

- Lock runtime ABI surface for bytes, resource, tasks, sync, file/dir.
- Build probe scenarios and record legacy/unknown status.
- Record known reverse findings, not fake pass results.
- Exit: matrix has no unowned package and every target has a scenario name.

### XDK-W1 — runtime base: bytes, IO, FS

- `xdk.bytes`: Bytes/ByteBuffer operations, endian/hex, mutation errors.
- `xdk.io`: Reader/Writer/stream minimal surface.
- `xdk.fs`: path/file/dir/atomic write, base/full Sys bridging.
- Exit: byte/IO/FS scenarios run through mini and legacy where supported.

### XDK-W2 — concurrency: tasks and sync

- Runtime bridge for Task/TaskGroup/Context, Mutex, Channel, Atomic*.
- XDK package sources and cancellation/timeout/error scenarios.
- Compiler types only as required by these scenarios.
- Exit: `xdk.tasks`/`xdk.sync` are no longer empty skeletons.

### XDK-W3 — Sys resource and context

- Load complete `Resource.x` and Context subunits with `xdk.sys`.
- Resource exists/read/count + missing/context-cancel paths.
- Exit: resource project and base/full parity tests.

### XDK-W4 — collections and generic boundaries

- Empty Map/container literal and contextual type inference (XDK need).
- Generic function-type parameters only where collections require them.
- Collections algorithms and legacy differential.
- Exit: `xdk.collections` scenario compiles and runs on mini.

### XDK-W5 — higher T0: log, config, CLI

- Implement each package against already-proven XDK/runtime primitives.
- No new compiler feature unless its XDK scenario requires one.
- Exit: one runnable package scenario each.

### XDK-W6 — T0 conformance and performance

- Add `m10_parity.sh`: all T0 packages, base/full modes.
- Keep M9-PAR 47/47 and 26 regressions green.
- Update the 200M performance curve; reject >20% regressions.
- Exit: full T0 matrix diff=0, performance evidence recorded.

### XDK-W7 — release

- `mini 0.3.0`, milestone record, README, RESUME, tag.
- Legacy remains selectable; deletion/default changes need separate approval.

## 5. Compiler dependency queue

Compiler work is allowed only after its XDK trigger exists:

| XDK trigger | Required compiler/runtime work |
| --- | --- |
| `xdk.sync` Atomic/Mutex/Channel | intrinsic types, constructors, method dispatch, runtime bridge |
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

- `xdk.sync` probe: AtomicInt/AtomicBool construction, `load` and `store`
  now run in both mini and legacy. Mutex/Channel/AtomicRef and the `cas`
  path remain W2 targets; the XDK package is not complete yet.
- `xdk.collections` probe: `import xdk.collections` and
  `Map<String, Int> m = [:]` now run in both mini and legacy; explicit map
  literals also match. The package's generic function-value algorithms are
  still not claimed until W4.
- Full Sys resource/context is not yet loaded with `xdk.sys`.
- M7-F1 Result/companion and closure lifetime remain open boundaries.

## 8. Current next action

Start **XDK-W0** only to the depth needed to unblock W1: lock the first
runtime/XDK probe set for bytes/IO/FS and record the existing tasks/sync and
collections failures. Then implement W1/W2 in that order; do not spend a wave
building compiler machinery before its XDK scenario exists.
