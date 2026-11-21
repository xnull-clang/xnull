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

- Any new XDK code using `Int` for epoch/size/handle must use `Long`.
- `xdk.fs.File` and the `xdk.sys` full File surface use `Long` for size,
  position, and seek offsets.

## 2.1 DET-01 authority

The authoritative memory-strategy decision table is
[`../DET-01.md`](../DET-01.md). README prose and comments in
`src/runtime/rt_policy.c` are non-normative references; when they disagree,
DET-01 wins. DET-01 includes the ordered table, positive examples (struct,
simple/data enum, stack candidate, ARC finalizer, GC `Any`/cycle) and negative
examples (source annotations, reclamation timing, identity-based inference).

## 2.2 Green-but-wrong test audit

Two known cases were checked against the spec, not against the old green output:

1. **String sorting**: `xdk_collections_algo.x` now sorts with
   `compareText(left, right) < 0`; the old expected order `b,a,c` was the bug.
   The current expectation is `a,b,c`. `xdk_core.x` independently asserts the
   sorted first element `alpha`.
2. **`writeText` status**: `xdk.fs.writeText` and `xdk.sys.writeFileText`
   return `Result<Long,Error>` with the UTF-8 byte count. Tests read
   `.value()` and assert the count (e.g. 7 for `a.txt`, 2 for `é`); the old
   `0` status is not an accepted expectation.

No test weakens an assertion to match current behavior. The expected files
`xdk_core.out` and `xdk_collections_algo.x` are the spec for these cases.

## 3. Package status

`Gate` is the package scenario/regression result. `Verified` is the stricter
CORE-CLOSURE state: design exists, T0-K scenarios pass, and T0-X is closed or
recorded. A package can be `Gate PASS` and still `Verified = no`; that is the
intended separation. `Reviewer` is deliberately `待签`; no self-signing. Package design docs may state
`Verified` for their documented scope; the `Verified` column here is the
stricter CORE-CLOSURE state (T0-K + T0-X), so a package can be `Gate PASS` and
`Verified = no` at the same time.

| Package | T0-K | 1.0 | Design | Implementation | Gate | Verified | Evidence | Reviewer | Date |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| xdk.errors | PASS | yes | v1.4 | mini | PASS | no | xdk_errors.x, xdk_errors_full.x | 待签 | 2026-11-21 |
| xdk.runtime | PASS | yes | v1.0 | mini | PASS | no | xdk_runtime.x, ref/u2_task_dump.x | 待签 | 2026-11-21 |
| xdk.meta | PASS | yes | v1.0 | mini | PASS | no | xdk_meta.x | 待签 | 2026-11-21 |
| xdk.bytes | PASS | yes | v1.2 | mini | PASS | no | xdk_bytes.x, xdk_bytes_strict.x | 待签 | 2026-11-21 |
| xdk.text | PASS | yes | v1.1 | mini | PASS | yes | xdk_text.x, xdk_text_full.x | 待签 | 2026-11-21 |
| xdk.collections | PASS | yes | v1.5 | mini | PASS | yes | xdk_collections.x, xdk_containers.x, xdk_members.x | 待签 | 2026-11-21 |
| xdk.math | PASS | yes | v1.2 | mini | PASS | no | xdk_math.x | 待签 | 2026-11-21 |
| xdk.time | PASS | yes | v1.0 | mini | PASS | no | xdk_time.x | 待签 | 2026-11-21 |
| xdk.io | PASS | yes | v1.0 | mini | PASS | yes | xdk_io.x | 待签 | 2026-11-21 |
| xdk.fs | PASS | yes | v1.1 | mini | PASS | yes | xdk_fs.x | 待签 | 2026-11-21 |
| xdk.sys | PASS | yes | v1.1 | mini | PASS | yes | xdk_sys.x, xdk_sys_full.x | 待签 | 2026-11-21 |
| xdk.log | PASS | yes | v1.0 | mini | PASS | yes | xdk_log.x (Field/Sink/Console/Memory) | 待签 | 2026-11-21 |
| xdk.config | PASS | yes | v1.0 | mini | PASS | yes | xdk_config.x (ConfigSource/FileSource/overlay) | 待签 | 2026-11-21 |
| xdk.cli | PASS | yes | v1.0 | mini | PASS | yes | xdk_cli.x (OptionSpec/Command/help) | 待签 | 2026-11-21 |
| xdk.tasks | builtin | no | v1.0 | language/runtime | PASS | n/a | xdk_tasks.x, xdk_cancel.x | 待签 | 2026-11-21 |
| xdk.sync | builtin | no | v1.1 | language/runtime | PASS | n/a | xdk_mutex.x, xdk_channel.x, xdk_sync_atomic.x | 待签 | 2026-11-21 |

## 3.1 P9=B package boundary

`xdk.tasks` and `xdk.sync` are **language/runtime builtins**, not 1.0 packages.
Their package documents are retained as builtin references and marked
deprecated for packaging purposes. The 1.0 package count is 14.

The seven synchronized documents are:

