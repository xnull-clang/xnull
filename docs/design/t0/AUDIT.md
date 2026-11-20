# T0 pre-freeze audit

Date: 2026-11-20  
Scope: mini-only authority, T0 package design/implementation,
Int 32-bit audit, and the gates required before freezing T0.

## 1. Removed paths

- `src/compiler`, `src/bootstrap`, `src/build`, `src/xnfmt`, `src/bindings`, `xdk/bindings`;
- the second engine selector; `auto` is now an alias for mini;
- `m9_parity`, `m9_cut`, `parity`, project/bootstrap CLI commands;
- source-splitting scripts, bundle/resolver helpers, and `.xsplit.json`;
- old design `docs/设计08-T0核心包详细设计方案-v1.0.0.md` and old perf assets.

## 2. Int 32-bit audit

Fixed:

- `Int` arithmetic/bitwise/local/return/print normalization; `Long` preserved
  for 64-bit values; shift count bounds panic.
- `Time/Duration/DateTime` public 64-bit fields and returns use `Long`.
- `parseInt` 32-bit overflow limit.
- `File.size()` and `fileMtime()` use `Long`.
- `Process` handles and `Resource` sizes use `Long`.
- `Random` removed from `xdk.math` (T1 package).

Still to watch:

- `File.seek` offsets are still `Int`; large-file offsets belong to T0-X.
- Any new XDK code using `Int` for epoch/size/handle must use `Long`.

## 3. Package status

| Package | Design | Implementation | Gate | Blocker |
| --- | --- | --- | --- | --- |
| errors | v1.4 | mini | PASS | flatten/cross-type map |
| runtime | v1.0 | mini | PASS | — |
| meta | v1.0 | mini | PASS | — |
| bytes | v1.2 | mini | PASS | Int overflow edge |
| text | v1.0 | mini | PASS | naming/Unicode edges; Regex T0-X |
| collections | v1.2 | partial | PASS (subset) | List.clear/try*, Map entries, generic Map/Set |
| math | v1.0 | partial | PASS | Int128 blocked; stats edges |
| time | v1.0 | mini | PASS | — |
| io | v1.0 | partial | PASS | strict/checked + copy semantics |
| fs | v1.0 | partial | PASS | Result face + File/Dir T0-X |
| sys | v1.0 | partial | PASS | File/Dir/Process T0-X |
| tasks | v1.0 | mini | PASS | — |
| sync | v1.0 | mini | PASS | — |
| log | v1.0 | mini | PASS | fields/sinks T0-X |
| config | v1.0 | mini | PASS | sources/codec T0-X/T1 |
| cli | v1.0 | mini | PASS | subcommands T0-X |

## 4. Gates

```sh
src/mini/tests/selfhost.sh
src/mini/tests/xdk.sh
src/mini/tests/m10_parity.sh
src/mini/tests/resources.sh
src/mini/tests/m8.sh
src/mini/tests/m10_perf.sh
for t in src/mini/tests/*.sh; do "$t"; done
```

All gates must pass on mini. There is no second engine.

2026-11-20 note: functional gates pass. `m10_perf` reported 1.29x while the host
was running a remote-desktop helper at ~90% CPU; rerun on an idle host before
using the performance number for freeze.

## 5. Freeze blockers

1. Collections container member surface is partial: `List.clear`/`Map.clear`/
   `Set.clear`/`Set.remove` are in; `List.try*`, `Map` entries/remove, and
   generic `Map<K,V>`/`Set<T>` runtime are still pending.
2. `flatten`/cross-type `mapOk/mapErr` await generic return-type inference;
   `collectOk` and `List<Result<...>>` are now implemented.
3. Typed channels now cover Int/String/class; protocol/nullable elements remain.
4. Int128 remains blocked: mini has no 128-bit scalar type or literals. It needs
   a compiler type (`__int128` or a library bigint with explicit ops), printing,
   parsing, and division/overflow tests. Do not fake a struct named Int128
   while the language spec says it is built-in.
5. Project build and formatter have no mini implementation and are not part of
   T0; do not claim them.

Freeze rule: a package is `Verified` only when its design exists, its scenario
and gate pass, and its blocked items are recorded. A blocking item makes the
package `Partial`, not `complete`.
