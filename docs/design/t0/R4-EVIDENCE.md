# R4 evidence closure — 41 Strict evidenced + 10 Optimized proposed + 3 Deferred + 9 out-of-scope

| Item | Value |
| --- | --- |
| Base | `core-verify@f254ab33` |
| Worktree | `../XNull-core-evidence` |
| Branch | `core-evidence` |
| Date | 2026-11-22 |
| Scope | R4 evidence gaps only; no merge, no ledger edit |
| Ledger owner | `docs/design/MINI-1.0.md` §15 (user-owned; **not modified** here) |

This file is the evidence attachment for the R4 ledger. It does not change any
status in `MINI-1.0.md`; the ledger remains the user-owned source of record.
Only the API-manifest count and the U3/U5 status wording were refreshed in
`C1-U0-U5-EVIDENCE.md`/`AUDIT.md`; no independent reviewer signature was added.

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
mini error codes: PASS
mini r4 evidence: PASS

$ ./src/mini/tests/error_codes.sh
check_error_codes: PASS (9 codes, 2 sources)
mini error codes: PASS

$ ./src/mini/tests/resources.sh
PASS resource resources [base]
PASS resource resources_full [full]
PASS resource resources_cancel [full]
mini resources: PASS

$ ./src/runtime/build_rt.sh
...
std 测试通过
...
empty resource table fallback ok
exit 0
```

`r4_evidence.sh` is the evidence runner for the scenarios added in these
batches; it now also invokes the W6 error-code registry test. It builds and runs
every program end-to-end and diffs exact output. The full C suite
(`build_rt.sh`, no `--lib`) is also green.

`resources.sh` is a **standalone** gate for the embedded-resource subset
(`resources`, `resources_full`, `resources_cancel`). `xdk.sh` does not invoke
it; the sys resource evidence above is the independent command/output, not an
`xdk.sh` sub-result.

## 1. Status after the B2/B8 batch

| State | Ledger start | After R4 batch | After follow-up | After text/errors | After config/log batch | After B2/B8 | Change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `Strict evidenced` (14-package ledger) | 27 | 29 | 31 | 39 | 41 | 41 | +14 total; log timestamp and config typed getter |
| `Strict candidate` | 13 | 11 | 9 | 2 | 0 | 0 | -13 total; all strict candidates now have a real chain |
| `Optimized proposed` | 0 | 3 | 3 | 2 | 8 | 10 | +10 total; B2 stdio and B8 log pipeline now have shim + scenario |
| `Optimized candidate` | 11 | 8 | 8 | 8 | 2 | 0 | -11 total; B2/B8 promoted, no optimized candidates remain |
| `Deferred candidate` | 3 | 3 | 3 | 3 | 3 | 3 | 0 promoted; C1-C3 decision packets refreshed |
| `Out-of-scope / deferred` | 9 | 9 | 9 | 9 | 9 | 9 | 0 changed; non-goal evidence attached |
| `Signed Strict/Optimized closed` | 0 | 0 | 0 | 0 | 0 | 0 | no signer in this batch |

`Strict evidenced` and `Optimized proposed` are **not closed**. Only a user or
independent reviewer signature makes a row `Signed ... closed`.

Sys resource subset (#28) is evidenced by the standalone
`./src/mini/tests/resources.sh` command/output in §0; `xdk.sh` covers the sys
stdio/signal surface but does not run `resources.sh`.

## 2. A. original 13 Strict candidates（已晋升）

Each item below starts from the ledger state and records the real source,
scenario, command, and observed output. The original 13 are now all promoted;
the per-item verdict lines preserve the historical `Strict candidate →
Strict evidenced` transition.

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

### A2. errors / 错误码命名空间工具 (ledger #2) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source/fixes:**
  - `docs/design/t0/appendices/error-codes.tsv`: W6 registry with
    `code/namespace/owner/severity/description/status` per code.
  - `src/toolchain/check_error_codes.py`: rejects malformed, duplicate,
    namespace-mismatched, and unregistered emitted codes.
  - `src/mini/tests/error_codes.sh`: positive gate plus three negative fixtures
    (unregistered `SEM-999`, duplicate row, namespace mismatch).
- **Registry contents:** `SEM-001..005` (compiler semantic diagnostics) and
  `CLI-001..003`, `CLI-901` (CLI namespace; `CLI-002` is active, the rest are
  reserved). `ErrorKind` code 0..13 remains the separate FFI error-kind table.
- **Scenario/command/output:**

```text
$ python3 src/toolchain/check_error_codes.py
check_error_codes: PASS (9 codes, 2 sources)

