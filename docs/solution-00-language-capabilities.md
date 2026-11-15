# XNull Solution Part 0: Language Capabilities and Application Boundaries (Preface)

| Item | Value |
| --- | --- |
| Document number | Part 0 (S0) |
| Document version | 1.1.0 |
| Specification status | Positioning preface (adds no syntax or semantics) |
| Release date | 2026-11-15 |
| Applies to | XNull language users and implementers |
| Related parts | Parts 1–9 |

## 0. Purpose of This Document

Before entering the specification, answer three questions first: **what XNull is, what it can take on, and what it explicitly does not promise.**

XNull's positioning is not "writing interfaces, doing backend work". As long as a problem consists mainly of data representation, computation, state changes, object collaboration, and task execution, existing language constructs usually provide an expression path. This document gives the capability map and application domains, and draws the execution boundary; the basis for every judgment can be found in the subsequent parts.

This specification is a refactoring draft: a clause is considered stable only after it has been validated in `dx/` scenarios or in actual toolchain testing; unvalidated clauses may be modified, and "already written into the specification" is not a reason for immutability.

## 1. Positioning

XNull is a **statically typed, C-compiled general-purpose language with a managed runtime and an explicit error model**. Its goals are:

- Take on **the main logic of applications and system services**: business state, protocol handling, task orchestration, object collaboration;
- Take on **data, rule, and algorithm engines**: cleaning, aggregation, indexing, graph algorithms, backtesting, simulation;
- Take on **local tools and language tools**: CLI, configuration handling, parsers, compilers, code analysis;
- Provide **long-lived object systems** within the managed runtime: connection tables, device trees, task graphs, observers, session state.

It does not treat "whether there is domain-specific syntax" as a capability prerequisite. Database syntax, AI syntax, and robot syntax affect expression convenience and optimization opportunities, but they cannot determine whether these algorithms can be written.

## 2. Capability Map

| Language construct | What it can express | Typical uses |
| --- | --- | --- |
| Scalars, simple enums | Numbers, flags, state codes | Arithmetic, bit manipulation, branch decisions |
| Pure-value `struct` | Coordinates, sample points, dimensions, numeric parameters, geometric quantities | Independent copies, inline storage, bulk data |
| `class` | Devices, sessions, orders, services, rule objects, graph nodes | Identity, shared state, object collaboration |
| Arrays and containers | Bulk data, indexes, sets, buffers, tree edges | Organizing large-scale data and dynamic structures |
| `protocol` | Rules, handlers, policies, device capabilities, storage entry points | Runtime replacement, dependency inversion, layered architecture |
| Closures | Callbacks, subscriptions, local policies, deferred execution | Passing behavior as parameters, return values, or fields |
| `Result` / `try` | Failure returns, layer-by-layer propagation, normal cleanup, failure compensation | Complete business chains and boundary conversion |
| Generics | Container algorithms, generic handlers, type-safe reuse | One codebase adapted to multiple element types |
| Task groups / `Context` | Structured concurrency, cancellation, timeouts, task trees | Service requests, batch processing, device polling |
| XDK | L1 public API layer (errors and observation, concurrency, data and text, system and resource reading; networking and other T1 later) → L2 primitive layer (memory and handles, scheduling, diagnostics, FFI contracts) → L3 native boundary | Platform capabilities required by applications, organized by layer rather than enumerated by package; per S6 §1 |
| FFI contracts | Native libraries, device interfaces, existing system integration | Controlled cross-language boundary |

These constructs can be combined. For example: protocol parsing uses integers, bit operations, arrays, and state machines; a query engine uses data structures, algorithms, and execution objects; a desktop application uses objects, closures, and application state; robot navigation uses arrays, graph search, and task orchestration.

### 2.1 Terminology and Ownership

A concept is defined in only one part; other parts reference it and do not redefine it. Terminology changes must go back to the authoritative part to be modified; other parts change only the references.

| Concept | Specification term | Authoritative part |
| --- | --- | --- |
| `Result` with no success value | `Result<Unit,E>` | S1 §10.1 |
| Empty value type | `Unit` / `unit` | S1 §9.1 |
| No return value | `void` | S1 §2.1 |
| Recoverable failure | `Result` / `Err` | S1 §10.1, S4 |
| Terminal failure | fatal (panic / throw) | S1 §10.4 |
| Object finalization | `deinit` / finalization | S2 §6.4, S3 §14–15 |
| Memory strategy | stack / ARC / GC | S3 §4 |
| Cancellation error surface | `Cancelled` | S4 §5.1 |
| Cancellation mechanism | checkpoint / propagation | S5 §4 |
| Timeout error surface | `Timeout` | S4 §5.2 |
| Timeout mechanism | deadline | S5 §5 |
| Task group | group / `TaskGroup` | S5 §3 |
| Context | `Context` | S5 §4.1 |
| XDK layer | L1 public API / L2 primitive / L3 native | S6 §1 |
| Three FFI contract surfaces | value / handle / buffer | S7 Appendix A §A.2.1 |
| Resource closing | `close()` / explicit close | S3 §18, S4 §4.5 |

