# XNull Compiler Parallel Multi-threaded Compilation Detailed Design

> Status: Design draft v1 · 2026-11-15
> Scope: `src/cli/`, `src/compiler/`, `src/build/`, `src/toolchain/`, `src/runtime/rt_task.c`, `rt_sync.c`
> Related: Design 01 (backend), Design 02 (AST/Token), Design 03 (containers), Design 05 (GC/ARC), Design 07 (PGO)
> Algorithm selection: every implementation node lists candidate algorithms, complexity, pros and cons, and the rationale for the choice; see the "Algorithm Selection and Comparison" section.

## 1. Conclusion

The current compilation pipeline is single-threaded:

```text
lex → parse → sema → codegen → emit C → cc → link
```

`src/compiler/codegen/Codegen.x` still has a large amount of global mutable state (`ESC_EXPR_N`, `STAGE_T`, the `unq` table, etc.), and the symbol table in `src/mini/main.x` is a parallel `List<String>` array; neither is thread-safe.

Goal: without changing the output, compress compilation time approximately linearly with the number of cores:

| Stage | Parallelism | Target speedup on 8 cores |
|---|---|---|
| lex/parse | per file | 6–7x |
| sema | per module DAG / file | 4–5x |
| MIR optimization | per function | 5–6x |
| C codegen | per function/module | 5–6x |
| cc compilation | per C file (external process) | 6–8x |
| link | serial | 1x |

Key constraint: **`--jobs=1` and `--jobs=N` produce byte-identical output**, diagnostic order is stable, and builds are reproducible.

## 2. Current State and Blockers

### 2.1 Pipeline

`src/toolchain/xnull-build.sh`:

```text
AST dump (xparser / Go oracle)
  → xnullc (xn-s4)
  → C files
  → cc + 14 runtime C sources
  → executable
```

Every step runs sequentially.

### 2.2 Global State

`Codegen.x`:

```x
static Int ESC_EXPR_N = 0
static Int ESC_STMT_N = 0
static Int ESC_BLOCK_N = 0
static Int ESC_MARK_N = 0
static Int INN_ITERS = 0
static Int FN_EMIT_N = 0
static Int STAGE_T = 0
static Bool STAGE_LOG = false
static Bool FAST_ROOTS = false
static Bool FAST_SP = false
```

There are also the `unq` table, string escape tables, and so on. Under parallel codegen these states contaminate one another.

### 2.3 Containers

- `Sem` in `src/mini/main.x` stores functions/variables/fields in parallel `List<String>` arrays;
- `fld(N, String)` in `Codegen.x` looks up fields linearly;
- there are no thread-local arenas or immutable snapshots.

### 2.4 Runtime Tasks

`xrt.h` already provides:

```c
xrt_task_group *xrt_task_group_new(xrt_context *parent);
int32_t xrt_task_group_spawn(xrt_task_group *g, xrt_task_body body, void *env, xrt_task **out);
int32_t xrt_task_join(xrt_task *t, xrt_task_result *out);
```

But these are runtime tasks for **user programs**, not a compiler thread pool. The compiler can use them, but note:

- the task body is an XNull function, and scheduling/ARC/GC carries overhead;
- a large number of fine-grained tasks amplifies that overhead;
- using a native thread pool (C/FFI) inside the compiler is more controllable; the XNull task layer can serve as a later self-hosting goal.

## 3. Goals and Non-Goals

### 3.1 Goals

| Metric | Target |
|---|---|
| 8-core speedup (100k lines) | ≥ 4x end to end |
| lex/parse on 8 cores | ≥ 6x |
| sema on 8 cores | ≥ 4x |
| MIR opt/codegen on 8 cores | ≥ 5x |
| Output determinism | byte-identical for `jobs=1..N` |
| Diagnostic order | stable, reproducible |
| Memory | ≤ 1.5x single-threaded |
| Compile-time overhead (2 cores) | ≤ 10% |
| Semantics | completely unchanged |

### 3.2 Non-Goals

- No distributed compilation;
- no incremental compilation (separate project);
- no background language server protocol;
- no change to the concurrency semantics of user programs;
- no parallel linking in the first version.

## 4. Parallel Architecture

### 4.1 Layered Parallelism

