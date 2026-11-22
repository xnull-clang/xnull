# XNull Solution Part 5: Error Handling

| Item | Value |
| --- | --- |
| Document number | Part 5 (S5) |
| Document version | 1.2.0 |
| Specification status | Formal |
| Release date | 2026-11-15 |
| Applies to | XNull language implementations |
| Related parts | Part 1 v3.4.0; Part 2 v3.6.0; Part 3 v1.0.0; Part 4 v3.2.0; Part 6 v1.3.0; Part 8 v2.2.0 |

Versioning rules: revision numbers are used for clarifications that do not change semantics, minor versions for backward-compatible additions, and major versions for breaking changes. Historical versions are in the git history.

Renumber note: document renumbered from Part 4 to Part 5 on 2026-11-23 to insert Part 3 (Annotations); content is unchanged.

Division of labor in this document: **the syntax and propagation of `Result` / `try` / `defer` / `errdefer` / `throw` are in S1 §10; the mechanisms of cancellation and timeout are in Part 6; this document defines error types, the `Error` protocol, `ErrorKind`, error observation, the error surface of cancellation/timeout, boundary conversion, and cleanup patterns.**

## 1. Positioning and Core Stance

### 1.1 Specification Responsibilities

| Topic | Owner |
| --- | --- |
| `Result<T,E>` syntax, `try` propagation, `defer` / `errdefer`, `throw` / fatal | S1 §10 |
| Memory representation of `Result` | S4 §9 |
| Resource close failure paths, cleanup responsibility model | S4 §17—18; §7 of this document completes the observation side |
| Cancellation mechanism, checkpoints, propagation | Part 6 §4 |
| Timeout mechanism, deadlines | Part 6 §5 |
| **Error surface** of cancellation/timeout | §5 of this document |
| Handles and leases at the FFI boundary | S4 §19, Part 8 Appendix A |
| Cross-language error conversion | §6.3 of this document |

### 1.2 Core Stance

- Errors are values. Recoverable failures only take the `Result` path; `panic` / fatal are uncatchable and terminate the process (S1 §10.4).
- Error observation is a boundary behavior, not control flow. Global notification centers, implicit recovery, and implicit logging are prohibited.
- Fault isolation for high-availability services is designed along process boundaries: a single request handler must not catch fatal and continue serving. See Appendix B for the distinction between recoverable and unrecoverable.
- Memory reclamation and resource closing are two separate responsibilities: the runtime only manages memory; closing resources is the explicit responsibility of the use site (S4 §17—18).

### 1.3 Boundary with the Standard Library

The names, ownership, and signatures of the `Error` protocol, `ErrorKind`, and error helper functions belong to the library API surface in Part 7 (appended with the implementation); this document only specifies their **semantics and invariants**.

## 2. Error Types and the `Error` Protocol

### 2.1 Legal Forms of Error Types

Per S1 §10.5: an error type `E` may be an enum, struct, class, or `Error` protocol implementation; `E` cannot be `void`. Additions:

- `E` must not be `Result`; nesting `Result<Result<..>>` as an error type is prohibited. Error types containing `Result` fields are handled per S4 §9 value semantics.
- Error types should be data carriers: fields are diagnostic information (context, cause, location), and do not carry mutable state.
- Error type selection: prefer enums (closed error sets) or structs (carrying context); classes are only for cases that need inheritance to reuse diagnostic fields.
- Once an error value is created, its `kind()` and `describe()` output must be stable; it must not change due to later state changes.
- Error types must not hold resource handles; when resource information needs to be carried, use identifiers or values.

### 2.2 The `Error` Protocol

```x
protocol Error {
    ErrorKind kind();        // General classification, see Section 3
    String describe();       // Single-line diagnostic description; must not contain multi-line or control characters
}
```

- `describe()` must be stable: multiple calls on the same error value within the same process return the same content; error type fields are immutable.
- `describe()` is single-line text without newlines, tabs, or NUL; a violation is a bug in the error type's declarer.
- Only `class` can implement the `Error` protocol (S2 §4.3); enums/structs can serve as the error type `E`, but do not implement the protocol and cannot be directly `report`ed.
- `report` only accepts a `Result` whose error type is `Error`; concrete errors are converted to `Error` with `mapErr` at the boundary, or wrapped with a basic error class.
- The protocol does not include a `cause` member; the cause chain is expressed with the conventional field `cause: Error?` (§2.3).
- The language built-in `panic` diagnostics do not go through the `Error` protocol; the fatal path is printed directly by the runtime.

### 2.3 Helper Functions and Cause Chains

