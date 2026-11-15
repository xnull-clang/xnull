# XNull Solution Part 3: Memory Management

| Item | Value |
| --- | --- |
| Document number | Part 3 (S3) |
| Document version | 3.2.0 |
| Specification status | Formal |
| Publication date | 2026-11-15 |
| Applies to | XNull language implementations |
| Related parts | Part 1 v3.4.0; Part 2 v3.4.0; Part 4 v1.2.0; Part 5 v1.3.0; Part 7 v2.2.0 |

Version rule: revision numbers are used for clarifications that do not change semantics, minor versions for backward-compatible additions, and major versions for breaking changes. Historical versions are recorded in git.

## Decision Summary

- Three memory strategies: stack (inline/stack values), ARC (reference counting), and GC (unreachable reclamation); the strategy is determined by the compiler according to deterministic rules and is not a source-level type.
- `struct` and simple enums are pure values stored inline and do not enter ARC/GC; `class` and `singleton` are strategy-determined objects; data enum cases are always GC roots.
- Mixed reference graphs MUST satisfy the invariants of §5.
- `Result` is an inline value structure: the discriminant and payload are inline, no box object is allocated, and no identity is exposed.
- Scalar arrays are stored at the element's actual width; scan-free pure-value regions are an optimization and do not change semantics.
- The language does not promise hard real time: there is no worst-case timing contract for reclamation timing or pauses.
- Resource closing and memory reclamation are two separate responsibilities; files, handles, locks, and task groups MUST be explicitly closed at the point of use.
- FFI is a contract-constrained boundary: for handles and call leases, see §19; arbitrary direct calls to native functions are not provided.

## 0. Normative Foundations

### 0.1 Scope

This document specifies XNull memory management: the memory model, strategy determination and propagation, escape analysis, reference counting and GC contracts, finalization order, weak references, tasks and cross-thread sharing, cleanup responsibility, resource handles, FFI ownership, memory safety invariants, and allocation failure.

This document does not specify:

- Object kinds, inheritance, protocols, and dispatch; see Part 2.
- The syntax and propagation semantics of `defer` / `errdefer`; see Part 1, Section 10.
- Library types and API shapes; see Part 6.
- Error observation, cancellation, and timeouts; see Parts 4 and 5.
- Specific allocator algorithms or GC generational/incremental strategies; implementations MAY choose these themselves, but MUST satisfy the invariants of this document.

### 0.2 Relationship to Parts 1 and 2

This document specifies the semantics and runtime contracts of memory management. Part 2 specifies only the observable order of construction, publication, and `deinit` during an object's lifetime. This document specifies:

- The observable semantics and runtime contracts of memory management;
- The rules for propagation of strategies across call boundaries, containers, closures, and tasks;
- The cleanup responsibility and resource handle model;
- The invariants of mixed reference graphs;
- The boundaries that are explicitly not promised.

When the two documents conflict, memory semantics are governed by this document; object model semantics are governed by Part 2.

### 0.3 Normative Language

**MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used with RFC 2119 semantics.

### 0.4 Determinism

The same source program, the same implementation version, and the same compilation options MUST produce the same strategy determinations, layout decisions, and runtime results. Reclamation timing is not required to be deterministic, but the observable results caused by reclamation (`deinit` order, weak references cleared to null) MUST satisfy the ordering rules of this document.

## 1. Memory Model Overview

### 1.1 Terminology

| Term | Meaning |
| --- | --- |
| Object | A reference value with identity; `class`, `singleton`, data enum cases, closures, arrays, containers, `String`, `Any` boxes |
| Value | Data copied by value and without identity, such as scalars, `struct`s, simple enums, tuples, and `Result` |
| Reference | A handle pointing to an object; copying a reference does not copy the object |
| Identity | The uniqueness of an object determined at creation; all references to the same object share the identity |
| Root | A storage location directly reachable by the runtime: stack slots, static/top-level fields, singletons, task roots, the ARC scan list, etc. |
| Reachable | Reachable from a root along strong references |
| Live | Reachable, or currently in use by a finalization/cleanup path |
| Finalization | The `deinit` call and field release; not equivalent to memory reclamation |

### 1.2 Storage Categories