$ ./src/mini/tests/error_codes.sh
check_error_codes: PASS (9 codes, 2 sources)
mini error codes: PASS
```

  The negative fixtures make the gate RED when a source emits `SEM-999`, when
  the registry repeats `SEM-001`, or when `CLI-777` is filed under `SEM`.
- **Gap:** none for the W6 registry scope. Runtime `ErrorKind` codes are not
  duplicated into this table; they stay in `01-errors.md` §3/§11.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

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

### A5. text / StringBuilder (ledger #6) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source/fixes:**
  - `src/xdk/text/full/StringBuilder.x` and the base mirror: append-only
    `StringBuilder` with `append/appendInt/appendLong/appendChar/clear`,
    `length()`, `isEmpty()`, and `toString()`.
  - The `xdk.text` package loader picks up the sibling builder unit; no
    `Text.x` change was needed.
  - `docs/design/t0/05-text.md` §2.4 defines the T0 contract; §6 narrows the
    remaining gap to zero-copy/extra overloads/T1.
- **Scenario:** `src/mini/tests/r4/text_builder.x` via `r4_evidence.sh`; also a
  small StringBuilder assertion in `xdk_core.x`.
- **Observed output:**

```text
$ ./src/mini/tests/r4_evidence.sh
mini error codes: PASS
mini r4 evidence: PASS
```

  The scenario observes `0/true/true/4/ab7-/14/ab7-9000000000/0/true/x/xy`;
  it covers the empty builder, chained append, UTF-8 byte length, integral and
  Long append, `clear()`, and immutable `toString()` snapshots.
- **Gap:** none for the §2.4 T0 contract. The C runtime `xrt_sb_*` buffer and a
  zero-copy XDK binding remain T1 optimization work.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

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

### A9. log / 时间戳/单调时钟字段 (ledger #31) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source/fixes:**
  - `src/xdk/log/Log.x`: `LogRecord` now carries `timestampMs`/`monotonicMs`
    plus `timestamp()`/`monotonic()` accessors.
  - A `Clock` protocol (`wallMs`/`monoMs`) and `SystemClock` default are added;
    `Logger.withClock` injects a replacement clock and `withSink`/`withField`
    preserve it.
  - `Logger.log` fills both fields before handing the record to the sink.
  - `MemorySink.captured()` returns the raw `LogRecord` objects, and
    `recordTextWithTime` provides an explicit timestamped rendering;
    `recordText` is unchanged so existing log output stays stable.
- **Design:** `docs/design/t0/14-log.md` CAP-7/CAP-8, contract, and test
  obligations updated; timestamp/clock is T0-X, not T1.
- **Scenario:** `src/mini/tests/r4/log_timestamp.x` via `r4_evidence.sh`.
- **Command/output:**
```text
$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/log_timestamp.x
2
1700000000000
500
1700000000000
500
true
[INFO] svc: ready
1700000000000 [INFO] svc: ready
[INFO] svc: ready
1700000000000
[INFO] svc: field k=v
```
  The scenario injects `FixedClock(1700000000000, 500)`, filters a debug
  record, observes both raw fields and accessors, checks the injected clock
  survives `withField`, and confirms the legacy text form is unchanged.
- **Gap:** no locale/time formatting; the fields are raw milliseconds.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### A10. config / 类型化 getter (ledger #33) — PROMOTED

- **Verdict:** `Strict candidate` → `Strict evidenced` (unsigned).
- **Source/fixes:** `src/xdk/config/Config.x` adds
  `getInt`/`getLong`/`getBool`/`getDouble`, all returning
  `Result<T, Error>`. Missing keys return `NotFound`, parse failures return
  `InvalidArgument`; `getLong` parses 64-bit decimal values, `getBool` accepts
  `true`/`false`/`1`/`0`, and `getDouble` uses the strict `parseFloat` contract.
- **Design:** `docs/design/t0/15-config.md` CAP-8, contract, and test
  obligations updated; `Duration` getter stays T1.
- **Scenario:** `src/mini/tests/r4/config_typed.x` via `r4_evidence.sh`.
- **Command/output:**
```text
$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/config_typed.x
true
9090
true
9000000000
true
3.5
true
true
true
true
true
true
```
  The scenario covers valid values (including a >32-bit Long), missing keys
  (with `ErrorKind.NotFound`), and invalid Int/Long/Bool/Double values.
- **Gap:** no `Duration` getter and no schema/error aggregation; both are T1.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

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
  `:502` (`ErrorGroup`), `:579` (`<index>.` detail prefix);
  `ErrorGroup.addDetailed(DetailedError)` now performs the single conversion
  through `basicErrorOf` instead of requiring callers to hand-build a
  `BasicError`. The documented T0 path is custom `DetailedError` →
  `addDetailed` → `ErrorGroup` (`docs/design/t0/01-errors.md` §5/§9/§14).
- **Scenario:** `src/mini/tests/r4/errors_detail.x`.
- **Command/output:** `./src/mini/tests/r4_evidence.sh` → `mini r4 evidence:
  PASS`; the scenario observes the original manual path plus direct
  aggregation:

```text
$ ./src/mini/tests/r4_evidence.sh
mini error codes: PASS
mini r4 evidence: PASS
```

  For the direct path it observes `1`, `[cfg.bad] InvalidArgument: bad setting`,
  `true`; the error is a custom `CustomFailure implements Error, DetailedError`
  passed to `addDetailed` with no manual conversion.
- **Gap:** T1 full aggregation of a custom `DetailedError`'s details/causes
  remains out of T0 (T0 converts kind/message/code); that is recorded in
  `01-errors.md` §14, not hidden.
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

## 3. B. original 11 Optimized candidates（已晋升）

For each item: retained/lost, impact, dependents, breakage, migration, and
test evidence. The original 11 are now promoted (B1 to Strict evidenced, the
rest to Optimized proposed); the per-item verdict lines preserve the historical
`Optimized candidate → ...` transition. `Optimized proposed` is still **not
closed**.

### B1. errors / tryWith* (ledger #38) — PROMOTED TO STRICT EVIDENCED

- **Verdict:** `Optimized candidate` → `Strict evidenced` (unsigned). The old
  `01-errors.md` §7.3 note that mini codegen blocked direct `tryWith*` methods
  was reproduced and disproved: the blocker was a class-method emission-order
  issue for *user* classes referencing imported package symbols, not for
  methods inside the package. `BasicError.tryWithCode/tryWithDetail/
  tryWithCause` now compile and run as direct methods.
- **Source:** `BasicError.tryWithCode`/`tryWithDetail`/`tryWithCause` in
  `src/xdk/core/errors/Errors.x`; checked return values, no exception, no
  silent drop at the 8-cause limit.
- **Retained:** direct same-name methods, checked validation before mutation,
  immutable `with*` copies, and `ErrorReport.tryWithStep`.
- **Lost:** nothing; the helper shim remains as the lower-level path.
- **Test:** `src/mini/tests/r4/errors_detail.x` via `r4_evidence.sh`; output
  covers `true/cfg.checked/true/true/2/true/true/1/true/true/true` for
  code success, code rejection, detail success/rejection, cause success/self/
  null, and the full-cause rejection. `xdk_core.x` also calls
  `tryWithCode("core.missing")`.
- **Impact:** errors API. **Dependents:** errors users. **Breakage:** none
  (additive methods; `with*` semantics unchanged). **Migration:** replace the
  `isValidErrorCode`/`tryErrorDetail` + `with*` shim with the direct method
  when a checked `Result` is wanted.
- **Status:** evidence is real; still **unsigned**, therefore not closed.

### B2. runtime/io / stdio 流 (ledger #39) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim (real OS descriptors, not a memory stream):**
  - `src/runtime/rt_std_ext.c` + mirror adds `xdkc_stdio_read_hex`,
    `xdkc_stdio_write_hex`, and `xdkc_stdio_flush`. Reads use `read(0)`, writes
    use `write(1/2)` after flushing the same fd's stdio buffer; bytes cross the
    FFI boundary as hex, so embedded NUL is preserved.
  - `src/ffi/io_raw.xfb` + mirror exposes those three primitives.
  - `src/xdk/io/IO.x` + mirror adds `StdioReader`, `StdioWriter`, and
    `stdinReader()`/`stdoutWriter()`/`stderrWriter()`. `StdioReader` implements
    the existing `Readable` protocol with checked `tryReadU8`/`readExact`;
    `StdioWriter` implements `Writable` and flushes without closing fd 1/2.
- **Retained:** `Reader`/`Writer`/`BufferedReader`/`BufferedWriter`/`ChainReader`/
  `TeeReader`/`LimitReader`/`LineReader`; `stdinReadLine` remains in
  `xdk.sys`. `BufferedReader.hasRemaining()` now also consults a streaming
  source, so the adapter composes with buffered reads.
- **Lost:** no terminal control (raw mode, window size), no non-blocking mode,
  no fd ownership transfer, and `StdioReader.remaining()` only reports buffered
  bytes (EOF is discovered by a read). `StdioWriter` accepts only fd 1/2.
- **Test/command/output:** `src/mini/tests/r4/stdio.x` is built by
  `r4_evidence.sh`, fed `alpha\nbeta\ngamma\n` through a pipe, and its stdout
  and stderr are diffed separately:

```text
alpha
10
beta
10
gamma
true
true
true
false
false
OUT:hello
!
true
true
true
12
true
true
13
```

  stderr is exactly `ERR:redacted`. The scenario covers `readExact`,
  `readU8`, `readBytes`, `LineReader` over stdin, EOF via
  `DataCorrupted`, and writes to both stdout and stderr.
- **Impact:** io/runtime additively. **Dependents:** io users, log sinks, CLI
  tools. **Breakage:** none; existing memory streams are unchanged.
  **Migration:** replace ad-hoc `stdinReadLine`/printf plumbing with
  `stdinReader()`/`stdoutWriter()` when byte-level streaming is needed.
- **Status:** proposed, not closed.

### B3. meta / BuildInfo (ledger #40) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:** `BuildInfo` and `buildInfo()` in `src/xdk/core/meta/Meta.x`
  aggregate language/XDK/compiler/platform/arch/mode/build time; `complete()`
  rejects any empty field and `describe()` provides a diagnostic string.
- **Retained:** `languageVersion`, `xdkVersion`, `targetPlatform`, and all
  previously frozen version/platform strings.
- **Lost:** no runtime capability probing and no package-manager metadata; the
  build identity is fixed by the compiler/runtime that produced the binary.
- **Test/command/output:**
```text
$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/meta_buildinfo.x
true
3.4.0
1.0.0
mini
3.4.0
true
true
true
true
true
true
true
mini
3.4.0
true
```
  The scenario checks `complete()`, all version/compiler fields, non-empty
  platform/arch/mode/build time, `describe()`, and the standalone functions.
- **Impact:** meta additively; existing three functions unchanged.
  **Dependents:** log/cli/diagnostics. **Breakage:** none.
  **Migration:** read the aggregate through `buildInfo()` when several fields
  are needed.
- **Status:** proposed, not closed.

### B4. meta / 能力矩阵 (ledger #41) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:** the build-time table `src/ffi/capabilities.tsv` (14 packages,
  one owner per capability) plus `src/ffi/api-manifest.tsv` (160 symbols /
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
api manifest: 160 symbols / 14 packages
```

