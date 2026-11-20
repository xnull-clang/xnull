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
| `xdk.errors` | `xdk_errors.x` + `xdk_errors_full.x` mini; `collectOk` implemented | flatten/cross-type map |
| `xdk.runtime` | diagnose/exit/clock mini | sleep/deadline edges |
| `xdk.meta` | versions/platform mini | build/target matrix |
| `xdk.bytes` | strict/checked surface mini; `ByteBuffer` T0-X | exact 32-bit overflow after Int audit |
| `xdk.text` | base + full mini | UTF-16/format edges |
| `xdk.math` | base mini | Int128/numeric edges |
| `xdk.time` | Instant/Duration/DateTime mini | timezone/format edges |
| `xdk.io` | in-memory Reader/Writer mini | file/network streams |
| `xdk.fs` | text exists/read/write mini | path/atomic/full File/Dir |
| `xdk.sys` | File/Dir/Process + `Resource.x` mini base/full | signal/dir edges |
| `xdk.tasks` | Task/TaskGroup/Context mini | select/race |
| `xdk.sync` | Atomic/Mutex/Channel<Int/String/class/protocol/nullable> mini | FFI elements |
| `xdk.collections` | List, Map<String,Int>, Set<Int>, algorithms, PriorityQueue/RingBuffer mini; member surface blocked | generic Map/Set runtime; List.try*; Map keys/values/entries/remove |
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

A package is frozen only after its scenario and regression pass. A blocked
T0-X item marks the package `partial`; it does not reopen a second engine.

## 3. Current compiler gaps

1. `Int` 32-bit audit: time epoch, parse limits, file sizes, process/resource
   handles and all public `Int64/Int32` aliases are now `Long/Int`; keep
   auditing new code.
2. `List<Result<...>>` / generic Result containers (`collectOk`, `flatten`).
3. Generic return-type inference for cross-type `mapOk/mapErr`; `flatten` nested Result.
4. `Map<Int,...>` / generic `Set<T>` runtime; Map entries/remove.
5. `Int128` scalar support (blocked on a 128-bit compiler type).
6. Project build and formatter are future mini work.

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
