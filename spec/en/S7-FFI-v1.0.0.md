# XNull Specification, Part 7: Foreign Function Interface (FFI)

> **Translation notice**: This is an English translation of the normative Chinese specification
> 《XNull 解决方案 第 7 部分：FFI》v1.0.0. The Chinese original prevails in case of any
> divergence. Translation version follows the original's version number.

| Item | Content |
| --- | --- |
| Document ID | Part 7 (S7) |
| Document Version | 1.0.0 |
| Specification Status | Normative (approved 2026-11-05) |
| Release Date | 2026-11-05 |
| Upstream Dependencies | Part 1 §0.6/§0.7; Part 2 §3.6/§14.5/§15.3; Part 3 §16/§18/§19/§22; Part 4 §7.3/Appendix A; Part 5 §2.2/§9; Part 6 §1.4/§4.7; S4 §6 |

## 0. Core Stances

- FFI is a **contract-bound cross-language interface**, not direct calls to arbitrary native functions (S4 §6, S3 §19). There is no `extern`, no `unsafe` blocks, and no raw-pointer syntax; every native interaction MUST go through the contractual entry points defined in this part.
- This part is the **completion** of Part 3 §19: Part 3 defines the memory dimension (handles, leases, liveness); this part completes the calling forms, layout verification, runtime ABI naming, error codes, and blocking classification.
- **Name ownership**: the `xdk.*` package names and API names appearing here (`xdk.sys`, `@unsafe`, etc.) are governed by Part 6 (XDK); this part defines only the cross-language contracts themselves. The landing points of attribute names (`@ffiEntry`, etc.) and `layout(c)` are settled: they belong to binding-layer declaration files, not the language grammar (Appendix B).

## 1. Positioning and Scope

### 1.1 Scope

This part defines the interaction contract between XNull and the native world (with the C ABI as the baseline): the FFI model and contract surface, call leases, type layout and boundary representation, callbacks and trampolines, stable runtime ABI naming, cross-boundary error codes, the blocking-classification contract, controlled entry forms, and safety invariants.

### 1.2 Not Defined Here

