# XNull Specification, Part 3: Memory Management

> **Translation notice**: This is an English translation of the normative Chinese specification
> 《XNull 解决方案 第 3 部分：内存管理》v3.0.0. The Chinese original prevails in case of any
> divergence. Translation version follows the original's version number.

| Item | Value |
| --- | --- |
| Document ID | Part 3 (S3) |
| Document Version | 3.0.0 |
| Specification Status | Normative (approved 2026-11-05) |
| Release Date | 2026-11-05 |
| Applies To | XNull compiler, runtime, LSP, test suites |
| Companion Documents | *Core Syntax* v3.3.0; *Object Programming* v3.3.0 (versions track the current edition; see the specification index) |

Version rules: file names retain the full version number; new versions are saved as new files and never overwrite old ones. The revision number covers semantic-preserving clarifications, the minor version covers backward-compatible additions, and the major version covers breaking changes. Any normative clause change must be synchronized with acceptance items and implementation boundaries.

This document was reconstructed from the clauses referenced by *Core Syntax*, *Object Programming*, and the capability-boundaries document; the original v3.0.0 file was lost, and the reconstruction keeps the referenced section numbers (§5, §9–11, §13–15, §17–19, §20, §25–26) resolvable. Where this document conflicts with Parts 1 and 2, Parts 1 and 2 prevail, and any conflict found in this document must be corrected in sync. **This reconstructed version was confirmed as normative by full review on 2026-11-05** — "reconstructed" describes the file's provenance only and does not indicate draft status.

## Decision Summary

- XNull employs three memory strategies: stack (inline / stack values), ARC (reference counting), and GC (mark–sweep). The strategy is adjudicated by the compiler under deterministic rules; it is not a source-level type.
- `struct` and simple enumerations are pure values, stored inline, and never enter ARC/GC; `class` and `singleton` are the subjects of strategy adjudication; data-enumeration cases are fixed GC global roots.
- The invariants of the mixed reference graph are defined by Part 2 §15.6; this document defines the runtime implementation contract and acceptance method.
- The language semantics of `Result` are those of a value type; the current implementation represents it as a GC box, and an inline ABI is an explicit optimization direction — no performance claims may be made before inlining lands.
- Scalar arrays are stored by actual element width; raw byte regions are scan-free. Containers holding references are GC-tracked.
- The language does not promise hard real-time behavior: GC rendezvous, ARC atomic operations, and reclamation latency carry no worst-case timing contracts; hard real-time control layers are outside the language's scope.
- Resource release and memory reclamation are two separate responsibilities. Files, handles, locks, and task groups must be closed explicitly at the point of use; `deinit` is only a last-resort fallback.
- FFI is a contract-bound boundary: handle and call leases are defined in §19 of this document; no promise of direct calls to arbitrary native functions is made.

## 0. Specification Foundations

### 0.1 Scope

This document defines XNull's memory management: the memory model, strategy adjudication and propagation, escape analysis, the ARC/GC implementation contracts, finalization order, weak references, tasks and cross-thread sharing, cleanup responsibilities, FFI ownership, optimization directions, acceptance, and application boundaries.

This document does **not** define:

- Object kinds, inheritance, protocols, and dispatch; see Part 2.
- The syntax and propagation semantics of `defer` / `errdefer`; see Part 1 §10.
- XDK package structure, type names, and API shapes; `xdk.*` names appearing in this document are governed by Part 6 (XDK), which is not redefined here.
- Error observation, cancellation, and timeouts; see the error-handling specification.
- XDK package APIs; see the XDK specification.
- Concrete allocator algorithms or GC generational/incremental policies; implementations may choose freely, but must satisfy this document's invariants.

### 0.2 Relationship to Parts 1 and 2

Part 2 §15 defines the source-observable semantics of memory strategies (the strategy decision table, escape classification, layout, mixed-graph invariants, `deinit` order, weak-reference rules). On top of that, this document defines:

- The data structures and management actions the runtime must provide;
- The propagation rules for strategies across call boundaries, containers, closures, and tasks;
- The cleanup-responsibility and resource-handle model;
- Optimization directions and the semantic boundaries they must not alter;
- Acceptance items and the explicitly non-promised boundaries.

Where the two conflict, Part 2's definition of source-observable semantics prevails; this document supplements the implementation contract.

