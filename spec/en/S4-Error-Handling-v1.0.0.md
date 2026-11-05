# XNull Specification, Part 4: Error Handling

> **Translation notice**: This is an English translation of the normative Chinese specification
> 《XNull 解决方案 第 4 部分：错误处理》v1.0.0. The Chinese original prevails in case of any
> divergence. Translation version follows the original's version number.

| Item | Content |
| --- | --- |
| Document ID | Part 4 (S4) |
| Document Version | 1.0.0 |
| Specification Status | Normative (approved 2026-11-05) |
| Release Date | 2026-11-05 |
| Normativity | Normative document; language per RFC 2119 (see reference R1) |
| Upstream Dependencies | S1 (Part 1 §6.9, §10), S2 (§6.6), S3 (§9, §17, §18, §11.4) |
| Downstream Dependencies | Part 5 (cancellation mechanism), Part 7 (boundary conversion), Part 6 (`xdk.errors` API contract) |

Division of responsibility for this document: **the syntax and propagation semantics of `Result` / `try` / `defer` / `errdefer` / `throw` are defined in S1 §10 and are not repeated here**. This document defines the semantics deferred by S1/S2/S3 — error observation, cancellation, timeouts, `ErrorKind`, logging and diagnostics, boundary conversion, and the formal definitions of the `Error` protocol and the `xdk.errors` package.

## 1. Positioning and Core Stances

### 1.1 Division of Normative Responsibility

| Topic | Owner |
| --- | --- |
| `Result<T,E>` syntax, `try` propagation, `defer` / `errdefer`, `throw` / fatal | S1 §10 |
| Resource-release failure paths, cleanup-responsibility model, the `Result` GC-box implementation | S3 §17, §18, §9; this document §4.4, §8 complete the observation side |
| Cancellation **mechanism** (tokens, task trees, scoped cancellation) | Task specification |
| Cancellation **error surface** (the `Cancelled` contract) | This document §5 |
| Timeout mechanism (timers, scheduling) | Task specification / XDK specification |
| Timeout **error surface** (the `Timeout` contract) | This document §6 |
| Handles and leases at the FFI boundary | S3 §19, Part 7 §2.2/§4 |
| Cross-language error **conversion** | This document §7.3 |

### 1.2 Core Stances

- Errors are values. Recoverable failure travels only through the `Result` path; `panic` / fatal cannot be caught and terminate the process (S1 §10.4).
- Error observation is boundary behavior, not control flow. Global notification centers, implicit recovery, and implicit logging are forbidden.
- Fault isolation for high-availability services is designed at the process boundary: a single request handler MUST NOT catch a fatal and continue serving (S4 §3.4). The recoverable/irrecoverable division is given in §2.5 (Appendix B).
- Memory reclamation and resource release are two separate responsibilities: the runtime manages memory only; resource release is an explicit responsibility at the point of use (S3 §17–18).

### 1.3 Boundary with the XDK (indicative binding declaration)

The `xdk.*` package names, type names (`Error`, `ErrorKind`), and function signatures (`wrap` / `mapErr` / `report`) appearing in this document are governed by Part 6 (XDK); this part defines only their **semantics and invariants**: the semantics of error observation (§4), the semantics and contracts of each `ErrorKind` classification (§3, Appendix A), the cancellation/timeout error surfaces (§5, §6), boundary conversion rules (§7), and cleanup patterns (§8). Name and signature changes follow Part 6's version process and do not affect this specification's semantics.

## 2. Error Types and the `Error` Protocol

### 2.1 Legal Shapes of Error Types

Per S1 §10.5: the error type `E` may be an enumeration, struct, class, or an `Error`-protocol implementation; `E` cannot be `void`. This document adds:

- `E` MUST NOT be a `Result` (nesting `Result<Result<..>>` as an error type is forbidden; a type `E` containing `Result` fields is analyzed per S3 §9's GC-box rule).
- Error types SHOULD be data carriers: fields are diagnostic information (context, cause, location) and carry no mutable state.
- Error-type selection rule (settled): prefer enumerations (closed error sets) or structs (context carriers); classes only where diagnostic fields must be shared via inheritance-like reuse.

### 2.2 The `Error` Protocol (Formal Definition)

S1 §10.5 references "an `Error`-protocol implementation" without defining the protocol; this document completes it. The `Error` protocol is declared by the `xdk.errors` package:

```x
protocol Error {
    ErrorKind kind();        // general classification; see §3
    String describe();       // single-line diagnostic; MUST NOT contain newlines or control characters
}
```

- `describe()` MUST be stable: multiple calls on the same error value within one process return identical content (error-type fields are immutable; a violation is a bug in the error type's declarer).
- A type implementing the `Error` protocol must also satisfy the legal forms of `E` in S1 §10.5.
- The language's built-in `panic` diagnostics do not pass through the `Error` protocol; fatal paths are printed directly by the runtime (S3 §25).

### 2.3 Helper Functions (`xdk.errors`)

`Result` is a predefined type and cannot be extended via `extension` (S2 §11.1); error helpers are provided as `xdk.errors` top-level functions:

| Function | Signature (indicative) | Semantics |
| --- | --- | --- |
| `wrap` | `<E>(Result<T,E>, E) -> Result<T,E>` | On failure, discards the original error and returns the new one. Used to convert internal classification errors into outward contract errors |
| `mapErr` | `<E1,E2>(Result<T,E1>, (E1) -> E2) -> Result<T,E2>` | On failure, maps the error with the caller-supplied function; success passes through unchanged |
| `report` | `<E: Error>(Result<T,E>) -> void` | On failure, writes `kind()` and `describe()` to the diagnostic output; does nothing on success. For boundary observation points only |

- `wrap`'s discarding of the original error is an explicit decision; where a cause chain is needed, the error type carries its own `cause` field assembled via `mapErr`.
- No implicit error stringification is provided; `describe()` is the only text outlet.
- The language's method set (`isOk` / `isErr` / `value` / `error` / `unwrapOr`) is governed by S1 §9.1; this document extends no language methods.

## 3. The `ErrorKind` Classification System

### 3.1 Built-in Classifications

`ErrorKind` is a simple enumeration declared by `xdk.errors`:

```x
enum ErrorKind {
    InvalidArgument,     // caller passed an illegal argument
    NotFound,            // target does not exist
    AlreadyExists,       // target already exists / conflict
    PermissionDenied,    // insufficient permission
    Io,                  // file/stream read-write failure
    Network,             // network connection, protocol failure
    Timeout,             // timeout (contract in §6)
    Cancelled,           // cancelled (contract in §5)
    Busy,                // resource busy / rate-limited; retryable
    Unavailable,         // dependency unavailable; possibly retryable
    DataCorrupted,       // data corruption / checksum failure
    Unsupported,         // unsupported operation
    OutOfMemory,         // allocation failure (observation surface; process may be about to terminate)
    Internal,            // unexpected internal error (equivalent to "should not happen")
}
```

### 3.2 Matching and Usage Rules

- `ErrorKind` is for **coarse-grained decisions** (retry, degradation, report tiering, exit-code mapping); fine-grained handling MUST use the error type itself (enum cases or fields); branching on `kind` for fine-grained control is FORBIDDEN.
- `Timeout` and `Cancelled` are contract-protected classifications: see §5, §6; no implementation may disguise cancellation as another classification.
- The `kind()` return value of a user error type is immutable for the lifetime of the error value.
- `OutOfMemory` is special: observation on the allocation-failure path cannot guarantee it can perform complex work; the observation implementation MUST NOT allocate memory (guaranteed by the runtime's diagnostic channel, see §9).

### 3.3 Classification Stability

The set of `ErrorKind` cases is a cross-version compatibility commitment: cases may only be appended, never renamed or removed; semantic interpretation is governed by Appendix A of this document.

## 4. Error Observation

### 4.1 Observation Is an Explicit Action

Only the following explicit forms of observation are permitted:

1. Direct reads via `isErr()` / `error()` (S1 §10.1);
2. `xdk.errors.report(r)` at boundary points (writes to diagnostic output);
3. Explicitly constructed observation intermediaries (wrapper functions that `report` first, then propagate), visible at the call site.

### 4.2 Forbidden Forms of Observation

- Global error notification centers, global error handlers, and implicit logging hooks are forbidden (prohibited by S1 §10.5; confirmed here as permanent design).
- Producing log side effects inside `mapErr` / `wrap` transformation functions is forbidden (transformations MUST be pure; observation occurs only in the forms of §4.1).
- Substituting observation for handling is forbidden: after `report`, the error MUST still be propagated or explicitly disposed of; "reporting counts as handling" is not a legal pattern.

### 4.3 Logging and Diagnostic Conventions

- The diagnostic output is the only built-in observation channel: single-line, containing `kind` and `describe()`, with no implicit call stack (the call stack belongs exclusively to the fatal path, S1 §10.4).
- Richer logging capability (levels, context, structured fields) is provided by the XDK logging package, explicitly at the call site; the logging package MUST NOT read implicit state such as "the global current error."
- Diagnostic output MUST NOT contain sensitive information (credentials, personal data); the error-type designer is responsible for the content of `describe()`.

### 4.4 Resource-Release Failure Paths

Aligned with S3 §18 (release failures are reported via `Result`; the caller decides whether to observe). This document defines the release contract and handling patterns:

- **Release contract**: a failure of a `close()`-style cleanup operation **does not mean the resource was not closed** — the cleanup action is irrevocable; `Result` only reports diagnostics (e.g., flush failed but the handle is already released). XDK resource APIs MUST declare this contract; an API violating it (resource still usable after failure) is a contract bug.
- **Handling pattern inside `defer`** (`try` / `return` are forbidden inside `defer` bodies, S1 §10.3; and an unhandled `Result` of a cleanup call produces a diagnostic):

```x
static void process(final String path) {
    final File input = File.open(path).unwrapOr(...); // open failure must be disposed explicitly, see below
    defer {
        final Result<void, IoError> r = input.close();
        if (r.isErr()) {
            xdk.errors.report(r);      // explicit observation; failure does not change the released fact
        }
    }
    // ... use input
}
```

- The disposal pattern for open failure: `unwrapOr` with a fallback value does not fit "must abort" scenarios; the correct form is an explicit check followed by a `Result` return:

```x
static Result<void, IoError> process(final String path) {
    final Result<File, IoError> opened = File.open(path);
    if (opened.isErr()) {
        return Err(opened.error()!);
    }
    final File input = opened.value()!;
    defer { /* release pattern as above */ }
    // ...
    return Ok(void);
}
```

- The absence of a `_` discard syntax is a design decision: every ignored `Result` must be written in a visible explicit form, making "ignoring" visible in code review.

## 5. Cancellation

### 5.1 Division and Model

- The **mechanism** of cancellation (cancellation tokens, task trees, scoped cancellation, automatic propagation) is defined by the task specification; S3 §11.4 confirms the shared responsibility.
- This document defines the **error surface** of cancellation, applicable uniformly to all cancellable operations, regardless of mechanism details.

### 5.2 The `Cancelled` Contract

- A cancelled operation reports via `Err` with `kind()` equal to `ErrorKind.Cancelled`; cancellation is an error value — not a control-flow exception, not `null`, not a boolean flag.
- **Swallowing cancellation is forbidden**: catching `Cancelled` and returning `Ok` or converting it to another classification is permitted only in the race where "the work completed before cancellation" (completion-first semantics; the race window is adjudicated by the task specification).
- **Disguising cancellation is forbidden**: failures with non-cancellation causes MUST NOT be reported as `Cancelled`.
- A cancelled operation MUST have stopped producing externally visible side effects before returning `Cancelled`; "cancelling while continuing to write" is an implementation bug.
- Cleanup paths (`defer` / `errdefer` bodies) MUST NOT be skipped due to a further cancellation; cancellation requests arriving during cleanup are queued until cleanup completes, as governed by the task specification.

### 5.3 Interaction with `Result`

- Cancellable function signatures are unchanged: still `Result<T,E>`; the error type `E` must be able to express `Cancelled` (directly or via `kind()`).
- Fallback methods such as `unwrapOr` treat `Cancelled` without special handling: falling back is an explicit decision to swallow the cancellation, visible at the call site. The framework-level guarantee "cancellation must keep propagating upward" is enforced by the task specification at task boundaries.

## 6. Timeouts

### 6.1 The Timeout Error Surface

- A timeout is reported via `Err` with `kind()` equal to `ErrorKind.Timeout`; a timeout is **not a panic** and not fatal.
- The timeout **mechanism** (timers, monitoring points) is defined by the task specification and the XDK specification; this document constrains only the contract:
  - Timeouts are isomorphic to cancellation: a timeout is a caller-driven cancellation; all contracts of §5.2 (side effects stopped, no disguise, cleanup not skipped) apply equally to timeouts;
  - After a timed-out operation returns, the underlying resource state MUST be in the documented deterministic state (committed / not committed — never "indeterminate").

### 6.2 Precision Promise Boundary

- XNull does not promise hard real time (S3 §0); a timeout takes effect "as soon as possible after, but not before, the deadline point," and a small overshoot past the deadline is legal behavior.
- Scenarios with contractual timeout-precision requirements (hardware protocols, etc.) are outside the language's scope and must be carried by a dedicated implementation outside the runtime.

## 7. Boundary Conversion

### 7.1 Boundary Inventory

| Boundary | Conversion Responsibility | Specification |
| --- | --- | --- |
| Process entry (`main` return) | This document §7.2 | S1 §12 entry rules |
| FFI cross-language calls | This document §7.3 | Part 7 §7; S3 §19 |
| Task boundaries (join / callback delivery) | Task specification | S3 §11.4 |
| Out-of-process communication (network, IPC) | Application layer; this document gives principles only | §7.4 |

### 7.2 Process Entry: Exit-Code Mapping

`main` has two signatures (S1 §11.2): `static void main` and `static Int main`. This document defines the exit-code mapping convention for `Int main`:

| Exit Situation | Exit Code |
| --- | --- |
| Normal return | `0` |
| Non-zero value returned | That value used as-is as the exit code |
| Initialization or runtime fatal (panic) | Fixed exit code `134` (settled; MUST NOT be `0`) |

- `main` cannot return a `Result` (`try` cannot be used in `main`, S1 §10.2); when the entry needs to report failure, use `Int main` to map errors to exit codes explicitly, with the mapping rules decided by the application and written explicitly at the entry point.
- Exit-code range conventions (settled, not acceptance-tested): `1–63` application-defined; `64` usage error (`InvalidArgument`); `69` dependency unavailable (`Unavailable`); `70` internal error (`Internal`); `134` reserved for fatal. Non-conformance is not a language error, but tooling may issue style warnings. The convention follows BSD `sysexits` practice for operational scripts.

### 7.3 The FFI Boundary

- `Result` is an XNull built-in value type and **does not cross language boundaries**: signatures of functions entering FFI MUST NOT contain `Result`-typed parameters or returns (errors are expressed as error codes / out-parameters; see Part 7 §7.1; this clause is the precondition constraint).
- Cross-language error conversion MUST be explicit: an XNull-side wrapper function maps FFI error codes to local error types (`kind` chosen per Appendix A semantics); silently mapping unknown error codes to `Ok` is FORBIDDEN.
- Cancellation/timeouts reported from the native side MUST map to the `Cancelled` / `Timeout` classifications; degrading them to `Internal` is FORBIDDEN.

### 7.4 Out-of-Process Communication Principles

- Error mapping for external protocols (HTTP, RPC) is written explicitly by the application; XNull provides no implicit "error auto-converted to status code" mechanism.
- Error information exposed to external systems may only come from `describe()` or explicitly constructed response bodies; internal error-type fields are not automatically leaked.

## 8. Structured Cleanup and Error Paths

S3 §17 defines the cleanup-responsibility model (defer LIFO; `goto` / `throw` / process exit do not run defer; fatal carries no cleanup guarantee). This document supplements the rules for error paths:

- `errdefer` is for **compensation** (reverse actions on failure: rollback, release, counter decrement); `defer` is for **unconditional cleanup**. The selection criterion: whether the action must also occur on the success path.
- Compensation failure: compensation is best-effort; `Result` handling inside compensation follows the §4.4 pattern; compensation failure MUST NOT block the propagation of the original error (`return` is forbidden inside `errdefer` bodies, S1 §10.3).
- Error paths introduce no new cleanup-responsibility tier: the point-of-use release pattern for any resource (S3 §17) behaves identically on the `try`-propagation, `Err`-return, and normal-return paths (acceptance MEM-10); this document adds no new mechanism.
- Partial-completion state: when a function fails midway after multi-step external-state modification, it must either roll back to the pre-entry state in `errdefer`, or carry "completed steps" information in the error type for the caller to decide; silently leaving a half-completed state is a design error.

## 9. Implementation Boundaries and Release Gates

Same rules as S2 §16: this section is a release gate, not a "not yet enforced" list.

- Until the `xdk.errors` package (`Error` protocol, `ErrorKind`, `wrap` / `mapErr` / `report`) is implemented, XDK APIs depending on it MUST NOT be released.
- The diagnostic output channel MUST be heap-allocation-free (ensuring observability under `OutOfMemory`); where this is impossible, degradation to a minimal single-line output is permitted, but silently losing fatal reports is FORBIDDEN (aligned with S3 §25).
- Runtime verification points for the `Cancelled` / `Timeout` contracts (side effects stopped, cleanup not skipped) are covered by the task specification's acceptance; this document's acceptance covers the error-surface mapping.
- Unhandled-`Result` diagnostics (S1 §10.5) MUST be configurable as compile errors (`@mustUse` strength); the default strength is decided by the implementation and pinned by the project-configuration specification.

## 10. Acceptance Matrix

| ID | Domain | Acceptance Content | Verdict |
| --- | --- | --- | --- |
| OBS-01 | Observation | `report` outputs one line with kind and describe; zero output on success; transformation purity is verifiable | Any behavior violating §4 fails |
| OBS-02 | Observation | Global notification centers, implicit recovery, observation side effects are rejected | Compile error or no such API |
| OBS-03 | Observation | Unhandled cleanup `Result` inside defer produces a diagnostic; the §4.4 pattern produces zero diagnostics | Missing diagnostic fails |
| KIND-01 | Classification | `ErrorKind` cases match Appendix A; `kind()` is immutable over the error lifetime | Compile error or runtime-invariant failure |
| CANCEL-01 | Cancellation | Cancellation reported as `Err` + `Cancelled`; side effects stopped; swallowing/disguise forms rejected by contract tests | Runtime contract tests |
| CANCEL-02 | Cancellation | Cleanup paths not skipped due to further cancellation | Runtime contract tests |
| TIMEOUT-01 | Timeout | Timeout is `Err` + `Timeout`, not panic; resource end-state is deterministic | Any behavior violating §6 fails |
| BOUND-01 | Boundary | `Int main` exit-code mapping correct; fatal exit code non-zero | Process-level tests |
| BOUND-02 | Boundary | Signatures containing `Result` MUST NOT pass through FFI; unknown error codes MUST NOT map to `Ok` | Compile error or contract tests |
| BOUND-03 | Boundary | Cancellation/timeout via FFI not degraded to `Internal` | Contract tests |
| CLEAN-01 | Cleanup | `errdefer` compensation failure does not block original-error propagation; partial-completion state has rollback or state reporting | Any behavior violating §8 fails |

## Appendix A. `ErrorKind` Semantics Table

| Classification | Semantics | Retryable? | Typical Source |
| --- | --- | --- | --- |
| `InvalidArgument` | Caller violated a precondition | No (fix the call) | Argument validation |
| `NotFound` | Target does not exist | Depends | Lookup, resource location |
| `AlreadyExists` | Creation conflict | No (resolve the conflict first) | Creation, registration |
| `PermissionDenied` | Insufficient permission | No (authorization needed) | Access control |
| `Io` | Local I/O failure | Depends on the operation | Files, streams |
| `Network` | Network failure | Often retryable | Connections, protocols |
| `Timeout` | Timeout (§6 contract) | Retryable | Tasks, I/O |
| `Cancelled` | Cancelled (§5 contract) | — | Task system |
| `Busy` | Resource busy / rate-limited | Retryable (backoff) | Concurrency control |
| `Unavailable` | Dependency unavailable | Retryable | Dependent services |
| `DataCorrupted` | Data corruption | No (recovery process needed) | Checksums, deserialization |
| `Unsupported` | Unsupported operation | No | Capability probing |
| `OutOfMemory` | Allocation failure | — | Runtime |
| `Internal` | Unexpected internal error | No (a bug) | Fallback classification |

## Appendix B. Recoverable vs. Irrecoverable Boundary Table

| Situation | Path | Basis |
| --- | --- | --- |
| Illegal argument, missing target, permission, network, timeout, cancellation | `Result` / `Err` | This document |
| Resource-release failure | `Result` (release contract §4.4) | S3 §18 |
| Division by zero, shift out of range, subscript out of range, null dereference, failed `as`, call on `null` | panic / fatal | S1 §7.1, §10.4 |
| Explicit `throw` (contract violation) | panic / fatal | S1 §10.4 |
| Allocation failure, stack overflow | fatal (observation surface `OutOfMemory`, see §3.2) | S3 §25 |
| `deinit` resurrection, finalization-chain panic | Terminate process | S3 §16 |
