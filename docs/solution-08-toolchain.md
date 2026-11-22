# XNull Solution Part 8: Toolchain

| Item | Value |
| --- | --- |
| Document number | Part 8 (S8) |
| Document version | 2.2.0 |
| Specification status | Draft (pending end-to-end verification) |
| Release date | 2026-11-15 |
| Applies to | XNull language implementations |
| Related parts | Part 1 v3.4.0; Part 2 v3.6.0; Part 3 v1.0.0; Part 4 v3.2.0; Part 5 v1.2.0; Part 6 v1.3.0; Part 7 v3.0.0; Part 10 v5.3.0 |

## Revision History

| Version | Date | Content |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | First edition. Establishes the toolchain as an independent part and gives the module division, cross-module contracts, specification basis, and coding basis. |
| 2.0.0 | 2026-11-15 | FFI is merged into the toolchain; only the CLI, build, and FFI contracts are retained, and the module structure moves into the implementation document. |
| 2.1.0 | 2026-11-15 | Completes the CLI contract; removes the module index. |
| 2.2.0 | 2026-11-15 | Marked as draft; added end-to-end validation status and unverified clauses. |
| — | 2026-11-23 | Document renumbered from Part 7 to Part 8 to insert Part 3 (Annotations); content version remains 2.2.0. |

---

## 0. Positioning and Specification Boundary

### 0.1 What Part 8 Is

Part 8 is the **contract standard** for the XNull toolchain, specifying the stable interfaces between the toolchain and users, and between the toolchain and implementations:

- the command surface, file/project modes, machine interface, and exit codes of the CLI;
- the inputs, artifacts, determinism, diagnostics, reproducibility, and stable ABI of builds;
- the three contract surfaces, leases, boundary representation, callbacks, error codes, and `@unsafe` of FFI (Appendix A).

The toolchain only performs compilation, linking, packaging, and contract validation; it does not implement standard library algorithms. Library types are defined by libraries, and the toolchain must not maintain member tables for library types.

It does not define types, control flow, object model, error model, or concurrency model; these are specified by Parts 1–7. The implementation structure, coding approach, and module division of the toolchain are not normative content of this part.

### 0.2 What Part 8 Is Not

- It is not a new language semantics part, and it does not expand capabilities already rejected by Parts 1–7;
- It is not an implementation design document, and it does not specify internal data structures, algorithms, file organization, or naming;
- It does not write unimplemented capabilities as promises; unimplemented commands must fail explicitly.

### 0.3 Verification Status

This part is a **draft**. The following have been verified on the bootstrap toolchain:

- file mode `build` / `run` (hello, class);
- success and diagnostic exit codes;
- same input, same artifact.

Not verified: XDK imports, project mode, `--json` machine interface, FFI contract, cross-platform behavior. Unverified clauses must not serve as a release basis before verification.

### 0.4 Marking of Three Kinds of Content

This document and the module documents use the following boundaries:

| Type | Meaning | Constraint |
| --- | --- | --- |
| Specification semantics | Behavior already defined by Parts 1–7 | Part 8 can only implement it, not rewrite it |
| Engineering contract | Implementation-level interface between modules / between the toolchain and users | May be stable and versioned, but must not back-infer language semantics |
| Implementation choice | Internal data structures, algorithms, file organization, naming | Replaceable; must not become source-observable behavior |

Examples:

- "`String` is a reference type, and its length is measured in bytes" is specification semantics;
- "`xrt_string_len` returns the byte length" is an engineering contract (Part 8 stable ABI);
- "the string object internally uses `rt_header + len + bytes[]`" is an implementation choice.

---

## 1. CLI Contract

### 1.1 Command Surface

