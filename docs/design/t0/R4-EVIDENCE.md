# R4 evidence closure — 13 Strict + 11 Optimized + 3 Deferred + 9 built-in

| Item | Value |
| --- | --- |
| Base | `core-verify@f254ab33` |
| Worktree | `../XNull-core-evidence` |
| Branch | `core-evidence` |
| Date | 2026-11-21 |
| Scope | R4 evidence gaps only; no merge, no ledger edit |
| Ledger owner | `docs/design/MINI-1.0.md` §15 (user-owned; **not modified** here) |

This file is the evidence attachment for the R4 ledger. It does not change any
status in `MINI-1.0.md`; the ledger remains the user-owned source of record.
`C1-U0-U5-EVIDENCE.md` and `AUDIT.md` were not modified: no independent
reviewer signature is available in this batch.

## 0. Gate results

Run from this worktree after the changes in §6:

```text
$ ./src/mini/tests/ref.sh
mini ref: PASS

$ ./src/mini/tests/xdk.sh
check_doc_naming: PASS
mini xdk: PASS

$ ./src/mini/tests/xdk_core.sh
xdk core: PASS

$ python3 src/toolchain/check_layers.py
check_layers: PASS (g1=0 g2=0 g3=0 allowlist=0/0; raw g1=0 g2=0 g3=0)

$ ./src/mini/tests/r4_evidence.sh
mini r4 evidence: PASS

$ ./src/runtime/build_rt.sh
...
std 测试通过
...
empty resource table fallback ok
exit 0
```

`r4_evidence.sh` is the new evidence runner for the scenarios added in this
batch. It builds and runs every program end-to-end and diffs exact output. The
full C suite (`build_rt.sh`, no `--lib`) is also green.

## 1. Status after the follow-up batch

| State | Ledger start | After R4 batch | After follow-up | After this batch | Change |
| --- | ---: | ---: | ---: | ---: | --- |
| `Strict evidenced` (14-package ledger) | 27 | 29 | 31 | 36 | +9 total: DetailedError, setChecked, complex receiver, escape/raw/unicode, RuntimeInfo, stats, Stopwatch, cancellable sleep, full layout parse |
| `Strict candidate` | 13 | 11 | 9 | 4 | -9 total; A2/A5/A9/A10 remain |
| `Optimized proposed` | 0 | 3 | 3 | 3 | +3: errors/tryWith*, meta/能力矩阵, time/日历加减 |
| `Optimized candidate` | 11 | 8 | 8 | 8 | -3 total; 8 remain |
| `Deferred candidate` | 3 | 3 | 3 | 3 | 0 promoted; 3 decision packets completed |
| `Out-of-scope / deferred` | 9 | 9 | 9 | 9 | 0 changed; non-goal evidence attached |
| `Signed Strict/Optimized closed` | 0 | 0 | 0 | 0 | no signer in this batch |

`Strict evidenced` and `Optimized proposed` are **not closed**. Only a user or
independent reviewer signature makes a row `Signed ... closed`.

## 2. A. The 13 Strict candidates

Each item below starts from the ledger state and records the real source,
scenario, command, and observed output. Items without a complete chain stay
`Strict candidate` and state exactly what is missing.

### A1. errors / 复杂接收者表达式推断 (ledger #1) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source:** `src/xdk/core/errors/Errors.x:623` (`mapOk`); inference contract
  in `docs/design/t0/01-errors.md:331-335` and `:404`.
- **Root cause:** `simpleExprType` only resolved the method name on a
  `MethodCall`; it did not resolve the receiver expression. `makeItem(value)`
  therefore left `U` uninferred, `typeArgsFor` returned empty, and the generic
  call stayed unresolved (`SEM-001 undefined function: mapOk`).
- **Fix:** `src/mini/main.x` now resolves `MethodCall` receivers through
  `simpleExprType` + `methodReturnType` before falling back to the old special
  names. The generated `mini.c` is refreshed by self-host.
- **Scenario:** `src/mini/tests/r4/inference.x` via `r4_evidence.sh`.
- **Observed output:**

```text
$ ./src/mini/tests/r4_evidence.sh
mini r4 evidence: PASS
```

  The scenario covers `makeItem(value).label()`, `items.get(0).label()`, and
  `mapOk(..., (Int value) -> makeItem(value))`; output is `v=1 / v=7 / v=1`.