### 0.3 Normative Language

**MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used with RFC 2119 semantics. The release gates of Part 2 §16 (BND-01..15) also bind this document; the acceptance items in §25 of this document are the supplementary memory-dimension gates.

### 0.4 Determinism

The same source program, the same implementation version, and the same compilation options MUST produce identical strategy adjudications, layout decisions, vtable slots, and run results. Reclamation timing is not required to be deterministic, but the observable consequences of reclamation (`deinit` order, weak-slot nulling) MUST satisfy this document's ordering rules.

## 1. Memory Model Overview

| Data | Storage | Management |
| --- | --- | --- |
| Value-type scalars, simple enumerations | Inline (variable slots, field slots, array elements) | None; die with their storage slot |
| `struct` values | Inline, copied by value | None; copying triggers no reclamation |
| Stack-allocated class objects (escape analysis passed) | Stack frame | Die with the frame; no action beyond the `deinit` obligation |
| ARC class objects | Heap | Reference counting; finalized at zero |
| GC class objects, data-enumeration cases, singletons | Heap | Mark–sweep; swept when unreachable |
| Closure objects with env and cells | Heap | GC |
| `Any` boxes | Heap | GC |
| `Result` (current implementation) | GC box | GC; inline ABI see §20 |

Invariants:

1. Source code contains no addresses, pointers, or manual release; all reclamation is performed by compiler-inserted management actions and the runtime.
2. Every strong reference either increments an ARC count or is GC-tracked (Part 2 §15.6, invariant 1).
3. Weak references neither increment counts nor prevent reclamation; when the target dies they are set to `null`.
4. Stack allocation is an optimization; it never alters reference semantics or object identity.

## 2. Allocation Header and Layout

Heap objects uniformly carry the allocation header (Part 2 §15.3):

- Object kind (ARC / GC);
- Type descriptor;
- ARC count or GC mark word;
- Scan information (offset table or bitmap of reference-bearing fields).

Contract:

- The type descriptor MUST support dynamic type checks for `is` / `as`, protocol-conformance checks, and `Any` unboxing checks.
- When an ARC object holds a GC reference, it MUST be registered as a GC scan object; when a GC object holds an ARC reference, the reference MUST be released during sweep (Part 2 §15.6, invariants 2 and 3).
- For classes implementing a protocol, the payload begins with the protocol vtable pointer; classes not implementing a protocol have no such pointer.
- Stack objects have no allocation header; the compiler MUST retain type information where dynamic type checks may be needed, and may omit it when statically provable.
- Fields are 8-byte aligned; scalar value fields occupy one 8-byte slot. More compact packing is an optimization direction (§20) and is not promised at present.

## 3. Value Types, Boxing, and Pure-Value Data

- `struct` values are stored inline; assignment, argument passing, returns, and container insertion all copy. Copying triggers no ARC/GC actions and calls no `deinit`.
- Simple enumerations are inline as `Int`; data-enumeration cases are GC objects, constructed at program start, resident as global roots.
- Value types entering `Any` MUST be boxed; the box is GC-managed, and unboxing checks the boxed type.
- `struct` fields may only be value fields satisfying Part 2 §3.2; the runtime need not provide any scanning, counting, or finalization actions for structs.
- Tuples are built-in value types, stored inline; tuples of all-value elements require zero management; tuples with reference elements are scanned per slot, and the owning class falls under GC per Part 2 §15.1 item 7.
- Classes with `Result` fields are analyzed as GC under the current implementation (`Result` is a GC box); once `Result` inlining lands, re-adjudication follows Part 2 §15.1.

## 4. Strategy Adjudication

The adjudication rules are governed by the strategy table in Part 2 §15.1. This document supplements the implementation contract:

- Adjudication happens after monomorphization and before code generation; the decision MUST be dumpable (a diagnostic option) for acceptance reproducibility.
- All adjudication inputs come from the monomorphized source structure: kind, field type graph, reference-cycle analysis, presence of `deinit`, `self` capture, and escape classification. Source code MUST NOT express reference strength or reclamation strategy.
- `@arc` / `@gc` are implementation-internal annotations (Part 2 §15.1.2): they MUST NOT appear in source code, are reserved for implementation previews, and are non-committal entry points.
- Adjudication MUST be conservative: when acyclicity cannot be proven or fields are not concrete, the object falls under GC; handing an unanalyzable object to ARC is FORBIDDEN.
- An unsatisfied `@arc` condition is a compile error; silent fallback to GC is FORBIDDEN (Part 2, BND-10).

