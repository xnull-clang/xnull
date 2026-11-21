# XDK plan — mini only

**Rule:** XDK is the product. mini is the only compiler. The runtime is the
substrate. mini is the only compiler.

The T0 package/API design baseline is
[`../../docs/design/t0/00-overview.md`](../../docs/design/t0/00-overview.md):
one package per acceptance gate, with per-file interfaces, contracts, scenarios,
and recorded gaps.

## 1. Package matrix

| Package | Current state | Next target |
| --- | --- | --- |
| `xdk.errors` | `xdk_errors.x` + `xdk_errors_full.x` mini; `collectOk`/`flatten`/cross-type map | complex method-call inference |
| `xdk.runtime` | diagnose/exit/clock mini | sleep/deadline edges |
| `xdk.meta` | versions/platform mini | build/target matrix |
| `xdk.bytes` | strict/checked surface mini; `ByteBuffer` T0-X | exact 32-bit overflow after Int audit |
| `xdk.text` | base + full mini; `compareText` byte ordering | UTF-16/format edges |
| `xdk.math` | base + Int128/Int/Long checked + saturating + combinatorics mini | random T1 |
| `xdk.time` | Instant/Duration/DateTime mini | timezone/format edges |
| `xdk.io` | `Verified`：memory/checked/buffered/composed/LineReader mini | file/network/stdio via fs/sys/runtime |
| `xdk.fs` | text exists/read/write mini | path/atomic/full File/Dir |
| `xdk.sys` | File/Dir/Process + `Resource.x` mini base/full | signal/dir edges |
| `xdk.tasks` | Task/TaskGroup/Context mini | select/race |
| `xdk.sync` | Atomic/Mutex/Channel<Int/Long/Bool/Char/Double/String/Bytes/class/protocol/nullable/Int128/Result> mini | RwLock/semaphore/select |
| `xdk.collections` | `Verified`：List, four Map/Set fast paths, generic Map/Set core, member surface, algorithms (`sortBy`/`sortedBy`/`groupBy`/`joinWith`), generic entries (`Entry<K,V>`), PriorityQueue/RingBuffer/OrderedMap/BTreeMap mini | T1 containers |
| `xdk.log` | Level/Logger/ConsoleSink mini | Field/Sink |
| `xdk.config` | key/profile/env mini | file/typed sources |
| `xdk.cli` | Args/usage/exit mini | subcommands/help |

## 2. Mini-only verification

```sh
src/mini/tests/selfhost.sh
src/mini/tests/xdk.sh
src/mini/tests/m10_parity.sh
src/mini/tests/resources.sh
src/mini/tests/m8.sh
src/mini/tests/m10_perf.sh
```

A package is frozen only after its scenario and regression pass. Gates and
commits run once per batch; batch items are not gated or committed individually.
A blocked T0-X item marks the package `partial`; it does not reopen a second
engine.

## 3. Current compiler gaps

1. `Int` 32-bit audit: time epoch, parse limits, file sizes, process/resource
   handles and all public `Int64/Int32` aliases are now `Long/Int`; keep
   auditing new code.
2. `List<Result<...>>`, `collectOk`, `flatten`, and cross-type `mapOk/mapErr`
   are implemented; complex receiver/return inference remains incremental.
3. Generic Map/Set core is implemented, including `List`/`Map`/`Set` map values and `Entry<K,V>` entries. Collections T0-X is closed; next is text.
4. Project build and formatter are future mini work.
5. Protocol dispatch fallback emits type-correct zero values for `Result` and
   closure returns; new protocol return types must keep this path covered.

## 4. Architecture

- `src/mini/main.x` — compiler source.
- `src/mini/bin/mini` — self-hosted compiler.
- `src/runtime` — C runtime.
- `src/xdk` — XDK source.
- `src/toolchain/xnull-build.sh` — mini build/run/check.
- `src/cli/xnull` — mini CLI.
- `src/ffi` — `.xfb` contracts consumed by mini.

The former second compiler, bootstrap tools, project reactor, formatter, and
split manifests are removed. Historical versions remain in git history.