1. `docs/design/t0/00-overview.md`
2. `docs/design/t0/12-tasks.md`
3. `docs/design/t0/13-sync.md`
4. `src/xdk/PLAN.md`
5. `xdk/lib/xdk/PLAN.md`
6. `docs/design/t0/AUDIT.md`
7. `src/mini/PLAN.md`

## 3.2 C0-8 T0-X evidence (io/collections/text/fs/sys)

The claim under audit is whether the five closure packages' T0-X surfaces are
actually empty. They are not empty; each has code, public symbols, and a
scenario. Evidence by package:

| Package | T0-X evidence (not empty) |
| --- | --- |
| xdk.io | `Readable`/`Writable`, `BufferedReader`/`BufferedWriter`, `ChainReader`, `TeeReader`, `LimitReader`, `LineReader`, `readAll`, `copyTo` in `src/xdk/io/IO.x`; `xdk_io.x`. |
| xdk.collections | generic `Map<K,V>`/`Set<T>` runtime, `groupBy`, `groupByInt`, `joinWith`, `Entry<K,V>`, `OrderedMap`, `BTreeMap`, `PriorityQueue`, `RingBuffer`; `xdk_collections.x`, `xdk_containers.x`, `xdk_members.x`. |
| xdk.text | Unicode validation/repair, `compareText`, POSIX ERE `Regex`, `Match`, `Utf16`, `printf`; `xdk_text.x`, `xdk_text_full.x`. |
| xdk.fs | `Result` read/write, `File`/`Dir`/`Path`, `Metadata`, permissions, links, `walk`, `glob`, temp leases, atomic writes; `xdk_fs.x`. |
| xdk.sys | `Result` file surface, `Process`/`ProcessResult`, piped stdio, `Signal`, process groups, `envNames`, embedded resources; `xdk_sys.x`, `xdk_sys_full.x`, `xdk_core.x`. |

The corresponding design docs (`05-text`, `06-collections`, `09-io`, `10-fs`,
`11-sys`) mark these surfaces `Verified`; the code and scenarios agree.

Residual after the implemented T0-X (not emptiness, and not a 1.0 blocker):

- io: stdio/terminal/network streams remain sys/runtime/T1; the package owns
  memory, buffered, composed, and line streams.
- collections: `Int128`/`Result` keys are intentionally rejected; HashMap,
  Deque, and BitSet remain T1 containers.
- text: the full regex engine is T1 `xdk.regex`; T0 ships the POSIX ERE subset.
- fs: watch, file locking, mmap, and PTY are T1; T0 ships Result, metadata,
  links, temp, atomic, walk, and glob.
- sys: PTY, network sessions, and device access are T1; T0 ships process,
  pipes, signals, env, platform, and embedded-resource reads.


## 3.3 Mirror and rt.c status

G3 compares three pairs, excluding `test_*` files and build artifacts:

- `src/xdk` ↔ `xdk/lib/xdk`
- `src/ffi` ↔ `xdk/ffi`
- `src/runtime` ↔ `xdk/runtime`

Current HEAD is clean for all three. `rt.c` is included in the runtime pair;
an artificial append to `src/runtime/rt.c` is reported as
`g3 xdk/runtime:rt.c [xdk/runtime]: content differs`, so the drift check is
live rather than a status line. `src/ffi/capabilities.tsv` is mirrored to
`xdk/ffi/capabilities.tsv` and is covered by the same rule.

## 3.4 Layer verification result

`src/toolchain/check_layers.py` at HEAD: PASS.

- G1 ownership: 0 violations; 14 packages, each capability has one owner.
- G2 closure: 0 raw violations; the four former gaps are implemented, so the
  allowlist is empty (`0/0`). Deleting a gap previously made G2 red; the
  current empty allowlist is the 1.0 state.
- G3 mirrors: 0 violations; `rt.c` is covered by the runtime pair. A probe
  append to `src/runtime/rt.c` is reported, then restored.
- `--release 1.0.0` PASS with an empty allowlist.

## 3.5 C1 reference programs

Three real programs under `src/mini/tests/ref/` are built and run by
`src/mini/tests/ref.sh`:

| Program | Covers | Expected output |
| --- | --- | --- |
| `ref/cli_tool.x` | FileSource, Config.apply, Command/subcommands/help, Logger Field/Sink, fixed DateTime.format, InvalidArgument code | `cli_help.out`, `cli_run.out`, `cli_missing.out` |
| `ref/concurrent.x` | 10k tasks, `Channel<Int>(16)` backpressure, `Mutex<Counter>`, cancellation, close | `concurrent.out` |
| `ref/ffi_bytes.x` | `demoNow`/`fileSize` FFI, ByteWriter/ByteReader, tryFromHex, readExact error kinds | `ffi_bytes.out` |

Gap found and fixed: `Bytes.toString` used `rt_string_from_c`, which relies on
NUL termination and re-evaluated the receiver twice. A compiler helper
`xn_bytes_to_string` now takes the Bytes pointer once and uses its length.
This was caught by the pipe/`readStdoutAll().toString()` and FileSource paths;
the reference programs and the existing xdk gates cover the fix.