| Data | Storage | Management |
| --- | --- | --- |
| Scalars, simple enums | Inline (variable slots, field slots, array elements) | Unmanaged; dies with the storage slot |
| `struct` values | Inline, copied by value | Unmanaged; copying does not trigger reclamation |
| Stack-allocated class objects | Stack frame | Dies with the frame; subject to §6 |
| ARC class objects | Heap | Reference counted; finalized when the count reaches zero |
| GC class objects, data enum cases, singletons | Heap | GC; reclaimed when unreachable |
| Closure objects and envs, cells | Heap | GC |
| `Any` boxes | Heap | GC |
| `Result` | Inline value structure | Value semantics; no box object allocated |

Invariants:

1. Source code has no addresses, pointers, or manual release; all reclamation is performed by management actions inserted by the compiler and by the runtime.
2. Every strong reference either increments an ARC count or is tracked by the GC (§5 invariant 1).
3. A weak reference does not increment a count and does not prevent reclamation; it is set to `null` when the target dies.
4. Stack allocation is an optimization and does not change reference semantics or object identity.

## 2. Object Representation and Identity

### 2.1 References and Values

- Reference type objects have identity; value types do not have identity.
- Copying a reference creates an alias and does not copy the object; modifications to the object are visible through any alias.
- Copying a value creates an independent copy; modifying the copy does not affect the original value.
- Value types cannot have their address taken, cannot be the target of a weak reference, and cannot be compared for identity with reference types.

### 2.2 Identity and Equality