- **Impact:** meta/sys. **Dependents:** meta/sys, all packages via the manifest.
  **Breakage:** none (build-time data; no runtime signature). **Migration:**
  read the table at build time instead of probing the runtime.
- **Status:** proposed, not closed.

### B5. meta / 构建元数据 (ledger #42) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:** read-only `targetArch`, `buildMode`, `compilerName`,
  `compilerVersion`, and `buildDate` in `src/xdk/core/meta/Meta.x`.
  `buildDate` is the C runtime's `__DATE__ __TIME__`; `buildMode` is
  `release`/`debug` from the runtime build.
- **Retained:** version constants and target platform.
- **Lost:** reproducible build timestamps and build numbers. `buildDate` is
  explicitly diagnostic-only and must not be used in business logic or cache
  keys; the docs say so.
- **Test/command/output:** the same `meta_buildinfo.x` run as B3 checks the
  non-empty build date, mode, arch, and compiler identity; `src/runtime/test_std.c`
  also asserts `xdkc_build_date()` is non-empty in the C suite.
- **Impact:** meta. **Dependents:** meta/diagnostics. **Breakage:** none
  (additive). **Migration:** none.
- **Status:** proposed, not closed.

### B6. bytes / NUL 边界工具 (ledger #44) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:** `src/xdk/core/bytes/Bytes.x` adds `nulIndex`, `hasNul`,
  `nulPrefix`, `withNulTerminator`, and `withoutTrailingNul`. They operate on
  byte 0 only, never expose a raw pointer, and always return new copies.