## 5. Strategy Graph and Strategy Propagation

Nodes of the strategy graph are types (monomorphized instances) and storage locations (locals, fields, statics/top-level, container elements, closure environments); edges are strong references.

Propagation rules:

| Edge | Propagation |
| --- | --- |
| ARC object → ARC object field | Count management; target field is ARC |
| ARC object → GC object field | ARC object registers as a scan object; field is GC-tracked |
| GC object → ARC reference field | GC keeps the target reachable; release at sweep |
| Anywhere → field of `Any` / `Object` / protocol / un-monomorphized generic | Owner analyzed as GC |
| Container element is a reference | Container object is GC; elements are tracked |
| Closure env captures an ARC reference | Env is a GC block; releasing the env releases the reference |
| Static / top-level fields, singleton fields | Global roots; ARC is retained, GC is tracked |

Rules:

- Strategies are adjudicated per node independently and then propagated per the table above; propagation MUST NOT alter a node's own adjudication.
- When at least one GC node appears in a reference cycle, the cycle is reclaimed by GC; all-ARC strong-reference cycles MUST be detected by memory analysis: the automatic strategy re-decides to GC, and an `@arc` strategy produces a compile error.
- Protocol-typed and `Any` fields put the owner under GC (Part 2 §15.1 item 7).
- The strategy graph MUST have no unadjudicated nodes; an unadjudicated node before code generation is a compiler-internal error.

## 6. Escape Analysis and Stack Allocation

Escape classification and conditions are governed by Part 2 §15.2. Implementation contract:

- `none`-class objects may be stack-allocated; stack allocation MUST preserve object identity and reference semantics.
- `return`-class objects are promoted to ARC; where a field already requires GC, GC is retained.
- `other`-class objects are promoted to GC.
- When analysis is incomplete or invisible boundaries exist (FFI, XDK calls, task submission), the object MUST be treated as escaping.
- When a stack object's `self` is captured by a closure, enters a container, or is published, it MUST be moved to heap allocation; copying a published object is FORBIDDEN.
- Escape analysis results never alter language semantics; no source-observable allocation-behavior contract is provided.

## 7. Reference Counting and Weak-Reference Foundations

- ARC counts MUST be atomic under concurrency; an implementation may use non-atomic counts in compilation units proven concurrency-free, but MUST NOT mix the two count formats across compilation units.
- retain / release MUST be paired; release to zero triggers the finalization chain (§14).
- Weak references are not a language feature: neither XNull source nor the XDK public API provides a weak-reference concept. The weak table is an internal runtime mechanism whose entry points are open only to the FFI contract layer and the runtime interior (§19, §22).
- Weak references are managed by the runtime's weak table: before the target is finalized, its slots are cleared and set to `null`; weak reads and writes MUST be atomic, and reading a finalized target is FORBIDDEN.
- The weak table may be implemented as per-object inline side tables or a global side table; the implementation MUST NOT hold strong references through the weak table.
- Assignment, nulling, and clearing of runtime-internal weak slots are weak-table operations and do not modify counts.

## 8. Mark–Sweep Foundations

- GC uses mark–sweep; implementations may use generational, incremental, or concurrent policies, but MUST keep the root set and write barriers correct.
- Root set: stack slots, top-level/static fields, singletons, data-enumeration cases, reachable closure envs, task external roots, and the ARC scan list.
- Reclamation may trigger at allocation points or safepoints; the runtime MUST ensure mutators rendezvous with GC only at safepoints.
- Sweep MUST satisfy Part 2 §15.6 invariants 3 and 6: dead GC objects release their ARC references; references of live objects remain valid.
- GC does not guarantee `deinit` execution at process exit (Part 2 §15.5).

## 9. Representation of Result

