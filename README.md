<p align="center">
  <img src="assets/logo.png" alt="XNull" width="640">
</p>

# XNull

**Write the code. Skip the ceremony.**

**English** | [简体中文](README/README.zh-CN.md) | [繁體中文](README/README.zh-TW.md) | [Русский](README/README.ru.md) | [العربية](README/README.ar.md) | [Italiano](README/README.it.md) | [Deutsch](README/README.de.md)

*English is the reference version; translations are updated as time allows.*

![status: research](https://img.shields.io/badge/status-research-orange)
![compiler: mini 1.0.0](https://img.shields.io/badge/compiler-mini%201.0.0-blue)
![license: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-green)

XNull is a statically typed, general-purpose programming language with a **self-hosting compiler that emits C**. The compiler chooses stack, ARC, or GC for each object from a decision table in the specification; source code never states lifetimes or reference strength.

- **Self-hosting compiler.** `src/mini` is written in XNull and compiles itself to a fixed point (`src/mini/tests/selfhost.sh`).
- **C backend, native binaries.** One entry file becomes C, then a native executable. No VM.
- **Errors are values.** `Result<T, E>`, `try`, `defer`/`errdefer`. No exceptions and no implicit unwinding.
- **Protocols, not inheritance.** No `extends`, no `@Override`; fields are fields.
- **Compile-time annotations, no runtime reflection.** Generated code and static metadata instead of runtime scanning.
- **Spec-first.** An 11-part specification records what XNull supports, what it rejects, and why.

> **Status: research / implementation phase.** The compiler is usable for the examples and the XDK T0 test suite; the language and standard library are not production-ready. There is one maintainer. See [Status](#status) for the current boundary.

## Try it

```sh
git clone https://github.com/xnull-clang/xnull.git
cd xnull

./src/cli/xnull run src/examples/hello.x
```

```text
hello, XNull
1 + 2 = 3
```

Build a native binary:

```sh
./src/cli/xnull build src/examples/hello.x -o /tmp/hello
/tmp/hello
```

Check without building:

```sh
./src/cli/xnull check src/examples/hello.x --json
# {"ok":true}
```

Requirements: a C11 compiler (`cc`) and a POSIX shell. Python 3 is used by a few test scripts.

## The language in one example

```x
static Result<Int, String> double(Int n) {
    if n < 0 {
        return Err("negative: " + str(n))
    }
    return Ok(n * 2)
}

static Int main() {
    Int v = try double(21)
    print(v)                  // 42
    return 0
}
```

`try` propagates `Err` to the caller as a value. There is no exception unwinding. More runnable examples: [`src/examples/`](src/examples) — classes, containers, `Result`/`try`, `defer`, and a multi-file program.

## What works today

| Area | Status |
| --- | --- |
| Compiler | `mini 1.0.0`; self-hosting fixed point; emits C |
| CLI | `build`, `run`, `check`, `version`, `clean`, `doctor` |
| Core language | classes, structs, enums, protocols, generics, `Result`/`try`, `defer`, tasks/channels (`Mutex`, close/cancel) |
| XDK | T0 packages: errors, text, math, time, collections, io/fs/sys, tasks/sync, log, config, cli; more in progress |
| Multi-file projects | `xnull.project` with `entryFile`; `build`/`run`/`check` |
| Tooling | Web IDE (`python3 ide/web/server.py`), VS Code extension prototype |
| Tests | `selfhost`, `xdk`, `m10_parity`, `resources`, `m8`, `m10_perf` |

Not yet: package manager, formatter, project reactor, full standard library, production hardening.

**One compiler, no fallback.** `src/mini` is the only compiler. There is no second engine and no delegation: if mini cannot run a command, the command is absent rather than silently handled elsewhere.

## Why XNull

**Memory is a decision table, not an annotation.** Source never states reference strength. The compiler applies DET-01 — stack, ARC, or GC — and the runtime executes the choice. The policy is closed and written down, so it can be checked rather than guessed. See [S4](docs/solution-04-memory-management.md) and [`DET-01`](docs/design/DET-01.md).

**Errors are values.** `Result<T, E>` puts failure in the type system; `try` propagates it; `defer`/`errdefer` make cleanup explicit. There are no exceptions and no hidden unwinding. See [S5](docs/solution-05-error-handling.md).

**Composition over inheritance, and no reflection.** Polymorphism is expressed with protocols, not fragile base classes. Fields are data, not getters and setters. Compile-time annotations generate code and metadata, so serialization and data mapping do not need runtime scanning. See [S2](docs/solution-02-object-programming.md) and [S3](docs/solution-03-annotation.md).

**Bounded abstraction.** XNull does not aim for the largest abstraction space. It aims for designs that are decidable from source plus specification. The full capability map and the trade-offs are in [S0](docs/solution-00-language-capabilities.md); the comparison with other languages is in [`docs/design/LANGUAGE-COMPARISON.md`](docs/design/LANGUAGE-COMPARISON.md).

### Explicitly unsupported, by design

| Feature | Reason |
| --- | --- |
| Method overriding | The method that runs must be answerable from static types; dynamic dispatch exists only through protocols |
| Accessors / properties | Fields are data; behavior is verb-named methods |
| Reflection | Breaks the rule that source + specification determine the program |
| Exceptions | Errors are values; `throw` is fatal-only and never unwinds |

## Performance

The 200M-iteration LCG loop is a regression gate, not a benchmark claim. The latest run on the project's reference machine was **0.675 s** for 200M iterations (2026-11-24), against the 0.733 s mini 0.2.0 baseline. Reproduce it with:

```sh
src/mini/tests/m10_perf.sh
```

The workload and the gate are in [`src/mini/tests/m10_perf.sh`](src/mini/tests/m10_perf.sh); the milestone record is in [`src/mini/MILESTONES.md`](src/mini/MILESTONES.md).

## Repository map

```text
src/
  cli/xnull          unified CLI
  mini/              the compiler (written in XNull, self-hosting)
  runtime/           C runtime
  xdk/               XDK sources
  ffi/               raw FFI bridge contracts (.xfb)
  toolchain/         mini build/run/check scripts
  examples/          runnable programs
docs/
  solution-00..10    the 11-part specification
  design/            architecture, annotations, DET-01, package map, plans
ide/
  web/               single-page web IDE (Python standard library only)
  vscode/            VS Code extension prototype
xdk/                 XDK delivery package (install.sh)
```

`src/` is the development tree; `xdk/` is the delivery copy. After changing `src/xdk/`, sync it to `xdk/lib/xdk/`.

## Documentation

| Part | Topic |
| --- | --- |
| [S0](docs/solution-00-language-capabilities.md) | Capabilities and application boundaries |
| [S1](docs/solution-01-basic-syntax.md) | Basic syntax |
| [S2](docs/solution-02-object-programming.md) | Objects and protocols |
| [S3](docs/solution-03-annotation.md) | Annotations |
| [S4](docs/solution-04-memory-management.md) | Memory management |
| [S5](docs/solution-05-error-handling.md) | Error handling |
| [S6](docs/solution-06-tasks-and-concurrency.md) | Tasks and concurrency |
| [S7](docs/solution-07-xdk.md) | XDK |
| [S8](docs/solution-08-toolchain.md) | Toolchain |
| [S9](docs/solution-09-ide.md) | IDE |
| [S10](docs/solution-10-project-configuration.md) | Project configuration |

Design documents: [`docs/design/README.md`](docs/design/README.md). Architecture baseline: [`docs/design/ARCHITECTURE.md`](docs/design/ARCHITECTURE.md).

## Status

| Area | Status |
| --- | --- |
| Compiler | Self-hosting, C backend, single-file and minimal project surface |
| Language | Core constructs implemented; coverage grows scenario by scenario |
| XDK | T0 packages pass; T1/T2 packages in progress |
| Annotations | Registry, codegen, and extension work in progress |
| IDE | Web IDE works; VS Code extension prototype |
| Release | Research/implementation phase; no stability promise yet |

**Roadmap, in order:** broader language coverage → XDK completion → project build and formatter → self-hosting release → production hardening. The queue is in [`src/mini/PLAN.md`](src/mini/PLAN.md); milestone evidence is in [`src/mini/MILESTONES.md`](src/mini/MILESTONES.md).

Development is spec-first: features land with executable scenarios and regression gates, not feature checklists.

XNull is deliberately not trying to be everything. It is not a systems language for manual memory control, not a framework language that depends on reflection, and not a macro/DSL language. If a feature cannot be decided from source plus specification, it is not part of the language.

## Contributing

XNull started as a one-person design project. Useful contributions right now:

- compiler and runtime bugs with a minimal reproducer;
- XDK packages with executable scenarios;
- specification counterexamples — a good argument becomes a spec revision;
- translations and documentation fixes.

Open an [issue](https://github.com/xnull-clang/xnull/issues) or send a pull request. For large changes, open an issue first so the design can be discussed before the code.

## License

Code (`src/`, `xdk/`, `src/examples/`) is licensed under Apache-2.0; see [LICENSE](LICENSE). Specifications and documentation (`docs/`, `README*.md`) are licensed under CC BY 4.0; see [LICENSE-docs.md](LICENSE-docs.md). The XNull name and logo are not covered by either license.

## Support

XNull is a one-person project. If you want to support it financially, see [Funding and sponsorship](docs/FUNDING.md). Sponsorship is voluntary and is not an investment.