- **Retained:** `Bytes`, `ByteReader`, `ByteWriter`, `ByteBuffer` and their
  existing scenarios.
- **Lost:** no `CString` type, no implicit C-string conversion, and no
  ownership transfer to/from native code; that remains outside the safe T0 API.
- **Test/command/output:**
```text
$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/bytes_nul.x
2
true
6162
686900
686900
6869
-1
false
706c61696e
6869
0
true
00
true
```
  The scenario covers embedded NUL, no NUL, an empty sequence, a leading NUL,
  adding a terminator (including to an empty sequence), and removing one
  trailing NUL.
- **Impact:** bytes additively. **Dependents:** bytes users.
  **Breakage:** none. **Migration:** replace manual NUL scans with the helpers.
- **Status:** proposed, not closed.

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

### B8. log / 过滤/脱敏/采样 (ledger #47) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim (`src/xdk/log/Log.x` + mirror):**
  - `Filter` + `PredicateFilter` (function predicate over `LogRecord`) and
    `KeepAllFilter` default.
  - `Redactor` + `ReplaceRedactor` (substring replacement) and
    `IdentityRedactor` default; applied to the message and every field value.
  - `Sampler` + `EveryNSampler` (every Nth accepted record, deterministic
    counter) and `KeepAllSampler` default.
  - `Logger.withFilter/withRedactor/withSampler` return new loggers and preserve
    `name`/`min`/`sink`/`fields`/`clock`. Pipeline order is
    level → filter → sampler → redactor → sink.