```text
┌───────────────────────────────────────────────────────────────┐
│ 1. File discovery / module graph (serial, fast)               │
├───────────────────────────────────────────────────────────────┤
│ 2. lex + parse (parallel by file)                             │
├───────────────────────────────────────────────────────────────┤
│ 3. module sema (parallel by dependency DAG waves)             │
├───────────────────────────────────────────────────────────────┤
│ 4. HIR → MIR (parallel by function)                           │
├───────────────────────────────────────────────────────────────┤
│ 5. MIR opt + C codegen (parallel by function)                 │
├───────────────────────────────────────────────────────────────┤
│ 6. C file merge / ordering (serial)                           │
├───────────────────────────────────────────────────────────────┤
│ 7. cc compilation (parallel by C file, external process pool) │
├───────────────────────────────────────────────────────────────┤
│ 8. link (serial)                                              │
└───────────────────────────────────────────────────────────────┘
```

### 4.2 Dependency Graph

```c
typedef struct {
    uint32_t module_id;
    uint32_t *deps;       /* ModuleId */
    uint32_t dep_n;
    uint32_t dependents_n;
    uint8_t  state;       /* pending/ready/running/done/failed */
} ModuleNode;
```

- the module graph comes from the `import` closure;
- topological sorting yields the waves;
- modules within the same wave can run sema in parallel;
- cyclic dependencies are an error (the language does not allow them);
- a single-file project degenerates to 1 module and can still be parallelized per function.

### 4.3 Task Granularity

| Stage | Task | Granularity |
|---|---|---|
| lex/parse | one file | medium |
| sema | one module | medium |
| HIR→MIR | one function | small |
| opt | one function | small |
| codegen | one function | small |
| cc | one C file/module | large (process) |

Too fine (per instruction) makes task overhead high; too coarse (the whole project) lowers parallelism. Per function is the right granularity for the MIR stages.

## 5. Task System

### 5.1 Native Thread Pool (first version)

```c
typedef struct XnJob {
    void (*fn)(struct XnJob *);
    void *arg;
    struct XnJob *next;
    _Atomic uint32_t deps;
    _Atomic uint32_t state;
} XnJob;

typedef struct {
    XnJob **deques;        /* per-worker work-stealing deque */
    uint32_t worker_n;
    _Atomic uint32_t stop;
    XnContext *cancel;
} XnPool;
```

- worker count = `min(CPU cores, --jobs)`;
- one deque per worker;
- idle workers steal tasks from the tail of other deques;
- when a task completes it decrements the dependency counter, and at zero the task is enqueued;
- cancellation: a `cancel` flag; workers check it and exit;
- errors: the first error is recorded and the remaining tasks are cancelled.

### 5.2 XNull Task Layer (later)

- wrap the thread pool with `xdk.concurrent`/`xrt_task`;
- task bodies are XNull functions;
- pros: after self-hosting, the compiler no longer needs a C thread pool;
- cons: ARC/GC/scheduling overhead; the first version uses the native pool, keeping the interface replaceable.

### 5.3 Task Dependencies

```c
job->deps = 2;
spawn(job_a);
spawn(job_b);
/* when job_a/job_b finish, job->deps--; enqueue when it reaches zero */
```

- no blocking waits (avoids thread starvation);
- the main thread also participates in work (work-stealing);
- results are merged after all tasks complete.

## 6. Determinism Design

The biggest risk for a parallel compiler is nondeterministic output. The rules:

1. **ID allocation is ordered by content**, not by arrival order:
   - `NameId`: by string byte order / hash shard;
   - `TypeId`: by `(module path, type name)`;
   - `FunctionId`: by `(module path, signature)`;
   - `SymbolId`: by `(scope, name)`;
2. **Output order is fixed**:
   - modules sorted by path;
   - functions sorted by `FunctionId`;
   - types sorted by `TypeId`;
   - never output by iterating a hash table directly;
3. **Diagnostic ordering**:
   - key `(file path, span.start, code, message)`;
   - all diagnostics are first collected into thread-local vectors, then merged and sorted at the end;
4. **Temporary file naming**:
   - use a content hash, not PID/timestamps;
5. **Hash seed**:
   - a fixed seed within a build, not random; random DoS-resistant seeds are used only for runtime Maps, never for compiler output;