Error helper capabilities are provided as top-level functions; names and signatures belong to the library API surface in Part 7; semantics are as follows:

| Function | Semantics |
| --- | --- |
| `wrap` | On failure, discards the original error and returns a new error; used to convert internal classified errors into external contract errors |
| `mapErr` | On failure, maps the error with a caller-provided conversion function; on success, passes through unchanged |
| `report` | On failure, writes `kind()` and `describe()` to diagnostic output; does nothing on success; only for boundary observation points |

- `wrap` discarding the original error is an explicit decision; when the cause chain needs to be preserved, the error type carries a `cause` field and is assembled with `mapErr`.
- The cause chain is a conventional field, not a protocol member; readers access `cause` through the concrete error type, and must not require every error to have a cause.
- The `mapErr` conversion function must be pure: it must not produce logs, I/O, or global state changes.
- The library provides the basic error class `BasicError` (`kind` / `message` / `cause`) and a coarse-grained `isRetryable(ErrorKind): Bool`; the concrete signatures belong to the library API surface in Part 7.
- No implicit error stringification is provided; `describe()` is the sole textual exit.
- The language method set (`isOk` / `isErr` / `value` / `error` / `unwrapOr`) follows S1 §10.1; this document does not extend language methods.

### 2.4 Construction and Inference

- `Ok(value)` / `Err(error)` are inferred according to the target type; when there is no target type, the type must be written explicitly or provided by context.
- A `Result` without a success value uses `Result<Unit,E>`; success is constructed with `Ok(unit)`, and `Err` must still carry an error value.
- Error type conversion must be explicit; there is no implicit conversion from `String` or any other type to `E`.
- When propagating with `try`, `E` must be assignable to the outer `E2`; implicit stringification or downgrading to `Internal` is prohibited.

## 3. The `ErrorKind` Taxonomy

### 3.1 Built-in Classification

```x
enum ErrorKind {
    InvalidArgument,     // Caller passed an illegal argument
    NotFound,            // Target does not exist
    AlreadyExists,       // Target already exists (conflict)
    PermissionDenied,    // Insufficient permissions
    Io,                  // File/stream read or write failure
    Network,             // Network connection or protocol failure
    Timeout,             // Timeout (see §5 for the error surface)
    Cancelled,           // Cancelled (see §5 for the error surface)
    Busy,                // Resource busy / rate limited, retryable
    Unavailable,         // Dependency unavailable, possibly retryable
    DataCorrupted,       // Data corrupted / checksum failure
    Unsupported,         // Unsupported operation
    OutOfMemory,         // Allocation failure (observation surface; the process may be about to terminate)
    Internal,            // Unexpected internal error
}
```

### 3.2 Matching and Usage Rules

- `ErrorKind` is for **coarse-grained decisions** (retry, degradation, reporting levels, exit code mapping); fine-grained handling must use the error type itself, and `kind` must not be used for fine-grained branching.
- `Timeout` and `Cancelled` are contract-protected classifications: see §5; no implementation may disguise cancellation as another classification.
- The `kind()` return value of a user error type does not change during the error value's lifetime.
- `OutOfMemory` is special: the observation of the allocation failure path is not guaranteed to complete complex work; observation implementations must not allocate memory.
- `Internal` is the fallback classification meaning "should not happen"; it must not be used to represent known recoverable failures.
- `isRetryable(kind)` is a coarse-grained recommendation: `Network` / `Timeout` / `Busy` / `Unavailable` are retryable, the rest are not; the concrete policy is decided by the caller.
- Unknown native error codes must be mapped to `Internal`, and must not be silently mapped to `Ok`.

### 3.3 Classification Stability

The set of `ErrorKind` enum items is a cross-version compatibility commitment: it may only be appended to, and must not be renamed or removed; the semantic interpretation follows Appendix A.

## 4. Error Observation

### 4.1 Observation Is an Explicit Action

Observation is permitted only in the following explicit forms:

1. direct reads of `isErr()` / `error()` (S1 §10.1);
2. `report(r)` at boundary points (writing to diagnostic output);
3. explicitly constructed observation middleware (a wrapper function calls `report` before propagating), visible to the caller at the call site.

### 4.2 Prohibited Observation Forms

- Global error notification centers, global error handlers, and implicit logging hooks are prohibited.
- Log side effects in the conversion functions of `mapErr` / `wrap` are prohibited; conversion must be pure.
- Using observation as a substitute for handling is prohibited: after `report`, the error must still propagate or be explicitly disposed of.
- Silently swallowing errors inside a library is prohibited; when ignoring is necessary, it must be written in an explicit form so that "ignoring" is visible in code review.