- **Retained:** `Level` threshold, `Field`, `LogRecord` timestamps,
  `ConsoleSink`, `MemorySink`, `Clock`/`SystemClock`, `recordText` and
  `recordTextWithTime`; existing `xdk_log.x`/`r4/log_timestamp.x` outputs are
  unchanged.
- **Lost:** no file sink, no async/batched sink, no rate limiter over wall time,
  and redaction is literal replacement rather than regex/structure-aware.
  Sampler state is per-instance (documented, not thread-safe).
- **Test/command/output:** `src/mini/tests/r4/log_pipeline.x` via
  `r4_evidence.sh` outputs:

```text
2
[INFO] svc: keep-one
[WARN] svc: keep-two
[INFO] svc: token [redacted]
[WARN] svc: second password=[redacted]
2
[INFO] svc: s2
[INFO] svc: s4
4
1
[WARN] svc: *** two
2
```

  It covers filter rejection, message and field redaction, every-second
  sampling with a deterministic counter, and the composed order (filtered info
  records do not advance the sampler).
- **Impact:** log additively. **Dependents:** log users, config/cli diagnostics.
  **Breakage:** none; defaults preserve the old pipeline exactly.
  **Migration:** add `withFilter`/`withRedactor`/`withSampler` at the logger
  construction site; no sink or call-site change is required.
- **Status:** proposed, not closed.

### B9. cli / 补全 (ledger #49) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:** `completionBash(Command root)` in `src/xdk/cli/Cli.x` emits one
  `complete -W` line for the root command and one for each direct subcommand.
  Words are the long option, its short name, child command names, and `help`.
- **Retained:** `OptionSpec`/`Command`/`help` and all existing parse behavior.
- **Lost:** no zsh/fish native completion and no dynamic value completion; the
  output is a deterministic word list only.
- **Test/command/output:**
```text
$ ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/cli_completion.x
...
complete -W "--verbose -v --all -a run help" demo
complete -W "--output -o help" "demo run"
```
- **Impact:** cli additively. **Dependents:** cli users. **Breakage:** none.
  **Migration:** call `completionBash` when generating a shell hook.
- **Status:** proposed, not closed.

### B10. cli / 短选项合并/重复策略 (ledger #50) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:**
  - `OptionSpec.withShort` attaches a short name without changing the original.
  - `Args.expandShortFlags(known)` expands `-abc` only when every short option
    is known; `Command.parse` performs the same expansion for all-flag clusters
    and rejects clusters that contain a value-taking option.
  - `Args.lastValue`/`Args.values` make the duplicate policy explicit;
    `Args.value` remains first-wins.
  - `--` is a documented terminator: `has`/`value`/`values` stop there and
    `positionals()` returns everything after it verbatim.
- **Retained:** long-option parsing (`--k v`, `--k=v`), unknown-option
  rejection, required/value checks, subcommands, help.
- **Lost:** bundling a value-taking short option (`-ovalue`) is rejected rather
  than guessed; only all-flag clusters are merged.
- **Test/command/output:** the `cli_completion.x` scenario observes `false/3/
  -c/--name/late/true/true/one/three/3/true/true/true` before the completion
  lines: terminator positionals, bundle expansion, and first/last/all duplicates.
- **Impact:** cli. **Dependents:** cli users. **Breakage:** none for existing
  long-option code; clusters were previously rejected as unknown.
  **Migration:** attach short names with `withShort`; use `lastValue`/`values`
  when a specific duplicate policy is needed.
- **Status:** proposed, not closed.

### B11. cli / 环境/配置文件默认值 (ledger #51) — PROMOTED TO PROPOSED

- **Verdict:** `Optimized candidate` → `Optimized proposed` (unsigned).
- **Shim:** `resolveValue(args, flag, envName, configValue, fallback)` in
  `src/xdk/cli/Cli.x` implements the documented order
  argv > environment > non-empty config value > fallback;
  `defaultFromEnv(envName, fallback)` is the two-level form. It reads the
  environment through the existing raw env primitives without importing
  `xdk.config`, so no dependency cycle is introduced.
- **Retained:** `Args` parsing and `valueOr`.
- **Lost:** no automatic prefix derivation and no direct `Config` parameter;
  the caller passes the config value explicitly.
- **Test/command/output:**
```text
$ XDK_R4_CLI=from-env ./src/cli/xnull --bootstrap --engine=mini run src/mini/tests/r4/cli_defaults.x
argv
from-env
config
fallback
from-env
fb
```
  The scenario exercises all four precedence levels and both `defaultFromEnv`
  branches.