`TaskGroup` / `Context` / `List` / `Map` / `Set` / `Iterator` and the like in the table are the current mapping names of **library types**; their members and signatures are in S6/source code, not in the compiler.

## 3. Application Domains

### 3.1 Main Work It Is Suited to Take On

| Direction | Main work it can take on | Platform interfaces required for full operation |
| --- | --- | --- |
| Enterprise business systems | Users and permissions, orders, work orders, approvals, billing, business validation, state transitions | Networking, persistence, time and tasks |
| Network services and gateways | Request parsing, routing, sessions, authentication, connection state, rate limiting, protocol handling | Sockets, network events, clock, synchronization |
| IoT and device access | Message encoding and decoding, device models, registration and heartbeats, command correlation, alarm rules | Networking, serial port or device access |
| Data processing and quantitative analysis | Cleaning, filtering, grouping, sorting, aggregation, window statistics, feature and signal computation | Data input and output; tasks and synchronization when parallel |
| Rules, workflows, and domain engines | Condition evaluation, rule composition, workflow state, execution plans, dependency graphs, compensation logic | Persistence, clock, external actions |
| Databases, caches, and messaging systems | Index and query algorithms, in-memory structures, transaction state, cache eviction, message routing | Files, persistence barriers, networking, concurrency |
| CPU algorithms and simulation | Search, graph traversal, path planning, geometric computation, numerical iteration, discrete-event simulation | Basic computation can be expressed directly; advanced numerics and parallelism must be defined by the user |
| AI applications and agents | Model request organization, routing decisions, tool execution, knowledge retrieval, task state | Input and output, task execution, model or device calls |
| Desktop and graphics programs | Application models, interaction state, layout algorithms, drawing command generation, local processing | Windows, input, drawing, fonts |
| Robotics and edge applications | Task orchestration, device state, map data, path search, behavior state machines | Device communication, time, sensors and actuators |
| Language and compiler tools | Lexical Structure, grammar, AST, interpreters, code generation, code analysis, formatting | Files, terminal, processes |
| Local tools and operations programs | Configuration handling, log analysis, protocol debugging, data labeling, offline management | Files, terminal, processes, networking as needed |

These directions rely on combinations of general constructs, not domain-specific syntax. Domain names differ, but the underlying programming capabilities share a great deal.

### 3.2 Directions Explicitly Not Promised

| Not promised | Reason |
| --- | --- |
| Kernels, drivers, bare metal | The source code has no addresses, pointers, or privileged instructions; execution depends on the managed runtime |
| Hardware registers / MMIO | No address or dereference semantics |
| Strict hard real-time | GC safepoints, ARC atomic operations, and reclamation delays have no worst-case timing contract |
| Custom allocators, manual freeing | Memory strategy is managed by the compiler and the runtime |
| Sharing arbitrary C struct layouts | Requires explicit `layout(c)` validation or marshaling; not compatible by default |
| Dynamically loading/unloading managed plugins | The first version uses closed linking; dynamic modules are not promised |
| GPU device code generation | Requires an independent contract, to be initiated separately |
| A complete high-performance training stack | The language can write CPU algorithms, but does not promise operator libraries, GPU scheduling, or training frameworks |

These boundaries cannot be inferred merely from "whether there is a GC": even if a code segment does not allocate objects, it may still encounter GC safepoints, synchronization blocking, or atomic operation delays.

## 4. Why These Designs Are Sufficient to Cover the Above Directions

### 4.1 Value Semantics and Reference Semantics Coexist

Data and objects have a clear division of labor: pure-value `struct`s carry coordinates, samples, and parameters; `class`es carry devices, sessions, orders, and graph nodes; arrays and containers organize bulk data; `protocol`s carry replaceable behavior. Computed data and complex objects can collaborate in the same program.

### 4.2 Protocols and Composition Express Replaceable Behavior

Ordinary class inheritance only reuses fields and methods; it cannot override. Dynamic behavior is achieved through protocols. This makes it possible to express the same rule entry point corresponding to different devices, the same command entry point corresponding to different equipment, and different parsers and handlers within the same processing chain. The cost is: code that relies on "a subclass overriding a parent hook" must be changed to protocol plus composition.