- `===` compares reference identity; the semantics of `==` are defined by the type (value types compare by value; reference types follow the type's specification).
- Stack allocation, heap allocation, and ARC/GC conversion do not change identity; the same object is still `===` to itself before and after promotion.
- Object identity does not change due to copying references, storing into containers, closure capture, or cross-task publication.
- Value types have no identity; using `===` on value types is treated as `==`.

### 2.3 Dynamic Type and Boxing

- Object representation MUST support dynamic type checks with `is` / `as`, protocol conformance checks, and `Any` unboxing.
- Allocation headers, slot layouts, and vtable layouts are implementation details and do not constitute source-observable semantics.
- Boxing into `Any` produces an independent boxed value; unboxing checks the boxed type and does not change the original value.
- A protocol variable strongly holds the implementing object; the protocol itself does not produce a wrapper object.

### 2.4 Stack Allocation and Identity

- Stack allocation applies only to class objects whose escape analysis result is `none`; stack objects still have identity.
- When a stack object is published, captured by a closure, enters a container or field, or is passed to an unknown function, it MUST be promoted to heap allocation; copying a published object is prohibited.
- Stack objects do not invoke management actions other than `deinit`; classes with a `deinit` are not stack-allocated.

## 3. Value Types, Boxing, and Pure-Value Data

### 3.1 Copy Semantics

- A `struct` value is copied on assignment, argument passing, return, storage in a container, and field initialization; the copy is independent of the original value.
- Simple enums are copied as their underlying integer; data enum cases are objects, and what is copied is the reference.
- Tuples are copied by value; a tuple whose elements are all values can be a `struct` field, while a tuple containing reference elements cannot be a `struct` field.
- Copying a value type does not call `deinit` and does not trigger ARC/GC actions.

### 3.2 Boxing

- A value type entering `Any` MUST be boxed; boxing produces an independent boxed value that retains the original value and type information.
- A reference type entering `Any` wraps the reference and does not copy the object.
- When unboxing `Any` to a concrete type or protocol, the boxed type is checked; failure is fatal (a failed `as`).
- Boxed values do not participate in `===` identity comparison; equality of `Any` follows the type's rules.

### 3.3 Tuples

- A tuple is a built-in value type; a tuple whose elements are all values requires no management; a tuple containing reference elements participates in reclamation scanning by reference.
- A field containing a tuple with reference elements causes its owner to be classified as GC under §4 item 5.
- Tuples do not produce object identity.

### 3.4 Result

- `Result<T,E>` is an inline value structure: the discriminant, `T`, and `E` are stored inline, and no box object is allocated.
- Copying, argument passing, and return follow value semantics; `Result` does not participate in `==` / `===`.
- A class with a `Result` field is analyzed as GC (conservative rule, see §4), but `Result` itself introduces no box identity.

## 4. Strategy Determination

### 4.1 Determination Inputs

Determination is based only on the source structure after monomorphization:

- Type kind (`class` / `singleton` / `struct` / `enum` / protocol);
- Field type graph and reference cycles;
- Whether a `deinit` exists;
- Whether a method captures `self`;
- Escape classification (§6);
- Whether a field contains `Any`, `Object`, a protocol, an unmonomorphized generic, a tuple containing reference elements, or `Result`.

Source code MUST NOT express reference strength or memory strategy.

### 4.2 Determination Table

The strategy is determined in the following order, stopping at the first match:

| Order | Condition | Strategy |
| ---: | --- | --- |
| 1 | `singleton` | GC root |
| 2 | `protocol` | No instances; analyzed as GC |
| 3 | Simple `enum` | Inline integer |
| 4 | Data `enum` | GC |
| 5 | A class strong-reference field contains `Any`, `Object`, a protocol, an unmonomorphized generic, a tuple containing reference elements, or `Result` | GC |
| 6 | Class strong references form a cycle | GC |
| 7 | A class method captures `self`, or the class has a `deinit` | ARC |
| 8 | Class has only value fields | Stack candidate; promoted under §6 after escape |
| 9 | Remaining acyclic class references | ARC |

### 4.3 Conservative Rules

- When acyclicity cannot be proven, fields are not concrete, or an invisible boundary exists, classify as GC; delegating an unanalyzable object to ARC is prohibited.
- When at least one GC node appears in a reference cycle, the cycle is reclaimed by GC; an all-ARC strong reference cycle MUST be reclassified as GC by analysis or rejected.
- Strategy determination MUST be deterministic; the same input, the same version, and the same options MUST produce the same determination.
- A memory strategy annotation appearing in source code is a compile error; determination MUST NOT be changed by source annotations.

### 4.4 Determination Timing

Determination occurs after monomorphization and before code generation; the determination result MAY be dumped for diagnostics, but the dump format is not part of the language semantics.

## 5. Strategy Graph and Strategy Propagation

### 5.1 Nodes and Edges

The nodes of the strategy graph are types (monomorphized instances) and storage locations (locals, fields, static/top-level, container elements, closure environments); the edges are strong references.

### 5.2 Propagation Table

| Edge | Propagation |
| --- | --- |
| ARC object → ARC object field | Count-managed; the target field is managed by ARC |
| ARC object → GC object field | The ARC object is registered as a GC scan object; the field enters GC tracking |
| GC object → ARC reference field | GC keeps the target reachable; the reference is released on reclamation |
| Any location → field containing `Any` / `Object` / protocol / unmonomorphized generic | The owner is analyzed as GC |
| Container element is a reference | The container object is GC; elements are tracked |
| Closure env captures an ARC reference | The env is a GC block; the reference is released when the env is released |
| Static/top-level fields, singleton fields | Roots; ARC references are retained and GC references are tracked |

Rules:

- Strategies are determined independently per node and then propagated according to the table above; propagation MUST NOT change a node's own determination result.
- When at least one GC node appears in a reference cycle, the cycle is reclaimed by GC; an all-ARC strong reference cycle MUST be detected by memory analysis: automatic strategies are reclassified as GC, and explicit strategies report a compile error.
- Protocol-typed fields and `Any` fields cause the owner to enter GC (§4 item 5).
- The strategy graph MUST have no undetermined nodes; an undetermined node before code generation is a compiler internal error.

### 5.3 Mixed Reference Graph Invariants

1. Every strong reference either increments an ARC count or is tracked by the GC; no strong reference exists that is neither counted nor tracked.
2. When an ARC object holds a GC reference, the ARC object is registered as a GC scan object for as long as it is live; the GC treats its GC reference fields as roots.
3. When a GC object holds an ARC reference, the GC marks the ARC target as reachable; the ARC reference is released when the GC object dies.
4. Weak references do not increment a count and do not prevent reclamation; they are cleared when the target dies.
5. A strong reference graph containing a cycle is reclaimed by GC as long as there is at least one GC object; an all-ARC strong reference cycle is avoided or rejected by analysis.
6. When an ARC object is released, its GC references are cleared to avoid dangling; when a GC object is reclaimed, its ARC references are released to avoid leaks.

## 6. Escape Analysis and Stack Allocation

### 6.1 Escape Conditions

An object escapes if any of the following conditions is met:

- It leaves the current function as a return value;
- It is stored into a field, static field, global field, or container;
- It is captured by a closure;
- It is passed to an unknown function, a library boundary, or FFI;
- It is shared across tasks;
- It is assigned to a variable that may escape.

### 6.2 Classification

| Category | Meaning | Allocation |
| --- | --- | --- |
| `none` | Only local reads, field reads/writes, and conditional use | May be stack-allocated |
| `return` | Leaves only as a return value | Promoted to ARC; remains GC if fields already require GC |
| `other` | Stored into a container/field, captured by a closure, passed as an argument, reassigned | Promoted to GC |

### 6.3 Promotion

- When analysis is incomplete or an invisible boundary exists (FFI, library calls, task submission), it MUST be treated as an escape.
- When a stack object is captured by a closure, enters a container, or is published, it MUST be changed to heap allocation; copying a published object is prohibited.
- Promotion MUST NOT change object identity, reference relationships, or `===` results.
- Classes with a `deinit` are not stack-allocated.

### 6.4 Analysis Boundaries

Escape analysis results do not change language semantics; no source-observable allocation behavior contract is provided. Stack allocation is an optimization, not source-observable behavior.

## 7. Reference Counting Contract

### 7.1 Strong References

- An ARC object is finalized after the last strong reference disappears; the object remains valid until finalization.
- Strong references MUST be paired: increments and releases correspond one-to-one; a double release or an omission is a runtime error.
- ARC references in reference fields, container elements, and closure environments all count as strong references.
- Copying a reference MUST increment the count; overwriting a reference field MUST first release the old value and then write the new value.

### 7.2 Atomicity

- ARC counts MUST be atomic under concurrency; an implementation MAY use non-atomic counts within a compilation unit where the absence of concurrency is proven, but MUST NOT mix the two across units.
- Weak reference operations MUST be atomic; concurrent clearing and reads MUST NOT observe an already-finalized target.
- Atomic counts do not change source-observable semantics; count operations are not exposed.

### 7.3 Cycles

- An all-ARC strong reference cycle MUST NOT be reclaimed by ARC alone; strategy determination MUST reclassify it as GC or reject it.
- A cycle containing a GC node is reclaimed by GC.
- Weak references do not participate in a cycle's strong reference count.

## 8. GC Contract

### 8.1 Root Set

The root set includes:

- Stack slots;
- Top-level/static fields;
- Singletons;
- Data enum cases;
- Closure environments (reachable ones);
- Task external roots;
- The ARC scan list.

### 8.2 Reachability and Reclamation

- GC objects are reclaimed after they become unreachable; reclamation timing is nondeterministic, and source code MUST NOT depend on it.
- A dead GC object MUST release its ARC references; targets referenced by live objects MUST remain valid.
- Unreachable objects MUST eventually be reclaimed, including cyclic references; they MUST NOT leak.
- The GC MUST NOT reclaim objects still reachable from roots or strong references.

### 8.3 Finalization

- A GC object enters finalization when it becomes unreachable; `deinit` is called during the reclamation phase, at an unspecified time.
- For finalization order, see §15.
- Mutual references among dead objects do not constitute resurrection; a dead object MUST NOT be marked reachable again during reclamation.
- Storing `self` into external state from `deinit` is a program error; if the runtime detects resurrection behavior, it MUST terminate the process.

### 8.4 Implementation Freedom

An implementation MAY use mark-sweep, generational, incremental, or concurrent strategies, but the root set and write barriers MUST remain correct; these strategies do not change source-observable semantics.

## 9. Representation of Result

- `Result<T,E>` is an inline value structure: the discriminant, `T`, and `E` are stored inline, no box object is allocated, and no object identity is exposed.
- Copying, argument passing, and return follow value semantics; `Result` does not participate in `==` / `===` (the language does not provide them).
- A class with a `Result` field is analyzed as GC (conservative rule, see §4), but `Result` itself introduces no box identity.
- The performance characteristics of `Result` are not guaranteed; implementations MUST NOT expose its representation through reflection or `===`.

## 10. Containers and Strings

### 10.1 Arrays

- `T[]` is a GC object: length + element region; the allocation header is an implementation detail.
- Scalar or pure-value elements are stored at the element's actual width, and pure-value regions are scan-free; reference elements are stored by reference and participate in reclamation scanning.
- `struct` elements are inlined in full within the element region; nested `struct`s are inlined recursively.
- The array object itself is always GC; its strategy is not changed because all elements are pure values.
- When an array element assignment overwrites a reference, the old reference is released under §7 or, for GC, left to be reclaimed.

### 10.2 Library Containers

- Library containers (lists, maps, sets, etc.) are GC objects; references in element regions/buckets/entries are managed under §7.
- The lifetimes of elements across growth, clearing, and removal are defined by the library API; on the memory side, removed ARC elements MUST be released under §7, while GC elements await reclamation.
- The container object itself is always GC; it is not reclassified as ARC even when all elements are pure values.
- Containers can form intermediary cycles (a container holds an element and the element holds the container); these are reclaimed by GC.

### 10.3 Built-in String and Library Text/Byte Types

- `String` is a built-in GC object: header + UTF-8 byte region; the byte region is scan-free.
- Library text/byte types (such as `Text` / `Bytes` / mutable string builders) are GC objects; byte regions/buffers are scan-free.
- Mutable buffers MUST NOT be shared; copy semantics are defined by the library API.
- These objects are not reclassified as ARC because their contents are pure bytes.

### 10.4 Element Lifetimes

- The lifetime of a container element is governed by the container that holds it; when the container releases/clears/removes an element, it handles it according to the element's strategy.
- When a container element is a reference, reading copies the reference and does not copy the object.
- When a container element is a value type, reading copies the value; modifying the copy does not affect the container.

### 10.5 Closure Environments

- A closure object is a GC object; captured variables are stored in the env and in cells.
- Captures share cells by reference; when multiple closures capture the same variable, they share the same cell, and modifications are visible to each other.
- The env lives as long as the closure is reachable; after the closure becomes unreachable, the env and cells may be reclaimed.
- When a reference type is captured, the env holds that reference; when a value type is captured, the cell stores the value.
- When a closure enters a task, the env is registered as an external root (§11).

## 11. Tasks and Cross-Thread Sharing

### 11.1 Publication

- References shared across tasks MUST be fully initialized before the publication point; after publication they are visible to other tasks.
- When an object is promoted from stack allocation to heap allocation, or reclassified from ARC to GC, its identity and reference relationships do not change.
- A task closure env is registered as an external root for the lifetime of the task and is unregistered when the task is finalized.

### 11.2 Concurrent Access

- ARC counts MUST be atomic under concurrency; the GC MUST scan the root set at safe points.
- Concurrent reads and writes of object fields are not synchronized; data races are program errors, the runtime does not detect them, and results are not guaranteed in any way.
- When synchronization is needed, use the synchronization primitives of Part 5; synchronization responsibility is explicit at the point of use.

### 11.3 Task Finalization

- Task finalization includes: the closure returns, finalization with `Err`, and finalization after cancellation.
- Group shutdown MUST wait for all tasks to finalize, and then unregister the env external root.
- A panic inside a task terminates the entire process; there is no task-level isolation.

## 12. Concurrency, Publication, and Reclamation Timing

- ARC counts MUST be atomic under concurrency; GC root scanning is performed at safe points.
- References shared across tasks MUST be fully initialized before the publication point; after publication they are visible to other tasks.
- When an object is promoted from stack allocation to heap allocation, or reclassified from ARC to GC, its identity and reference relationships do not change.
- Data races are program errors; the runtime does not detect them, and results are not guaranteed in any way.
- For reclamation timing and pauses, see §13.

## 13. Reclamation Timing and Pauses

- Reclamation timing is nondeterministic; source code MUST NOT depend on the exact moment of `deinit` or weak reference clearing.
- No worst-case pause time is promised, and no hard real-time contract is provided.
- Implementations MAY choose their pause strategy; pauses MUST NOT change object identity, reference relationships, or `deinit` order.

## 14. ARC Finalization

When the ARC count reaches zero, execution follows the order in Part 2, 6.4 / 14.2:

1. Clear weak references (set to `null`).
2. Execute the derived class `deinit`.
3. Execute the base class `deinit` chain (when an explicit `super.deinit()` takes over the remaining chain, the compiler no longer calls it automatically).
4. Release remaining reference fields.
5. Reclaim memory.

Contract:

- Fields are still valid inside `deinit`; the runtime releases reference fields only after the chain completes.
- Weak fields in `deinit` may already be `null`; the runtime MUST NOT release a field that has already been set to `null` again.
- The finalization chain MUST NOT re-enter the reclamation state; resurrection of `self` inside `deinit` is prohibited (storing it into a global, container, closure, or returning it).
- A panic in the finalization chain terminates the process directly, and the remaining cleanup is not guaranteed.

## 15. GC Finalization

- A GC object enters reclamation when it becomes unreachable; `deinit` is called during the reclamation phase, at an unspecified time.
- Reclamation order: after entering the reclamation phase, `deinit` is first called on dead objects (if declared), and after the `deinit` chain completes, their ARC references are released, and finally memory is reclaimed.
- The order in which `deinit` is called for multiple dead objects within the same reclamation cycle is an implementation detail; a `deinit` MUST NOT depend on the `deinit` order of other objects (Part 2, 6.6).
- Mutual references among dead objects do not constitute resurrection; a dead object MUST NOT be marked reachable again during reclamation.
- Storing `self` into external state from `deinit` is a program error; if the runtime detects resurrection behavior, it MUST terminate the process.

## 16. Weak References

- The language and public library APIs do not provide weak references; weak references are an internal runtime mechanism, open only to the FFI contract layer and runtime internals.
- A weak reference does not increment a count and does not prevent reclamation; it is cleared before the target is finalized.
- Weak reference reads and writes MUST be atomic; an already-finalized target MUST NOT be read.
- A weak reference may only point to a reference type with identity; a weak reference to a value type is a compile error.

## 17. Cleanup Responsibility Model

- Memory reclamation is the responsibility of the runtime; resource closing is explicitly the responsibility of the point of use.
- For the syntax and execution order of `defer` / `errdefer`, see Part 1 §10.3; this document specifies only resource responsibility.
- `goto`, `throw`, and process exit do not execute `defer`; fatal paths do not guarantee cleanup.
- Cleanup paths themselves MUST NOT depend on `deinit`; `deinit` is only a last-resort fallback.

## 18. Resource Handles and Close at Point of Use

- Resource types provided by libraries (files, sockets, task groups, etc.) MUST design their close entry point as an explicit method and MUST ensure that repeated close is safe.
- A close failure does not mean the resource is still open: cleanup actions are irreversible, and `Result` only reports diagnostics.
- Handles MUST NOT rely on `deinit` as the only close path.
- The lifetime of a handle is determined by the object or scope that holds it; sharing a handle across tasks requires synchronization.
- For concrete types and signatures, see Part 6.

## 19. FFI and Cross-Language Ownership

FFI is a contract-constrained boundary, not a direct call to arbitrary native functions.

- Only three forms are permitted across the boundary: value passing, handle passing, and buffer passing.
- Handles are held by the native side; the XNull side holds only opaque handles, with an explicit close entry point.
- Call leases are declared per parameter: lend (`.borrow`), transfer (`.transfer`), reclaim (`.reclaim`).
- Buffers MUST remain address-stable for the duration of the boundary; out-of-bounds writes are contract violations.
- Layout compatibility MUST be verified per type; XNull field slots and the target ABI are not identical by default.
- For the complete contract, see Part 7, Appendix A.

## 20. Diagnostics and Observability

The compiler MUST report: strategy determination cannot be completed, recursive struct values or struct values containing reference fields, residual generic type parameters, source code using memory strategy annotations, and `self` escaping before construction completes.

The runtime MUST report: allocation failure, stack overflow, null reference dereference, index out of bounds, failed `as`, division by zero, shift out of bounds, and explicit `throw`.

The runtime library MAY provide allocation statistics, GC metrics, live object dumps, and leak diagnostics; these are tool capabilities, not language semantics.

## 21. Memory Safety Invariants

1. **No dangling**: strong references keep the target alive; weak references are cleared after the target dies.
2. **No double release**: ARC reaching zero finalizes only once; GC reclamation does not process the same object twice.
3. **No leaks**: unreachable objects are eventually reclaimed; cyclic references are reclaimed by GC.
4. **Identity preservation**: stack allocation, movement, and reference copying do not change object identity.
5. **Value independence**: copies of a value type do not affect each other.
6. **No resurrection**: `deinit` MUST NOT publish `self` to external state.
7. **Publication safety**: `self` MUST NOT escape before construction completes.
8. **Root completeness**: the GC root set MUST cover all reachable storage locations; roots MUST NOT be missed.

## 22. Allocation Failure

- Allocation failure is fatal; `OutOfMemory` MAY serve as an observation surface, but a partially initialized object MUST NOT be returned.
- When a constructor panics, the object is not published and the process terminates.
- Stack overflow is fatal.
- APIs that require capacity control MUST explicitly return errors at L1 (Part 4); a general allocation failure MUST NOT be treated as a recoverable error and retried.
- Allocation failure MUST NOT trigger undefined behavior; the process MUST terminate with a fatal diagnostic.