| Command | Contract | Status |
| --- | --- | --- |
| `new <app\|library> <dir>` | Create a project skeleton; refuse to overwrite a non-empty directory | Stable |
| `check <file\|dir>` | Load and semantic-check only, produce no artifacts | Stable |
| `build <file\|dir> [-o out]` | Build an executable artifact | Stable |
| `run <file\|dir> [-- args…]` | Build and run; program output is passed through | Stable |
| `policy <file\|dir>` | Output the memory policy decision | Stable |
| `fmt [--check] <file…>` | Format source files | Stable |
| `test` / `lock` | Project lifecycle commands | Target state |
| `dev <check\|ledger\|res>` | Internal maintenance tools, not a stable user surface | Internal |
| `version` / `doctor` | Version and environment information | Stable |

- File mode: when the argument of `run` / `build` / `policy` is a `.x` file, file mode is entered; otherwise project mode is entered, requiring `xnull.project`.
- Project mode lifecycle, dependencies, locks, resources, and plugins are specified by Part 10; the CLI is only responsible for dispatch and exit codes.
- Unimplemented commands must fail explicitly (`CLI-901`, exit 2), and must not succeed silently.

### 1.2 Machine Interface

- `check --json` and `build --json` output stable JSON; stdout contains only JSON, and logs go into the `log` field.
- `--json` fields: `ok` / `file` / `output` / `exitCode` / `diagnostics` / `log`; diagnostic fields: `file` / `line` / `column` / `code` / `message` / `hint` / `snippet` / `width`.
- Normal results are written to stdout; diagnostics and errors are written to stderr; internal governance information is not written into user-visible output.
- Subprocess exit codes are not swallowed.

### 1.3 Exit Codes

| Case | Exit code |
| --- | --- |
| Success | `0` |
| Compilation/semantic/build diagnostics | `1` |
| Usage error, missing manifest | `2` |
| Interrupted | `130` |
| Program fatal | `134` |
| Program returns normally | `main` return value passed through |

CLI's own diagnostic codes: `CLI-001` unknown command, `CLI-002` unknown flag, `CLI-003` `xnull.project` not found, `CLI-901` command not implemented.

## 2. Build Contract

### 2.1 Diagnostic Contract

- All modules produce structured diagnostic values and do not write stderr directly;
- Diagnostic code ranges are registered jointly by Parts 1–7 and the Part 8 modules;
- Rendering, ordering, and exit code mapping belong to 07/02;
- Same input, same diagnostic order.

### 2.2 Determinism Contract

- Same source program + same toolchain version + same compilation options → same C text/artifact/run result;
- Maps participating in output must be sorted;
- Registries, policy results, resource tables, lock files, and diagnostics are all sorted;
- Temporary variable numbering, diagnostic order, and link argument order are stable;
- Reclamation timing is not required to be deterministic, but observable order must conform to Part 4.

### 2.3 Error and Exit Code Contract

| Layer | Failure manifestation | Exit code |
| --- | --- | --- |
| Usage/manifest | CLI/project diagnostics | 2 |
| Compilation/semantic/build | Diagnostics | 1 |
| Interruption | Toolchain signal handling | 130 |
| Program fatal | Runtime termination | 134 |
| Program returns normally | `main` return value | Passed through |

### 2.4 Stable ABI Contract

- `xrt.h` is the only externally stable ABI;
- Generated code, FFI wrappers, and the native side manage memory only via `xrt_*`;
- `rt.h` is an internal header and is not distributed with the SDK;
- Symbol/signature changes go through a major version;
- Handle close is idempotent and does not depend on `deinit`;
- Weak tables are open only to the FFI contract layer.

### 2.5 No Silent Degradation Contract

- Construct not supported by the compiler → explicit error;
- Shape not covered by FFI → `Problems`/build failure;
- Unknown field/unresolved variable in project configuration → build failure;
- Runtime contract violation → fatal;
- Must not generate a substitute implementation that "looks like it runs".

### 2.6 Reproducibility Contract

- Builds do not access the network (project plugins are network-forbidden);
- Dependencies are recognized only from the manifest and agreed directories;
- Lock file bytes are stable;
- Builds write only to `target/`;
- `.xmeta` records input digests;
- Same input, same artifact.

---

## Appendix A: FFI Contract

### A.0 Core Position

