# XNull Specification, Part 5: Runtime Tasks and Concurrency

> **Translation notice**: This is an English translation of the normative Chinese specification
> 《XNull 解决方案 第 5 部分：运行时任务与并发》v1.0.0. The Chinese original prevails in case of any
> divergence. Translation version follows the original's version number.

| Item | Content |
| --- | --- |
| Document ID | Part 5 (S5) |
| Document Version | 1.0.0 |
| Specification Status | Normative (approved 2026-11-05) |
| Release Date | 2026-11-05 |
| Normativity | Normative document; language per RFC 2119 (see reference R1) |
| Upstream Dependencies | S1 (§0.6), S2 (§14.4, §16), S3 (§11, §13, §17), S4 (§5, §6, §7.1) |
| Downstream Dependencies | Part 6 (package implementation contract), Part 7 (blocking-call boundary), `xdk.ui` (thread affinity, long-term) |

This document is the scheduling and concurrency design of the "runtime." Division of responsibility: **the language layer has no `async` / `await` and no task syntax** (S1 §0.6); the memory rules of task closures are in S3 §11; the **error surfaces** of cancellation/timeouts are in S4 §5–6; this document defines the mechanism side — the execution model, task API contracts, cancellation propagation, synchronization primitives, and cross-task data rules.

## 1. Positioning and Core Stances

### 1.1 Division of Normative Responsibility

| Topic | Owner |
| --- | --- |
| `async` / `await`, function coloring | Rejected (S1 §0.6); confirmed here as permanent design |
| Task-closure capture, env cross-thread roots, GC liveness | S2 §14.4, S3 §11.1–11.3 |
| Memory safety of cross-task sharing (publication points, atomic counts) | S3 §11.3 |
| Cancellation error surface (the `Cancelled` contract) | S4 §5 |
| Timeout error surface (the `Timeout` contract) | S4 §6 |
| Error delivery shape at task boundaries | This document §4.4 (aligned with S4 §7.1) |
| Cancellation mechanism, task groups, contexts, synchronization primitives, scheduling contracts | This document |

### 1.2 Core Stances

- Concurrency is a library capability, not a syntax capability. Concurrent code has the same shape as sequential code: functions return `Result`, cancellation and timeout are `Err` — there is no second control flow.
- Structured first: tasks MUST belong to an explicit task group; the group's lifecycle constrains the tasks' lifecycles (§4). Free-floating (detached) tasks are not provided.
- Data races are program errors: the runtime performs no detection and makes no guarantees about results (non-committed; rationale: no race detection; consequence: programs with data races receive no behavioral guarantees, S3 §11.3); synchronization responsibility is explicit at the point of use.
- Scheduling fairness and real-time behavior are not promised (aligned with S3 §0, S4 §6.2); what is promised is a deterministic behavior contract: cancellation arrives, timeouts take effect, tasks terminate before group closure.

### 1.3 Boundary with the XDK (indicative binding declaration)

The `xdk.*` package names (`xdk.tasks`, `xdk.sync`, `xdk.ui`), type names (`Task`, `TaskGroup`, `Context`, `Mutex`, `Channel`, `Atomic*`), and function signatures (`spawn` / `join` / `close` / `checkCancel` / `withDeadline`, etc., including the full table in Appendix A) appearing in this document are governed by Part 6 (XDK); this part defines only their **semantics and mechanisms**: the execution model and scheduling contract (§2), structured-concurrency constraints (§4), the cancellation/timeout propagation mechanisms (§5, §6), synchronization semantics and usage rules (§7), cross-task data rules (referencing S3 §11), and runtime behavior boundaries (§8). The semantics of the `@tasks` block annotation (§2.3) are normative; annotation-name changes follow Part 6's version process.

## 2. Execution Model

### 2.1 Threads and Tasks

- Threads are runtime resources; tasks are the units of scheduling and cancellation. The task-to-thread mapping (M:N, 1:1, or hybrid) is decided by the implementation and not promised by the language.
- `main` is the holder of the root scope: the task groups inside the entry function's body form the root of the task tree (§4.2).
- When a task closure enters `xdk.tasks`, its env is registered as an external root and guaranteed reachable for the task's lifetime; it is removed when the task terminates (S2 §14.4, S3 §11.1). This document refines it: **"task alive" = from submission until the group confirms termination**, see §4.4.

### 2.2 The Scheduling Contract

- The scheduler guarantees: a submitted task is eventually scheduled or cancelled; a cancelled task eventually terminates (no starved orphans).
- Blocking inside tasks falls into two classes:
  - **Task-aware blocking** (XDK I/O, locks, channels, join): the scheduler suspends the task without occupying a thread;
  - **Task-unaware blocking** (FFI calls, unknown native code): occupies the carrier thread until return. Part 7 §7.3 has defined the contract of "submitting long-blocking calls to a dedicated executor"; this part establishes the classification principle.
