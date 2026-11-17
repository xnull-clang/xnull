# Mini compiler support plan

> The product plan is now XDK-first: [`../xdk/PLAN.md`](../xdk/PLAN.md).
> This file only tracks compiler/language work derived from that plan.

The compiler is not the driver. Every item below must cite a concrete XDK
package scenario and runtime contract.

## Priority queue

| Order | XDK trigger | Compiler work |
| --- | --- | --- |
| 1 | `xdk.sync` Atomic/Mutex/Channel | intrinsic types, constructors, methods, dispatch |
| 2 | `xdk.tasks` Task/TaskGroup/Context | task types, cancellation and result mapping |
| 3 | `xdk.collections` empty Map | parser/checker/CGen for `{}` and contextual element types |
| 4 | collections algorithms | typed function parameters/generic function values |
| 5 | resource/context | Result/companion and Context bridge |
| 6 | log/config/cli | package adapters only; avoid new language features unless blocked |

## Rules

- No compiler-only feature without an XDK probe and a runtime consumer.
- No empty package implementation counts as capability.
- The current runtime and XDK evidence live in `src/xdk/PLAN.md`.
- Keep `legacy` as oracle where it works; record where it does not.
- Existing M9-PAR 47/47, 26 regressions, selfhost and m8 remain the regression
  floor for any compiler change.

## Current evidence

- `xdk.sync` probe fails in mini at unsupported import/type; legacy CGen emits
  an invalid `AtomicInt_new` call.
- Empty `Map<String, Int> m = {}` fails in mini at parser/codegen level.
- Full Sys Resource/Context and M7-F1 Result/companion remain open.

## Archive

The completed Mini 1.0 / M9-CUT plan is
[`archive/2026-11-18-m9cut/`](archive/2026-11-18-m9cut/).