6. **Floating point**:
   - no floating point for IDs/sorting; constant folding follows deterministic rules;
7. **Parallel reduction**:
   - counts/statistics use integer atomic adds, whose results are order-independent;
   - set merging uses sort-then-merge, not hash iteration order.

Acceptance: the C output SHA-256 is identical for `--jobs=1` and `--jobs=8`; diagnostics are line-for-line identical for `--jobs=1..N`.

## 7. Thread-Safe Data

### 7.1 Immutable Snapshots

- after parse completes, the AST is read-only;
- after sema completes, the HIR is read-only;
- MIR is per-function and independent; functions share no mutable nodes;
- the type table/symbol table are frozen after sema and read-only.

### 7.2 Thread-Local

- lexer/parser: independent arena and token stream per file;
- sema: independent scopes/diagnostics per module;
- MIR/codegen: independent arena and output buffer per function;
- statistics counters: thread-local, merged at the end.

### 7.3 Shared Read-Only

- `SourceMap`: read-only;
- `Interner`: sharded reads/writes, atomic `NameId` allocation;
- `TypeTable`: written during sema, read-only afterwards;
- configuration/options: read-only.

### 7.4 Shared Mutable (avoid as much as possible)

- global diagnostic collection: thread-local + merge;
- global ID allocation: atomic counters or pre-allocated ranges;
- caches: sharded + atomic.

## 8. Per-Stage Design

### 8.1 File Discovery

- scan the entry point/project manifest serially;
- build the module graph;
- compute topological waves;
- estimate token/node counts and pre-allocate arena sizes.

### 8.2 lex + parse

- one job per file;
- output `ParsedFile { TokenStream, AstArena, Diags }`;
- no dependencies between files;
- failed files are marked `failed` and do not block other files;
- the main thread merges the ASTs, sorted by file path.

### 8.3 sema

- by module DAG waves;
- modules in the same wave run in parallel;
- each module's imported symbol tables are read-only;
- cross-module type checking requires the dependency modules' export tables to be complete first;
- diagnostics are thread-local and merged at the end;
- functions within a module can be parallelized further (phase two).

### 8.4 HIR → MIR

- one job per function;
- inputs are the read-only HIR/type table;
- output is `MFunction` + a thread-local arena;
- no shared mutable state between functions;
- inlining/devirtualization need the callgraph/RTA: first build the global callgraph serially, then optimize each function in parallel;
- the PGO profile is read-only.

### 8.5 Optimization

- function-level passes run in parallel;
- cross-function inlining reads callee MIR (read-only) and writes caller MIR (local);
- inlining budgets/callgraph updates use atomic counters;
- iterating to a fixed point may require global barriers (all functions finish one round before the next);
- first version: independent per-function optimization + limited cross-function inlining (read-only callee).

### 8.6 C codegen

- each function generates into an independent `CBuf`;
- type declarations/global tables are aggregated by the main thread;
- function bodies are concatenated in `FunctionId` order;
- emit the prelude exactly once;
- write to a temporary file, then atomically rename at the end.

### 8.7 cc Compilation

- generate multiple `.c` files per module (rather than one huge file);
- invoke `cc` concurrently from an external process pool;
- each `.c` compiles independently to `.o`;
- linking is serial;
- `.c` file names/order must be stable to guarantee reproducibility;
- `ccache` optional.

## 9. Memory Management

### 9.1 Thread-Local Arenas

```c
typedef struct {
    NodeChunk *ast_chunks;
    MnChunk   *mir_chunks;
    CBuf       output;
    DiagVec    diags;
} WorkerCtx;
```

- independent arena per worker;
- freed all at once at the end of a stage;
- no cross-thread frees;
- avoids lock contention on the global allocator.

### 9.2 Global Memory

- `Interner` string arena: appended in shards, chunks are never moved;
- `TypeTable`/`SymbolTable`: frozen after sema;
- output buffers: independent per function, concatenated in order at the end.

### 9.3 Memory Budget

- `--mem-limit` optional;
- when the threshold is exceeded, lower the parallelism / raise an error;
- monitor peak RSS;
- silent OOM crashes are not allowed.

## 10. Error Handling and Cancellation