## 3.5.1 ByteBuffer evidence

`ByteBuffer` is code-complete in `src/xdk/core/bytes/Bytes.x` and covered by
`src/mini/tests/xdk_bytes_extra.x` (append/put/get/reserve) and
`src/mini/tests/xdk_bytes_strict.x` (checked construction/position). The
per-symbol API manifest row carries the same scenario/test/gate evidence.

## 3.5.2 API manifest and task dump evidence

- `src/ffi/api-manifest.tsv` has 114 per-symbol rows across 14 packages,
  generated from capabilities + source signatures + design stability. Missing
  symbol/signature/design is a generator RED.
- `ByteBuffer`: `xdk_bytes_extra.x` + `xdk_bytes_strict.x` + `test_std.c`.
- `dumpTasks`: `xdk.runtime.dumpTasks()` → `xdkc_dump_tasks`, exercised by
  `ref/u2_task_dump.x` with `XNULL_CARRIERS=1`; expected stderr is
  `tasks: live=1 ...` followed by `tasks: live=0 ... settled=1 ...`.

## 3.6 Per-package signature ledger

Reviewer remains `待签`; evidence columns record the command that was actually
run, not a self-signature.

| Package | Reviewer | Date | Evidence command | Observed |
| --- | --- | --- | --- | --- |
| xdk.errors | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_errors.x` | PASS |
| xdk.runtime | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_runtime.x` | PASS |
| xdk.meta | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_meta.x` | PASS |
| xdk.bytes | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_bytes*.x` | PASS |
| xdk.text | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_text*.x` | PASS |
| xdk.collections | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_collections*.x` | PASS |
| xdk.math | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_math.x` | PASS |
| xdk.time | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_time.x` | PASS |
| xdk.io | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_io.x` | PASS |
| xdk.fs | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_fs.x` | PASS |
| xdk.sys | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_sys*.x` | PASS |
| xdk.log | 待签 | 2026-11-21 | `src/mini/tests/ref.sh` + `xdk_log.x` | PASS |
| xdk.config | 待签 | 2026-11-21 | `src/mini/tests/ref.sh` + `xdk_config.x` | PASS |
| xdk.cli | 待签 | 2026-11-21 | `src/mini/tests/ref.sh` + `xdk_cli.x` | PASS |
| xdk.tasks | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_tasks.x` | PASS (builtin) |
| xdk.sync | 待签 | 2026-11-21 | `src/mini/tests/xdk.sh` + `xdk_sync*.x` | PASS (builtin) |

C1 evidence and U0–U5 journeys: [`C1-U0-U5-EVIDENCE.md`](C1-U0-U5-EVIDENCE.md).

## 3.7 U3 official build status

Bootstrap `src/bootstrap/build.sh` succeeds (`xn-s4`, `xparser` hashes
recorded). The official `src/mini/build.sh` legacy path did not finish within
1800s and was terminated (143), leaving a 0-byte `mini.c`; this is the only
remaining RED. The substitute 0.3.0 artifact and its upgrade outputs are
recorded in `C1-U0-U5-EVIDENCE.md`.

## 4. Gates

```sh
src/mini/tests/selfhost.sh
src/mini/tests/xdk.sh
src/mini/tests/xdk_core.sh
src/mini/tests/ref.sh
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

2026-11-21 batch 5 (sys): `xdk.sys` is `Verified`. `readFileText` now returns
`Result<String, Error>` and `writeFileText` returns `Result<Long, Error>` with
the UTF-8 byte count. The default sys surface gained environment enumeration
(`envNames`), platform/cwd/pid/mtime, `ProcessResult`, piped child processes
(`spawnProcessPiped` with stdin/stdout/stderr), named signals, and process-group
signalling; every child is its own group leader. Embedded resources upgraded to
the `Result`/`Context` surface with size, count, and listing. The full
`io/system` File/Dir/Path handles now match the `xdk.fs` contract. The runtime
also hardens `rt_string_from_c(NULL)` to an empty string, and the compiler wraps
`platformRaw` as a `String`. Scene coverage: `xdk_sys.x`, `xdk_sys_full.x`,
`xdk_core.x`, `m7_sys.x`, and `resources.sh`.

2026-11-21 batch 4 (fs): `xdk.fs` is `Verified`. `readText` now returns
`Result<String, Error>` and `writeText` returns `Result<Long, Error>` with the
UTF-8 byte count. Added `readBytes`/`writeBytes`, real `File` handles with
`Long` size/position/seek, `FileMode`, `Dir` with `Ok(null)` EOF, and `Path`
join/normalize/parent/extension. Metadata, permissions, symbolic/hard links,
`walk`, `glob` (`*`/`?`/`**`), temp file/dir leases, and atomic writes are
covered. The runtime `sys_raw.xfb` bridge gained file-handle, metadata,
permission, link, temp, and atomic-write primitives. Scene coverage:
`xdk_fs.x` and `xdk_core.x`.

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