- The language semantics of `Result<T,E>` are those of a value type (Part 1 §2.1, §10.1).
- The current implementation represents it as a GC box: every `Ok` / `Err` construction allocates a box object holding the discriminator, the `T` value, and the `E` value.
- The resulting current boundaries (consistent with Part 1 §12):
  - `Result` follows value semantics in arithmetic and copy-semantics checks; runtime identity is not exposed to source code.
  - Classes with `Result` fields are analyzed as GC; `@arc` cannot be applied to classes with `Result` fields.
  - The `Result` box does not enter `Result`'s `==` / `===` (the language provides neither); box identity is not exposed.
- An inline ABI for `Result` is an explicit optimization direction (§20); until it lands, this document makes no performance claims regarding `Result`.

## 10. Memory of Containers and Arrays

- `T[]` is a GC object: allocation header + length + element region.
  - Scalar or pure-value elements (value types, simple enumerations, `struct`, all-value tuples) are stored at actual element width, tightly packed; the element region is a raw byte region and is scan-free.
  - Reference elements are stored as pointer slots; the element region is registered for scanning.
  - `struct` elements are inlined whole into the element region; nested `struct`s inline recursively.
- `List<T>`: a GC object with length, capacity, and an element buffer; growth copies the element region. Element scanning rules match `T[]`.
- `Map<K,V>` / `Set<T>`: GC objects with a hash-bucket array and entry storage; buckets and entries holding references are registered for scanning. Key-value layout is an implementation detail.
- `String` / `Text`: GC objects, header + UTF-8 byte region; the byte region is scan-free.
- `Bytes`: GC object, header + mutable byte region; scan-free.
- `StringBuilder`: GC object with a mutable buffer; the buffer is scan-free.
- On container shrink (`remove` / `clear`), removed reference elements MUST be released immediately or within the operation (GC elements may await sweep, but ARC elements MUST be released).
- The container object itself is always GC; its strategy never changes because elements happen to be pure values. Scan-free pure-value element regions are a performance property, not a strategy change.

## 11. Tasks and Cross-Thread Sharing

- When a closure enters `xdk.tasks`, its env is registered as an external root; for the task's lifetime the runtime guarantees reachability of the env and its capture graph.
- On task dispose, the external root is removed; afterwards the env is reclaimed under ordinary GC rules.
- ARC objects passed across tasks are managed by atomic counts; GC objects are protected by the root set and safepoints.
- Concurrent access to fields and captured variables is not synchronized; data races are program errors: the runtime performs no detection and makes no guarantees about the results (non-committed; rationale: no race detection; consequence: programs with data races receive no behavioral guarantees). Synchronization responsibility is explicit at the point of use (Part 2 §15.9).
- `@Sendable` is retained in v3.0.0 but not enforced; the runtime performs no data-race checks.
- A singleton captured by a task is the same global instance; it is not copied.
- Establishing and tearing down cross-thread references MUST go through runtime-provided publication points; implementations MUST NOT allow mutators to swap heap references without synchronization.

### 11.4 Explicit Boundaries of Concurrency Capability

Task-closure cross-thread liveness does not imply the following capabilities; until companion specifications land, implementations and documentation MUST NOT claim them:

- Structured concurrency (task trees, scoped cancellation, exception aggregation);
- Automatic cancellation propagation;
- Data-race detection;
- Priority, fairness, or latency contracts.

These capabilities belong to the task specification and the error-handling specification.

## 12. Write Barriers and Safepoints