- each job returns `Result<(), Diag>`;
- the first error is recorded in the global `ErrorState`;
- optional `--fail-fast`: cancel the other jobs;
- by default all diagnostics are collected and emitted together at the end;
- cancellation checkpoints: job start, loop bodies, allocation points;
- arenas/temporary files must still be released after cancellation.

## 11. CLI and Configuration

```text
--jobs N            parallelism, default auto (CPU cores, at most 8/16)
--jobs=1            serial, for reproduction/debugging
--no-parallel       equivalent to --jobs=1
--parallel-report   print per-stage time/speedup
XNULL_JOBS=N        environment variable
```

`--parallel-report` example:

```text
stage        wall    cpu     speedup
lex/parse    0.42s   3.10s   7.4x
sema         0.31s   1.20s   3.9x
mir          0.25s   1.40s   5.6x
codegen      0.18s   0.90s   5.0x
cc           0.80s   5.60s   7.0x
link         0.12s   0.12s   1.0x
total        2.08s   12.32s  5.9x
```

## 12. Acceptance and Benchmarks

### 12.1 Benchmarks

```text
bench/parallel/1k      1k lines
bench/parallel/10k     10k lines
bench/parallel/100k    100k lines
bench/parallel/self    the compiler itself
```

### 12.2 Metrics

| Metric | Target |
|---|---|
| 8-core end-to-end speedup | ≥ 4x |
| lex/parse on 8 cores | ≥ 6x |
| sema on 8 cores | ≥ 4x |
| MIR/codegen on 8 cores | ≥ 5x |
| 1-core overhead | ≤ 10% |
| Output consistency | 100% |
| Diagnostic consistency | 100% |
| Memory | ≤ 1.5x |
| Thread races | no TSan reports |

### 12.3 Correctness Gates

- C output hashes match for `--jobs=1` and `--jobs=8`;
- all tests pass under `--jobs=1/2/4/8`;
- TSan/ASan stress testing;
- cancellation/error-path tests;
- large-file/single-file/multi-module/cyclic-dependency negative cases;
- the self-compilation fixed point is reproducible under parallel builds.

## Algorithm Selection and Comparison (by Parallel Node)

> Notation: N = number of tasks, T = number of threads, E = number of dependency edges, W = total work.
> The first goal of a parallel algorithm is "do not change the output"; speedup is second. Determinism takes priority over peak utilization.

### A1. Scheduling Model

| Model | Load balancing | Overhead | Determinism | Pros | Cons | Verdict |
|---|---|---|---|---|---|---|
| Fork-Join | Medium | Low | Easy | Clear structure | Requires explicit join, may starve | Module-level alternative |
| Work-Stealing | High | Medium | Needs stable merge | Dynamic balancing, suits irregular tasks | Complex to implement | **Adopted** |
| Static partitioning | Low | Lowest | High | Simple | Long-tail tasks slow things down | Not adopted |
| Dataflow/DAG | High | Medium | High | Explicit dependencies, pipelinable | Scheduler complexity | **Adopted (task DAG)** |
| Master-worker | Medium | Low | High | Simple | Master node becomes a bottleneck | Not adopted |

Choice: task DAG + work-stealing. The DAG guarantees dependency correctness; work-stealing handles the unevenness of file/function granularity.

### A2. Work-Stealing Queues

| Algorithm | push/pop | steal | Concurrency | Pros | Cons | Verdict |
|---|---|---|---|---|---|---|
| Lock-protected deque | O(1) | O(1) | Lock | Simple | High contention | Not adopted |
| Michael–Scott queue | O(1) | O(1) | Lock-free | General-purpose | Pointer/ABA complexity | Alternative |
| Chase–Lev deque | O(1) | O(1) | Lock-free | Fast locally, steals rarely conflict | Memory ordering is hard to write | **Adopted** |
| ABP (array blocking) | O(1) | O(1) | Lock-free | Batched, cache-friendly | Complex to implement | Alternative |

Choice: Chase–Lev — the owner pushes/pops from the head, thieves steal from the tail; local operations use no atomics, and only steals use CAS. Combined with one deque per worker.

### A3. DAG Scheduling