### 4.3 Logging and Diagnostic Conventions

- Diagnostic output is the only built-in observation channel: single-line, containing `kind` and `describe()`, with no implicit call stack; the call stack belongs only to the fatal path (S1 §10.4).
- Richer logging capabilities (levels, context, structured fields) are provided by the library, explicit at the call site; logging capabilities must not read implicit state such as a "global current error".
- Diagnostic output must not contain sensitive information (credentials, personal data); the error type designer is responsible for the content of `describe()`.
- When the same error is observed multiple times, the output must be stable; the content must not change based on the number of observations.

### 4.4 Unhandled `Result`

- `Result` is `@mustUse`: discarding it as a bare expression statement is a compile error (S1 §10.1).
- An unhandled `Result` in a cleanup path likewise produces a diagnostic; it must not be silently ignored.
- An unhandled `Result` must not be downgraded to a warning and then continue the build; the diagnostic strength is configured by the implementation, but by default silent discarding must be prevented.

### 4.5 Resource Close Failures

Aligned with S4 §18: close failures are reported through `Result`, and the caller decides whether to observe.

- **Close contract**: the failure of a cleanup operation such as `close()` **does not equal not closed**—the cleanup action is irrevocable, and the `Result` only reports diagnostics (e.g., flush failed but the handle has been released).
- Handling pattern inside `defer`: the `Result` of a cleanup call must be explicitly checked or observed; it must not be discarded directly.
- Handling of open failures: after explicit checking, return via `Result`; `unwrapOr` only applies to scenarios with a clear fallback value.
- There is no `_` discard syntax: every ignored `Result` must be written in a visible, explicit form.

## 5. The Error Surface of Cancellation and Timeout

**Mechanism** (checkpoints, propagation, deadlines, task groups) is in Part 6; this section defines the contract that error values must satisfy.

### 5.1 The `Cancelled` Contract

- A cancelled operation reports `Err` with `kind()` equal to `ErrorKind.Cancelled`; cancellation is an error value, not a control-flow exception, not `null`, and not a boolean flag.
- **Cancellation must not be swallowed**: after catching `Cancelled`, returning `Ok` or converting to another classification is allowed only in the race case where "work completed before cancellation".
- **Cancellation must not be disguised**: failures for non-cancellation reasons must not be reported as `Cancelled`.
- A cancelled operation must have stopped producing externally visible side effects before it may return `Cancelled`.
- Cleanup paths must not be skipped due to another cancellation; cancellation requests during cleanup are queued and handled after cleanup completes (Part 6 §4.4).
- The signature of a cancellable function is unchanged: it is still `Result<T,E>`; `E` must be able to express `Cancelled` (directly or via `kind()`).

### 5.2 The `Timeout` Contract

- A timeout reports `Err` with `kind()` equal to `ErrorKind.Timeout`; a timeout is not a panic and not fatal.
- After a timed-out operation returns, the underlying resource state must be in the deterministic state declared by the documentation (committed / not committed, never "indeterminate").
- Timeout and cancellation are isomorphic: the §5.1 contracts of stopping side effects, not disguising, and not skipping cleanup also apply to timeout.
- A timeout is a caller-driven cancellation; whether to also cancel the underlying operation is explicitly decided by the caller (Part 6 §5.1).

### 5.3 Completion-First and the Race Window

- When completion races with cancellation, "completion first" applies: if the work completed before cancellation arrived, success may be returned.
- The race window determination must be deterministic; the result must not change randomly due to scheduling timing.
- After cancellation returns, no new externally visible side effects may be produced.
- Fallback methods (such as `unwrapOr`) do not treat `Cancelled` specially: falling back is an explicit decision to swallow the cancellation, visible at the call site.

## 6. Boundary Conversion

### 6.1 Boundary List

| Boundary | Conversion responsibility | Specification |
| --- | --- | --- |
| Process entry (`main` return) | §6.2 | S1 §11 |
| FFI cross-language calls | §6.3 | Part 8 Appendix A; S4 §19 |
| Task boundary (join / group close) | Part 6 §3.6 | S4 §11 |
| Out-of-process communication (network, IPC) | Application layer; this document only gives principles | §6.4 |

### 6.2 Process Entry: Exit Code Mapping

The two signatures of `main` are in S1 §11.1. Exit code mapping for `Int main`:

| Exit case | Exit code |
| --- | --- |
| Normal return | `0` |
| Returns a nonzero value | That value is used as the exit code as-is |
| Initialization or runtime fatal (panic) | Fixed exit code `134`; must not be `0` |

