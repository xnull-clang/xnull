# XNull Solution Part 6: Runtime Tasks and Concurrency

| Item | Value |
| --- | --- |
| Document ID | Part 6 (S6) |
| Document version | 1.3.0 |
| Specification status | Formal |
| Publication date | 2026-11-15 |
| Applies to | XNull language implementations |
| Related parts | Part 1 v3.4.0; Part 2 v3.6.0; Part 3 v1.0.0; Part 4 v3.2.0; Part 5 v1.2.0; Part 7 v3.0.0 |

Version rules: Revision numbers are used for clarifications that do not change semantics, minor versions for backward-compatible additions, and major versions for breaking changes. Historical versions are in the git record.

Renumber note: document renumbered from Part 5 to Part 6 on 2026-11-23 to insert Part 3 (Annotations); content is unchanged.

This document specifies the runtime execution model, structured concurrency, cancellation and timeouts, synchronization semantics, and runtime behavior boundaries. **The language layer has no `async` / `await` and no task syntax (S1 §0.6); the memory rules for task closures are in S4 §11; the names and signatures of task and synchronization APIs are in Part 7.**

## 1. Positioning and Core Stance

### 1.1 Specification Division of Labor

| Topic | Ownership |
| --- | --- |
| `async` / `await`, function coloring | Rejected (S1 §0.6), permanent design |
| Task closure capture, env cross-thread roots, GC keep-alive | S4 §11 |
| Memory safety for cross-task sharing (publication points, atomic counts) | S4 §11–12 |
| Names, signatures, package ownership of task and synchronization APIs | Part 7 |
| Cancellation mechanism, checkpoints, propagation | §4 of this document; error surface see S5 §5 |
| Timeout mechanism, deadlines | §5 of this document; error surface see S5 §5 |
| Error delivery form at task boundaries | §3.6 of this document |
| Scheduling contract, structured concurrency, synchronization semantics | §2, §3, §6 of this document |

### 1.2 Core Stance

- Concurrency is a library capability, not a language capability. Concurrent code has the same shape as sequential code: functions return `Result`, cancellation and timeout are `Err`, there is no second control flow.
- Structured first: tasks MUST belong to an explicit task group; the group's lifetime constrains the tasks' lifetimes (§3). No free-floating (detached) tasks are provided.
- Data races are program errors: the runtime does not detect them and makes no guarantees about results; synchronization responsibility is explicit at the point of use (S4 §11).
- No commitment to scheduling fairness or real-time behavior; what is committed is a deterministic behavioral contract: cancellation arrives, timeouts take effect, and tasks terminate before the group closes.

### 1.3 Boundary with the Standard Library

The names, ownership, and signatures of task and synchronization APIs belong to the library API surface of Part 7 (appended as implementations proceed). For readability, this document uses current mapping names (`Task` / `TaskGroup` / `Context` / `Mutex` / `Channel` / `Atomic*`); they are all library types. This document only specifies their **semantics and mechanisms**: execution model and scheduling contract (§2), structured concurrency (§3), cancellation and timeout (§4, §5), synchronization semantics (§6), runtime behavior boundaries (§7). The block semantics of `@tasks` are normative in this Part; its annotation syntax and name are specified by Part 3, and changes to either require the owning Part's version process.

## 2. Execution Model

### 2.1 Threads, Tasks, and Scheduling Units

- Threads are runtime resources; tasks are the unit of scheduling, cancellation, and error delivery. The mapping of tasks to threads (M:N, 1:1, or hybrid) is implementation-defined and not promised by the language.
- `main` is the holder of the root scope: task groups created within the entry function body form the root of the task tree (§3).
- A task is not a thread: one thread can execute multiple tasks in sequence; a task can migrate across threads.
- Tasks have no source-visible thread-local storage; they MUST NOT depend on thread IDs or thread-local variables.

### 2.2 Task Lifecycle

| Phase | Meaning |
| --- | --- |
| Created | `spawn` submits the closure and returns a task handle; the task has not yet run |
| Submitted | Enters the scheduling queue, waiting for execution |
| Running | The closure is executing |
| Terminated | The closure returns, terminates with `Err`, or terminates after cancellation |

