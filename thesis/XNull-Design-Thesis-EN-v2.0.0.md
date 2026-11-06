# Designing an Explicit and Predictable Programming Language: Compiler-Adjudicated Memory Management and Language Constructs in XNull

**Author**: Feiheng Li (李飞恒)

---

## Abstract

Modern general-purpose programming languages exhibit a structural tension between expressiveness and behavioral predictability. To reduce writing effort, mainstream languages routinely introduce implicit mechanisms: implicit type conversions, invisible exception propagation, automatic accessor synthesis, and semantically opaque uniform memory management. These mechanisms move critical decisions out of the source code, making a program's actual behavior under-determined by its source text and the specification, and thereby undermining static reasoning, performance analysis, and fault localization. The opposing route — explicit resource ownership systems — restores predictability but requires programmers to express reference strength and lifetimes in source code, imposing a steep adoption cost.

This paper proposes a new design paradigm — **compiler-adjudicated decisions with explicit channels** — and presents XNull, a general-purpose programming language systematically designed around it. The paradigm's core is this: implementation concerns such as object memory strategy are removed from the source level entirely; the compiler adjudicates among three strategies (stack inlining, atomic reference counting / ARC, and mark–sweep GC) according to a deterministic rule set, DET-01; the runtime executes the adjudication; and the source code contains no reference-strength expression whatsoever. In contrast, all channels that carry domain semantics — error propagation, concurrent cancellation, resource release — remain fully explicit: errors are values expressed in the type system, cancellation signals travel through explicitly passed `Context` values, and external resources are closed at the point of use with `defer`.

The contributions of this paper are: (1) a formal articulation of the design axioms of explicitness and predictability, with an argument that implementation concerns can be moved into compile-time adjudication without violating them; (2) a complete design of the memory strategy decision rules, strategy propagation rules, escape-analysis contracts, and the invariants of mixed ARC/GC reference graphs, together with a proof sketch that the adjudication satisfies the determinism axiom (the same source program, implementation version, and compilation options yield identical decisions); (3) the design of the object model (the no-accessor discipline, composition over inheritance, protocol polymorphism) and of the error-handling, concurrency, and FFI subsystems, consistent with the paradigm; (4) a layered verification methodology — specification, conformance ledger, implementation — and the current state of the Go-implemented compiler frontend.

The analysis shows that the conservativeness of the adjudication (unprovable acyclicity defaults to GC) establishes the correctness lower bound of strategy decisions, and that removing reference strength from source code turns strategy upgrades into non-breaking changes — an additional benefit along the language-evolution axis. XNull demonstrates that predictability can stand as the first constraint of language design and hold up in engineering practice.

**Keywords**: programming language design; memory management; escape analysis; reference counting; garbage collection; explicitness; predictability; protocol polymorphism

---

## 1 Introduction

### 1.1 Background and Motivation

Over the past two decades, mainstream industrial languages have converged on reducing writing cost: ever-stronger type inference, automatic accessor synthesis, exceptions propagating invisibly up the call stack, and garbage collection fully transparent to the user. The common trait is that decisions are moved out of the source code. The engineering costs appear in three forms. First, reading the source no longer suffices to infer program behavior; program comprehension depends on memorized implicit rules. Second, performance characteristics resist static reasoning; resource behavior (allocation, finalization, propagation) cannot be observed from type signatures. Third, fault-localization cost grows superlinearly with the number of implicit mechanisms.

The opposing route in resource management is exemplified by Rust's ownership system: resource semantics are made explicit and statically checked by the compiler, yielding predictable performance without sacrificing safety. The cost is that reference strength and lifetimes become part of the source; the adoption barrier rises sharply, and every tightening of the rules risks ecosystem-level breaking changes.

The divergence between the two routes reduces to one question: **where should implementation concerns live — in the source, in the compiler, or in the runtime?** Fully transparent GC places them in the runtime; ownership systems place them in the source. Each extreme carries its own cost.