- `main` cannot return `Result` (`try` cannot be used in `main`, S1 §10.2); when the entry point needs to report failure, use `Int main` to explicitly map the error to an exit code.
- Exit code range conventions: `1—63` application-defined; `64` usage error (`InvalidArgument`); `69` dependency unavailable (`Unavailable`); `70` internal error (`Internal`); `134` reserved for fatal. Not following them does not constitute a language error.

### 6.3 FFI Boundary

- `Result` is a built-in value type of XNull and **does not cross language boundaries**: function signatures entering FFI must not contain `Result` type parameters or return values; errors are expressed as error codes/out-parameters (Part 8 Appendix A).
- Cross-language error conversion must be explicit: wrapper functions map FFI error codes to local error types (`kind` is selected according to the semantics in Appendix A); silently mapping unknown error codes to `Ok` is prohibited.
- Cancellation/timeout reported by the native side to XNull must be mapped to `Cancelled` / `Timeout`, and must not be downgraded to `Internal`.
- Error code mapping must be deterministic; the same error code must not be mapped to different classifications at different call sites.

### 6.4 Out-of-Process Communication

- Error mapping for external protocols (HTTP, RPC) is written explicitly by the application; no implicit "automatic error-to-status-code" mechanism is provided.
- Error information facing external systems may only come from `describe()` or an explicitly constructed response body; internal error type fields do not leak automatically.
- Sensitive information must not enter external error text; when internal and external information need to be distinguished, the application constructs it explicitly.

## 7. Structured Cleanup and Error Paths

S4 §17 defines the cleanup responsibility model: defer LIFO, `goto` / `throw` / process exit do not execute defer, fatal has no cleanup guarantee. This document supplements the usage rules for error paths:

- `errdefer` is for **compensation** (the reverse action on failure: rollback, release, decrement counters); `defer` is for **unconditional cleanup**. The selection criterion: whether the action must also happen on the success path.
- The compensation action itself fails: compensation is best-effort, and `Result` handling within compensation follows the §4.5 pattern; a compensation failure must not block propagation of the original error (no `return` in an `errdefer` body, S1 §10.3).
- Error paths do not introduce a new level of cleanup responsibility: the use-site close pattern for resources (S4 §17) behaves consistently across the three paths of `try` propagation, `Err` return, and normal return.
- Partially completed state: when a function modifies external state in multiple steps and fails midway, it must either roll back to the pre-entry state in `errdefer`, or carry "completed steps" information in the error type for the caller to decide; silently leaving a half-completed state is a design error.
- Cleanup bodies must not contain control transfer, `try`, or `throw`; cleanup must be non-throwing.

## Appendix A. `ErrorKind` Semantics Table

| Classification | Semantics | Retryable? | Typical source |
| --- | --- | --- | --- |
| `InvalidArgument` | Caller violates a precondition | No (fix the call) | Argument validation |
| `NotFound` | Target does not exist | Depends on semantics | Lookup, resource location |
| `AlreadyExists` | Creation conflict | No (handle the conflict first) | Creation, registration |
| `PermissionDenied` | Insufficient permissions | No (authorization required) | Access control |
| `Io` | Local I/O failure | Depends on the operation | Files, streams |
| `Network` | Network failure | Often retryable | Connections, protocols |
| `Timeout` | Timeout (§5.2) | Retryable | Tasks, I/O |
| `Cancelled` | Cancelled (§5.1) | — | Task system |
| `Busy` | Resource busy / rate limited | Retryable (with backoff) | Concurrency control |
| `Unavailable` | Dependency unavailable | Retryable | Dependency services |
| `DataCorrupted` | Data corrupted | No (recovery process required) | Validation, deserialization |
| `Unsupported` | Unsupported operation | No | Capability probing |
| `OutOfMemory` | Allocation failure | — | Runtime |
| `Internal` | Unexpected internal error | No (it is a bug) | Fallback classification |

## Appendix B. Recoverable vs. Unrecoverable Boundary Comparison

| Case | Path | Basis |
| --- | --- | --- |
| Illegal arguments, missing target, permissions, network, timeout, cancellation | `Result` / `Err` | This document; Part 6 |
| Resource close failure | `Result` (close contract §4.5) | S4 §18 |
| Division by zero, shift out of range, index out of bounds, null reference dereference, failed `as`, call on `null` | panic / fatal | S1 §7.1, §10.4 |
| Explicit `throw` (contract violation) | panic / fatal | S1 §10.4 |
| Allocation failure, stack overflow | fatal (observation surface `OutOfMemory` see §3.2) | S4 §22 |
| `deinit` resurrection, finalizer chain panic | Terminate the process | S4 §15 |