- The implementation form of binding generators (hand-written declarations and code-generation tools are both compliant; their output MUST satisfy this part's contracts);
- Runtime internals (allocation-header structure, GC algorithms — see Part 3 §15);
- XDK package structure, API naming, and ownership (finalized in Part 6);
- Linking options and build integration in project configuration (Part 8).

### 1.3 Boundaries with Other Parts

| Dimension | Definer | This Part's Role |
| --- | --- | --- |
| Memory semantics of handles and call leases | Part 3 §19 | Realized as executable declaration formats (§2, §4) |
| Runtime ABI entry set | Part 3 §22 | Completes cross-FFI stable naming (§6) |
| Error observation and classification semantics | Part 4 §7.3, Appendix A | Completes the error-code set and mapping rules (§7) |
| Blocking dichotomy principle | Part 5 §2.2 | Completes the per-API classification-list format and the dedicated-executor contract (§7.3) |
| GC rules for callback closures | Part 2 §14.5 | Completes the trampoline form and lifetime contract (§5) |
| Resource-handle close contract | Part 3 §18 | Referenced, not redefined |

## 2. The FFI Model and Contract Surface

### 2.1 The Three Contract Forms

Cross-boundary data admits only three forms (refining Part 3 §19):

1. **Value transfer**: scalars, layout-verified compatible `struct`s (requiring `layout(c)`, §3.3), marshaled copies;
2. **Handle transfer**: opaque handle + explicit lifetime contract (§4.3);
3. **Buffer transfer**: the raw byte regions of `Bytes` / scalar arrays, kept alive by the runtime for the boundary duration (§4.4).

Types outside the three forms (references, closures, `Result`, optionals, containers, direct `String` handover) are rejected by the contract layer (§3.6).

### 2.2 Call Leases

Every FFI entry MUST declare its **call lease** explicitly — who holds, when to release (Part 3 §19; acceptance MEM-11 "entries without declared leases are rejected"):

```x
// Entry declaration form; landing point is the xdk.sys binding layer (Part 6 §4.7)
@ffiEntry(cName = "sqlite3_open")
@lease(path = .borrow, db = .transfer)      // per-parameter lease: borrow / transfer
@errorCode(codeParam = .result)             // error-code out-parameter (§7.1)
@blocking(.unaware)                         // blocking classification (§7.3)
Int ffiSqliteOpen(Bytes path, Handle db);
```

Contract rules:

- Leases are declared **per parameter**; omission is a contract violation (rejected at the compile/contract layer);
- `.borrow`: ownership stays on the XNull side; the native side may use it only during this call; the native side MUST NOT retain the pointer beyond the call's return;
- `.transfer`: ownership passes to the native side; a symmetric return entry (`.reclaim`) MUST be declared, or "never returned" explicitly declared (process-lifetime objects, with a stated reason);
- Linked with Part 3 §19: under no form may an XNull object reference be used as a cross-language address.

### 2.3 Capability Boundary

- "Direct calls to arbitrary native functions" are not promised; every entry is a declarative contract object verified by the contract layer (aligned with S4 §6);
- FFI MUST NOT be used to inflate the language's own capabilities (S4 §6): native capabilities, once entering XNull, MUST adapt to this language's error, resource, and cancellation contracts; parallel mechanisms MUST NOT be introduced;
- Capabilities beyond this contract (kernel/driver/bare-metal) require new dedicated contracts; this part does not cover them (S4 §6.4).

## 3. Type Layout and Boundary Representation

### 3.1 General Rules

- Layout compatibility MUST be **verified per type**; XNull field slots are not assumed identical to the target ABI (Part 3 §19);
- Implementation layout promises (Part 2 §3.6/§15.3): `struct` fields in declaration order, 8-byte slots, scalars occupying 8 bytes, no object header. These are implementation layouts, **not cross-boundary promises** — cross-boundary matters are governed by this section.

### 3.2 Scalar Mapping

| XNull Type | C Baseline | Notes |
| --- | --- | --- |
| `Int` / `UInt` | `int64_t` / `uint64_t` | Fixed 64-bit (Part 1 §2.1) |
| `Int64`…`Int8` family | Corresponding fixed-width types | |
| `Float` / `Float64` | `double` | `Float32` → `float` |
| `Bool` | `uint8_t` (0/1) | Non-zero reads normalized to 1 |
| `Char` | `uint32_t` (Unicode code point) | |
| Pointer-width scalars | None | No pointer-width integers; address operations do not exist (Part 1 §0.7) |

### 3.3 `struct` and `layout(c)`

- `struct`s crossing the boundary by value MUST be explicitly annotated `layout(c)` (indicative name; landing point belongs to the Part 1/2 grammar or the binding layer): fields in declaration order, C natural alignment; unannotated `struct`s may only travel as marshaled copies or handles;
- `layout(c)` field types are limited to scalars and nested `layout(c)` structs; those containing references, optionals, or containers are rejected;
- Recursive value containment is rejected (aligned with Part 2 STRUCT-01).

### 3.4 `String` / `Text` / `Bytes`

- The boundary representation is uniformly a `ptr + byte_len` pair: `String` / `Text` are immutable UTF-8 (Part 1 §9.2), delivered when borrowed as `const char*` + length, **with NUL-termination explicitly NOT part of the contract** (length is explicit);
- `Bytes` mutable buffers are lent as `void*` + length; native writes MUST NOT exceed the declared length;
- Transfer (`.transfer`) is allowed only for `Bytes` (ownership is clear); `String` / `Text` cannot be transferred (immutable and runtime-managed); where persistence is needed, the binding layer copies into `Bytes`.

### 3.5 Arrays and Buffers

- Scalar arrays (`T[]`, T a scalar or `layout(c)` struct) may be lent: `ptr + count`, kept alive by the runtime for the boundary duration (Part 3 §19);
- Multidimensional arrays (nested arrays) do not cross the boundary directly; handle them as per-row buffers;
- Pin obligation: lent objects do not move during the boundary duration — this is a joint obligation of the contract layer and the runtime.

### 3.6 The Non-Crossing Type List

`Result`, optionals, reference-type objects, closures, containers such as `List` / `Map` / `Set`, direct `String` / `Text` handover, tuples (inlined in the implementation but without a cross-boundary contract). Violating entries are rejected by the contract layer (acceptance FFI-01).

## 4. Call Leases and Handle Lifecycles

### 4.1 Borrowing

- The lifetime of a borrowed parameter = this call; the pointer is invalid after return, as stated in the contract text;
- The native side MUST NOT keep copies of borrowed pointers for asynchronous use; asynchronous retention requires transfer or copying.

### 4.2 Transfer

- After `.transfer`, the XNull side no longer releases; the native side becomes the owner;
- The `.reclaim` entry declares the return path: the native side hands ownership back and XNull-side management resumes (typically: buffer filling completed);
- "Never returned" is limited to process-lifetime objects, with the reason explicitly stated in the lease text.

### 4.3 Opaque Handles

- Native resources are represented on the XNull side as **opaque handle types** (implementation details belong to the binding layer; the close contract aligns with Part 3 §18: explicit `close()`, safe repeated closes, no reliance on `deinit`);
- Handles are not shared across tasks (Part 3 §18); cross-task sharing follows Part 5's sharing rules (channel transfer + ownership-transfer semantics);
- Handle values MUST NOT participate in arithmetic, ordering comparisons, or serialization.

### 4.4 The Buffer-Liveness Contract

- Lent buffers are guaranteed alive and unmoved (pinned) by the runtime during the call;
- Writes during the boundary are limited to the declared range; out-of-range writes are native-side contract violations: **the process terminates upon detection** (settled, §9); detecting all out-of-range writes is not promised (non-committed; rationale: detection requires instrumentation with unacceptable performance cost; consequence: the consequences of undetected out-of-range writes are not guaranteed).

## 5. Callbacks and Trampolines

### 5.1 Form

- Closures cannot be passed directly as C function pointers (Part 2 §14.5); cross-boundary callbacks are generated by the binding layer as **trampolines**: C functions matching the target ABI that internally invoke the XNull closure `fn(env, args...)`;
- A trampoline is a contract object: it declares the boundary representations of parameters/returns, the error path (§7.1), and the blocking classification (§7.3).

### 5.2 The Lifetime Contract

- At creation, a trampoline registers its `env` as a runtime root (Part 3 §19; entry `task_root_bind`, §22); it deregisters at destruction;
- Trampoline lifetimes are managed explicitly: valid while the native side holds it; the destruction contract matches handles (§4.3);
- A native call to a deregistered trampoline is a native-side contract violation.

### 5.3 Restrictions Inside Callbacks

- Callbacks MUST NOT block beyond their declared classification (§7.3);
- Panic inside a callback: the contract layer catches it and terminates the process (aligned with Part 5 — panic has no task-level isolation; callbacks are the root boundary on the embedded side);
- Callbacks MUST NOT re-enter the same native call lending the same buffer (re-entrancy aliasing violations are flagged by contract text).

## 6. The Runtime ABI and Embedding

### 6.1 Stable Naming

The runtime entry set of Part 3 §22 receives cross-FFI stable names (indicative prefix, adjustable at finalization):

| Entry | C Symbol (indicative) | Source |
| --- | --- | --- |
| Allocation | `xrt_alloc` | Part 3 §22 |
| Counting | `xrt_retain` / `xrt_release` | Part 3 §22 |
| Weak table | `xrt_weak_bind` / `xrt_weak_read` / `xrt_weak_clear` | Part 3 §22 |
| Barriers and roots | `xrt_write_barrier` / `xrt_register_root` / `xrt_unregister_root` / `xrt_safepoint` | Part 3 §22 |
| Task roots | `xrt_task_root_bind` / `xrt_task_root_unbind` | Part 3 §22 |

- Once finalized, symbols and signatures are frozen as ABI commitments; changes require a major version;
- Compiler-generated code and the native side manage memory only through these entries; bypassing the allocation header is forbidden (Part 3 §22).

### 6.2 How Weak-Table Entries Are Opened

- The weak table is an internal runtime mechanism whose entries are open **only to the FFI contract layer** (Part 3 §16/§19): native code MUST NOT call weak-table symbols directly; only binding-layer code generated under this part's contracts may;
- Typical use: native-side caching of weak references to XNull objects.

### 6.3 Embedding

- Native programs embedding the XNull runtime in reverse is a **non-committed entry**: this part promises only the ABI symbols and a minimal initialization-order contract (no object creation before safepoints are available); a complete embedding API is **rejected within 1.x** (rationale: the embedded API surface is unverified; consequence: projects depending on a full embedding API are unsupported); additions require a dedicated contract.

## 7. Error Codes and Boundary Conversion

### 7.1 The Error-Code Contract

- `Result` does not cross language boundaries (Part 4 §7.3): signatures entering FFI MUST NOT contain `Result` parameters/returns;
- XNull calls native: errors are delivered via an **error-code out-parameter** (`@errorCode` in the §2.2 example); the binding layer maps codes to local error types:
  - Known codes → mapped semantically to `ErrorKind` classifications (Part 4 Appendix A);
  - **Unknown codes → `Internal`**; silent mapping to `Ok` is forbidden (Part 4 §7.3; acceptance BOUND-02);
  - Baseline convention: `Int32` out-parameter, `0 = ok`; complex errors beyond the error-code channel (error structs) go through the handle + getter form.

### 7.2 Cancellation / Timeout Mapping

- Cancellation/timeouts reported from the native side MUST map to the `Cancelled` / `Timeout` classifications and **MUST NOT be degraded to `Internal`** (Part 4 §7.3; acceptance BOUND-03);
- Calls the native side cannot cancel MUST NOT be declared cancellable; the blocking classification of an FFI entry (§7.3) determines whether it may carry a `Context`.

### 7.3 Blocking Classification and the Dedicated Executor

Implementing the mandatory interface of Part 5 §2.2:

- **Per-API blocking-classification list**: every FFI entry MUST declare `.aware` (task-aware, suspends without occupying a thread — only for entries implemented via the scheduler) or `.unaware` (task-unaware, occupies a thread until return). The list ships with package documentation (Part 5 §9) and is an acceptance item (SCHED-01);
- **The dedicated-executor contract for long-blocking calls**: `.unaware` entries expected to block long MUST provide a companion "submit to a dedicated executor" form (returns a task handle after submission, thread-pool isolation), to avoid starving scheduler threads;
- Mis-declared classifications (e.g., `.unaware` that actually blocks long) are implementation-layer contract violations.

## 8. `@unsafe` and Controlled Entries

- Part 1 §0.6 reserves the `@unsafe` API form for `xdk.sys`. This part settles: an `@unsafe`-annotated entry is a **contract-layer-exempt controlled entry** — it may express operations the binding layer cannot statically verify (direct native memory reads/writes, etc.), but MUST:
  1. Explicitly declare preconditions and violation consequences (contract text);
  2. Exist only in `xdk.sys` / the binding layer (Part 6 §4.7); application code MUST NOT create `@unsafe` entries;
  3. Have its own acceptance class (FFI-04).
- This is the settlement between "no `unsafe` block syntax" and "the implementation layer needs an escape hatch": danger is isolated in contract-bearing library-level entries, not in language syntax.

## 9. Safety Invariants

| ID | Invariant | Basis |
| --- | --- | --- |
| INV-FFI-1 | FFI entries without declared leases are rejected | Part 3 §19, MEM-11 |
| INV-FFI-2 | `Result` signatures exposed via FFI are rejected; unknown error codes map to `Internal`, not `Ok` | Part 4 §7.3, BOUND-02 |
| INV-FFI-3 | Cancellation/timeout via FFI not degraded to `Internal` | Part 4 §7.3, BOUND-03 |
| INV-FFI-4 | Object references are not cross-language addresses; ARC/GC do not manage objects in another language | Part 3 §19 |
| INV-FFI-5 | Lent buffers are alive and pinned during the boundary | Part 3 §19, §4.4 |
| INV-FFI-6 | The env is a root for the trampoline's duration; calls after deregistration are violations | Part 3 §19/§22, Part 2 §14.5 |
| INV-FFI-7 | Compiler and native side manage memory only through stable ABI entries | Part 3 §22 |
| INV-FFI-8 | Panic across FFI terminates the process at the contract layer (no isolation) | Part 5 §8 |
| INV-FFI-9 | Handle repeated closes are safe; no reliance on `deinit` as the only release path | Part 3 §18 |

## 10. Acceptance Matrix

| ID | Domain | Acceptance Content |
| --- | --- | --- |
| FFI-01 | Contract surface | Types outside the three forms (`Result`/closures/containers/`String` handover, etc.) are rejected; missing leases are rejected; unknown error codes map to `Internal` rather than `Ok` |
| FFI-02 | Layout | `layout(c)` struct field layouts match the C baseline item by item; unannotated structs only marshal/handle; the scalar mapping table is correct item by item |
| FFI-03 | Leases | `.borrow` pointer invalidation after return is visible; XNull does not release after `.transfer`; `.reclaim` return paths are correct; buffers are pinned for the boundary duration and out-of-range writes are reported |
| FFI-04 | `@unsafe` | Controlled entries exist only in the binding layer; contract text is complete; application code cannot create them |
| FFI-05 | Trampolines | Callback creation registers roots, destruction deregisters; calls after deregistration are detected; panic inside callbacks terminates the process; error-code out-parameter mapping is correct (cancellation/timeout not degraded) |
| FFI-06 | ABI | Stable-name symbols are linkable from native code; signatures match §6.1; the native side manages memory only through the ABI |
| FFI-07 | Blocking classification | Every entry carries a classification declaration; long-blocking entries have dedicated-executor companion forms; declarations match actual behavior (linked with SCHED-01) |

## 11. Implementation Boundaries

- Binding-layer output (declarations, trampolines, marshaling code) MUST be mechanically verifiable against its contract declarations; unverifiable entries are treated as lease-less (rejected);
- The implementation of pinning (no-move / temporary relocation counting) is an implementation detail; the contract requires only "address stability during the boundary";
- Until this part passes acceptance, the rows related to "cross-language calls" in the S4 capability-gap table remain "partially fulfilled" (the memory contract exists; the calling contract is governed by this part).

## Appendix A: Decision Record

1. **The three-way lease** (borrow / transfer / reclaim): turns Part 3 §19's "who holds, when to release" into per-parameter, mechanically verifiable declarations; it expresses real binding needs (e.g., sqlite handle transfer, buffer-fill-and-return) better than either "all manual" or "all copied."
2. **Explicit `layout(c)` annotation**: continues "layout compatibility is not assumed" (Part 3 §19), turning the promise into an explicit action; unannotated types automatically degrade to marshaling — a safe default.
3. **`ptr + len` without NUL termination**: `String` length is known in bytes (Part 1 §9.2); NUL termination is C's historical constraint and should not become a cross-language contract; where a C string is needed, the binding layer copies and appends NUL.
4. **Error-code baseline `Int32` out-parameter + 0=ok**: covers the vast majority of C libraries; complex errors go through handle + getter, without relaxing the `Result` prohibition for them.
5. **Callback panic terminates the process**: isomorphic with Part 5's "panic has no task-level isolation"; isolation needs in embedded scenarios belong to the implementation layer (out-of-process isolation), not the language contract.
6. **Embedding (reverse) is non-committed**: avoids promising a full embedding API before implementation; only the ABI symbols and the minimal initialization order are frozen.

## Appendix B: Name-Settlement Status

| Matter | Status |
| --- | --- |
| `xdk.sys` / `xdk.net` package ownership | **Settled** (Part 6 §4.7: net independent, sys not split) |
| `@unsafe` controlled entries | **Settled** (this part §8) |
| `xrt_*` symbol prefix | **Frozen** (§6.1, ABI commitment; changes require a major version) |
| Dedicated-executor companion API form | **Aligned** (§7.3 + Part 6 §4.2 decision) |
| Hosts of `@ffiEntry` / `@lease` / `@errorCode` / `@blocking` | **Settled**: binding-layer declaration files (the FFI declaration block of `xdk.sys`); the language grammar introduces none of these annotations |
| Grammar landing point of `layout(c)` | **Settled**: `layout(c) struct` syntax inside binding-layer declaration files; the language grammar introduces no `layout` keyword |

This table has no pending items: all are settled. Changes follow the version process (settlements → rejections/non-commitments require a record).