| Algorithm | Complexity | Pros | Cons | Verdict |
|---|---|---|---|---|
| Topological waves | O(N+E) | Simple, deterministic | Barriers between waves limit utilization | **Adopted** |
| List scheduling | O(N log N) | Critical path first | Needs priorities/estimates | Alternative |
| Critical-path first | O(N+E) | Shortens makespan | Dynamic updates are complex | Later |
| Random scheduling | O(N) | Simple | Nondeterministic | Not adopted |

Choice: waves over the module DAG first, then work-stealing within a wave; function-level tasks use dependency counters with no global barriers.

### A4. Deterministic Merging

| Algorithm | Determinism | Overhead | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Merge by ID order | High | O(N log N) | Fully reproducible | Requires stable IDs | **Adopted** |
| Commutative reduction (sum/max) | High | O(N) | Fast | Only fits commutative operations | Adopted for statistics |
| Serial merge | High | O(N) | Simplest | Loses parallelism | Adopted for small results |
| Arrival-order merge | Low | O(1) | Fastest | Not reproducible | Not adopted |

Choice: diagnostics/output use stable-ID sort-merge; counters use atomic adds/commutative reductions; hash tables are never iterated for output.

### A5. Parallel Parsing

| Algorithm | Complexity | Parallelism | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Per-file | O(N/T) | Number of files | Simple, no sharing | No speedup for single files | **Adopted** |
| Parallel prefix/chunking | O(N/T) | Arbitrary | Parallelizes single files too | Requires a splittable grammar | Later |
| Speculative parsing | O(N) | High | Fast on large files | Rollback is complex | Not done |
| Serial | O(N) | 1 | Simple | Slow | Baseline |

Choose per-file: XNull projects are usually multi-file; single-file projects degenerate to function-level parallelism (sema/codegen).

### A6. Parallel sema

| Algorithm | Parallelism | Precision | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Module DAG waves | Number of modules | High | Clear dependencies, deterministic | Wave barriers | **Adopted** |
| Function-level | Number of functions | Medium | Speeds up single modules too | Complex symbol-table sharing | Phase two |
| Global fixed-point parallelism | High | High | Theoretical parallelism | Convergence/contention are hard | Not done |
| Serial | 1 | High | Simple | Slow | Baseline |

Choose the module DAG: import dependencies already provide natural waves; within a module run serially first, and do function-level parallelism only after the symbol table is frozen.

### A7. Parallel codegen

| Algorithm | Parallelism | Output merging | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Per function | Number of functions | Sort by FunctionId | Right granularity, deterministic | Global type table must be aggregated | **Adopted** |
| Per module | Number of modules | Sort by module | Simple | Low parallelism for single modules | Alternative |
| Whole program | 1 | Direct output | No merging | No parallelism | Baseline |
| Per basic block | Number of blocks | Complex | Extreme parallelism | High overhead/merging cost | Not done |

### A8. Load Balancing

| Algorithm | Balance | Overhead | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Static even split | Low | 0 | Simple | Long tail | Not adopted |
| Dynamic chunks | High | Medium | Simple and effective | Chunk size needs tuning | Alternative |
| Work-stealing | High | Medium | Adaptive | Implementation complexity | **Adopted** |
| Priority queue | High | Medium-high | Critical path first | Needs estimates | Later |

### A9. Synchronization

| Mechanism | Overhead | Pros | Cons | Verdict |
|---|---|---|---|---|
| Mutex | Medium-high | Simple, correct | Contention/blocking | Slow paths only |
| Atomics | Low | Lock-free, fast | ABA/memory ordering | **Counters/queues** |
| Thread-local | Lowest | No contention | Merge cost | **Default** |
| RW lock | Medium | Read-mostly workloads | Writer starvation | Config / before tables are frozen |

Choice: thread-local by default; frozen snapshots for shared read-only data; atomics for counters; global locks protect only diagnostic/error state.

### A10. Cancellation and Error Propagation

| Algorithm | Latency | Overhead | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Flag polling | Medium | Low | Simple | Checkpoints must be dense | **Adopted** |
| Exceptions/longjmp | Low | Medium | Immediate | Unsafe across tasks | Not adopted |
| Task-group cancellation | Medium | Low | Structured | Requires a task tree | **Adopted** |
| Thread killing | Lowest | High | Immediate | Unsafe | Not adopted |