- A task handle can still query the result once after the task terminates; `join` can succeed only once, and a repeated `join` is a contract error.
- A task's lifetime does not exceed its owning group: after group close returns, all tasks in the group MUST have terminated.
- Task closures MUST have a return value; tasks with no success value use `Result<Unit, E>`.

### 2.3 Scheduling Contract

- The scheduler guarantees: submitted tasks are eventually scheduled or cancelled; cancelled tasks eventually terminate (no starved orphans).
- The scheduler does not guarantee fairness, priority, or execution order; source code MUST NOT depend on task start order.
- Code inside a task MUST NOT assume an execution thread; thread-affinity requirements (such as a UI main thread) are expressed by the library using explicit dispatch to a designated executor.
- Scheduling parameters (carrier thread count, queue policy) are implementation configuration, not language semantics.

### 2.4 Blocking Classification

Blocking inside a task falls into two categories:

| Classification | Meaning | Scheduling behavior |
| --- | --- | --- |
| Task-aware blocking | Suspensible operations such as library I/O, locks, channels, join | The scheduler suspends the task without occupying a thread |
| Task-unaware blocking | FFI calls, unknown native code | Occupies a carrier thread until return |

- Library APIs MUST declare their blocking classification; an undeclared blocking entry point is considered a contract violation.
- Task-unaware entry points for long blocking MUST provide a companion form with a dedicated executor; they MUST NOT occupy scheduling threads for long periods.
- The blocking classification list is published with the library documentation; application code MUST NOT assume that an undeclared entry point is task-aware.

### 2.5 `@tasks` Block Annotation

- `@tasks` annotates a method or block: it declares that the body submits or awaits tasks.
- All task APIs can be used inside a `@tasks` block; using task APIs outside a block is a compilation error.
- The closure environment of a submitted task is treated as an external root per S4 §11 (an invisible boundary for escape analysis).
- The annotation does not change the function signature, error surface, or scheduling semantics; it only marks the legal scope for task APIs.

### 2.6 Runtime Exit

- Before `main` returns, groups in the root scope MUST be closed; failure to close is a usage error.
- Before process exit, the runtime cancels and waits for groups that are still unclosed, ensuring no scheduler threads leak; this fallback does not change the determination that "failure to close is a usage error."
- Process exit does not guarantee execution of `deinit`; task cleanup MUST be completed explicitly at the point of use.

## 3. Structured Concurrency

### 3.1 The Group Is the Only Creation Boundary

**This specification adopts scoped task groups**: a group is the only way to create tasks; there are no tasks outside a group.

- The task tree is isomorphic to the call tree: groups are created within a scope, and tasks do not outlive their group; "background task leaks" are impossible at the language level.
- Forms not adopted: global `spawn`, direct submission to thread pools, detached tasks.
- When daemon-like background work is needed, express it with a long-lived group (e.g., an application-level group attached to the `main` root scope); the lifetime remains explicit.

### 3.2 Submission Contract

- When a group submits a task, the task closure returns `Result<T,E>`; `E` MUST be a valid error type (Part 5 §2.1).
- The closure obtains `Context` and shared data via capture; it MUST NOT depend on an implicit thread-local context.
- Submission MUST NOT copy the task closure's mutable captures; captures are shared according to the cell rules of S4 §10.5.
- No tasks may be submitted after the group is closed; submission returns a usage error and MUST NOT silently discard.

### 3.3 Group Close

- A group is a resource: it MUST be closed explicitly at the point of use (S4 §17–18).
- Close contract:
  1. Issue cancellation to the contexts of all unterminated child tasks (contract in §4.1 takes effect);
  2. Wait for all child tasks to terminate, including completion of their cleanup paths (§4.4 "cleanup is not skipped");
  3. Return **the first non-cancellation child task error in submission order**; the caller decides whether to observe it (S5 §4.1).
- Close is the only termination path: there is no legal form of "discarding without closing the group"; exiting a scope without closing is a usage error.
- Close is idempotent: repeated close does not repeat cancellation or waiting, and subsequent closes return success.
- After group close returns, the environment roots of tasks in the group MUST have been removed.

### 3.4 Nested Groups