- FFI is a **contract-constrained cross-language interface**, not a direct call to arbitrary native functions (S5 §6, S4 §19). There is no `extern`, `unsafe` block, or raw pointer syntax; all native interaction must go through the contract entry points specified in this part.
- This part is the **completion** of Part 4 §19: Part 4 specifies the memory dimension (handles, leases, liveness), and this part completes four blocks: call shape, layout verification, runtime ABI naming, and error codes and blocking classification.
- **Name ownership**: library API names belong to the library API surface of Part 7; this part specifies only the cross-language contract itself. The landing point of declarations such as `@ffiEntry` / `@lease` and of `layout(c)` is the binding layer declaration file (internal format), which does not enter the language grammar.

### A.1 Positioning and Scope

#### A.1.1 Scope

This part specifies the interaction contract between XNull and the native world (with the C ABI as the baseline): FFI model and contract surfaces, call leases, type layout and boundary representation, callbacks and trampolines, stable runtime ABI naming, cross-boundary error codes, blocking classification contract, controlled entry shape, and safety invariants.

#### A.1.2 Not Specified

- The implementation shape of binding generators (hand-written declarations and code generation tools are both compliant; artifacts must satisfy the contract of this part);
- Runtime internal implementation (allocation header structures, GC algorithms); for memory semantics see Part 4;
- Library layering, capability ownership, and API naming (finalized by Part 7); members and algorithms of library types are defined by libraries, and this part specifies only boundary representation and rejection rules;
- Link options and build integration in project configuration (Part 10).

#### A.1.3 Boundaries with Other Parts

| Dimension | Specified by | Role of this part |
| --- | --- | --- |
| Memory semantics of handles and call leases | Part 4 §19 | Instantiated as an executable declaration format (sections 2, 4) |
| Runtime ABI entry set | Appendix A §A.6 | Completes cross-FFI stable naming (§A.6) |
| Error observation and classification semantics | Part 5 §6.3, Part 5 Appendix A | Completes the error code set and mapping rules (§A.7) |
| Blocking dichotomy principle | Part 6 §2.4 | Completes the per-API classification list format and the dedicated executor contract (§A.7.3) |
| GC rules for callback closures | Part 4 §10.5 | Completes trampoline shape and lifecycle contract (section 5) |
| Resource handle close contract | Part 4 §18 | Referenced, not redefined |

### A.2 FFI Model and Contract Surfaces

#### A.2.1 Three Contract Surfaces

Cross-boundary data is allowed only in three shapes (refining Part 4 §19):

1. **Value passing**: scalars and `struct`s that are layout-verified as compatible (must be `layout(c)`, §A.3.3), marshalled copies;
2. **Handle passing**: opaque handles + explicit lifecycle contract (§A.4.3);
3. **Buffer passing**: raw byte regions of `Bytes` / scalar arrays, kept alive by the runtime during the boundary (§A.4.4).

Types not in the three shapes (references, closures, `Result`, optionals, containers, direct handover of `String`) are rejected by the contract layer (§A.3.6).

#### A.2.2 Call Leases

Every FFI entry must explicitly declare a **call lease** — who holds it and when it is released (Part 4 §19):

```x
// entry declaration shape; the landing point belongs to the library binding layer (Part 7 §4)
@ffiEntry(cName = "sqlite3_open")
@lease(path = .borrow, db = .transfer)      // per-parameter lease: borrow / transfer
@errorCode(codeParam = .result)             // error code out-parameter (§A.7.1)
@blocking(.unaware)                         // blocking classification (§A.7.3)
Int ffiSqliteOpen(Bytes path, Handle db);
```

Contract rules:

- Leases are declared **per parameter**; omission is treated as a contract violation (rejected by the compiler/contract layer);
- `.borrow`: ownership stays on the XNull side, and the native side may use it only during this call; the native side must not retain the pointer before the call returns;
- `.transfer`: ownership is given to the native side; there must be a symmetric return entry declaration (`.reclaim`), or an explicit declaration of "never returned" (process-lifetime object, with a stated reason);
- Linked with Part 4 §19: under no shape may an XNull object reference serve as a cross-language address.