- **Remaining:** direct `new X(...).method()` chaining is still a parser
  limitation, but the audited complex-receiver inference case now passes.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A2. errors / 错误码命名空间工具 (ledger #2)

- **Verdict:** stays `Strict candidate`.
- **Evidence of the current namespace:**

```text
$ grep -o 'SEM-[0-9][0-9][0-9]' src/mini/main.x | sort -u
SEM-001
SEM-002
SEM-003
SEM-004
SEM-005

$ find . -path ./.git -prune -o -iname '*registry*' -print
(no output)
```

- **Gap:** there is no W6 error-code registry file, no owner/description per
  code, and no negative test for an unregistered code. `SEM-001..005` are
  literal strings in the compiler; `ErrorKind` name/code mapping in
  `src/xdk/core/errors/Errors.x` is a different table (FFI error kinds, not
  compiler diagnostics).
- **What closes it:** a registry artifact plus a test that rejects an
  unregistered code and a duplicate code; `MINI-1.0` W6 is the delivery point.

### A3. runtime / dumpTasks / stats (ledger #3) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **dumpTasks (retained):**
  - Source: `src/xdk/core/runtime/Runtime.x:29`.
  - Scenario: `src/mini/tests/ref/u2_task_dump.x`.
  - Command/output:

```text
$ ./src/cli/xnull --bootstrap --engine=mini build src/mini/tests/ref/u2_task_dump.x -o /tmp/r4_u2
$ XNULL_CARRIERS=1 /tmp/r4_u2
stdout:
true
1
stderr:
tasks: live=1 spawned=1 settled=0 carrier=1
tasks: live=0 spawned=1 settled=1 carrier=1
```

- **stats is now a public XDK surface:**
  - Source: `src/xdk/core/runtime/Runtime.x` (`class RuntimeStats`, `stats`,
    `statsEnabled`, `statsSetEnabled`, `statsReset`); primitives
    `statsAllocsRaw`…`statsResetRaw` in `src/ffi/runtime_raw.xfb`; C wrappers in
    `src/runtime/rt_std_runtime.c` over the existing `xrt_stats_*` ABI.
  - C test: `src/runtime/test_std.c` (`test_stats`) now checks that the XDK
    wrappers match `xrt_stats_get`, reset zeroes the counters, and the enable
    flag round-trips.
  - Scenario: `src/mini/tests/r4/runtime_stats.x`.
  - Command/output:

```text
$ ./src/mini/tests/r4_evidence.sh
mini r4 evidence: PASS

$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/runtime_stats.x
true
11
true
true
true
true
true
true
false
```

  The scenario resets and enables stats, allocates a string, snapshots
  `RuntimeStats`, checks `allocs >= 1`, `bytes > 0`, `live()/frees/gc* >= 0`,
  disables stats, and checks the flag is off.
- **Gap:** none for the documented T0 stats surface. The snapshot is explicitly
  approximate (`live() = allocs - frees`), not a precise heap census.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A4. runtime / RuntimeInfo (ledger #4) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source:** `src/xdk/core/runtime/Runtime.x` (`class RuntimeInfo`,
  `runtimeInfo`); read-only primitives `runtimePlatformRaw`, `runtimeArchRaw`,
  `buildModeRaw` in `src/ffi/runtime_raw.xfb`; `xdkc_build_mode` in
  `src/runtime/rt_std_runtime.c`.
- **Contract:** `docs/design/t0/02-runtime.md` §1 CAP-6 and §2 now list
  `RuntimeInfo`/`runtimeInfo` as a T0-X surface.
- **Scenario:** `src/mini/tests/r4/runtime_info.x`.
- **Command/output:**

```text
$ ./src/mini/tests/r4_evidence.sh
mini r4 evidence: PASS

$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/runtime_info.x
true
true
true
true
true
true
true
true
true
true
```

  The scenario checks language version, XDK version, platform, architecture,
  build mode (`release` or `debug`), `complete()`, a non-empty `describe()`,
  and equality with `xdk.meta`'s `languageVersion`/`xdkVersion`/`targetPlatform`.
- **Gap:** the version strings mirror `xdk.meta` because `xdk.runtime` is the
  lower layer and does not import `meta`; they are kept identical by contract.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A5. text / StringBuilder (ledger #6)

- **Verdict:** stays `Strict candidate`.
- **Evidence:**

```text
$ grep -rn "StringBuilder" src/xdk
(no matches)
```

  The C runtime has `StringBuilder` (`src/runtime/rt_std_text.c:340-385`) and
  `test_std.c:546` only mentions it in the S3-04 GC-type comment. There is no
  XDK symbol and no XDK scenario.
- **Design:** `docs/design/t0/05-text.md:175` says the complete `StringBuilder`
  belongs to a later package; `00-overview.md:207` lists it as text T0-X.
- **Gap:** either an XDK surface + scenario + design contract, or an explicit
  reclassification to out-of-scope/T1. The current row cannot be strict.
- **What closes it:** add the XDK API and a scenario such as
  `xdk_text_builder.x`, or move the row to out-of-scope with the T1 statement.

### A6. text / 转义 (ledger #8) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source/fixes:**
  - String literals are emitted with `rt_string_new(<literal>, sizeof(<literal>) - 1)`
    (`src/mini/main.x`), so embedded NUL is length-preserving.
  - The lexer accepts `r"..."` and `r"""..."""`, converts raw content into a
    C literal that preserves backslashes, and validates the S1 escape table
    (unknown escapes and invalid scalars are lexical errors).
  - `Char` literals are emitted as `((int32_t)U'...')`, so non-ASCII scalars
    are not narrowed to C `char`.
- **Scenario:** `src/mini/tests/r4/escape.x` plus the negative
  `src/mini/tests/r4/escape_bad.x`, run by `r4_evidence.sh`.
- **Observed output (escape.x):**

```text
26
10
13
9
2
65
127
2
233
4
128512
1
10
1
13
1
9
1
92
1
39
1
34
3
97
0
98
false
3
97
0
49
4
97
92
110
98
9
\u{1F600}
2
92
113
5
120
10
121
92
110
true
128512
4
128512
```

  This covers `\n`, `\r`, `\t`, `\\`, `\'`, `\"`, `\xHH`, `\uHHHH`,
  `\u{...}`, embedded `\0` (`a\0b` → length 3, code points 97/0/98;
  `a\01` → length 3, code points 97/0/49, so `\0` does not merge with a
  following octal digit), raw `r"a\nb"` (backslash preserved), raw `r"\q"`,
  multi-line raw `r"""x\ny\n"""`, and `'\u{1F600}'` (128512).
- **Negative case:** `escape_bad.x` (`"\q"`) is rejected:

```text
$ ./src/cli/xnull --bootstrap --engine=mini check src/mini/tests/r4/escape_bad.x
...: invalid escape sequence
```

- **Gap:** none for the documented S1 escape/raw/Char surface.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A7. time / 可取消 sleep (ledger #15) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Signature:** `sleepContext(Context context, Duration duration) ->
  Result<Unit, Error>`; the existing `sleepMs`/`sleep` stay non-cancellable.
  The context-first parameter order follows the rest of the XDK.
- **Source:** `src/xdk/core/time/Time.x` (`sleepContext`); FFI
  `sleepContextRaw` in `src/ffi/ext_raw.xfb`; runtime implementation
  `xdkc_sleep_ctx_ms` in `src/runtime/rt_task.c`. It polls
  `xrt_context_check_cancel` in 10ms slices and returns 1 on cancellation.
- **C test:** `src/runtime/test_task.c` (`test_sleep_context`) covers a full
  30ms sleep, an already-cancelled context, and a sleeping task cancelled by
  its group.
- **Scenario:** `src/mini/tests/r4/time_sleep_cancel.x`.
- **Command/output:**

```text
$ ./src/mini/tests/r4_evidence.sh
mini r4 evidence: PASS

$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/time_sleep_cancel.x
true
true
true
true
```

  The task calls `sleepContext(context, 5000ms)`; the main task cancels the
  group, joins, observes `ErrorKind.Cancelled` (code 7), and measures the join
  under 1s. `xdk_cancel.x` remains the built-in task-cancellation gate.
- **Design:** `docs/design/t0/08-time.md` now documents the cancellable path
  separately from `sleepMs`.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A8. time / 全量 layout 解析/格式化 (ledger #16) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Format:** `src/xdk/core/time/DateTime.x` scans the layout left-to-right
  with longest-token matching. It covers `yyyy`, `MM`, `MMM`, `MMMM`, `dd`,
  `ddd`, `dddd`, `EEE`, `EEEE`, `HH`, `mm`, `ss`, `SSS`; month/weekday names
  are real names, not literals.
- **Parse:** `src/xdk/core/time/Time.x` adds `parseDateTimeLayout(String text,
  String layout)` over the same token set and longest-match order, with
  strict literals, duplicate-field rejection, range validation, weekday
  consistency, and trailing-character rejection. `parseDateTime` is now a
  thin ISO wrapper that tries `T`/space separators, optional `.SSS`, and an
  optional trailing `Z` through the same parser.
- **Scenario:** `src/mini/tests/r4/time_layout_parse.x`.
- **Command/output:**

```text
$ ./src/mini/tests/r4_evidence.sh
mini r4 evidence: PASS

$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/time_layout_parse.x
true
2024-01-31 23:59:59.250
true
Wednesday, January 31 2024
true
1706659200000
true
1706745599250
true
2024-01-31 23:59:59
true
true
true
true
1706659200000
```

  It covers numeric and name tokens, `EEE`/`EEEE`, `MMM`/`MMMM`, `.SSS`,
  `Z`, space-separated ISO, invalid day (`2024-02-30`), weekday mismatch,
  trailing characters, and format→parse→format round trips.
- **Gap:** no `M`/`d`/`H` single-letter tokens or locale-specific names;
  `08-time.md` documents the exact supported set.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A9. log / 时间戳/单调时钟字段 (ledger #31)

- **Verdict:** stays `Strict candidate`.
- **Evidence:** `src/xdk/log/Log.x:51-61` (`LogRecord`) has only
  `level`, `loggerName`, `message`, `fields`; there is no timestamp or
  monotonic value:

```text
$ grep -n "timestamp\|nowMono\|nowWall" src/xdk/log/Log.x
(no matches)
```

- **Design:** `docs/design/t0/14-log.md:79` puts timestamp/monotonic fields in
  T1.
- **Gap:** a timestamp field (and clock injection for deterministic tests) plus
  a scenario.
- **What closes it:** add the field/API, update `LogRecord` formatting, and add
  a deterministic clock test.

### A10. config / 类型化 getter (ledger #33)

- **Verdict:** stays `Strict candidate`.
- **Evidence:** `src/xdk/config/Config.x` has `getOr(String,String)` only:

```text
$ grep -n "getInt\|getBool\|getLong\|getDouble\|getFloat\|getDuration" src/xdk/config/Config.x
(no matches)
```

- **Design:** `docs/design/t0/15-config.md:26` and `:75` put typed getters in
  T1.
- **Gap:** typed getters with parse errors and a scenario covering valid,
  invalid, and missing values.
- **What closes it:** add `getInt/getBool/...` returning `Result<T, Error>` (or
  the documented shape) and a scenario.

### A11. time / Stopwatch (ledger #36) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source:** `class Stopwatch` in `src/xdk/core/time/Time.x` over `nowMono`.
  `Stopwatch()` starts immediately; `start` restarts, `stop` freezes the
  reading, `reset` returns the previous reading and restarts, `elapsedMs`
  returns monotonic milliseconds, and `elapsed` returns a `Duration`.
- **Contract:** `docs/design/t0/08-time.md` §1 CAP-7, §3 class list, §4 top-level
  list, and §5 test obligations now include `Stopwatch`.
- **Scenario:** `src/mini/tests/r4/time_stopwatch.x`.
- **Command/output:**

```text
$ ./src/mini/tests/r4_evidence.sh
mini r4 evidence: PASS

$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/time_stopwatch.x
true
true
true
true
true
true
true
true
true
```

  It checks a 25ms elapsed window, `isRunning`, frozen elapsed after `stop`,
  previous reading from `reset`, restart, and `elapsed().millis()`.
- **Gap:** none for the documented T0-X contract (not wall-clock, not
  high-resolution beyond milliseconds).
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A12. errors / DetailedError 聚合 (ledger #37) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source:** `src/xdk/core/errors/Errors.x:36` (`DetailedError`),
  `:502` (`ErrorGroup`), `:579` (`<index>.` detail prefix); the documented T0
  path is custom `DetailedError` → `BasicError` → `ErrorGroup`
  (`docs/design/t0/01-errors.md` §5/§9/§14).
- **Scenario:** `src/mini/tests/r4/errors_detail.x`.
- **Command/output:** `./src/mini/tests/r4_evidence.sh` → `mini r4 evidence:
  PASS`; the scenario observes:

```text
2
2
0.origin
custom
1.path
true
2
[cfg.bad] InvalidArgument: bad setting
[cfg.bad] InvalidArgument: bad setting; NotFound: missing
true
```

  It defines a custom `CustomFailure implements Error, DetailedError`, converts
  it to `BasicError` with code/detail, aggregates it with a second error,
  checks the `<index>.` detail prefix, `causes()`, `kind()`, and
  `Cancelled` precedence.
- **Gap:** T1 generalisation (adding arbitrary `DetailedError` directly to the
  group) remains out of T0; that is recorded in `01-errors.md` §14, not hidden.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A13. config / 最小键校验（setChecked） (ledger #48) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source:** `src/xdk/config/Config.x:117` (`setChecked`), `:128` (`apply`).
- **Scenario:** `src/mini/tests/r4/config_checked.x`.
- **Command/output:** `./src/mini/tests/r4_evidence.sh` → PASS; the scenario
  observes:

```text
true
demo
true
true
1
true
1
next
true
true
on
override
next
```

  It covers valid set, empty key rejection, `=` in key rejection, replacement
  without growing the snapshot, `apply` stopping on an invalid entry with
  `InvalidArgument`, and `overlay` not mutating the source.
- **Gap:** none for the documented T0 contract.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

## 3. B. The 11 Optimized candidates

For each item: retained/lost, impact, dependents, breakage, migration, and
test evidence. A row moves to `Optimized proposed` only when the shim and the
test/output exist. `Optimized proposed` is still **not closed**.

### B1. errors / tryWith* (ledger #38) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:** `isValidErrorCode` (`Errors.x:92`) + `tryErrorDetail` (`:59`) +
  `withCode/withDetail/withCause` (`:368-395`) + `ErrorReport.tryWithStep`
  (`:470`).
- **Retained:** checked validation before mutation; checked detail construction;
  checked report step; immutable `with*` copies.
- **Lost:** direct same-name `BasicError.tryWithCode/tryWithDetail/
  tryWithCause` methods. The shim is explicit helper calls, not duplicate
  methods. `ErrorReport.tryWithStep` is the one direct `tryWith*` that exists.
- **Test:** `src/mini/tests/r4/errors_detail.x` via `r4_evidence.sh`; output
  includes `true/true/false/false/true/true/true/true/true/true/16/true` for
  code validation, detail validation, step success/failure, and the 16-step
  limit. `xdk_errors_full.x` (via `xdk.sh`) also covers the helper path.
- **Impact:** errors API. **Dependents:** errors users. **Breakage:** none
  (additive helpers; no existing signature changed). **Migration:** replace a
  desired `tryWithCode/tryWithDetail` with `isValidErrorCode`/`tryErrorDetail`
  plus the existing `with*`.
- **Status:** proposed, not closed.

### B2. runtime / stdio 流 (ledger #39)

- **Verdict:** stays `Optimized candidate`.
- **Retained:** `xdk.io` `Reader`/`Writer`/`BufferedReader`/`BufferedWriter`/
  `ChainReader`/`TeeReader`/`LimitReader`/`LineReader` (`src/xdk/io/IO.x`), and
  `stdinReadLine` (`src/xdk/io/system/Sys.x:196`).
- **Lost:** no adapter returns a `Reader`/`Writer` over process stdio; there is
  no runtime stdio stream surface. `02-runtime.md:80` puts stdio in T1.
- **Test evidence:** none that connects stdio to `xdk.io`. `xdk_io.x` tests
  memory streams only (`xdk.sh` PASS), which is not the optimized item.
- **Impact:** runtime/io. **Dependents:** io/runtime. **Breakage:** none.
  **Migration:** use `xdk.io` streams plus `stdinReadLine` where possible.
- **Gap:** adapter (`stdinReader()/stdoutWriter()` or equivalent) + scenario.

### B3. meta / BuildInfo (ledger #40)

- **Verdict:** stays `Optimized candidate`.
- **Retained:** `languageVersion`, `xdkVersion`, `targetPlatform`
  (`src/xdk/core/meta/Meta.x:5,9,13`).
- **Lost:** compiler version, architecture, build mode; the proposal asks for
  version/platform/compiler. `xdk_meta.x` tests only the two version strings.
- **Test evidence:** `xdk.sh` runs `xdk_meta.x` (`3.4.0`, `0.1.0`) — PASS, but
  it is not the BuildInfo surface.
- **Impact:** meta. **Dependents:** log/cli. **Breakage:** none.
  **Migration:** none.
- **Gap:** compiler/arch/mode constants + scenario; `03-meta.md:51` is T0-X.

### B4. meta / 能力矩阵 (ledger #41) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:** the build-time table `src/ffi/capabilities.tsv` (14 packages,
  one owner per capability) plus `src/ffi/api-manifest.tsv` (114 symbols /
  14 packages), generated by `src/toolchain/gen_api_manifest.py`, and checked
  by `src/toolchain/check_layers.py` G1/G2/G3.
- **Retained:** package/capability ownership, L1/L2 closure, per-symbol API
  manifest, empty 1.0 allowlist.
- **Lost:** runtime capability probing and a `xdk.meta` query API; no
  per-platform feature flags. That is the intended trade: the table is fixed at
  build time.
- **Test/command/output:**

```text
$ python3 src/toolchain/check_layers.py
check_layers: PASS (g1=0 g2=0 g3=0 allowlist=0/0; raw g1=0 g2=0 g3=0)

$ python3 src/toolchain/gen_api_manifest.py
api manifest: 114 symbols / 14 packages
```

- **Impact:** meta/sys. **Dependents:** meta/sys, all packages via the manifest.
  **Breakage:** none (build-time data; no runtime signature). **Migration:**
  read the table at build time instead of probing the runtime.
- **Status:** proposed, not closed.

### B5. meta / 构建元数据 (ledger #42)

- **Verdict:** stays `Optimized candidate`.
- **Retained:** version constants and target platform (`Meta.x`).
- **Lost:** build date, compiler identity, target architecture, build mode.
- **Test evidence:** none for build metadata; `xdk_meta.x` covers versions only.
- **Impact:** meta. **Dependents:** meta. **Breakage:** none.
  **Migration:** none.
- **Gap:** read-only build metadata constants + scenario; `03-meta.md:53` is
  T0-X.

### B6. bytes / NUL 边界工具 (ledger #44)

- **Verdict:** stays `Optimized candidate`.
- **Retained:** `Bytes`, `ByteReader`, `ByteWriter`, `ByteBuffer`
  (`src/xdk/core/bytes/Bytes.x`) and their scenarios (`xdk_bytes*.x` PASS).
- **Lost:** C-string/NUL-boundary helpers (no `nul`/`CString` symbol):

```text
$ grep -rni "nul\|cstring\|fromCString\|toCString" src/xdk/core/bytes
(no matches)
```

- **Test evidence:** none for the optimized item; the existing ByteBuffer
  evidence is a different ledger row.
- **Impact:** bytes. **Dependents:** bytes users. **Breakage:** none.
  **Migration:** use `ByteReader`/`ByteWriter` explicitly.
- **Gap:** the thin NUL-boundary wrapper and a scenario.

### B7. time / 日历加减边界 (ledger #45) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Retained:** `Duration` arithmetic; `DateTime.add(Duration)`/`addDays`/
  `addMonths`/`addYears`, `diff`, `before/after/compare`; field extraction;
  `dateTimeFromTimestamp`; ISO and full-layout parsing; fixed civil factory
  `dateTimeOf`.
- **Lost:** DST/TimeZone and locale-specific month names. The retained
  calendar arithmetic is UTC civil arithmetic; no tz database is involved.
  Full layout parsing moved from this optimized proposal to the now-evidenced
  strict item A8, so it is no longer a loss.
- **Test:** `src/mini/tests/r4/time_calendar.x` and
  `src/mini/tests/r4/time_calendar_edges.x` via `r4_evidence.sh`; also
  `xdk_time.x` via `xdk.sh`.
- **Observed output (edges):**

```text
2024-02-29 12:34:56
2023-02-28
2024-02-29
2025-02-28
2025-02-28
2023-02-28
2022-11-30
2025-02-28
2024-02-29
2024-03-01
2023-12-31
2025-01-31 12:34:56
```

  The scenario covers leap/non-leap month-end clamping, negative month
  arithmetic, year boundaries, Feb 29 ±1 year, leap-day `addDays`, and
  time-of-day preservation.
- **Bug found and fixed:** `dateTimeOf` multiplied `Int days * 86400000` in
  32-bit, so fixed dates after 1970-01-25 were wrong (e.g. `2024-01-31`
  produced `1970-01-20`). It now casts both factors to `Long`
  (`src/xdk/core/time/Time.x` and the mirror). `xdk_time.x` now asserts a fixed
  date and timestamp as a regression.
- **Impact:** time API. **Dependents:** time users. **Breakage:** additive;
  the only behavior change is wrong `dateTimeOf` output becoming correct.
  **Migration:** use `addDays`/`addMonths`/`addYears` for civil arithmetic;
  do not assume DST or locale names.
- **Status:** proposed, not closed.

### B8. log / 过滤/脱敏/采样 (ledger #47)

- **Verdict:** stays `Optimized candidate`.
- **Retained:** level threshold, `Field`, `LogRecord`, Console/Memory sink
  (`src/xdk/log/Log.x`), covered by `xdk_log.x` via `xdk.sh`.
- **Lost:** filter chain, redaction hooks, deterministic sampler; there are no
  such symbols:

```text
$ grep -rni "filter\|redact\|sample" src/xdk/log
(no matches)
```

- **Test evidence:** none for the optimized item; `14-log.md:24` puts these in
  T1.
- **Impact:** log. **Dependents:** log users. **Breakage:** none.
  **Migration:** add hooks later.
- **Gap:** predicates/redaction/sampler + tests, or keep as T1 non-goal.

### B9. cli / 补全 (ledger #49)

- **Verdict:** stays `Optimized candidate`.
- **Retained:** `OptionSpec`/`Command`/`help` (`src/xdk/cli/Cli.x`), covered by
  `xdk_cli.x` via `xdk.sh`.
- **Lost:** shell completion generation; no symbol:

```text
$ grep -rni "completion\|complete" src/xdk/cli
(no matches)
```

- **Design:** `docs/design/t0/16-cli.md:28` lists completion as T1.
- **Impact:** cli. **Dependents:** cli users. **Breakage:** none.
  **Migration:** generated later.
- **Gap:** generator from `OptionSpec` + test.

### B10. cli / 短选项合并/重复策略 (ledger #50)

- **Verdict:** stays `Optimized candidate`.
- **Retained:** long-option parsing (`--k v`, `--k=v`), unknown-option
  rejection, required/value checks, subcommands, help (`Cli.x`).
- **Lost:** POSIX short-option bundling (`-abc`), an explicit duplicate-option
  policy, and a `--` terminator contract. The current `Args.value` returns the
  first match; that is incidental behavior, not a documented rule.
- **Design:** `docs/design/t0/16-cli.md:28` lists short-option merging and
  duplicate policy as T1.
- **Impact:** cli. **Dependents:** cli users. **Breakage:** subset.
  **Migration:** keep long options; do not rely on bundling.
- **Gap:** document/implement the rule and add a scenario.

### B11. cli / 环境/配置文件默认值 (ledger #51)

- **Verdict:** stays `Optimized candidate`.
- **Retained:** `Args` parsing and `valueOr` fallback.
- **Lost:** environment/config precedence chain; no symbol:

```text
$ grep -rni "env\|config" src/xdk/cli
(no matches)
```

- **Design:** `docs/design/t0/16-cli.md:75` lists env/config defaults as T1.
- **Impact:** cli. **Dependents:** cli users. **Breakage:** subset.
  **Migration:** pass explicit defaults at the call site.
- **Gap:** a fixed precedence chain + scenario.

## 4. C. The 3 Deferred candidates

These remain `Deferred candidate`. The meeting date and the decision are the
user's; this batch supplies the strict plan, options, and impact. No row is
promoted or closed here.

### C1. math / random (ledger #52)

- **Current evidence:** no `xdk.math` random symbol; `07-math.md:27` and `:124`
  say random is T1 `xdk.random`. A deterministic raw bridge already exists but
  is unused by XDK: `src/ffi/ext_raw.xfb:113-126` (`randSeedRaw`,
  `randNextRaw`, `randDoubleRaw`) and `src/runtime/rt_std_ext.c:52-81`
  (xorshift64*).
- **Strict plan:** define `xdk.random` as a T1 package with explicit seed,
  `nextLong`, bounded `nextInt(min,max)`, `nextDouble`, `nextBool`, and
  `shuffle<T>`; document that it is deterministic and not cryptographic; add
  range/determinism/seed-reset tests.
- **Options:** A) T1 package over the existing xorshift64* bridge
  (recommended); B) OS RNG adapter (`getrandom`/`arc4random`) with no
  reproducibility promise; C) no random in the 1.x core.
- **Impact:** new package, additive. **Dependents:** math users, tests.
  **Breakage:** none. **Migration:** none (no existing symbol).
- **Meeting/signature:** date TBD; signer: user.

### C2. time / TimeZone (ledger #53)

- **Current evidence:** UTC-only; `DateTime.toUTC()`/`toLocal()` return `self`
  (`src/xdk/core/time/DateTime.x`); `08-time.md:24` excludes IANA tzdata and
  `:104` puts `TimeZone`/`toZone` in T0-X. There is no `TimeZone` source.
- **Strict plan:** A) fixed-offset subset: `FixedOffset(seconds)` and
  `DateTime.toZone(FixedOffset)`/`offsetSeconds()`, epoch value unchanged,
  formatting applies the offset; tests for +08:00/-05:00 and round trips; no
  DST/IANA. B) IANA: TZif parser, tzdata discovery/update policy, caching,
  DST transitions. C) none.
- **Options:** A) fixed offset for 1.0 (recommended); B) IANA; C) no timezone.
- **Impact:** time API. **Dependents:** time/log/config users. **Breakage:**
  none if additive; UTC remains default. **Migration:** explicit offset for
  display; keep epoch math in UTC.
- **Meeting/signature:** date TBD; signer: user.

### C3. config / codec (ledger #54)

- **Current evidence:** `Config.x` only has `FileSource` `key=value` parsing;
  `15-config.md:25-26` excludes JSON/TOML/YAML and `:77` puts codec injection
  in T1. There is no codec symbol.
- **Strict plan:** A) JSON codec: `protocol Codec { decode(String) ->
  Result<List<ConfigEntry>, Error> }` plus `JsonCodec`; object-only, scalar
  values converted to strings, arrays/nesting rejected or flattened by rule;
  tests for valid/invalid JSON and duplicate keys. B) external adapter: user
  supplies a `ConfigSource`; no core codec. C) none.
- **Options:** A) JSON codec (recommended); B) external adapter; C) none.
- **Impact:** config API. **Dependents:** config/cli/app users. **Breakage:**
  none (additive); `FileSource` stays. **Migration:** implement `ConfigSource`
  for other formats until a codec is chosen.
- **Meeting/signature:** date TBD; signer: user.

## 5. D. The 9 language built-in items (out-of-scope / deferred)

These are **not** strict evidence items. The package designs explicitly list
them as non-goals. The package API is user-signed; this batch adds no strict
evidence and does not call them closed.

| # | Item | Non-goal evidence | Status |
| --- | --- | --- | --- |
| 55 | tasks / select/race | `docs/design/t0/12-tasks.md:26`, `:75` | out-of-scope / deferred |
| 56 | tasks / Context 值 | `12-tasks.md:26`, `:76` | out-of-scope / deferred |
| 57 | tasks / 取消作用域 | `12-tasks.md:26`, `:76` | out-of-scope / deferred |
| 58 | sync / RwLock | `docs/design/t0/13-sync.md:26`, `:76` | out-of-scope / deferred |
| 59 | sync / Semaphore | `13-sync.md:26`, `:76` | out-of-scope / deferred |
| 60 | sync / WaitGroup | `13-sync.md:26`, `:76` | out-of-scope / deferred |
| 61 | sync / Once | `13-sync.md:26`, `:76` | out-of-scope / deferred |
| 62 | sync / Barrier | `13-sync.md:26`, `:76` | out-of-scope / deferred |
| 63 | sync / select | `13-sync.md:26`, `:77` | out-of-scope / deferred |

`12-tasks.md:26` reads “非目标：select/race、Context 值、取消作用域、线程池调优”;
`13-sync.md:26` reads “非目标：RwLock、Semaphore、WaitGroup、Once、Barrier、
select、无锁容器”. The existing `xdk.tasks`/`xdk.sync` scenarios
(`xdk_tasks.x`, `xdk_cancel.x`, `xdk_mutex.x`, `xdk_channel.x`,
`xdk_sync_atomic.x`) remain the built-in gate; they are not strict evidence for
these nine items. No ledger row is changed by this batch.

## 6. Files changed across the R4 evidence batches

New evidence:

- `docs/design/t0/R4-EVIDENCE.md` (this file)
- `src/mini/tests/r4_evidence.sh`
- `src/mini/tests/r4/escape.x`, `src/mini/tests/r4/escape_bad.x`
- `src/mini/tests/r4/inference.x`
- `src/mini/tests/r4/errors_detail.x`
- `src/mini/tests/r4/config_checked.x`
- `src/mini/tests/r4/time_calendar.x`

Follow-up fixes (all real code, no stubs):

- `src/mini/main.x` + regenerated `src/mini/bin/mini.c`:
  - string literals use `rt_string_new(..., sizeof(...) - 1)`, preserving
    embedded NUL and `\u{...}` byte length;
  - raw strings `r"..."` / `r"""..."""` are lexed and converted to C literals;
  - the S1 escape table is validated (unknown escapes / invalid scalars are
    lexical errors);
  - `Char` literals emit `((int32_t)U'...')`, so non-ASCII scalars build;
  - `MethodCall` receiver types are resolved for cross-type inference;
  - top-level parse errors return an empty program, so `--sema`/`--emit-c`
    fail instead of emitting partial C.
- `src/xdk/core/time/DateTime.x` and `xdk/lib/xdk/core/time/DateTime.x`:
  token-aware layout formatting with longest-token matching and real
  month/weekday names.
- `src/xdk/core/time/Time.x` and `xdk/lib/xdk/core/time/Time.x`:
  `dateTimeOf` widens `days * 86400000` and the time-of-day term to `Long`
  (32-bit overflow fix from the first R4 batch).
- `src/runtime/rt_std_sys.c` and `xdk/runtime/rt_std_sys.c`:
  `xdkc_read_file_text` returns `NULL` on error, matching the
  `xdkc_read_file_text_code` contract.
- `src/runtime/test_std.c`: the missing-file case uses the real path length.
- `src/mini/tests/xdk_time.x` + `src/mini/tests/xdk.sh`: fixed-date, layout
  token, and timestamp regression output.

This batch (RuntimeInfo/stats/Stopwatch/cancellable sleep/layout parse/calendar):

- New scenarios: `src/mini/tests/r4/runtime_info.x`,
  `src/mini/tests/r4/runtime_stats.x`,
  `src/mini/tests/r4/time_stopwatch.x`,
  `src/mini/tests/r4/time_sleep_cancel.x`,
  `src/mini/tests/r4/time_layout_parse.x`,
  `src/mini/tests/r4/time_calendar_edges.x`.
- `src/mini/tests/r4_evidence.sh`: exact-output cases for all six.
- `src/xdk/core/runtime/Runtime.x` + mirror: `RuntimeInfo`, `RuntimeStats`,
  `runtimeInfo`, `stats`, `statsEnabled`, `statsSetEnabled`, `statsReset`.
- `src/xdk/core/time/Time.x` + mirror: `Stopwatch`, `sleepContext`,
  `parseDateTimeLayout`, and `parseDateTime` rewritten over the layout parser.
- `src/xdk/core/time/DateTime.x` + mirror: `addDays`, `addMonths`, `addYears`.
- `src/ffi/runtime_raw.xfb` + mirror: runtime-info and stats primitives.
- `src/ffi/ext_raw.xfb` + mirror: `sleepContextRaw`.
- `src/runtime/rt_std_runtime.c` + mirror: `xdkc_build_mode` and
  `xdkc_stats_*` wrappers over `xrt_stats_*`.
- `src/runtime/rt_task.c` + mirror: `xdkc_sleep_ctx_ms`.
- `src/runtime/test_std.c`: XDK stats wrappers match the ABI snapshot.
- `src/runtime/test_task.c`: full sleep, already-cancelled context, and
  group-cancelled sleeping task.
- `src/ffi/capabilities.tsv` + `api-manifest.tsv` + mirrors: new L1/L2
  symbols, scenarios, and C tests.
- `docs/design/t0/02-runtime.md`, `docs/design/t0/08-time.md`: contract and
  test-obligation updates.

Deliberately untouched:

- `docs/design/MINI-1.0.md` (ledger owner; user asked not to edit).
- `docs/design/t0/C1-U0-U5-EVIDENCE.md` (U3 session owns it).
- `docs/design/t0/AUDIT.md` (no independent signer in this batch, so no
  signature row was added; the U3 section was not touched).

## 7. Remaining RED / unsigned

| Area | Remaining | Why |
| --- | ---: | --- |
| Strict candidates | 4 | A2, A5, A9, A10; each has a named gap and a close path |
| Optimized candidates | 8 | B2, B3, B5, B6, B8-B11; no shim/test yet |
| Deferred candidates | 3 | C1-C3; decision meeting date is user-owned |
| Out-of-scope / deferred | 9 | D1-D9; spec non-goals, package API user-signed |
| Signed closed | 0 | no independent reviewer signature |

Resolved by the first follow-up:

1. `text / 转义`: embedded `\0`, raw strings, and non-ASCII `Char` literals
   now work; unknown escapes are rejected (A6).
2. `errors / 复杂接收者表达式推断`: `makeItem(value).label()` and
   `items.get(0).label()` now infer `mapOk` (A1).
3. `time / layout`: `MMM`/`MMMM` and `ddd`/`dddd` are longest-token matched;
   `"EEE, dd MMM yyyy"` renders `"Wed, 31 Jan 2024"` (A8 formatting).
4. `src/runtime/build_rt.sh` (full C suite) is green after the
   `xdkc_read_file_text` error contract fix.

Resolved by this batch:

1. `runtime / RuntimeInfo` (A4): real class + `runtimeInfo()` + scenario.
2. `runtime / stats` (A3): public `RuntimeStats`/`stats` over the existing
   `xrt_stats_*` ABI, with C and XDK tests.
3. `time / Stopwatch` (A11): monotonic start/stop/reset/elapsed + scenario.
4. `time / 可取消 sleep` (A7): `sleepContext` over a context-aware runtime
   wait + cancellation scenario + C test.
5. `time / 全量 layout 解析/格式化` (A8): token-aware
   `parseDateTimeLayout`; `parseDateTime` is now a thin ISO wrapper over it.
6. `time / 日历加减边界` (B7): `addDays`/`addMonths`/`addYears` with
   month-end clamping and leap/year-boundary tests (stays Optimized proposed).

Still open (Strict candidates):

- A2 error-code registry, A5 StringBuilder, A9 log timestamp/monotonic field,
  A10 config typed getter.
- B2/B3/B5/B6/B8-B11 optimized candidates, C1-C3 deferred, D1-D9 out-of-scope.

The required gates (`r4_evidence.sh`, `ref.sh`, `xdk.sh`, `xdk_core.sh`,
`check_layers`) and the full C suite (`src/runtime/build_rt.sh`) are green as
shown in §0. The worktree is clean after the single batch commit.
