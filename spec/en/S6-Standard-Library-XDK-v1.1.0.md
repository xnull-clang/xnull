# XNull Specification, Part 6: Standard Library (XDK)

> **Translation notice**: This is an English translation of the normative Chinese specification
> 《XNull 解决方案 第 6 部分：标准库（XDK）》v1.1.0. The Chinese original prevails in case of any
> divergence. Translation version follows the original's version number.

| Item | Content |
| --- | --- |
| Document ID | Part 6 (S6) |
| Document Version | 1.1.0 |
| Specification Status | Normative (approved 2026-11-05) |
| Release Date | 2026-11-05 |
| Upstream Basis | S1 (§9 built-in types), S2 (§16, §17), S3 (§17, §18), S4 (error semantics), S5 (concurrency semantics), S8 (§5.6 resource packaging) |

> **Finalization note**: This part is based on a discussion draft (v0.1.0, 2026-11-05, archived) and, after review, was finalized as the v1.0.0 normative specification per the decision record in §6. The library-wide contract principles (§3) apply to all XDK packages from that point; the `xdk.*` names appearing in Parts 4/5/7 are the official names defined here. Future revisions follow the version process.
>
> **Version note**: 1.1.0 adds §4.8, the `xdk.sys` resource-reading contract (first-class APIs for reading embedded resources), implementing Part 8 §5.6's packaging rules; v1.0.0 content is unchanged — a backward-compatible minor-version addition.

## 1. What the XDK Is

- The XDK (XNull Development Kit) is XNull's standard library: every **public API directly callable from source code** beyond the language's built-in capabilities (types, syntax, runtime semantics).
- A three-layer division:
  1. **Language layer** (S1/S2): syntax, type system, built-in types and literals — no APIs;
  2. **Runtime-semantics layer** (S3/S4/S5): the semantics and invariants of memory, errors, and concurrency — constrains behavior, not API names;
  3. **XDK layer** (this part): turns the semantic contracts into concrete packages, types, and functions.
- Design principles inherited from the language: explicit, predictable, no implicit magic; every fallible operation returns `Result`; resources are closed explicitly at the point of use; no global mutable state; no reflection.

### 1.4 Architecture Overview (Developer's Right to Know)

**Right-to-know principle**: the XDK is the entire interface surface between developers and the runtime. Developers are entitled to understand, in one place, the XDK's capability boundaries, inter-package relationships, dependency paths to runtime services, and which behaviors cross the FFI boundary. This section is the authoritative view; once package structure is finalized, the architecture diagram ships with each specification version, and packages MUST NOT hide their dependencies on runtime services.

#### 1.4.1 Layered Architecture

```text
┌────────────────────────────────────────────────────────────────┐
│                      XNull application code                     │
└───────────────────────────┬────────────────────────────────────┘
                            │ Sole entry: XDK public API (contract principles, §3)
┌───────────────────────────▼────────────────────────────────────┐
│ XDK package layer                                               │
│                                                                 │
│  errors       tasks        sync        runtime    collections  text  │
│  error proto  tasks/groups  mutex/ch    diag/exit  containers  text  │
│  kinds/observ Context      atomics      time/env   specialized fmt    │
│                                                                 │
│  sys (files/dirs/subprocesses)   net (network, decision 3-g)   ui (long-term) │
└──────┬──────────────┬───────────────┬──────────────┬───────────┘
       │              │               │              │
   Result error flow  spawn/cancel    diag/exit      handles/leases
   (S4 contracts)     (S5 mechanism)  (S4 §4.3)      (S3 §18/§19)
┌──────▼──────────────▼───────────────▼──────────────▼───────────┐
│ Runtime service layer (semantics: Parts 3/4/5; implementation:  │
│ compiler & runtime)                                             │
│                                                                 │
│  task scheduler │ ARC/GC (decision table DET-01) │ weak table   │
│  (internal) │ safepoints                                        │
│  diagnostic channel (allocation-free) │ FFI contract layer       │
│  (lease verification) │ finalization chain                      │
└───────────────────────────┬────────────────────────────────────┘
┌───────────────────────────▼────────────────────────────────────┐
│      Operating system / native world (C ABI, Part 7 FFI spec)   │
└────────────────────────────────────────────────────────────────┘
```

Key points:

- Application code uses runtime capabilities **only** through the XDK package layer; there is no public channel bypassing it (diagnostics output and exit both live in the `runtime` package).
- The four vertical lines between the package layer and the runtime service layer are the complete set of dependency paths: error flow, concurrency control flow, process control flow, resource flow — every contract has a numbered source and is auditable.
- The runtime service layer is not exposed directly to application code; its behavioral contracts are defined by Parts 3/4/5, and the XDK only "translates them into APIs."

#### 1.4.2 Communication Structure

```text
Inter-task data flow    TaskA ──Channel<T> (bounded, cancellable suspension)──▶ TaskB
Inter-task sharing      TaskA ──Mutex<T>.withLock / Atomic*──▶ shared state
Cancellation flow       TaskGroup.cancel / ctx.withDeadline
                            ──▶ child task Context ──▶ checkCancel() ──▶ Err(Cancelled)
Result delivery flow    task-closure Result<T,E> ──join()──▶ caller (as-is, no degradation)
Error propagation flow  XDK API ──Result──▶ caller ──try/explicit conversion──▶ main exit code / FFI error code
Diagnostic flow         XDK / runtime ──diagnose (single line, allocation-free)──▶ process diagnostic output
FFI bidirectional flow  XNull ──lease + error code (Result does not cross)──▶ native
                        native ──weak-table entries (runtime ABI, Part 3 §22)──▶ runtime
```

#### 1.4.3 Capability and Dependency Matrix

| Package | Outward Capability | Runtime Services Depended On | Specification Basis |
| --- | --- | --- | --- |
| `errors` | Error protocol, classifications, observation | Diagnostic channel | Part 4 (S4) |
| `tasks` | Tasks, task groups, contexts | Scheduler, safepoints, GC external roots | Part 5 (S5), S3 §11 |
| `sync` | Mutexes, channels, atomics | Scheduler (suspension), atomic counts | Part 5 (S5), S3 §11.3 |
| `runtime` | Diagnostics, exit, clock, environment | Diagnostic channel, process control | Part 4 §4.3 + this part §4.4 |
| `collections` | Algorithms and specialized containers | Memory allocation (ARC/GC) | S1 §9 + this part §4.5 |
| `text` | Encoding, formatting, parsing | Memory allocation | S1 §9.2/§9.7 + this part §4.6 |
| `sys` | Files, directories, subprocesses | Handle contract (§18/§19), FFI contract layer | S3 §18 + this part §4.7 |
| `net` | Sockets, protocols | Handle contract, scheduler (async I/O) | This part §4.7 |
| `ui` (long-term) | Windows, widgets, lifecycles | Scheduler (main-thread executor), handle contract | Specification index §9 |

Matrix constraint: new packages MUST register their dependency paths in this table; a package MUST NOT call a runtime service it does not list (verified at the implementation layer by the FFI contract layer).

## 2. Package Structure (Settled)

| Package | Responsibility | Content Source | Status |
| --- | --- | --- | --- |
| `xdk.errors` | Error protocol, classifications, helpers | S4 §2–3 | Settled |
| `xdk.tasks` | Tasks, task groups, contexts | S5 §3 | Settled |
| `xdk.sync` | Mutexes, channels, atomics | S5 §7 | Settled |
| `xdk.runtime` | Diagnostic output, process exit, time, environment | S4 §4.3 (diagnostics); rest in this part §4.4 | Settled |
| `xdk.collections` | Container algorithms and specialized containers | S1 §9 built-in containers + this part §4.5 | Settled (A+B combination) |
| `xdk.text` | Text encoding, formatting, parsing | S1 §9.2/§9.7 + this part §4.6 | Settled |
| `xdk.sys` | Files, directories, processes, platform info, embedded-resource reading (§4.8) | S3 §18 handle contract + S8 §5.6 | Settled |
| `xdk.net` | Sockets, protocol stacks | This part §4.7 | Settled (independent package) |
| `xdk.ui` | Windows, widgets, lifecycle contract | Specification index §9 GUI disposition | Long-term, not defined this round |

**Decision 1-a (package count and granularity)**: keep 8 packages (excluding `ui`); `sync` is not merged into `tasks` (a concurrent family with distinct responsibilities: task lifecycle vs. shared-state protection); `sys` is not split into `io` / `process` (same package in the first version; split later if specialization requires).
**Decision 1-b (`runtime` vs. `sys` boundary)**: time, environment variables, process exit, and diagnostics belong to `runtime` (the "runtime-visible surface," never touching OS resource handles); files, directories, subprocesses, and sockets belong to `sys` / `net` (the "operating-system surface," all through the handle contract).