#### A.2.3 Capability Boundary

- "Arbitrary native function direct calls" are not promised; every entry is a declarative contract object validated by the contract layer (aligned with S5 §6);
- FFI extensions are not used to inflate the language's own capabilities (S5 §6): after native capabilities enter XNull they must adapt to this language's error, resource, and cancellation contracts, and must not introduce parallel mechanisms;
- Capabilities beyond this contract, such as kernels/drivers/bare metal, require new dedicated contracts and are not covered by this part (S5 §6.4).

### A.3 Type Layout and Boundary Representation

#### A.3.1 General Rules

- Layout compatibility must be **verified type by type**; XNull field slots and the target ABI are not identical by default (Part 4 §19);
- Implementation layout commitments (Part 2 §3.2, Part 4 §2): `struct` fields follow declaration order, 8-byte slots, scalars occupy 8 bytes, and there is no object header. These are implementation layouts, **not cross-boundary commitments** — cross-boundary matters follow this section.

#### A.3.2 Scalar Mapping

| XNull type | C baseline | Notes |
| --- | --- | --- |
| `Int` / `UInt` | `int64_t` / `uint64_t` | Fixed 64-bit (Part 1 §2.1) |
| `Int64`…`Int8` series | Corresponding fixed-width types | |
| `Float` / `Float64` | `double` | `Float32` → `float` |
| `Bool` | `uint8_t` (0/1) | Non-zero values are normalized to 1 when read |
| `Char` | `uint32_t` (Unicode code point) | |
| Pointer-width scalars | No correspondence | No pointer-width integer types are provided; address operations do not exist (Part 1 §0.7) |

#### A.3.3 `struct` and `layout(c)`

- A `struct` passing by value across the boundary must be explicitly annotated `layout(c)` (illustrative name; the landing point belongs to the Part 1/2 grammar or the binding layer): fields follow declaration order with C natural alignment; an unannotated `struct` can only go through marshalled copies or handles;
- `layout(c)` field types are limited to scalars and nested `layout(c)` structs; those containing reference, optional, or container fields are rejected;
- Recursive value containment is rejected (aligned with Part 2 STRUCT-01).

#### A.3.4 `String` / `Text` / `Bytes`

- The boundary representation is uniformly a `ptr + byte_len` pair: `String` / `Text` are immutable UTF-8 (Part 1 §9.2), and when borrowed they are delivered as `const char*` + length, **not contracted to be NUL-terminated** (the length is explicit);
- `Bytes` mutable buffers are borrowed as `void*` + length; native writes must not exceed the declared length;
- Transfer (`.transfer`) is allowed only for `Bytes` (clear ownership); `String` / `Text` cannot be transferred (immutable and managed by the runtime); when persistence is needed, the binding layer copies them into `Bytes`.

#### A.3.5 Arrays and Buffers

- Scalar arrays (`T[]`, where T is a scalar or a `layout(c)` struct) may be borrowed: `ptr + count`, with the runtime guaranteeing liveness during the boundary (Part 4 §19);
- Multi-dimensional arrays (nested arrays) do not cross the boundary directly; they are handled as per-row buffers;
- Pin obligation: borrowed objects do not move during the boundary — this is a linked obligation of the contract layer and the runtime.

#### A.3.6 List of Types That Do Not Cross the Boundary

`Result`, optional types, reference-type objects, closures, containers such as `List` / `Map` / `Set`, direct transfer of `String` / `Text`, tuples (inlined in the implementation but without a cross-boundary contract). Violating entries are rejected by the contract layer.

### A.4 Call Leases and Handle Lifecycle

#### A.4.1 Borrow

- The lifetime of a borrowed parameter = this call; after return the pointer is invalidated, as declared by the contract text;
- The native side must not retain a copy of the borrowed pointer for asynchronous use; anything that needs to be held asynchronously must go through transfer or copy.

#### A.4.2 Transfer

