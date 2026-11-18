# Mini compiler support plan

> The product plan is now XDK-first: [`../xdk/PLAN.md`](../xdk/PLAN.md).
> This file only tracks compiler/language work derived from that plan.

The compiler is not the driver. Every item below must cite a concrete XDK
package scenario and runtime contract.

## Priority queue

| Order | XDK trigger | Compiler work |
| --- | --- | --- |
| 1 | `xdk.sync` Mutex<T> (W2 / S2-1) | DONE: Mutex type, scoped `withLock` lowering, runtime bridge |
| 2 | `xdk.tasks` Task/TaskGroup/Context (W2 / S2-2, S2-4) | DONE: task types, spawn/join/cancel, result mapping, join deadline, context threaded into channel ops |
| 3 | `xdk.sync` Channel completion (W2 / S2-3) | DONE: close/cancel semantics; legacy `Result<void, ...>` gap recorded |
| 4 | `xdk.collections` algorithms (W4) | typed function parameters/generic function values |
| 5 | resource/context (W3) | DONE: full Sys loads Resource.x; null handle args, `Int?` print, Bytes method typing |
| 6 | log/config/cli (W5) | package adapters only; avoid new language features unless blocked |

## Rules

- No compiler-only feature without an XDK probe and a runtime consumer.
- No empty package implementation counts as capability.
- The current runtime and XDK evidence live in `src/xdk/PLAN.md`.
- Keep `legacy` as oracle where it works; record where it does not.
- Existing M9-PAR 47/47, 26 regressions, selfhost and m8 remain the regression
  floor for any compiler change.

## Current evidence

- W1 is closed: `tests/xdk_bytes*.x`, `tests/xdk_io.x`, `tests/xdk_fs.x` pass
  through mini and legacy in `src/mini/tests/xdk.sh`.
- W2 is closed. `tests/xdk_mutex.x` passes mini + legacy; `tests/xdk_tasks.x`,
  `tests/xdk_cancel.x`, and `tests/xdk_channel.x` pass on mini. `xdk.sync`
  AtomicInt/AtomicBool/AtomicRef/Mutex pass in mini and legacy; `Channel<Int>`
  is mini-only with the legacy `Result<void, ...>` typedef gap recorded.
- `xdk.tasks` now has a working mini surface: `Context`, `TaskGroup`,
  `Task<T>`, spawn/join/joinDeadline/cancel/close, and cancellation of
  blocked channel operations. Legacy fails on undeclared `xn_task_body_*`
  adapters and is recorded as an open differential gap.
- `import xdk.collections` + `[:]` now works in mini/legacy; longer Collections
  algorithms still need W4.
- W3 is closed: full Sys loads `io/resource/Resource.x`; base/full resource
  projects and the cancelled-context path pass in `tests/resources.sh`.
- M7-F1 Result/companion and closure lifetime remain open.

## Archive

The completed Mini 1.0 / M9-CUT plan is
[`archive/2026-11-18-m9cut/`](archive/2026-11-18-m9cut/).