### 1.2 Research Question

The central question of this work is whether a third path exists that simultaneously satisfies three constraints:

- **C1 (Hiding)**: implementation concerns such as reference strength never appear in source code;
- **C2 (Determinism)**: strategy selection is adjudicated by the compiler under normalized deterministic rules, and the adjudication is reproducible and acceptance-testable;
- **C3 (Explicitness)**: every decision that belongs to domain semantics — error propagation, cancellation, resource release, data sharing — must be expressed explicitly in the source.

If such a path exists, how should its rule system be constructed, how can its cost be controlled, and can the paradigm generalize coherently to other dimensions of the language?

### 1.3 Contributions

The contributions of this paper are:

1. The paradigm of *compiler-adjudicated decisions with explicit channels*, fully instantiated in the general-purpose language XNull;
2. The design of the deterministic memory-strategy rule set (DET-01), strategy propagation rules, and escape-analysis contracts, with an argument that they jointly satisfy C1–C3;
3. The design of the object model, error handling, concurrency, and FFI subsystems consistent with the paradigm, together with an auditable record of the alternatives rejected at each key decision point and the reasons for rejection;
4. A three-layer verification methodology (specification — ledger — implementation) and the current state of the compiler frontend implementation.

## 2 Related Work and Design Positioning

**Uniform managed-runtime languages** (Java, Go, C#) manage the heap with a tracing collector. Their advantage is a low adoption barrier; the costs are that allocation and reclamation are unobservable from source, latency boundaries carry no worst-case contracts, and strategy is fixed by the runtime rather than the specification. XNull shares the stance that source should not express reclamation details, but differs in that strategy selection happens at **compile time** and is **dispatched by type and escape structure**: value-semantics types leave the reclamation channel entirely, and the specification imposes determinism constraints on the *observable consequences* of reclamation (finalization order, weak-slot nulling).

**Ownership systems** (Rust) place resource semantics in the source. XNull absorbs the idea of compile-time adjudication under contractual specifications, but rejects reference strength in source: in XNull's stance, reference strength is an implementation concern, not a domain semantic. "Who owns, who shares, who mutates" is expressed by types and composition structure; the choice between counting and tracing belongs to the compiler.

**ARC languages** (Swift) use reference counting as the primary channel and rely on compiler optimization to eliminate redundant counts. In XNull, ARC is one of three strategies rather than the sole channel; ARC and GC objects coexist in one reference graph, and the specification fixes the mixed-graph invariants (an ARC object holding a GC reference must register for scanning; a GC object holding an ARC reference must release it during sweep).

For **error handling**, XNull adopts the Result-as-value channel (akin to Rust and Swift, opposed to the exception channels of Java/C++), but provides no short-circuit unwrapping operators: the control flow of failure propagation must close within the source. For **concurrency**, cancellation is passed explicitly (akin to Go's `context` pattern, opposed to thread-local interruption), while data-race detection and structured concurrency are explicitly not promised.

In summary, XNull's design position is a third stance between "the source expresses everything" (ownership) and "the runtime decides everything" (managed GC): **the compiler adjudicates under the specification, the runtime executes under contract, and the source expresses only domain semantics**.

## 3 Design Axioms and Overall Shape

XNull rests on three axioms:

- **A1 (Explicit)**: every important semantic of a program has a unique, unambiguous expression in the source.
- **A2 (Predictable)**: language behavior is fully determined by the source and the specification; the same source program, implementation version, and compilation options must produce identical strategy decisions, layout decisions, vtable slots, and run results.
- **A3 (Reject the implicit)**: any implicit mechanism whose existence weakens A1 or A2 is rejected, regardless of its convenience.

Consequences include: no implicit conversions; no exceptions; no accessor synthesis; no thread-local implicit propagation; explicit resource release at the point of use. The axioms equally entail a set of **permanent rejections**: overriding, abstract methods, and reflection. Rejection rationales are recorded alongside the normative clauses, making the design auditable.

A3 must be distinguished from a rejection of automation. XNull's automation takes the form of **compile-time decisions** (memory strategy, escape-driven stack allocation, layout selection) rather than **source-level semantic ambiguity**. The former's rules are part of the specification and mechanically verifiable; the latter strips the source of its capacity to fully describe behavior. This distinction is the pivot of the paradigm.

## 4 Object Model

### 4.1 Value/Reference Dichotomy and Layout

Data shapes are distinguished naturally by constructs: `struct` and simple enumerations are pure values — stored inline, copied by value, with copying triggering no reclamation actions; `class` and `singleton` are reference-semantics entities; data-enumeration cases are GC global roots constructed at program start. Heap objects uniformly carry an allocation header (object kind, type descriptor, count or mark word, scan information); the type descriptor must support `is`/`as` dynamic checks and protocol-conformance checks.

### 4.2 The No-Accessor Discipline

Properties and behavior are strictly separated at the syntax level: properties are read and written directly; behavior is invoked through methods; the two are non-interchangeable. The discipline eliminates the statically undecidable "field or method?" question and forces computed values to be modeled explicitly as methods. The theoretical rationale: accessors make "reading a slot" and "running a computation" indistinguishable at the call site, violating A1's requirement that important semantics have a unique expression.

### 4.3 Composition over Inheritance, Protocol Polymorphism

Classes do not support override-based inheritance; polymorphism is achieved exclusively through protocols. Override inheritance is permanently rejected on the grounds that it makes subclass behavior depend on the internal details of superclass implementations — cross-layer implicit coupling, a direct violation of A3. Customization points are provided explicitly as protocol hooks. This aligns with Go's composition-first orientation but tightens it by excluding method overriding in any form.

## 5 Memory Management: The Core Instance of Decision Elevation

### 5.1 Three Strategies and the Decision Rules

XNull defines three memory strategies: **stack** (inline / stack values), **ARC** (atomic reference counting), and **GC** (mark–sweep). Adjudication occurs after monomorphization and before code generation; its inputs come entirely from the monomorphized source structure: object kind, field type graph, reference-cycle analysis, presence of `deinit`, `self` capture, and escape classification. The general outline: value-semantics types are always inlined; a class object whose escape class is `none` may be stack-allocated; `return`-class objects are promoted to ARC; `other`-class objects go to GC; objects participating in shared mutable state, with lifetimes spanning tasks, or held behind protocol/`Any`-erased fields, are assigned to GC.

Adjudication follows a **conservativeness principle**: when acyclicity cannot be proven or field types are not concrete, the object defaults to GC; unanalyzable objects are never handed to ARC. Conservativeness trades bounded, controllable performance for the correctness lower bound of the adjudication — the key construction for satisfying C2.

### 5.2 Strategy Propagation and the Mixed Reference Graph

The strategy graph takes monomorphized types and storage locations as nodes and strong references as edges. The core propagation clauses: an ARC object holding a GC reference must register as a scan object; a GC object holding an ARC reference must release it during sweep; container objects are always GC, though scalar/pure-value element regions are registered as scan-free raw byte regions; when a reference cycle contains at least one GC node the entire cycle is reclaimed by GC, and all-ARC strong cycles must be detected by memory analysis — the automatic strategy re-decides to GC, while an explicit (implementation-internal) annotation must produce a compile error, never silent degradation.

### 5.3 Determinism and the Runtime Contract

The specification imposes no determinism requirement on reclamation timing, but does impose ordering constraints on the **observable consequences** of reclamation: an ARC count reaching zero triggers the finalization chain (clear weak slots → derived-class `deinit` → superclass chain → release reference fields → reclaim memory); the finalization chain must not re-enter allocation state, and resurrecting `self` terminates the process; during GC sweep, dead objects release their ARC references first, then run `deinit`, then are reclaimed. The runtime ABI fixes a minimal entry set — allocation, counting, weak table, write barriers, safepoints, task roots — and compiler-generated code manages memory only through these entries.

### 5.4 No Language-Level Weak References

Weak references do not exist as a language feature: neither the source language nor the public standard-library API exposes them; the weak table is an internal runtime mechanism whose entries are available only to the FFI contract layer and the runtime itself. This removes a classic source of implicit invalidation (the dereference semantics of dangling weak references) while retaining the internal capability the runtime requires.

### 5.5 The Two-Responsibility Cleanup Model

Memory reclamation and resource release are normatively defined as two independent responsibilities. External resources — files, handles, locks, task groups — must be closed at the point of use with `defer`; `deinit` is a last-resort fallback and is not guaranteed to run on GC reclamation, process exit, or panic paths. This dichotomy eliminates the pattern of "relying on destructors to release external resources," a recurring defect class in managed languages.

### 5.6 Explicitly Non-Promised Boundaries

The design simultaneously fixes a non-promise list: no source-level addresses or manual release semantics, hence no promise for kernel/driver/bare-metal or MMIO contexts; no worst-case timing contracts for GC rendezvous, marking/sweeping, or atomic counting, hence no hard-real-time promise; no arbitrary custom allocators; layout sharing with C structs requires per-type verification. Performance claims are normatively restricted to "must be established item by item under named workloads and metrics (p50/p99 latency, peak memory, pause-time distributions)," with unsupported global rankings forbidden.

## 6 Explicit Error Handling

Errors are values expressed in the type system: the return types of fallible operations carry the `Result<T,E>` channel in their signatures, and the type system forces callers to face the failure path. Error types follow a data-carrier principle — fields are diagnostic information (context, cause, location) and carry no mutable state. The language provides no short-circuit unwrapping operators; the control flow of failure propagation closes level by level in the source. `defer`/`errdefer` provide structured cleanup; unstructured jumps do not execute cleanup callbacks — together guaranteeing a one-to-one correspondence between cleanup paths and control-flow paths.

## 7 Concurrency and the Task Model

Execution is organized around tasks. A `Context` carries the cancellation signal and deadline and is passed explicitly, making the reachability of cancellation visible level by level along the call chain; thread-local implicit propagation is not used. When a task closure enters the scheduler, its captured environment is registered as an external root and deregistered at task termination. The concurrency design explicitly lists its non-promises: structured concurrency, automatic cancellation propagation, data-race detection, and scheduling fairness contracts are all outside the current baseline; field and captured-variable accesses are not synchronized, and data races are defined as program errors. This style of "explicit non-promise" is itself an extension of the predictability axiom: the language's capability boundary must close within the specification, not be left to implementation variance.

## 8 FFI and Cross-Language Ownership

FFI is defined as a contract-bound boundary, not a channel for arbitrary native calls. Cross-boundary data transfer admits exactly three forms: value transfer with verified layout compatibility, opaque handle transfer with an explicit lifetime contract, and buffer transfer whose liveness the runtime guarantees for the duration of the call. Call leases (holding and release responsibilities) must be declared explicitly; callbacks entering the language require an explicit trampoline that registers the environment as a root for the call duration. XNull object references must not be used directly as cross-language addresses. The design keeps the internal complexity of the three memory strategies from crossing the language boundary.

## 9 Implementation and Verification Methodology

The compiler is implemented in Go, with command-line driving, lexical analysis, syntax analysis, and diagnostic infrastructure in place. Verification is a three-layer alignment:

1. **Specification layer**: cross-reference integrity checking guarantees mechanical consistency of the specification text (zero dangling references; all grammar non-terminals defined);
2. **Ledger layer**: the conformance ledger, generated automatically by tooling, serves as the single source of truth for the implementation, recording per-case status (unimplemented / partial / PASS / N-A); declaring any milestone complete requires the corresponding rows to be set to PASS;
3. **Implementation layer**: acceptance items cover positive, negative, and stress cases, with negative cases required to assert specific diagnostics.

Memory-dimension acceptance includes dumpable-and-reproducible strategy adjudication, mixed-graph freedom from dangling/leaks/double-release, concurrency-safe weak-slot clearing, finalization-order contracts with resurrection detection, and adjudication determinism (the regression of DET-01). This system converts "predictability" from a design slogan into a mechanically enforceable engineering constraint.

## 10 Discussion

**Costs and limitations.** The cost of decision elevation is borne by the compiler: the correctness of adjudication and escape analysis depends on full coverage of the source structure; any invisible boundary (FFI, cross-task publication) must conservatively be treated as escaping, possibly yielding suboptimal strategies. Conservativeness shrinks ARC's applicability below the theoretical optimum. The decision rules themselves become part of the specification and must evolve in lockstep with acceptance items and implementation-boundary clauses, raising specification-maintenance costs relative to runtime-managed strategies.

**Threats to validity.** The design claims rest on specification construction and the frontend implementation; they have not yet been exercised by a minimal end-to-end loop. All performance claims are normatively suspended until named benchmarks exist. Before self-hosting, the implementation's fidelity to the decision rules depends on ledger coverage, which carries case-coverage risk.

**Generality of the paradigm.** Beyond memory, "decisions elevated, channels explicit" has been applied to cancellation (explicit reachability) and error propagation (explicit failure paths), which provides preliminary evidence of cross-dimensional coherence. Its upper bound awaits examination in later topics such as generic erasure and dynamic loading.

## 11 Conclusion and Future Work

This paper proposed the paradigm of compiler-adjudicated decisions with explicit channels and instantiated it systematically in XNull. Three conclusions follow. First, delegating memory-strategy selection entirely to the compiler under deterministic rules can satisfy the hiding, determinism, and explicitness constraints simultaneously, given a conservativeness principle. Second, removing reference strength from source turns strategy upgrades into non-breaking changes, yielding additional freedom for language evolution. Third, combined with explicit error handling and explicit cancellation, the paradigm forms a coherent language shape.

Future work proceeds in order: complete the minimal C-backend closed loop and run the first full program end to end; drive incremental completion through the conformance ledger; achieve self-hosting by rewriting the compiler in XNull; complete the English normative translation of the approved baseline; and establish performance benchmarks on named workloads, replacing every suspended performance claim in this paper with empirical data.

## References

[1] XNull Language Specification, Part 1: Core Syntax, v3.3.0, 2026.
[2] XNull Language Specification, Part 2: Object Programming, v3.3.0, 2026.
[3] XNull Language Specification, Part 3: Memory Management, v3.0.0, 2026.
[4] XNull Language Specification, Part 4: Error Handling, v1.0.0, 2026.
[5] XNull Language Specification, Part 5: Runtime Tasks and Concurrency, v1.0.0, 2026.
[6] XNull Language Specification, Part 6: Standard Library (XDK), v1.1.0, 2026.
[7] XNull Language Specification, Part 7: Foreign Function Interface, v1.0.0, 2026.
[8] XNull Language Specification, Part 8: Project Configuration, v5.2.0, 2026.
[9] XNull Language Capabilities and Application Boundaries, v3.0.0, 2026.
[10] S. Bradner. Key words for use in RFCs to Indicate Requirement Levels. RFC 2119, 1997.
[11] S. Klabnik, C. Nichols. The Rust Programming Language. No Starch Press, 2019.
[12] R. Jones, A. Hosking, E. Moss. The Garbage Collection Handbook: The Art of Automatic Memory Management. 2nd ed., CRC Press, 2023.
[13] Apple Inc. The Swift Programming Language: Automatic Reference Counting. Apple Developer Documentation.
[14] M. Bos. Rust Atomics and Locks: Low-Level Concurrency in Practice. O'Reilly Media, 2023.
[15] R. Hudson. Getting to Go: The Journey of Go's Garbage Collector. The Go Blog, 2018.