- Groups can be nested; closing a parent group before a child group is closed is treated as part of closing the parent group.
- Cancellation propagates downward in preorder: parent group → child group → child tasks.
- Only after the child group close returns can the parent group complete its close.

### 3.5 Task Termination

- Task termination includes: the closure returns, terminating with `Err`, and terminating after cancellation.
- Group close MUST wait for all terminations to complete; it MUST NOT merely wait for the scheduler to report "cancelled."
- After a task terminates, the external root of its env is released; there are no further task references.

### 3.6 Error Delivery

- Business errors from child tasks are **delivered as-is**: `join` passes the `Err(E)` value of the task closure to the caller as-is, without wrapping or degrading `kind()`.
- Only termination produced by group cancellation/timeout is expressed as `Cancelled` / `Timeout`, and is type-distinguishable from business errors.
- `try` cannot cross task boundaries: a `try` inside a task closure can only propagate to the closure's own return (S1 §10.2 closure rules); cross-boundary transfer can only occur via `join`'s `Result`.
- Group close returns only the first non-cancellation error; the remaining errors MUST be explicitly observed by the task itself or the caller, and MUST NOT be implicitly aggregated or discarded.

## 4. Cancellation

### 4.1 Context Model

- Cancellation signals are passed explicitly via `Context`; there is no implicit thread-local propagation.
- The root context `Context.background()` has no cancellation and no deadline; it is used only by `main` and test entry points.
- Child contexts are derived via `withDeadline` or a group scope; cancellation of a child context does not affect the parent context.
- Group cancellation and context deadline are the only two cancellation entry points.

### 4.2 Checkpoints

- Cancellation is cooperative: tasks respond to cancellation at checkpoints; a CPU-intensive task with no checkpoints can only continue running until its next checkpoint.
- Checkpoints include: channel send/receive, context-bearing blocking I/O, `join`, `checkCancel`.
- `checkCancel` returns `Result<Unit, CancelledError>`; long-running tasks MUST periodically call a checkpoint.
- The contract is "cancellation eventually takes effect" (group close waits for termination), not "immediate interruption."

### 4.3 Propagation

- Cancellation propagation chain: group cancellation → child task context cancellation → checkpoint inside the task closure returns `Err(Cancelled)` → the task terminates with `Err` → group close converges.
- Parent group cancellation precedes child group; child group cancellation does not affect the parent group in reverse.
- Execution of cleanup paths (`defer` / `errdefer`) after cancellation is not affected by cancellation; when I/O is needed during cleanup, use an independent context that is not subject to cancellation by that context.

### 4.4 `Cancelled` Error Surface

The error value contract for cancellation (must not be swallowed, must not be disguised, side effects stop, cleanup is not skipped, completion takes priority) is in S5 §5.1 and §5.3. This section only defines the mechanism:

- A checkpoint returns `Err(Cancelled)`; the task terminates with `Err`.
- Cancellation requests during cleanup are queued and processed after cleanup completes; cleanup MUST NOT be skipped due to repeated cancellation.
- Group close waits for all tasks to terminate and does not return early due to cancellation.

### 4.5 Race Window

- When completion races with cancellation, "completion takes priority" applies; see S5 §5.3 for the determination contract.
- The scheduler reports cancellation only at checkpoints; execution outside checkpoints MUST NOT be asynchronously interrupted.
- No new externally visible side effects may occur after cancellation returns.

### 4.6 Interaction with `Result`

- The signature of a cancellable function is unchanged: it is still `Result<T,E>`; the error type of `E` MUST be able to express `Cancelled` (directly or via `kind()`).
- Fallback methods (such as `unwrapOr`) do not treat `Cancelled` specially: a fallback is an explicit decision to swallow cancellation, visible at the call site.
- The framework-level guarantee that "cancellation must continue propagating upward" is enforced at task boundaries.

## 5. Timeout

### 5.1 Mechanism

- Timers are provided by the scheduler; context deadlines and deadline-bearing waits are the only two timeout entry points.
- After a deadline-bearing wait times out, the task continues executing until it terminates itself or is cancelled by its group; timeout does not automatically cancel, and the caller decides explicitly.
- The deadline is determined when the context is created; derived child contexts MUST NOT extend the parent context's deadline.