- After `.transfer`, the XNull side no longer frees it; the native side becomes the owner;
- The `.reclaim` entry declares the return path: the native side hands ownership back, and the XNull side resumes management (typical case: buffer fill completed);
- "Never returned" is limited to process-lifetime objects and must explicitly state the reason in the lease text.

#### A.4.3 Opaque Handles

- Native resources are represented on the XNull side as **opaque handle types** (implementation details belong to the binding layer; the close contract is aligned with Part 4 §18: explicit `close()`, repeated closes are safe, and it does not depend on `deinit`);
- Handles are not shared across tasks (Part 4 §18); cross-task sharing follows the Part 6 sharing rules (channel passing + ownership transfer semantics);
- Handle values must not participate in arithmetic, ordering comparisons, or serialization.

#### A.4.4 Buffer Liveness Contract

- Borrowed buffers are guaranteed by the runtime to be alive and not moved (pinned) during the call;
- Writes during the boundary are limited to the declared range; an out-of-bounds write is a native-side contract violation: **terminate the process upon detection** (final, §A.9); detection of all out-of-bounds writes is not promised (non-promise; reason: out-of-bounds detection requires instrumentation, and the performance cost is unacceptable; dependency consequence: the consequences of undetected out-of-bounds writes are not guaranteed).

### A.5 Callbacks and Trampolines

#### A.5.1 Shape

- Closures cannot be passed directly as C function pointers (Part 4 §10.5); cross-boundary callbacks are generated by the binding layer as a **trampoline**: a C function conforming to the target ABI that internally calls the XNull closure `fn(env, args...)`;
- A trampoline is a contract object: it declares the boundary representation of parameters/returns, the error path (§A.7.1), and the blocking classification (§A.7.3).

#### A.5.2 Lifecycle Contract

- At trampoline creation, `env` is registered as a runtime root (Part 4 §19; entry `task_root_bind`, §A.22); it is unregistered on destruction;
- Trampoline lifecycle is managed explicitly: it is valid while the native side holds it, and its destruction contract is the same as handles (§A.4.3);
- A registered-then-unregistered trampoline being called again by the native side is a native-side contract violation.

#### A.5.3 Restrictions Inside Callbacks

- A callback must not block beyond its declared classification (§A.7.3);
- Panic inside a callback: the contract layer catches it and terminates the process (aligned with Part 6 — panic does not do task-level isolation; a callback is the root boundary on the embedding side);
- A callback must not re-enter the same native side and borrow the same buffer (re-entrant aliasing violations are flagged by the contract text).

### A.6 Runtime ABI and Embedding

#### A.6.1 Stable Naming

The runtime entry set of Appendix A §A.6 is given cross-FFI stable naming (illustrative prefixes, adjustable at finalization):

| Entry | C symbol (illustrative) | Source |
| --- | --- | --- |
| Allocation | `xrt_alloc` | Appendix A §A.6 |
| Counting | `xrt_retain` / `xrt_release` | Appendix A §A.6 |
| Weak tables | `xrt_weak_bind` / `xrt_weak_read` / `xrt_weak_clear` | Appendix A §A.6 |
| Barriers and roots | `xrt_write_barrier` / `xrt_register_root` / `xrt_unregister_root` / `xrt_safepoint` | Appendix A §A.6 |
| Task roots | `xrt_task_root_bind` / `xrt_task_root_unbind` | Appendix A §A.6 |

- Once finalized, symbols and signatures are frozen as ABI commitments, and changes go through a major version;
- Compiler-generated code and the native side manage memory only through these entries and must not bypass the allocation header (Appendix A §A.6).

#### A.6.2 How Weak Table Entries Are Opened

- Weak tables are a runtime internal mechanism, and their entries are **open only to the FFI contract layer** (Part 4 §16/§A.19): native code must not call weak table symbols directly; only binding layer code generated by the contract of this part may;
- Typical use: the native side caches weak references to XNull objects.

#### A.6.3 Embedding

