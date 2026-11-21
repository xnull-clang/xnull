# T0 pre-freeze audit

Date: 2026-11-21
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
| errors | v1.4 | mini | PASS | — |
| runtime | v1.0 | mini | PASS | — |
| meta | v1.0 | mini | PASS | — |
| bytes | v1.2 | mini | PASS | Int overflow edge |
| text | v1.1 | mini | PASS | — |
| collections | v1.5 | mini | PASS | — |
| math | v1.2 | mini | PASS | — |
| time | v1.0 | mini | PASS | — |
| io | v1.0 | mini | PASS | — |
| fs | v1.0 | partial | PASS | Result face + File/Dir T0-X |
| sys | v1.0 | partial | PASS | File/Dir/Process T0-X |
| tasks | v1.0 | mini | PASS | — |
| sync | v1.1 | mini | PASS | — |
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

All gates must pass on mini. There is no second engine. Gates run once per
batch; items inside a batch are not gated or committed individually, and a red
gate blocks the next batch rather than the next item.

2026-11-21 note: all functional gates pass. Generic Map/Set core runtimes and
boxed Channel<Int128>/Channel<Result<...>> have landed. `m10_perf` remains within
baseline (latest 200M run 0.635s, 0.866x). The earlier 1.29x reading was taken
while a remote-desktop helper held ~90% CPU.

2026-11-21 batch 0 (core-integration): `xdk_core.sh` is green. `xdk.text`
gained `compareText` for byte-lexicographic ordering (String has no `<`), and
`writeFileText`/`writeText` now return the UTF-8 byte count instead of the raw
status code. The previous expected order in `xdk_collections_algo` was the bug,
not the contract.

2026-11-21 batch 1 (io): `xdk.io` is `Verified`. `Reader.readU8` now panics at
EOF instead of returning the `0` sentinel; `tryReadU8`/`readExact` return
`Result` without advancing on failure. `Writer.toBytes` returns a copy and
`Writer` gained idempotent `flush`/`close`. The package now has `Readable` /
`Writable` protocols, buffered streams, `ChainReader` / `TeeReader` /
`LimitReader`, `LineReader`, and `readAll` / `copyTo`. The mini protocol
dispatch fallback now emits a type-correct zero value for `Result` and closure
returns instead of `return 0`.

2026-11-21 batch 2 (collections): `xdk.collections` is `Verified`. The generic
`Map<K,V>` runtime now accepts `List`/`Map`/`Set` values, so
`Map<K,List<T>>` works. `Map.entries()` covers every supported K/V: fast paths
keep `Pair`/`IntPair`, other combinations return `Entry<K,V>` (`key`/`value`).
Added `groupByInt`, `groupBy`, and `joinWith`; `OrderedMap<V>`/`BTreeMap<V>`
now expose `V? put`, `keys()`, and `values()` and are part of the acceptance
surface. Scene coverage: `xdk_collections_algo.x`, `xdk_containers.x`,
`xdk_members.x`, and `xdk_core.x`.

2026-11-21 batch 3 (text): `xdk.text` is `Verified`. Unicode now has strict
UTF-8 validation (overlong, surrogate, >U+10FFFF), U+FFFD repair for invalid
UTF-8, `DataCorrupted` for isolated UTF-16 surrogates, and code-point
access/count APIs. Regex is a documented POSIX ERE subset with intervals,
POSIX named classes, capture groups, alternation, anchors, and code-point
atoms; the parser tree now stores child references instead of copying
subtrees, fixing a latent matcher defect where a group followed by another
atom failed. The stale `replaceAll` expectation `!b x !b` encoded that defect
and is corrected to `! x !`. printf formatting adds `%d/i/x/X/o/f/e/E/g/G/s/c/b`
with flags, width, and precision. Public value parameters use full names.
Scene coverage: `xdk_text.x`, `xdk_text_full.x`, and `xdk_core.x`.

## 5. Freeze blockers

No T0-K blocking item remains. Remaining T0-X gaps are recorded rather than
claimed as complete:

1. Generic `Map<K,V>`/`Set<T>` core runtimes are implemented for scalar,
   String, Double, Bytes, class, protocol, and data-enum elements, with
   `List`/`Map`/`Set` values in maps. `Map.entries`, `groupBy`, `OrderedMap`,
   and `BTreeMap` are closed; `Int128`/`Result` keys and elements remain
   intentionally rejected.
2. Cross-type `mapOk/mapErr` inference covers literal, binary, `new`, `str`,
   class/protocol methods, and common Result/List/Map/Set members; complex
   receiver expressions remain incremental.
3. Project build and formatter have no mini implementation and are outside T0;
   do not claim them.

Freeze rule: a package is `Verified` only when its design exists, its scenario
and gate pass, and its blocked items are recorded. A blocking item makes the
package `Partial`, not `complete`.