- Code inside tasks MUST NOT assume an execution thread; thread-affinity requirements (e.g., a UI main thread) are expressed by `xdk.ui` through explicit dispatch to a designated executor.

### 2.3 The `@tasks` Block Annotation (defining a deferral from S2 §16)

- `@tasks` annotates a method or block: it declares that its body submits or awaits tasks. Semantics:
  - The closure environment of submitted tasks is treated as an external root per S3 §11.1 (an invisible boundary for escape analysis, S3 §15);
  - Inside an `@tasks` block, the full task API of this specification may be used; using the task API outside such a block is a compile error.
- `@arena` is an implementation-side tuning annotation, of the same class as `@arc` / `@gc`: a non-committal entry point whose semantics are defined by implementation documentation; it does not enter this specification or the acceptance matrix. Its former name was `@memoryPool`, renamed during design for brevity (never implemented, so no compatibility burden).

## 3. The `xdk.tasks` API Contract

Signatures are indicative (the authoritative forms are the XDK specification's implementation contracts):

```x
final TaskGroup group = TaskGroup.create(ctx);

final Task<Int> t = group.spawn(() -> Result<Int, TaskError> {
    return compute(ctx);          // ctx enters the task via capture
});

final Result<Int, TaskError> r = t.join();
```

### 3.1 `Task<T>`

- `Task<T>` is a task handle: a non-copyable ticket with value-type semantics; `join()` succeeds only once, and repeated `join` is a contract error.
- `join()` returns `Result<T, TaskError>`; `TaskError.kind()` is `Cancelled` (group or context cancellation) or `Timeout` (a deadline join that timed out); the task's own business errors pass through **as-is** (§4.4).
- `joinDeadline(deadline)` returns `Err(Timeout)` at the deadline point while the task continues running until it terminates on its own or is cancelled by the group (timeout does not auto-cancel — the caller decides explicitly, aligned with S4 §6.1 "a timeout is a caller-driven cancellation").

### 3.2 `TaskGroup`

- A `TaskGroup` is a resource: it MUST be closed explicitly at the point of use (S2 §16; S3 §17 "task groups must be closed explicitly at the point of use").
- The close contract (`close()`):
  1. Issue cancellation to the contexts of all unterminated child tasks (the S4 §5.2 contract takes effect);
  2. Wait for all child tasks to terminate (including completion of their cleanup paths, S4 §5.2 "cleanup not skipped");
  3. Return `Result<void, TaskError>`: the first non-cancellation child-task error (the caller decides whether to observe; pattern as in S4 §4.4).
- Closure is the only termination path: there is no legal form of "discarding the group without closing"; exiting the scope without calling `close` is a usage error (`defer group.close();` is the standard idiom).
- Groups may nest: closing a subgroup before the parent is considered part of the parent's closure (cancellation propagates in pre-order).

### 3.3 `Context`

- `Context` carries the cancellation signal and deadline, and is **passed explicitly** — no implicit thread-local propagation (no TLS implicit state; consistent with the explicitness ethos).
- `Context.background()`: a root context with no cancellation and no deadline (used only by `main` and test entries, settled; application code MUST NOT call it).
- `ctx.checkCancel()`: returns `Result<void, CancelledError>`; long-running tasks MUST call checkpoints periodically; cancellation is cooperative (S4 §5.2).
- `ctx.withDeadline(d)`: derives a child context with a deadline; deadline expiry is equivalent to cancellation (`Cancelled`), to be distinguished by the caller or handled uniformly as `Cancelled`.
- Convention (not enforced): the first parameter of a cancellable API is a `Context`.

### 3.4 Error Delivery (aligned with the task-boundary row of S4 §7.1)

- Child-task business errors are **delivered as-is**: `join()` passes the task closure's `Err(E)` value to the caller unchanged — no wrapping, no `kind()` degradation.
- Only terminations caused by group cancellation/timeout are expressed as `TaskError` (`Cancelled` / `Timeout`), type-distinguishable from business errors.
- `try` cannot cross task boundaries: a `try` inside a task closure propagates only to the closure's own return (S1 §10.2 closure rules); crossing the boundary happens only via `join()`'s `Result`.

## 4. Structured Concurrency (Decision Item)

**This specification adopts scoped task groups**: `group.spawn` is the only way to create tasks; no task exists outside a group.

- The task tree is isomorphic to the call tree: groups are created within scopes, tasks do not outlive their groups; "background task leaks" are impossible at the language level.
- Cancellation propagates downward automatically: cancelling a group → all child tasks (S4 §5.2's "framework-level guarantee of upward propagation" is realized here as downward cancellation + close-and-wait).
- Rejected shapes (recorded for the record): global `spawn`, direct thread-pool submission, detached tasks. Daemon-style background work is expressed with a long-lived group (e.g., an application-level group attached to the `main` root scope); the lifecycle remains explicit.

## 5. The Cancellation Mechanism (mechanism side, interfacing with S4 §5)

- The cancellation signal travels via `Context`; `TaskGroup.cancel()` and context deadlines are the only two cancellation entry points.
- Cancellation is cooperative: tasks respond at checkpoints; a checkpoint-free CPU-bound task can only continue until its next checkpoint — the contract is "cancellation eventually takes effect" (group close waits for termination), not "immediate interruption."
- The cancellation propagation chain: group cancellation → child-task context cancellation → `checkCancel()` inside the task closure returns `Err(CancelledError)` (`kind()` = `Cancelled`) → the task terminates with `Err` → the group's close `join` converges.
- Cleanup paths (`defer` / `errdefer`) execute after cancellation unaffected by it (S4 §5.2 "cancellation requests during cleanup are queued"); when cleanup itself needs I/O, use an independent context not cancelled by this context.

## 6. The Timeout Mechanism

- Timers are provided by the scheduler; `Context.withDeadline` and `joinDeadline` are the only two timeout entry points.
- The semantics of a timeout firing are isomorphic to cancellation (S4 §6.1): side effects stopped, cleanup not skipped, error classified as `Timeout` (joinDeadline) or `Cancelled` (context deadline).
- The precision boundary follows S4 §6.2: effective as soon as possible after, not before, the deadline; no hard-real-time promise.

## 7. Synchronization (`xdk.sync`)

### 7.1 The Minimal Primitive Set

| Primitive | Shape | Contract |
| --- | --- | --- |
| `Mutex<T>` | Data-carrying lock: `Mutex<T>` wraps shared data | `withLock((T) -> Result<R,E>)` scoped access; no bare lock/unlock pair (prevents forgotten unlocks); re-locking the same lock inside the lock is at the user's peril (no detection promised) |
| `Channel<T>` | Bounded channel | `send` / `receive` are both cancellable suspension points (`Result` + `Cancelled`); after close, `receive` returns a deterministic end state; the preferred form for inter-task data flow |
| `AtomicInt` / `AtomicBool` / `AtomicRef<T>` | Atomic cells | `load` / `store` / `compareExchange`; sequentially consistent; memory-ordering parameters are not exposed (predictability first; weak-ordering needs are an implementation boundary) |

### 7.2 Usage Rules

- Mutable state shared across tasks MUST go through one of `Mutex` / `Atomic` / `Channel` (the concretization of S3 §11.3 "the caller is responsible for synchronization"); immutable snapshots (object graphs never written after construction) need no synchronization and are the recommended default sharing form.
- Locks and tasks: `checkCancel` may be called inside `withLock`, but cancellation handling within the lock must defer heavy operations until after unlocking; `join` inside a lock is forbidden (deadlock at the user's peril).
- The `T` of `Mutex<T>` MUST NOT be a `struct` (value copying would bypass mutual exclusion); class objects shared via `Mutex` are managed by atomic counts per S3 §11.3.
- No `Condvar` (first version): waiting semantics are expressed with `Channel`; genuine need may evolve in a minor version.

## 8. Runtime Behavior Boundaries

- **Panic inside a task**: terminates the entire process; no task-level isolation (S1 §10.4 "uncatchable", S4 §3.4 "process boundary"). Service-style isolation is designed on the process model (a process per request or supervisor processes; belongs to the project-configuration specification).
- Task dumps (diagnosing all live tasks and their wait points) are an implementation-side diagnostic capability: the output format is **non-committed** (rationale: debug-info structure is implementation freedom; consequence: tools and scripts MUST NOT depend on its format) and does not enter the language contract.
- Carrier-thread counts, scheduling parameters, etc. are implementation configuration (pinned by the project-configuration specification); language programs MUST NOT assume a specific thread count.

## 9. Implementation Boundaries and Release Gates

- Until `xdk.tasks` / `xdk.sync` are implemented, any XDK package claiming concurrency support (network, asynchronous file I/O) MUST NOT be released.
- The classification list of task-aware vs. task-unaware blocking MUST be declared per API by Part 7 (FFI entry `@blocking` declaration, §7.3) and Part 6 (XDK package documentation) (§2.2).
- GC safepoints MUST cover task suspension points: reference exchanges on task suspend/resume paths MUST go through publication points (S3 §11.3), covered by acceptance.
- Until this specification passes acceptance, the rows "multithreaded tasks" (scheduling, blocking, cancellation, closing, thread affinity) and "asynchronous processing" (result delivery, timeout, cancellation, resource release) in the S4 capability-gap table remain "not fulfilled".

## 10. Acceptance Matrix

| ID | Domain | Acceptance Content | Verdict |
| --- | --- | --- | --- |
| TASK-01 | Tasks | `spawn` only via groups; groupless tasks cannot be created; `join` is one-shot; business errors delivered as-is with no `kind` degradation | Compile error or runtime contract tests |
| TASK-02 | Tasks | Group `close`: cancels all child tasks and waits for termination (including cleanup-path completion); scope exit without closing is rejected | Runtime contract tests |
| TASK-03 | Tasks | Task-closure env reachable during task lifetime, reclaimed after termination (aligned with S3 §11.1) | GC stress tests |
| TASK-04 | Tasks | Panic inside a task terminates the process; no task-level isolation | Process-level tests |
| CANCEL-01 | Cancellation | Group cancellation propagates downward; tasks terminate with `Cancelled` via `checkCancel`; checkpoint-free tasks are still awaited at close | Runtime contract tests |
| CANCEL-02 | Cancellation | Cleanup paths run fully after cancellation; cancellation during cleanup is queued | Runtime contract tests (interfacing with S4 CANCEL-02) |
| TIMEOUT-01 | Timeout | `joinDeadline` returns `Err(Timeout)` without auto-cancelling; context deadline triggers `Cancelled` | Runtime contract tests |
| SYNC-01 | Synchronization | `Mutex.withLock` is scoped; Guard escaping the lock is rejected; `Mutex<struct>` is rejected | Compile error |
| SYNC-02 | Synchronization | `Channel` close end-state is deterministic; `send` / `receive` are cancellable | Runtime contract tests |
| SYNC-03 | Synchronization | Atomic operations are sequentially consistent; unsynchronized cross-task sharing is identified as escaping (conservatively GC) | Runtime tests (interfacing with S3 §11.3) |
| SCHED-01 | Scheduling | The blocking-classification list covers all XDK blocking APIs; task-aware blocking does not occupy a carrier thread | Implementation declaration + tests |
| BLOCK-01 | Block annotation | Task API outside an `@tasks` block is rejected; submissions inside the block are treated as external roots | Compile error |

## Appendix A. API Contract Table (`xdk.tasks` / `xdk.sync`)

| API | Package | One-Line Contract |
| --- | --- | --- |
| `TaskGroup.create(ctx)` | `xdk.tasks` | Create a task group; a resource, must be closed |
| `group.spawn(closure)` | `xdk.tasks` | Submit a task; the only creation method |
| `group.cancel()` | `xdk.tasks` | Cancel all child tasks (without waiting) |
| `group.close()` | `xdk.tasks` | Cancel + wait for all terminations; returns the first non-cancellation error |
| `Task<T>.join()` | `xdk.tasks` | Wait for termination and deliver `Result<T, TaskError>` |
| `Task<T>.joinDeadline(d)` | `xdk.tasks` | Deadline-bounded wait; on timeout returns `Err(Timeout)` while the task continues |
| `Context.background()` | `xdk.tasks` | Root context (main / tests) |
| `ctx.checkCancel()` | `xdk.tasks` | Cooperative cancellation checkpoint |
| `ctx.withDeadline(d)` | `xdk.tasks` | Derive a deadline-bounded child context |
| `Mutex<T>.withLock(fn)` | `xdk.sync` | Scoped mutual exclusion |
| `Channel<T>` | `xdk.sync` | Bounded channel; suspension points are cancellable |
| `AtomicInt/Bool/Ref` | `xdk.sync` | Sequentially consistent atomic cells |

## Appendix B. Decision Record

| Decision | Adopted | Not Adopted (recorded) |
| --- | --- | --- |
| Structured concurrency | Tasks must belong to groups; group closure is the only termination path | Global spawn, direct thread-pool submission, detached tasks |
| Cancellation delivery | `Context` passed explicitly | Implicit TLS / implicit propagation |
| Panic isolation | None (process boundary) | Task-level panic catching, supervisor trees (belongs to project configuration) |
| Lock shape | `Mutex<T>` data-carrying lock + `withLock` | Bare lock/unlock, reentrant locks |
| Wait coordination | `Channel` first | First-version `Condvar` (may be added in a minor version) |
| Memory ordering | Sequentially consistent, fixed | Exposing acquire/release memory-ordering parameters |