- **Impact:** cli additively. **Dependents:** cli users.
  **Breakage:** none. **Migration:** replace ad-hoc precedence code with
  `resolveValue`.
- **Status:** proposed, not closed.

## 4. C. The 3 Deferred candidates

These remain `Deferred candidate`. The meeting date and the decision are the
user's; this batch supplies the strict plan, options, and impact. No row is
promoted or closed here.

### C1. math / random (ledger #52)

- **Verdict:** stays `Deferred candidate` (no XDK surface, not closed).
- **Current evidence:** no `xdk.math` random symbol; `07-math.md:27` and `:124`
  say random is T1 `xdk.random`. A deterministic raw bridge already exists but
  is unused by XDK: `src/ffi/ext_raw.xfb:113-126` (`randSeedRaw`,
  `randNextRaw`, `randDoubleRaw`) and `src/runtime/rt_std_ext.c:52-81`
  (xorshift64*).
- **Retained:** the raw bridge (seed, non-negative 63-bit `next`, `[0,1)`
  double) and the existing math package; neither is part of the T0 public API.
- **Lost:** no XDK `nextLong`/bounded `nextInt`/`nextBool`/`shuffle`, no
  seed-reset contract, and no scenario; the bridge alone is not evidence for
  the ledger item.
- **Strict plan:** define `xdk.random` as a T1 package with explicit seed,
  `nextLong`, bounded `nextInt(min,max)`, `nextDouble`, `nextBool`, and
  `shuffle<T>`; document that it is deterministic and not cryptographic; add
  range/determinism/seed-reset tests.
- **Options:** A) T1 package over the existing xorshift64* bridge
  (recommended); B) OS RNG adapter (`getrandom`/`arc4random`) with no
  reproducibility promise; C) no random in the 1.x core.
- **Impact:** new package, additive. **Dependents:** math users, tests.
  **Breakage:** none. **Migration:** none (no existing symbol).
- **Test evidence:** none for the XDK item; deferred. Do not cite the raw
  bridge as a passing scenario.
- **Meeting/signature:** date TBD; signer: user.

### C2. time / TimeZone (ledger #53)

- **Verdict:** stays `Deferred candidate` (UTC-only, not closed).
- **Current evidence:** UTC-only; `DateTime.toUTC()`/`toLocal()` return `self`
  (`src/xdk/core/time/DateTime.x`); `08-time.md:24` excludes IANA tzdata and
  `:104` puts `TimeZone`/`toZone` in T0-X. There is no `TimeZone` source.
- **Retained:** UTC epoch milliseconds, civil arithmetic, `addDays`/`addMonths`/
  `addYears`, layout formatting/parsing, and `Stopwatch`.
- **Lost:** no fixed-offset or IANA zone type, no `toZone`, and no DST
  transition handling; `toUTC`/`toLocal` are identity operations.
- **Strict plan:** A) fixed-offset subset: `FixedOffset(seconds)` and
  `DateTime.toZone(FixedOffset)`/`offsetSeconds()`, epoch value unchanged,
  formatting applies the offset; tests for +08:00/-05:00 and round trips; no
  DST/IANA. B) IANA: TZif parser, tzdata discovery/update policy, caching,
  DST transitions. C) none.
- **Options:** A) fixed offset for 1.0 (recommended); B) IANA; C) no timezone.
- **Impact:** time API. **Dependents:** time/log/config users. **Breakage:**
  none if additive; UTC remains default. **Migration:** explicit offset for
  display; keep epoch math in UTC.
- **Test evidence:** none for the deferred item; existing `xdk_time.x` and R4
  time scenarios cover UTC only.
- **Meeting/signature:** date TBD; signer: user.

### C3. config / codec (ledger #54)

- **Verdict:** stays `Deferred candidate` (no codec, not closed).
- **Current evidence:** `Config.x` only has `FileSource` `key=value` parsing;
  `15-config.md:25-26` excludes JSON/TOML/YAML and `:77` puts codec injection
  in T1. There is no codec symbol.
- **Retained:** `ConfigSource`/`MapSource`/`FileSource`, ordered snapshots,
  overlay, `setChecked`, and the new typed getters.
- **Lost:** no structured codec (JSON/TOML/YAML), no duplicate-key policy, and
  no nested/array value mapping; callers must supply `key=value` sources.
- **Strict plan:** A) JSON codec: `protocol Codec { decode(String) ->
  Result<List<ConfigEntry>, Error> }` plus `JsonCodec`; object-only, scalar
  values converted to strings, arrays/nesting rejected or flattened by rule;
  tests for valid/invalid JSON and duplicate keys. B) external adapter: user
  supplies a `ConfigSource`; no core codec. C) none.