### 4.3 Numerics, Arrays, Loops, and Recursion Are Sufficient to Express General Algorithms

Integers and bit operations handle messages, flags, and encodings; floating point and arrays express numerical processing; reference recursion in `class`es expresses linked lists, trees, graphs, and ASTs; functions and control flow implement search, parsing, and execution algorithms. Matrices can be represented by one-dimensional arrays plus shape and stride; fixed-point amounts can be represented by integers plus an agreed scale.

### 4.4 Explicit Error Propagation Organizes Complete Business Chains

`Result`, `try`, `defer`, and `errdefer` express failure returns, layer-by-layer propagation, normal cleanup, and failure compensation. Recoverable failures stay on the `Result` path; null references, out-of-bounds, failed `as`, and explicit `throw` are fatal, terminate the process, and cannot be caught by a single request handler to continue serving. High-availability services must be designed around this process boundary.

### 4.5 Managed Memory Supports Long-Lived Object Systems

Identity objects, shared references, closure captures, recursive object graphs, and cross-boundary retention all have explicit rules. Connection tables, device trees, task graphs, observers, and multi-stage business objects can live for a long time. Memory reclamation and resource closing are two separate responsibilities: automatic memory management does not replace the explicit closing of files, connections, locks, and device resources.

### 4.6 Structured Concurrency and FFI Cover the Execution Boundary

Tasks must belong to a task group; cancellation and timeouts are error values; blocking calls distinguish task-aware from task-unaware; native capabilities enter through FFI contracts, with no arbitrary direct calls. Both concurrency and cross-language boundaries have auditable contracts, rather than implicit mechanisms.

## 5. Execution Boundaries and Performance

- **Execution is within the managed runtime**: there are no source-level addresses, pointers, manual freeing, or privileged instructions; kernels, drivers, and bare metal are out of scope.
- **There is no hard real-time contract**: GC safepoints, ARC atomic operations, and reclamation delays have no worst-case timing guarantees; strict deadline layers such as motor servos and safety control are not part of the language's promise.
- **Not C-layout compatible by default**: cross-boundary structs must be explicitly validated or marshaled.
- **Performance holds only for specific workloads**: no overall performance ranking against any language is promised; the actual throughput and latency of CPU algorithms, protocol handling, and data pipelines must be measured on the specific workload.
- **Being able to write algorithms does not mean having a complete backend**: CPU matrix computations and inference algorithms can be written; GPU operators, training frameworks, and model scheduling are not currently promised.

## 6. Judging Whether a Scenario Suits XNull

Answer in order:

1. Does it require source-level addresses, pointers, or manual freeing? — If yes, it is not suitable.
2. Does it require hard real-time or worst-case timing guarantees? — If yes, it is not suitable.
3. Can it execute within the managed runtime, with resources explicitly closed at the point of use? — If yes, it is suitable.
4. Does it require cross-language calls? — If yes, follow the FFI contract in Appendix A of Part 7; do not make arbitrary direct native calls.
5. Does it rely on implicit behavior not written into the specification? — If yes, it is not promised.

## 7. Relationship with the Parts of the Specification

| Part | Question it answers |
| --- | --- |
| S0 (this document) | Why this language exists, what it can do, and what it does not do |
| S1 Basic Syntax | Lexical Structure, Type System, Expressions and Operators, Statements and Control Flow, closures, generics, error handling core, Program Entry Point |
| S2 Object Programming | Type declarations, inheritance, protocols, enums, singletons, factories, extensions, annotations, visibility |
| S3 Memory Management | Strategy determination, escape, ARC/GC, finalization, weak references, resource cleanup, FFI ownership |
| S4 Error Handling | Error types, `Error` protocol, `ErrorKind`, observation, boundary conversion, cleanup |
| S5 Tasks and Concurrency | Execution model, structured concurrency, cancellation, timeouts, synchronization semantics |
| S6 Standard Library XDK | XDK's layered design: public API layer, primitive layer, native boundary; capability and dependency matrix |
| S7 Toolchain | CLI, builds, determinism, FFI contracts |
| S8 IDE | Editing, project creation, standard library browsing, build/run entry points |
| S9 Project Configuration | Manifests, dependencies, lifecycle, resources, linking, reproducibility |

## 8. Non-Promises

- No overall performance ranking against any language is promised; performance conclusions hold only for specific workloads.
- No promise is made about ecosystem size or whether third-party libraries exist.
- No promise is made about behavior not written in the specification; implementations must not substitute "it seems to run" for clauses.
- Implementation progress is not the specification: the fact that a capability is not implemented does not mean the language does not define it; the fact that a capability is implemented does not mean the specification covers it.