- A native program embedding the XNull runtime in reverse is a **non-promised entry**: this part promises only ABI symbols and a minimal initialization order contract (no objects may be created before safepoint is available); the full embedding API is **rejected** within 1.x (reason: the embedding API surface has not been verified; dependency consequence: projects depending on the full embedding API are unsupported), and additions require a separate contract.

### A.7 Error Codes and Boundary Conversion

#### A.7.1 Error Code Contract

- `Result` does not cross language boundaries (Part 5 §6.3): signatures entering FFI must not contain `Result` parameters/return values;
- XNull calling native: errors are delivered as an **error code out-parameter** (`@errorCode` in the §A.2.2 example); the binding layer maps error codes to local error types:
  - Known codes → mapped by semantics to `ErrorKind` classifications (Part 5 Appendix A);
  - **Unknown codes → `Internal`**, and silent mapping to `Ok` is forbidden (Part 5 §6.3);
  - Baseline convention: `Int32` out-parameter, `0 = ok`; complex errors beyond the error code channel (error structs) go through the handle + getter shape.

#### A.7.2 Cancellation / Timeout Mapping

- Cancellation/timeout reported by the native side to XNull must be mapped to the `Cancelled` / `Timeout` classifications, and **must not be degraded to `Internal`** (Part 5 §6.3);
- Calls that the native side cannot cancel must not be declared cancellable; the blocking classification of an FFI entry (§A.7.3) determines whether it can carry a `Context`.

#### A.7.3 Blocking Classification and Dedicated Executors

Implementing the mandatory interface of Part 6 §2.2:

- **Per-API blocking classification list**: every FFI entry must declare `.aware` (task-aware, suspension does not occupy a thread — only for entries implemented via the scheduler) or `.unaware` (task-unaware, occupies a thread until return). The list is published with package documentation (Part 6 §7).
- **Long-blocking dedicated executor contract**: `.unaware` entries expected to block for a long time must provide a "submit to a dedicated executor" companion shape (after submission a task handle is returned, isolated by a thread pool), avoiding occupying a scheduler thread indefinitely;
- Incorrect classification declarations (e.g., `.unaware` actually blocking for a long time) are implementation-layer contract violations.

### A.8 `@unsafe` and Controlled Entries

- Part 1 §0.6 reserves the `@unsafe` shape for library APIs. This part finalizes: an `@unsafe`-annotated entry is a **controlled entry exempted by the contract layer** — it allows expressing operations that the binding layer cannot statically verify (such as direct reads and writes of native memory), but it must:
  1. explicitly declare preconditions and the consequences of violation (contract text);
  2. exist only in the library binding layer (Part 7 §4); application code cannot create `@unsafe` entries;
  3. form a separate class, verified by the contract layer.
- This is the final decision between "no `unsafe` block syntax" and "the implementation layer needs an escape hatch": danger is isolated in contract-bearing library-layer entries rather than in language syntax.

### A.9 Safety Invariants

| ID | Invariant | Basis |
| --- | --- | --- |
| INV-FFI-1 | FFI entries without a lease declaration are rejected | Part 4 §19, MEM-11 |
| INV-FFI-2 | `Result` signatures exposed through FFI are rejected; unknown error codes map to `Internal`, not `Ok` | Part 5 §6.3 |
| INV-FFI-3 | Cancellation/timeout through FFI does not degrade to `Internal` | Part 5 §6.3 |
| INV-FFI-4 | Object references are not used as cross-language addresses; ARC/GC does not manage objects in another language | Part 4 §19 |
| INV-FFI-5 | Borrowed buffers are alive and pinned during the boundary | Part 4 §19, §A.4.4 |
| INV-FFI-6 | `env` is a root during the trampoline; calling after unregistration is a violation | Part 4 §19, Appendix A §A.6, Part 4 §10.5 |
| INV-FFI-7 | The compiler and the native side manage memory only through stable ABI entries | Appendix A §A.6 |
| INV-FFI-8 | Panics across FFI terminate the process at the contract layer (no isolation) | Part 6 §7 |
| INV-FFI-9 | Repeated handle closes are safe; `deinit` is not relied on as the only close path | Part 4 §18 |