- **Options:** A) JSON codec (recommended); B) external adapter; C) none.
- **Impact:** config API. **Dependents:** config/cli/app users. **Breakage:**
  none (additive); `FileSource` stays. **Migration:** implement `ConfigSource`
  for other formats until a codec is chosen.
- **Test evidence:** none for the deferred item; `xdk_config.x` and
  `r4/config_typed.x` cover only `key=value` sources.
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
  - string literals containing embedded NUL use
    `rt_string_new(..., sizeof(...) - 1)`; other literals keep
    `rt_string_from_c`, so self-host output stays small while NUL is preserved;
  - raw strings `r"..."` / `r"""..."""` are lexed and converted to C literals;
  - the S1 escape table is validated (unknown escapes / invalid scalars are
    lexical errors);
  - non-ASCII `Char` literals emit `((int32_t)U'...')`, so wide scalars build;
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

This batch (B2 stdio adapter + B8 log pipeline):

- New scenarios: `src/mini/tests/r4/stdio.x`,
  `src/mini/tests/r4/log_pipeline.x`.
- `src/mini/tests/r4_evidence.sh`: exact stdout/stderr diffs for the piped
  stdio case and the log pipeline case.
- `src/xdk/io/IO.x` + mirror: `StdioReader`, `StdioWriter`,
  `stdinReader`/`stdoutWriter`/`stderrWriter`, plus streaming-source
  `BufferedReader.hasRemaining`.
- `src/xdk/log/Log.x` + mirror: `Filter`/`PredicateFilter`/`KeepAllFilter`,
  `Redactor`/`ReplaceRedactor`/`IdentityRedactor`,
  `Sampler`/`EveryNSampler`/`KeepAllSampler`, and the three `Logger.with*`
  hooks.
- `src/ffi/io_raw.xfb` + mirror: `stdioReadHexRaw`, `stdioWriteHexRaw`,
  `stdioFlushRaw`.
- `src/runtime/rt_std_ext.c` + mirror: `xdkc_stdio_read_hex`,
  `xdkc_stdio_write_hex`, `xdkc_stdio_flush`.
- `src/ffi/capabilities.tsv`, `src/ffi/api-manifest.tsv` + mirrors: new
  L1/L2 symbols and the two scenarios.
- `docs/design/t0/09-io.md`, `docs/design/t0/02-runtime.md`,
  `docs/design/t0/14-log.md`: contracts and T1 boundaries.

Deliberately untouched:

- `docs/design/MINI-1.0.md` (ledger owner; user asked not to edit).
- `docs/design/t0/C1-U0-U5-EVIDENCE.md`: only the base commit, manifest count,
  and U3/U5 status wording were refreshed; U5 remains human-pending, not a
  human PASS.
- `docs/design/t0/AUDIT.md` signatures/`Verified` states: only the
  `xdk.errors`/`xdk.text` design-version and evidence cells were refreshed and
  the API-manifest row count was corrected; the reviewer stays `待签` and no
  package was marked signed.

This batch (text/errors strict candidates):

- New scenarios: `src/mini/tests/r4/text_builder.x`; extended
  `src/mini/tests/r4/errors_detail.x` and `src/mini/tests/xdk_core.x` /
  `xdk_core.out`.
- `src/xdk/text/full/StringBuilder.x`, `src/xdk/text/base/StringBuilder.x`
  + mirrors: T0 append-only `StringBuilder`.
- `src/xdk/core/errors/Errors.x` + mirror: `tryWithCode`, `tryWithDetail`,
  `tryWithCause`, `ErrorGroup.addDetailed`, and the `basicErrorOf` conversion.
- `docs/design/t0/appendices/error-codes.tsv`,
  `src/toolchain/check_error_codes.py`, `src/mini/tests/error_codes.sh`:
  W6 registry plus positive/negative gate.
- `src/mini/tests/r4_evidence.sh`: builder case and the registry test.
- `docs/design/t0/01-errors.md`, `docs/design/t0/05-text.md`,
  `docs/design/t0/AUDIT.md`, `src/xdk/PLAN.md`: contract, version, and
  evidence-cell updates (no signature).
- `src/ffi/capabilities.tsv`, `src/ffi/api-manifest.tsv`: `StringBuilder`
  symbol and the new scenarios.

This batch (config/log/cli/meta/bytes optimized candidates + deferred packets):

- New scenarios: `src/mini/tests/r4/config_typed.x`,
  `src/mini/tests/r4/log_timestamp.x`,
  `src/mini/tests/r4/meta_buildinfo.x`,
  `src/mini/tests/r4/bytes_nul.x`,
  `src/mini/tests/r4/cli_completion.x`,
  `src/mini/tests/r4/cli_defaults.x`.