## 3. Library-Wide Contract Principles

The following seven rules are mandatory for all XDK APIs (normative):

1. **Error contract**: every fallible operation returns `Result<T, E>`; `E` follows the error-type rules (S4 §2); expressing recoverable failure via panic is forbidden.
2. **Resource contract**: types holding OS resources MUST provide `close()`; release failure does not mean not-released (S4 §4.4); handles MUST NOT rely on `deinit` as the only release path (S3 §18).
3. **Cancellation contract**: blockable operations take a `Context` parameter (the S5 §3.3 convention); suspension points are cancellable and report `Cancelled`.
4. **Naming contract**: packages are all-lowercase words; types are PascalCase; methods are lowerCamelCase verb-first; boolean reads are `isX` / `hasX`; private internal names are `_name` (S2 §6.1).
5. **No-implicit contract**: no global mutable singletons (`singleton` only for genuinely unique, immutable globals); no implicit initialization/cleanup hooks; no implicit thread-local state.
6. **Stability line**: every API is annotated with stability (stable / preview / internal); preview may change in minor versions, internal is non-committal — corresponding to the "non-committal entry point" idea of S2 §15.1.2.
7. **Architecture right-to-know**: the XDK MUST publish the architecture overview with the specification (layer diagram, communication structure, capability and dependency matrix, see 1.4); every package MUST declare the runtime services it depends on and the behaviors crossing the FFI boundary; packages MUST NOT hide runtime-service dependencies, and unregistered dependency paths are contract violations. Developers are entitled to fully understand the XDK's capabilities and structure from documentation alone, without reading the implementation.

## 4. Per-Package Contracts

### 4.1 `xdk.errors` (source: S4)

- Types: the `Error` protocol (`kind()` + `describe()`), the `ErrorKind` enumeration (14 cases, semantics in S4 Appendix A).
- Functions: `wrap` (discard and replace), `mapErr` (transform), `report` (boundary observation output).
- **Decision 3-a-1**: `report` returns the original `Result` (supporting the `return report(r)` chained form), with the observation output as a side effect.
- **Decision 3-a-2**: cause chains use **conventional fields** — error structs carry their own `cause: Error?` field; the protocol gains no members (keeping the `Error` protocol minimal).

### 4.2 `xdk.tasks` (source: S5)

- Types: `Task<T>`, `TaskGroup`, `Context`.
- Contracts: structured concurrency (the group is the only spawn entry), group closure as the only termination path, cancellation/timeout error surfaces (S4 §5–6).
- **Decision 3-b-1**: `Context` passing follows the "first-parameter convention" (a specification convention, not compiler-enforced); compiler enforcement was **rejected for this version** — if needed, propose in a minor version with misuse evidence.

### 4.3 `xdk.sync` (source: S5)

- Types: `Mutex<T>` (scoped `withLock`), `Channel<T>` (bounded, cancellable suspension points), `AtomicInt` / `AtomicBool` / `AtomicRef<T>`.
- **Decision 3-c-1**: the `T` of `AtomicRef<T>` is restricted to reference types (object references); the first-version atomics are `AtomicInt` / `AtomicBool` / `AtomicRef<T>`; value-type atomics (`AtomicU64`, etc.) follow use cases (minor version).

### 4.4 `xdk.runtime`

| Capability | API (settled) | Basis |
| --- | --- | --- |
| Diagnostic output | `diagnose(String)` (single line, allocation-free channel, S4 §9) | S4 §4.3 |
| Process exit | `exit(Int)` (does not run `defer`, aligned with S1 §10.3) | S1 §10.3 |
| Time | `nowMono()` (monotonic clock), `nowWall()` (UTC millisecond timestamp, may step backward) | S5 §6 requires a clock |
| Environment variables | `env(String) -> String?` (immutable snapshot) | This part §1.4.3 |
| Task dump | `dumpTasks()` (implementation-side diagnostics, non-committed) | S5 §8 |

- **Decision 3-d-1**: time and environment variables belong to `runtime` (runtime-visible surface, never touching OS handles); local-timezone formatting is the `text` package's responsibility.
- **Decision 3-d-2**: the `nowWall` contract is UTC millisecond precision and may step backward; use `nowMono` where monotonicity is needed. Higher precision is not promised.

### 4.5 `xdk.collections`

