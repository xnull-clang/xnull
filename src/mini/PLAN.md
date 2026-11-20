# mini compiler plan

**Status:** mini is the canonical compiler. Legacy engine and bootstrap tools
are removed. The only supported command is the mini single-file surface.

## 1. Product rule

```text
mini scenario
  → mini codegen
  → runtime/XDK support only where the scenario requires it
  → regression evidence
  → commit
```

mini is the only compiler and the only evidence source. If mini cannot do
something, it is recorded as a mini gap or removed from the public CLI until
mini can do it.

## 2. Current surface

- `xnull build <entry.x>`
- `xnull run <entry.x> [-- args]`
- `xnull check <entry.x> [--json]`
- `xnull version`
- `xnull clean`
- `xnull doctor`
- `--resources <dir>` for embedded resources
- `.xfb` FFI projection through `src/ffi`

Project/package commands (`validate`, `tree`, `why`, `install`, `lock`,
`repro`, `xmeta`, `fmt`, project `build/run`) are intentionally absent until
mini can implement them. They are not delegated to another engine.

## 3. Compiler queue

1. **Int 32-bit semantics**: keep arithmetic/bitwise/return/local normalization
   and shift bounds; audit XDK code that used 64-bit Int assumptions.
2. **String/collection member surface**: `List.clear`, `Map` checked members,
   generic Result containers as required by T0 scenarios.
3. **Resource/FFI**: keep single-file `--resources` and `.xfb` projection green.
4. **Project build**: only after a mini project scenario exists.
5. **Formatter**: build it as mini source when it compiles with mini.

## 4. Verification gates

```sh
src/mini/tests/selfhost.sh
src/mini/tests/xdk.sh
src/mini/tests/m10_parity.sh
src/mini/tests/resources.sh
src/mini/tests/m8.sh
src/mini/tests/m10_perf.sh
```

All gates are mini-only. A red gate blocks the next change; there is no
second-engine override.

## 5. Architecture

- `src/mini/main.x`: compiler source (self-hosted).
- `src/mini/bin/mini`: current seed/self-hosted binary.
- `src/runtime`: C runtime.
- `src/xdk`: XDK source.
- `src/toolchain/xnull-build.sh`: mini-only build/run/check.
- `src/cli/xnull`: mini-only CLI entry.

The former second compiler, bootstrap tools, project reactor, formatter, and
split manifests are deleted. Historical versions remain in git history.