- `src/mini/tests/r4_evidence.sh`: exact-output cases for the six scenarios
  (and an env-passing form of `run_case` for the cli precedence test).
- `src/xdk/config/Config.x` + mirror: `getInt`/`getLong`/`getBool`/`getDouble`
  and the 64-bit decimal parser.
- `src/xdk/log/Log.x` + mirror: `Clock`/`SystemClock`, clock injection,
  `LogRecord.timestampMs/monotonicMs`, `MemorySink.captured`, and
  `recordTextWithTime`; `recordText` is unchanged.
- `src/xdk/core/meta/Meta.x` + mirror: `BuildInfo`, `buildInfo`, `targetArch`,
  `buildMode`, `compilerName`, `compilerVersion`, `buildDate`.
- `src/xdk/core/bytes/Bytes.x` + mirror: NUL-boundary helpers.
- `src/xdk/cli/Cli.x` + mirror: `OptionSpec.withShort`, duplicate/terminator
  Args surface, short-cluster expansion, `completionBash`, and
  `resolveValue`/`defaultFromEnv`.
- `src/ffi/runtime_raw.xfb` + mirror: `buildDateRaw`.
- `src/runtime/rt_std_runtime.c` + mirror: `xdkc_build_date`.
- `src/runtime/test_std.c`: non-empty build-date assertion.
- `src/ffi/capabilities.tsv`, `src/ffi/api-manifest.tsv`: new L1 symbols and
  scenarios.
- `docs/design/t0/03-meta.md`, `04-bytes.md`, `14-log.md`, `15-config.md`,
  `16-cli.md`: contracts, test obligations, and T1 boundaries updated.

Deliberately not touched in this batch:

- `docs/design/MINI-1.0.md` (ledger owner; user asked not to edit).
- `docs/design/t0/C1-U0-U5-EVIDENCE.md` and `AUDIT.md` signatures.
- `src/xdk/cli/Cli.x` still does not import `xdk.config`; `resolveValue` takes
  the config value as an argument to keep the layer direction clean.

## 7. Remaining RED / unsigned

| Area | Remaining | Why |
| --- | ---: | --- |
| Strict candidates | 0 | A9/A10 now have real source + scenario + output |
| Optimized candidates | 0 | B2/B8 promoted; no optimized candidate remains |
| Optimized proposed | 10 | B2-B11: shim + scenario exist; still unsigned |
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

Resolved by the runtime/time batch:

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

Resolved by the text/errors batch:

1. `errors / 错误码命名空间工具` (A2): W6 registry + checker + negative tests.
2. `text / StringBuilder` (A5): XDK append-only builder + scenario.
3. `errors / DetailedError 聚合` (A12): direct `addDetailed` path + scenario.
4. `errors / tryWith*` (B1): the codegen blocker was disproved; direct
   `BasicError.tryWith*` methods + scenario (moves from Optimized to Strict
   evidenced).

Resolved by the config/log/cli/meta/bytes batch:

1. `log / 时间戳/单调时钟字段` (A9): injected `Clock`, per-record fields, and a
   deterministic scenario (Strict evidenced).
2. `config / 类型化 getter` (A10): Int/Long/Bool/Double Result getters and a
   valid/invalid/missing scenario (Strict evidenced).
3. `meta / BuildInfo` and `构建元数据` (B3/B5): aggregate plus standalone
   metadata functions and a scenario (Optimized proposed).
4. `bytes / NUL 边界工具` (B6): five copy-returning helpers and a scenario
   (Optimized proposed).
5. `cli / 补全`, `短选项合并/重复策略`, `环境/配置文件默认值` (B9-B11):
   completion text, short clusters/duplicates/terminator, and the precedence
   chain (Optimized proposed).

Resolved by the B2/B8 batch:

1. `runtime-io / stdio adapter` (B2): real fd 0/1/2 reader/writer with a
   piped stdin/stdout/stderr scenario (Optimized proposed).
2. `log / 过滤/脱敏/采样` (B8): `Filter`, `Redactor`, and `Sampler` hooks wired
   into `Logger` with a deterministic pipeline scenario (Optimized proposed).

Still open:

- C1-C3 remain `Deferred candidate`; D1-D9 remain out-of-scope.
- No row is `Signed ... closed`; only a user or independent reviewer signature
  can make that true.

The required gates (`r4_evidence.sh`, `ref.sh`, `xdk.sh`, `xdk_core.sh`,
`check_layers`) and the full C suite (`src/runtime/build_rt.sh`) are green as
shown in §0. The worktree is clean after the single batch commit.