- Write barriers for GC implementations MUST cover: reference writes to GC object fields, and maintenance of the ARC scan list.
- Compilation units implementing `@arc` need no write barriers; mixed write points MUST insert barriers.
- Safepoints MUST cover: allocation points, call boundaries, and (at the implementation's option) loop back-edges; the runtime MUST NOT assume a mutator will reach any point beyond safepoints.
- Stack scanning MUST occur at safepoints; conservative scanning is permitted only as an implementation fallback and MUST NOT cause premature release or dangling references (Part 2 §15.6 correctness conditions).

## 13. Reclamation Rendezvous and Latency Boundaries

- GC rendezvous (STW or safepoint waiting), marking, sweeping, ARC atomic operations, and user `deinit` all carry no worst-case timing contracts.
- XNull therefore does not promise hard real time; strict-deadline layers such as motor servo control and safety control are outside the language's promise (capability-boundaries document §4.3, §6).
- Implementations may offer reclamation tuning options (trigger thresholds, incremental step sizes); these options do not constitute latency contracts.
- Code regions requiring "uninterrupted reclamation" can only be arranged through the task model and external design; the language provides no source syntax to disable reclamation.

## 14. ARC Finalization

When the ARC count reaches zero, execution follows Part 2 §6.5 / §15.7:

1. Clear weak references (weak-table removal, weak slots set to `null`).
2. Run the derived-class `deinit`.
3. Run the superclass `deinit` chain (when an explicit `super.deinit()` takes over the remaining chain, the compiler no longer calls it automatically).
4. Release remaining reference fields: ARC fields are released; GC fields are unregistered from scanning.
5. Reclaim the memory.

Contract:

- Fields remain valid inside `deinit`; the runtime releases reference fields only after the chain completes.
- Weak fields inside `deinit` may already be `null`; the runtime MUST NOT release a nulled field twice.
- The finalization chain MUST NOT re-enter the allocation-header state; resurrecting `self` inside `deinit` (storing it into globals, containers, closures, or returning it) is FORBIDDEN.
- A panic on the finalization chain terminates the process directly; the remaining cleanup is not guaranteed.

## 15. GC Finalization

- GC objects are swept when unreachable; `deinit` runs during the sweep phase at an indeterminate time.
- Sweep order: after marking, for each dead object, release its ARC references first, then call `deinit` (if declared), then reclaim memory.
- The `deinit` call order among multiple dead objects within one sweep cycle is an implementation detail; `deinit` MUST NOT depend on the `deinit` order of other objects (Part 2 §6.6).
- Mutual references among dead objects do not constitute resurrection; dead objects MUST NOT be re-marked reachable during sweep.
- Storing `self` into external state inside `deinit` is a program error; on detecting resurrection the runtime MUST terminate the process.

## 16. The Weak-Reference Table

The weak table is an internal runtime mechanism: the language and the XDK public API do not expose weak references (Part 2 §15.8); the entries in this section serve only the FFI contract layer (§19) and the runtime interior (§22).

- The weak table manages the mapping of all weak slots to target objects.
- Before a target enters the finalization chain, the runtime clears all of its weak slots.
- Weak-table operations (bind, read, clear) MUST be atomic; concurrent clearing and reading MUST NOT observe a finalized target.
- The weak table MUST NOT prevent target reclamation; cleared slots MUST be reusable.
- Weak references may only point to identity-bearing reference types (Part 2 §15.8); `weak` on a value type is a compile error.

## 17. The Cleanup-Responsibility Model

- Memory reclamation and resource release are two separate responsibilities; ARC/GC handles memory only — not files, connections, locks, transactions, sockets, task groups, or other external resources.
- External resources MUST be closed explicitly at the point of use: the `defer input.close();` pattern (Part 1 §10.3).
- `deinit` is only the last-resort fallback: GC timing is indeterminate, and process exit and panic do not guarantee `deinit` (Part 2 §6.4).
- `goto`, `throw`, and process exit do not run `defer`; code relying on structured cleanup MUST NOT use unstructured jumps (Part 1 §6.10, §10.4).
- When a cleanup call returns a `Result`, it MUST be handled explicitly; `@mustUse` applies inside `defer` bodies as well.
- The language provides no implicit cleanup mechanism beyond the finalization guarantee chain; cleanup order is determined by the source-level `defer` registration order (LIFO).

## 18. Resource Handles and Point-of-Use Release

- Resource types provided by the XDK (files, sockets, task groups, etc.) MUST design their release entry points as explicit methods and MUST guarantee that repeated closes are safe.
- Handle types MUST NOT rely on `deinit` as the only release path.
- Close failures are reported through `Result`; the caller decides whether to observe them.
- Handles MUST NOT be shared across tasks without synchronization; where sharing is needed, the caller synchronizes or transfers ownership (the transfer mechanism is defined by the task specification).
- This section constrains the XDK resource APIs; concrete types and signatures are defined by the XDK specification.

## 19. FFI and Cross-Language Ownership

- FFI is a contract-bound boundary, not direct calls to arbitrary native functions (capability-boundaries document §6).
- Data crossing the boundary MUST satisfy one of the following:
  - Value transfer: scalars, `struct` (layout verified compatible), or marshaled copies;
  - Handle transfer: opaque handle + explicit lifetime contract;
  - Buffer transfer: the raw byte regions of `Bytes` / scalar arrays, kept alive by the runtime for the boundary duration.
- Source code has no `extern` or `unsafe` blocks; FFI entry points are defined by the XDK / FFI specifications, and the call lease (who holds, when to release) MUST be declared explicitly.
- XNull object references MUST NOT be used as cross-language addresses; ARC/GC do not manage objects in another language.
- Callbacks entering XNull require an explicit trampoline and a lifetime contract (Part 2 §14.5); the trampoline MUST register the env as a root for the call duration.
- Layout compatibility MUST be verified per type; XNull field slots are not assumed identical to the target ABI (capability-boundaries document §6).
- The complete FFI specification is Part 7; this section is its memory-dimension precondition, and Part 7 has been completed on this basis (calling forms, layout verification, ABI naming, error codes).

## 20. Optimization Directions

The following optimizations are evolution directions of the implementation baseline; each MUST land separately under the acceptance method of §25 and MUST NOT be generalized into whole-program performance claims:

| Optimization | Content | Semantics that MUST NOT change |
| --- | --- | --- |
| Pure-value zero management | `struct` and simple enumerations cost zero management | Value-copy semantics |
| Scan-free reference-free payloads | Objects with all-pure-value fields and raw byte regions never enter scanning | Reference semantics, identity |
| `Result` inlining | Discriminant + payload inlined into the storage slot, eliminating box allocation | Value semantics, `@mustUse`, panic paths |
| Allocation elimination | Non-escaping class objects, non-escaping closures and cells stack-allocated | Object identity, capture-sharing semantics |
| Compact layout | Field packing, width compression | Observable behavior of 8-byte slot semantics (currently no source-observable difference, but ABI changes require acceptance) |
| ARC de-atomization | Non-atomic counts in compilation units proven concurrency-free | Weak-reference atomicity, cross-unit consistency |

Constraints:

- Optimizations MUST NOT change observable behavior: identity, evaluation order, panic paths, and the `deinit` ordering constraints.
- Shared cells and observable capture semantics MUST NOT be altered by optimization (capability-boundaries document §7).
- When each optimization lands, the corresponding implementation-boundary clauses of Parts 1 and 2 MUST be updated.

## 21. Diagnostics and Observation

Compile-time reporting is REQUIRED (consistent with Part 2 §15.10): uncertain or cyclic `@arc` fields, residual type parameters after monomorphization, recursive struct values, struct reference fields, `weak` on non-identity types, private-field violations, `self` escaping before construction completes, `final` field assignment violations, and so on.

Runtime reporting is REQUIRED: allocation failure, stack overflow, null dereference, subscript out of range, `as` failure, division by zero, shift out of range, and explicit `throw`. The report format is printing diagnostics and the call stack, then terminating the process without unwinding.

`xdk.runtime` may provide allocation statistics, GC metrics, live-object dumps, and leak diagnostics; these are tooling capabilities, not language semantics.

## 22. Minimal Runtime ABI Contract

The runtime MUST provide the following entries (naming is an implementation detail; stable cross-FFI naming is defined by the FFI specification):

- Allocation: `alloc(desc, size)` — allocate a heap object and install the allocation header;
- Counting: `retain(obj)`, `release(obj)` — atomic counting and finalization triggering;
- Weak table: `weak_bind(slot, obj)`, `weak_read(slot)`, `weak_clear(slot)`;
- GC: `write_barrier(obj, field, value)`, `register_root` / `unregister_root`, `safepoint()`;
- Scan registration: scan-information queries (by type descriptor);
- Task roots: `task_root_bind(env)` / `task_root_unbind(env)`.

Compiler-generated code manages memory only through these entries; bypassing the allocation header to manipulate counts or mark bits directly is FORBIDDEN.

## 23. Compilation Options and Configuration

- Memory-related compilation options: strategy-adjudication dump, escape-analysis dump, GC strategy selection (`auto` default / `arc` / `gc`, a settled three-value choice), allocation-statistics switch.
- Options MUST NOT alter language semantics; the observable behavior of the same program under different legal options (except diagnostic output and performance) MUST be identical.
- Options are not part of the language specification; how the project manifest pins options is defined by the project-configuration specification.

## 24. Metrics and Benchmarks

Performance conclusions MUST be grounded in named workloads and metrics:

- Packets per second, per-batch sampling-processing time, connection and task scale;
- p50 / p99 latency, peak memory, pause-duration distributions;
- Allocation rate and GC frequency.

Consistent with the capability-boundaries document §7, this document provides no basis at the current stage for rankings such as "faster overall than Go, Java, Rust, or C++"; the high-performance positioning is established item by item through the acceptance of §25.

## 25. Acceptance

| ID | Verification Point | Pass Condition |
| --- | --- | --- |
| MEM-01 | Strategy adjudication | Every input of the Part 2 §15.1 table yields the correct strategy; decisions are dumpable and reproducible |
| MEM-02 | Strategy and internal annotations | Adjudication inputs come entirely from source structure; `@arc` / `@gc` in source are rejected; internal annotations are preview-only; mixed-graph behavior follows the ARC contract with no silent fallback |
| MEM-03 | Mixed graph | The six invariants of §15.6 hold under stress cases; ARC↔GC mixing has no dangling references, no leaks, no double release |
| MEM-04 | Weak references | Cleared before target finalization; no reading of finalized targets; concurrent clearing is safe |
| MEM-05 | Stack allocation | Stack-allocated `none`-class objects preserve identity and reference semantics; all escape paths are promoted |
| MEM-06 | Containers | Scalar/pure-value element regions are scan-free; reference elements are correctly tracked; references after `clear` follow §10 |
| MEM-07 | Result | Under the current GC-box implementation, box identity is not exposed; classes with `Result` fields are analyzed as GC |
| MEM-08 | Finalization | The ARC-zero chain and the GC sweep order follow §14/§15; resurrection terminates the process |
| MEM-09 | Tasks | Env external-root binding and unbinding are correct; reclaimable after dispose |
| MEM-10 | Cleanup | The `defer` release pattern runs on success, `try` propagation, and error-return paths; fatal-path behavior follows §17 |
| MEM-11 | FFI | Handle transfer and buffer transfer follow the §19 contracts; entry points without declared leases are rejected |
| MEM-12 | Determinism | The same source program, version, and options produce identical strategy adjudications and run results (the memory dimension of DET-01) |
| MEM-13 | Optimizations | When each §20 optimization lands, semantic regression passes; unlanded items MUST NOT be claimed |

Acceptance MUST include positive, negative, and stress cases; negative cases MUST assert specific diagnostics.

## 26. Application Boundaries

Consistent with the capability-boundaries document §6, the memory dimension of this design makes no promises for:

| Goal | Verdict | Reason |
| --- | --- | --- |
| Kernels, drivers, bare metal | Not promised | No source-level address/dereference semantics; no execution contract outside the managed runtime |
| Hardware registers / MMIO | Not promised | No address or dereference semantics |
| Strict hard real time | Not promised | §13: no worst-case timing contracts for reclamation rendezvous and finalization |
| Arbitrary custom allocators, manual release | Not provided | Memory strategy is managed by the compiler and the runtime |
| Shared layout with arbitrary C structs | Not assumed | Requires per-type verification or marshaling (§19) |
| Dynamically loaded/unloaded managed plugins | Excluded from the initial baseline | Closed linking; dynamic modules are a future direction |
| GPU device memory model | Not covered (explicitly rejected) | Requires a separate contract; support only after a dedicated project |

These boundaries cannot be inferred merely from "whether there is a GC"; even code that allocates no objects may encounter GC rendezvous, synchronization blocking, or atomic-operation latency.

## Appendix A: Companion-Specification Synchronization Checklist

When this document is revised, the following specifications MUST be synchronized; until then, the affected clauses are marked "pending synchronization":

| Companion Specification | Clauses to Synchronize | Status |
| --- | --- | --- |
| Error-handling specification | Relation of error observation to the `Result` box implementation; resource-release failure paths | Pending |
| Task specification | Env external-root lifetime; structured concurrency, cancellation, ownership transfer | Pending |
| XDK specification | §18 resource-handle APIs; `xdk.runtime` observation APIs | Pending |
| FFI specification | §19 call leases, trampolines, layout verification | Finalized (Part 7 v1.0.0, normative 2026-11-05) |
| Project-configuration specification | §23 compilation-option pinning | Pending |
| Part 1 §12 / Part 2 §16 | Boundary-clause updates after optimizations such as `Result` inlining and compact layout land | Ongoing |