### 5.2 `Timeout` Error Surface

The error value contract for timeout (not a panic, deterministic resource final state, isomorphic to cancellation) is in S5 §5.2. This section only defines the mechanism:

- A deadline-bearing wait returns `Err(Timeout)` after timing out; the task continues executing and is not automatically cancelled.
- The caller explicitly decides whether a context deadline also cancels the underlying operation.
- Resource state MUST be deterministic after timeout returns; an indeterminate state is an implementation contract violation.

### 5.3 Precision

- XNull does not promise hard real-time; timeout means "takes effect as soon as possible no earlier than the expiry point," and a small overshoot before expiry is legal behavior.
- Scenarios with contractual requirements on timeout precision (hardware protocols, etc.) are outside the scope of language promises and must be undertaken by implementations outside a dedicated runtime.

## 6. Synchronization Semantics

This section describes the contracts for three categories of library synchronization capabilities: mutexes, channels, and atomics; `Mutex` / `Channel` / `Atomic*` are the current implementation mapping names, and the specific names and signatures belong to the library API surface of Part 7.

### 6.1 Mutex

- `Mutex<T>` is data-with-lock: it wraps shared data; access is scoped, and no bare lock/unlock pair is provided.
- Locks are not reentrant: a task repeatedly acquiring the same lock is a usage error, and the runtime does not detect deadlocks.
- Lock poisoning is not provided: a lock-holding task that panics terminates the process, leaving no lock state that can continue to be used.
- Cancellation can be checked inside a lock-holding body, but cancellation handling within the lock MUST complete heavy operations after unlocking; `join` MUST NOT be called while holding the lock.
- `T` in `Mutex<T>` MUST NOT be a `struct` (value copying would bypass mutual exclusion).

### 6.2 Channel

- `Channel<T>` is a bounded channel; capacity is determined at creation, and capacity 0 means synchronous handoff.
- `send` / `receive` are both cancellable suspension points; when blocked, they respond to context cancellation.
- After close: `send` returns failure; `receive` first drains buffered elements, then returns a deterministic final state.
- Multiple receivers can receive concurrently; each element is delivered to exactly one receiver.
- Channel close is idempotent; repeated close is a no-op.
- Channels are the preferred form for inter-task data flow; a shared mutable container MUST NOT be used in place of a bounded channel for unbounded queuing.

### 6.3 Atomics

- `AtomicInt` / `AtomicBool` / `AtomicRef<T>` provide sequentially consistent semantics; no memory-order parameters are exposed.
- `T` in `AtomicRef<T>` is restricted to reference types; reads and writes of the value atomically replace the reference.
- `compareExchange` returns whether the exchange succeeded; it MUST NOT be used for implicit synchronization beyond implementing lock-free algorithms.
- Atomic operations do not replace `Mutex` protection of composite invariants.

### 6.4 Data Races

- A data race means two tasks concurrently access the same memory location, at least one writes, and there is no synchronization.
- Data races are program errors; the runtime does not detect them and makes no guarantees about results.
- Immutable snapshots (object graphs that are no longer written after construction) require no synchronization and are the recommended default sharing form.
- Mutable state shared across tasks MUST go through one of `Mutex` / `Atomic` / `Channel` (the concretization of S4 §11).

### 6.5 Primitives Not Provided

- `Condvar`, reader-writer locks, semaphores, and task-local storage are not provided.
- Waiting semantics are expressed with `Channel`; when there is a genuine need, they evolve via minor versions.

## 7. Runtime Behavior Boundaries

- **Panic inside a task**: terminates the entire process, with no task-level isolation (S1 §10.4). Service-level isolation is designed according to the process model (one process per request or a supervisor process, which belongs to engineering configuration specifications).
- Task dump (diagnosing all live tasks and their wait points) is an implementation-side diagnostic capability: the output form is not promised and does not enter the language contract.
- Carrier thread count, scheduling parameters, etc. are implementation configuration; language programs MUST NOT assume a specific thread count.
- No commitment to scheduling fairness, task priority, or worst-case response time.
- Task-local storage is not provided; cross-task state MUST be passed explicitly.