Choice: an atomic `cancel` flag + task-group cancellation; checkpoints at job start, loop bodies, and allocation points; arenas/temporary files are still released after cancellation.

### A11. Algorithm Selection Summary

| Node | Candidates | Choice | Main rationale |
|---|---|---|---|
| Scheduling | fork-join / work-stealing / static | DAG + work-stealing | Dynamic balancing |
| Deque | lock / Michael-Scott / Chase-Lev | Chase-Lev | Fast locally |
| DAG | waves / list / critical path | waves + dependency counting | Simple and deterministic |
| Merging | sort-merge / commutative reduction / serial | sort-merge | Reproducible |
| Parsing | per-file / chunking / speculative | per-file | No sharing |
| sema | module DAG / function-level / global | module DAG | Clear dependencies |
| codegen | per function / module / block | per function | Right granularity |
| Balancing | static / chunk / steal | work-stealing | Adaptive |
| Synchronization | lock / atomic / local | local + atomic | Low contention |
| Cancellation | polling / exceptions / thread killing | polling + group cancellation | Safe |

### Implementation Mapping

| Algorithm/Node | Implementation location | Phase |
|---|---|---|
| Chase–Lev deque + work-stealing | new `src/compiler/support/pool.c`, `pool.h` (FFI-replaceable) | P1 |
| Task DAG + dependency counting | new `src/compiler/support/dag.c`, `dag.h` | P1 |
| File-level lex/parse parallelism | per-file ctx in `src/compiler/lexer/`, `parser/` | P1 |
| Module DAG wave sema | new `src/compiler/sema/schedule.x` | P2 |
| Function-level MIR/codegen parallelism | `src/compiler/opt/`, `codegen/emit_c.x` | P3 |
| Multiple `.c` + cc process pool | `src/toolchain/xnull-build.sh`, `src/cli/xnull` | P4 |
| `--jobs`/`--parallel-report` | `src/cli/xnull` | P0–P1 |

**Fallback conditions**: `--jobs=1` takes the fully serial path; when the task count is < 2×T, no parallelism is used; when memory exceeds the budget, parallelism is lowered; when output is inconsistent, immediately fall back to serial and report an error.

## 13. Phased Rollout

| Phase | Deliverable | Acceptance |
|---|---|---|
| P0 | `--jobs` option; stage timing; serial baseline | Report is readable |
| P1 | native thread pool + task DAG; file-level lex/parse parallelism | 6x parse; identical output |
| P2 | module DAG sema parallelism | 4x sema; stable diagnostics |
| P3 | function-level MIR/codegen parallelism | 5x; identical C output |
| P4 | multiple `.c` files + cc process pool | 6–8x cc |
| P5 | parallel convergence of cross-function inlining/RTA | no races; performance targets met |
| P6 | XNull task layer replaces the native pool (optional) | usable after self-hosting |

## 14. Risks and Mitigation

| Risk | Mitigation |
|---|---|
| Global state contamination | Audit `Codegen.x` globals first; convert to per-worker ctx |
| Nondeterministic output | Stable IDs/ordering; `jobs=1` baseline; hash comparison |
| Thread races/false sharing | Thread-local arenas; sharded interner; TSan |
| Tasks too fine-grained | Per file/module/function; batched tasks |
| Higher peak memory | Arena reuse; budgets; lower parallelism |
| Complex error handling | Unified `Result` + cancellation checkpoints |
| Self-hosted compiler's single-threaded assumptions | Self-host with `--jobs=1` first; enable gradually afterwards |
| Platform differences in the cc process pool | POSIX `fork/exec` baseline; Windows deferred |

## 15. Open Questions

1. Native C or XNull `xrt_task` for the compiler thread pool? The first version should use native, behind an abstract interface.
2. Should sema be parallelized at function level within a module? Depends on symbol-table dependencies.
3. How does cross-function inlining converge under parallelism? Are global barriers/iteration rounds needed?
4. Generate one `.c` or one `.c` per module? The latter helps parallel cc, but means more link symbols.
5. Interaction between incremental and parallel compilation (cache granularity).
6. Upper bound for `--jobs=auto` (to avoid memory blowup on 64-core machines).