- **Decision 3-e (relationship to built-in containers)**: adopt the **A + B combination** — built-in containers (`T[]`, `List<T>`, `Map<K,V>`, `Set<T>`, `StringBuilder`) stay as they are; `xdk.collections` provides algorithm functions (sort, group, dedupe, search) + specialized containers.
- First-version specialized-container list: `RingBuffer`, `OrderedMap`, `BTreeMap`, priority queue (`PriorityQueue`); the list freezes when the implementation layer initiates; additions are minor versions.
- Alternative C (sinking built-in containers into the package) was rejected and recorded in the index §6 decision record; it will not be revisited.

### 4.6 `xdk.text`

- S1 §9.2/§9.7 already provides `String` / `Text` / `Bytes` / `StringBuilder` built-ins. `xdk.text` provides: encoding conversion, explicit formatting (format control beyond built-in interpolation), and parsing (integers / floats / custom formats).
- **Decision 3-f-1**: formatting uses the **builder style** (chained constructors), not printf-style format strings.
- **Decision 3-f-2**: regular expressions enter the first version (`Regex` type; a compile-time-checkable literal form belongs to a grammar minor version; the dynamic-compile form enters this package).

### 4.7 `xdk.sys` and `xdk.net`

- `xdk.sys`: per the S3 §18 resource-handle contract — files (open/read/write/close), directories, subprocesses, platform information.
- `xdk.net`: **Decision 3-g-1** — networking is an independent package (server-language positioning; its lifecycle differs from `sys`'s local resources).
- **Decision 3-g-2 (I/O shapes)**: dual shapes within the package — the task-aware asynchronous shape is the default (carries a `Context`, suspends without occupying a thread, S5 §2.2); the synchronous shape is an explicit plain API (named in `sys` as base functions without an `Async` suffix, with blocking classification declared in package documentation, S5 §9).

### 4.8 `xdk.sys` Resource Reading (added in v1.1.0)

Embedded resources = read-only files under the `resources/` prefix inside the artifact (packaging rules in Part 8 §5.6). **Decision 3-g-3**: the resource-reading APIs belong to `xdk.sys`, not a new package — they are in the same "data access" family as the file APIs, sharing path rules and the error surface.

| API | Signature | Semantics |
| --- | --- | --- |
| `resourceExists` | `resourceExists(String) -> Bool` | True if the path is legal and the resource exists; returns `false` if missing (no error) |
| `readResource` | `readResource(Context, String) -> Result<Bytes, Error>` | Read all bytes; missing → `NotFound`; illegal path → `InvalidArgument` |
| `readResourceText` | `readResourceText(Context, String) -> Result<Text, Error>` | UTF-8 decode and return `Text`; illegal bytes → reported per S4 Appendix A decode/input error classes |
| `listResources` | `listResources(Context, String) -> Result<List<String>, Error>` | List all resource paths under the prefix (`/`-separated, ascending lexicographic); prefix is not a directory → empty list |
| `resourceSize` | `resourceSize(String) -> Int?` | Byte count; `null` if missing |

**Mandatory constraints**:

1. Paths are rooted at `resources/`, separator fixed as `/`; absolute paths, `..` segments, empty segments, and backslashes → `InvalidArgument`;
2. **Read-only**: no write, delete, or rename; the return value is not a handle and needs no `close()` — resources exist with the artifact and share the process lifetime, so the §3 resource contract's `close()` requirement does not trigger;
3. **Cancellable**: the first parameter of `readResource` / `readResourceText` / `listResources` is a `Context`; suspension points are cancellable and report `Cancelled` (S4 §5);
4. **No implicit caching**: each call reads once; internal caching MUST NOT change visible semantics (the content at a given path is constant for the process lifetime);
5. **No source confusion**: only embedded resources inside the artifact are read, never falling back to the file system — a file of the same path in the working directory is not read. Embedded resources and working-directory files are two sources; mixing them would make deployment behavior depend on the current directory;
6. **Missing is a recoverable error**: always return a `Result` error, never panic (§3 rule 1);
7. **File APIs MUST NOT read embedded resources**: the artifact may be a single-file executable; the file API's path space and the resource space are unrelated.

## 5. Versioning

- **Decision 4-1**: XDK versions are decoupled from language versions — during language v3.x the XDK is independently versioned (this part from v1.0.0); XDK breaking changes do not drag language versions along.
- **Decision 4-2 (reverse constraint)**: changes to the contract principles (§3) are protected by the language specification's contracts (e.g., the resource contract linked to S3 §18) and cannot be unilaterally weakened.
- **Decision 4-3 (declaration mechanism)**: an explicit mechanism for the XDK to require "language version ≥ X" belongs to the project-configuration specification (Part 8).
- **Decision 4-4 (minor-version addition)**: v1.1.0 adds §4.8 in a minor version, deleting or rewriting no v1.0.0 contract (backward compatible); projects written against the v1.0.0 contracts need no changes.

## 6. Decision Record (finalized 2026-11-05)

The following decisions are normative (all adopted 2026-11-05); revisions follow the version process:

| ID | Question | Decision |
| --- | --- | --- |
| 1-a | Package count and granularity (merge sync into tasks? split sys?) | Keep 8 packages (with `net`); neither sync nor sys is split |
| 1-b | Boundary between runtime and sys | Time/env/exit → runtime; files/network → sys/net |
| 2 | Adopt the library-wide contract principles? | All seven adopted (normative) |
| 3-a | report chained return; cause-chain shape | Return the original value; conventional field |
| 3-b | Context passing: convention or enforcement | Convention first; compiler checks may come later |
| 3-c | Atomic type coverage | First version Int/Bool/Ref<T> (Ref restricted to references) |
| 3-d | The runtime API surface (table 4.4) | Adopted per table; nowWall = UTC milliseconds |
| 3-e | collections vs. built-in containers | A + B combination (4 specialized containers in first version) |
| 3-f | Formatting style; regex in version | Builder style; regex in first version |
| 3-g | net independent; sync/async I/O shapes | net independent; dual shapes in one package (async default) |
| 4 | Version decoupling and declaration mechanism | Decoupled; declaration mechanism belongs to Part 8 |

## 7. Finalization Actions (Completed)

1. This part was revised per the decision record and raised to the v1.0.0 normative specification (2026-11-05); the discussion draft v0.1.0 was archived.
2. The indicative binding declarations of Parts 4/5/7 are retained (guarding against future drift); the `xdk.*` names they reference are the official names of this document.
3. The acceptance-matrix extension (per-package XDK-01… rows) was completed on 2026-11-06 with the implementation-layer initiation (§8).
4. The specification index's document list and todo items were synchronized.

## 8. Acceptance Matrix

| ID | Domain | Acceptance Points |
| --- | --- | --- |
| XDK-01 | Package structure | All 8 packages (with `net`) present; dependency matrix matches §2 layering and dependency direction; package names consistent with the `xdk.*` references of Parts 4/5/7 |
| XDK-02 | Contract principles | §3's seven rules apply to all packages; cases violating any (hidden global state, implicit caching, panic escape, silent degradation, etc.) are rejected |
| XDK-03 | errors | All 14 `ErrorKind` cases present; `wrap` discard-and-replace, `mapErr` transform, `report` returns the original `Result`; cause chains via the `cause` conventional field with no protocol members added |
| XDK-04 | tasks | spawn outside groups is unreachable (the group is the only spawn entry); group closure is the only termination path; cancellation/timeout error surfaces match S4; `Context` first parameter is a convention (not compiler-enforced) |
| XDK-05 | sync | `Mutex.withLock` is scoped (the lock cannot leak out of scope); `Channel` is bounded with cancellable suspension points; the `T` of `AtomicRef<T>` is restricted to reference types, value-type atomics rejected |
| XDK-06 | runtime | `diagnose` single-line output; `exit` runs no `defer`; `nowMono` monotonic, `nowWall` UTC milliseconds and may step backward; `env` is an immutable snapshot |
| XDK-07 | collections | Built-in container semantics unchanged; algorithm functions and the 4 first-version specialized containers (`RingBuffer`/`OrderedMap`/`BTreeMap`/`PriorityQueue`) available |
| XDK-08 | text | Builder-style formatting; encoding conversion and integer/float parsing; `Regex` dynamic-compile form available with compile failure as a recoverable error |
| XDK-09 | sys/net | Files/directories/subprocesses follow the S3 §18 handle contract (`close()` always runs); dual-shape I/O: async default (with `Context`) + explicit plain sync; networking as an independent package |
| XDK-10 | Resource reading | Each of §4.8's five APIs and seven mandatory constraints has corresponding cases: illegal paths (absolute/`..`/empty segment/backslash) → `InvalidArgument`; missing → recoverable `NotFound`; `listResources` lexicographic order; return values are not handles and need no `close()`; cancellable suspension points; no filesystem fallback; file APIs cannot read embedded resources |
