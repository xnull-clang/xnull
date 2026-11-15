# XNull Backend Maturity Detailed Design

> Status: Design draft v1 · 2026-11-15
> Scope: `src/compiler/codegen/`, `src/runtime/`, `src/toolchain/`, `src/bootstrap/`
> Related: Design 02 (AST/Token), Design 03 (Map/arrays), Design 04 (inlining/devirtualization), Design 05 (GC/ARC), Design 06 (parallel compilation), Design 07 (PGO)
> Algorithm selection: every implementation node lists candidate algorithms, complexity, pros and cons, and the rationale; see the "Algorithm Selection and Comparison" section.

## 1. Conclusion

The current backend is:

```text
XNull AST ──string concatenation──> C text ──cc -O2──> executable
```

It can run existing scenarios, but it is not yet a mature backend:

- There is no MIR; all optimization can only hope for the C compiler;
- There is no explicit ownership, root table, or safepoint model; GC correctness relies on manually maintained `xn_root_*` in generated code;
- Every artifact duplicates a giant prelude, with no on-demand emission;
- Output order depends on traversal order; reproducibility has no hard guarantee;
- `src/compiler/codegen/Codegen.x` is already 7,883 lines and still "concatenates strings while traversing", so pass-level verification is impossible.

Backend maturity has two levels; **do the first level first, and do not start the second level at the same time**:

| Level | Content | Required |
|---|---|---|
| C backend maturity | MIR + structured C output + explicit ownership/safepoints + determinism + optimization passes | Required |
| Native backend | x86-64/ARM64, linear-scan register allocation, direct machine-code emission | Optional, deferred |

## 2. Current-State Evidence

| Current state | Location | Impact |
|---|---|---|
| String concatenation to C | `PRELUDE_*`, `fw.push(...)`, `res = res + ...` in `src/compiler/codegen/Codegen.x` | O(n²) concatenation, no structured rewriting, no precise source mapping |
| Generic string-based AST | `N/TN { String raw; String nm; List<String> fn; List<N> fv; }` | Field lookup is linear `fld(n, "Name")`; every node carries multiple strings |
| One container implementation per type | `xn_arr_i`, `xn_arr_s`, `xn_map_s_i`, etc. | Code bloat; container logic cannot be optimized uniformly |
| Linear Map | `xn_map_s_i_find` does a `memcmp` on each item from 0 to len | O(n) symbol-table/field-table lookup |
| Manually emitted root table | `xn_root_hold/xn_root_add/xn_root_restore` in the prelude | Correctness hard to verify, high performance overhead |
| Threshold-triggered collection on every allocation | `XN_GC_SAFEPOINT_THRESHOLD 1024` | Frequent STW under allocation-heavy workloads |
| Frozen C artifact | `src/bootstrap/xn-s4.c`, 115,751 lines | Self-compilation currently still hangs (E4 debt); the backend has no fixed-point guarantee |

## 3. Goals and Non-Goals

### 3.1 Goals

1. **Correctness first**: all existing `src/examples/`, `src/mini/tests/`, and toolchain scenarios pass; diagnostic codes/exit codes are unchanged.
2. **MIR becomes the sole optimization contract**: inlining, devirtualization, escape analysis, and PGO all operate on MIR, never directly on C strings.
3. **Explicit ABI**: ownership of parameters/return values (borrow / owned / out), GC roots, safepoints, and exception/error paths all have IR-level representations.
4. **Determinism**: the same source + the same compiler => byte-identical C output; independent of `--jobs`.
5. **Measurable**: compile time, generated-code runtime, binary size, and peak memory — all four metrics must have benchmarks.
6. **Reversible**: the new backend can be disabled via a feature flag; the old path remains until fixed-point acceptance.

### 3.2 Non-Goals

- No native backend in the first phase;
- Do not pursue LLVM-level optimization;
- Do not change language semantics (including DET-01's stack/ARC/GC decisions);
- Do not replace the C compiler; C remains the portable backend.

## 4. Overall Architecture

```text
.x source file
  │
  ├─ lexer        TokenStream (compact tokens, see Design 02)
  ├─ parser       Arena AST (typed nodes, see Design 02)
  ├─ sema         Typed HIR (name resolution, type checking, DET-01 decisions)
  ├─ lower        MIR (CFG + explicit ownership/roots/safepoints)
  ├─ opt          inline → devirt → constprop → DCE → escape → SROA
  │               → ARC opt → CSE/LICM → bounds-check → CFG simplify
  ├─ emit-c       Structured C (on-demand prelude, stable order)
  └─ cc/link      cc -O2 + runtime (xrt ABI v1)
```

### 4.1 IR Layering

| Layer | Responsibility | Stable? |
|---|---|---|
| TokenStream | Lexical result, no objects, no strings | Within compilation unit |
| AST | Syntax structure, preserves source locations | Within compilation unit |
| HIR | Names/types resolved, syntactic sugar expanded | Within module |
| MIR | CFG, explicit locals, calls, ownership, roots, safepoints | Optimization contract |
| C | Target text | Disposable |

### 4.2 MIR Data Structures

Use arena + indices rather than an object graph:

```c
typedef uint32_t MnId;      /* 0 = null */
typedef uint32_t MnTypeId;
typedef uint32_t MnSpanId;

typedef struct {
    uint16_t op;            /* MnOp */
    uint16_t flags;         /* borrow / owned / cold / tail */
    MnTypeId type;
    MnId     dst;
    MnId     a, b, c;
    MnSpanId span;
} MnInst;

typedef struct {
    MnId     first;
    MnId     last;
    MnId     pred[2];
    MnId     succ[2];
    uint32_t pred_n, succ_n;
    uint32_t idom;
    uint32_t loop_depth;
} MnBlock;

typedef struct {
    MnId        id;
    MnId        entry;
    MnBlock    *blocks;
    MnInst     *insts;
    MnTypeId    ret;
    uint32_t    flags;
    const char *name;
} MnFunction;
```

Instructions cover at least:

```text
const / param / local / load / store / field / index
call / callvirt / new / alloc / retain / release / borrow
safepoint / root / unroot / branch / condbranch / switch / return
phi / cast / box / unbox / is / as / str / len / bounds_check
defer / errdefer / try_begin / try_end
```

MIR invariants:

- Every value has a unique `MnTypeId`;
- `retain/release` must be paired; `borrow` does not change the count;
- Before every allocation point that may trigger GC, all live references must be visible in the root table;
- Every back edge and allocation point has a safepoint;
- Every `callvirt` records the protocol slot and the set of candidate implementations (for devirtualization).

### 4.3 Types and Layout

`TypeId -> Layout` is the backend's only source of layout:

```c
typedef struct {
    uint32_t size;
    uint32_t align;
    uint8_t  kind;          /* value / arc / gc / string / enum */
    uint8_t  field_n;
    uint16_t flags;         /* repr(C) / packed / nullable-niche */
    const MnField *fields;
    const uint64_t *gc_bitmap;   /* which 8-byte slots are GC references */
    const uint64_t *arc_bitmap;  /* which slots are ARC references */
} MnLayout;
```

Rules:

- Layout follows source field order by default, ensuring a predictable ABI;
- Only `repr(C)` or FFI boundaries may use C-compatible layout;
- `Option<T>` uses a niche (null pointer) for nullable references, avoiding the two-word `{has, value}`;
- `Result<T,E>` uses tag + union, with tag width selected by variant count;
- Field offsets, GC bitmaps, and ARC bitmaps are computed once during sema; codegen no longer guesses.

### 4.4 Calling Convention and Ownership

| Position | Convention |
|---|---|
| Parameters | `borrow` by default; explicit `owned` when the lifetime must be extended |
| Returns | ARC/GC pointers default to `owned +1`; scalars by value |
| Struct returns | Use an sret hidden parameter when larger than 16 bytes |
| Errors | `Result<T,E>` returned by value; no C++ exceptions/longjmp |
| `self` | `borrow` by default; `retain` only when the method returns `self` |
| FFI | Strict `borrow`/`owned` annotations; ownership is not transferred across the boundary |

Code generation must insert `retain/release` on MIR; it must not decide ad hoc at the C-string stage.

### 4.5 Safepoints and Roots

- Safepoint locations: every GC allocation, every loop back edge, every call that may block;
- Before a safepoint, live GC/ARC references are written to the stack map;
- Stack maps are generated by MIR liveness analysis, not by hand-written `xn_root_add`;
- `xrt_safepoint()` only polls; it does not scan the C stack;
- Root sets: global roots, task roots, ARC scan chain, current thread stack map;
- Thus `rt_gc_collect` no longer depends on the global root array maintained by generated code.

### 4.6 C Emitter

Stop using `String + String`. Use a chunked buffer:

```c
typedef struct {
    char  *buf;
    size_t len, cap;
    uint32_t chunk_count;
} CBuf;

void cbuf_append(CBuf *b, const char *s, size_t n);
void cbuf_printf(CBuf *b, const char *fmt, ...);
```

Output rules:

1. `xn_prelude.h` is emitted only once, containing runtime constants and `static inline` container helpers;
2. Emit only referenced helpers (collect dependencies by scanning MIR);
3. Type declarations follow dependency topological order, with same-level entries stably sorted by `TypeId`;
4. Functions are stably sorted by `(module path, FunctionId)`;
5. Annotate cold functions with `XN_COLD` and hot functions with `XN_HOT` (PGO can override);
6. Optional `#line` mapping back to `.x` source files;
7. Write to a temporary file and then atomically rename, avoiding partial artifacts.

### 4.7 Pass Management

```text
PassManager:
  analyses: dominator, liveness, callgraph, type-flow, escape, loop-info
  passes:   inline, devirt, constprop, dce, sroa, escape, arc-opt,
            cse, licm, bounds-check, cfg-simplify
  verify:   run the MIR verifier after each pass (debug/CI)
```

- `--O0`: lowering + required cleanup only;
- `--O1`: DCE, CFG simplify, simple inlining;
- `--O2`: default, full passes;
- `--O3`: more aggressive inlining + PGO (see Design 07);
- `--emit=mir|c|asm`, `--dump-pass=inline`, `--verify-ir` as debugging interfaces.

## Algorithm Selection and Comparison (by Backend Node)

> Notation: N = number of instructions/nodes, E = number of CFG edges, B = number of basic blocks, D = dominator tree depth.
> The selection criterion is not "theoretically optimal", but optimal under four constraints: 100k-line scale, C backend, parallelizable, implementable.

### A1. HIR → MIR: SSA Construction

| Algorithm | Complexity | Pros | Cons | Conclusion |
|---|---|---|---|---|
| Cytron dominator-tree phi insertion | O(E α(E)) | Precise, general, textbook standard | Requires building the dominator tree first; phi pruning is complex | Alternative |
| Braun et al. sealed-block | O(E) | Single-pass construction, simple to implement, incremental, parallel-friendly | Requires maintaining sealed-block state | **Adopted** |
| Aycock–Horspool | O(E) | Simplest | Phi insertion is not optimal; high pressure on later DCE | Not adopted |
| Direct AST interpretation/codegen | O(N) | No IR | Cannot do inlining/devirtualization/PGO | Not adopted |

Why Braun: XNull function bodies are usually small, but there are many compilation units; Braun can build each function independently without a global dominator tree, making it naturally suited to the function-level parallelism in Design 06. The dominator tree is built only when needed, using Cooper iteration.

### A2. Dominator Tree

| Algorithm | Complexity | Pros | Cons | Conclusion |
|---|---|---|---|---|
| Lengauer–Tarjan | O(E α(E)) | Theoretically optimal | Complex to implement, large constant, hard to make incremental | Alternative for large functions |
| Cooper–Harvey–Kennedy iteration | O(E·D), close to linear in practice | Simple, incremental, cache-friendly | Degrades in the worst case | **Adopted** |
| Semi-NCA | O(E log N) | Compromise | More complex to implement than Cooper | Alternative |

XNull function CFGs are usually < 1k blocks; Cooper iteration outperforms LT in practice and can recompute locally after CFG changes.

### A3. Data-Flow Analysis

| Algorithm | Complexity | Pros | Cons | Conclusion |
|---|---|---|---|---|
| Round-robin iteration | O(B·H·N/64) | Simplest to implement | Many useless traversals | Not adopted |
| worklist | O(E·H) | Visits only changed nodes; fast in practice | Needs a queue/dedup | **Adopted** |
| Sparse data flow (SSA edges) | O(E) | Cheapest; suited to sparse facts | Complex to implement; not applicable to non-SSA facts | Alternative for global analysis |
| Bitmaps vs sparse sets | O(N/64) vs O(k) | Bitmaps are cache-friendly; sparse sets suit large sets with few changes | Each has its strengths | Bitmaps for local, sparse for global |

Choice: use bitmaps + worklist for local liveness/reachability; use sparse sets for interprocedural/large modules, avoiding scanning the full bitmap per block at 100k lines.

### A4. Constant Propagation

| Algorithm | Complexity | Pros | Cons | Conclusion |
|---|---|---|---|---|
| Simple constant folding | O(N) | Fast; can be done at the parser stage | Not across branches; limited benefit | Front end does it first |
| SCCP (sparse conditional constant propagation) | O(E) | Handles branches/phi; large benefit | Complex to implement; requires SSA | **Adopted in MIR** |
| Abstract interpretation | O(N·H) | Can express more domains | Too heavy | Not done |

Choice: the parser does literal folding; MIR does SCCP, followed by DCE. SCCP's benefit mainly comes from `if false` branch removal and `Result` tag folding.

### A5. Dead Code Elimination (DCE)

| Algorithm | Complexity | Pros | Cons | Conclusion |
|---|---|---|---|---|
| Mark-sweep | O(N+E) | Simple, correct | Requires full graph traversal | Alternative |
| worklist reverse liveness | O(N+E) | Incremental; processes only affected instructions | Requires use-def chains | **Adopted** |
| Incremental DCE | O(Δ) | Suited to repeated calls between passes | High maintenance cost | Later |

Choice: worklist — after inlining/devirtualization instructions change a lot, and worklist can recompute only the affected part.

### A6. Inlining (see Design 04 for details)

| Algorithm | Complexity | Pros | Cons | Conclusion |
|---|---|---|---|---|
| Greedy bottom-up | O(N·budget) | Simple, stable benefit | Not globally optimal | **Adopted** |
| Top-down | O(N·budget) | Can see call context | Prone to premature bloat | Alternative |
| Knapsack/ILP | NP-hard | Theoretically optimal code size/benefit | Compile time uncontrollable | Not done |
| ML prediction | Training cost | Potentially more accurate | Not explainable; needs data | Not done |

Choice: greedy + PGO weights; budget allocated by function size and call frequency.

### A7. Devirtualization (see Design 04 for details)

| Algorithm | Complexity | Precision | Code size | Conclusion |
|---|---|---|---|---|
| CHA | O(N) | Low (all subclasses/implementations) | Small | Baseline only |
| RTA | O(N) | Medium-high (instantiated types) | Small | **Adopted** |
| VTA | O(N²) | High | Medium | Alternative for large projects |
| 0-CFA | O(N³) | High | Medium | Not done |
| Guarded devirt | O(1)/site | Depends on profile | Controllable | **Adopted for polymorphic sites** |

Choice: RTA + type flow + guarded; XNull classes cannot be inherited, so RTA precision is already high.

### A8. Escape Analysis

| Algorithm | Complexity | Precision | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Steensgaard | O(N α(N)) | Low | Fast, scalable | Merges too much; misjudges escape | Fallback for very large modules |
| Andersen | O(N³) | High | Precise | Slow, high memory | Not in the first version |
| Flow-sensitive, field-sensitive | O(N²) worst case | High | Can prove fields do not escape | Complex to implement | **Adopted (with budget)** |
| Connection analysis | O(N²) | Medium-high | Suited to object graphs | Still needs tuning | Alternative |

Choice: start with a lightweight flow-sensitive, field-sensitive version; when over budget (function > 5k instructions), fall back to Steensgaard to bound compile time.

### A9. Register Allocation (Native Backend, Future)

| Algorithm | Complexity | Code quality | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Linear scan | O(N log N) | Medium | Fast, simple to implement | Not good at complex live ranges | **Adopted for the first version** |
| Graph coloring | O(N²) | High | Classic, good quality | Slow, complex to implement | Later |
| PBQP | NP-hard | High | Can express complex constraints | Hard to implement/tune | Not done |
| Greedy | O(N log N) | Medium-low | Simplest | Many spills | Alternative |

No register allocation during the C backend phase; the native backend starts with linear scan and moves to graph coloring once benchmarks prove the bottleneck.

### A10. Instruction Selection (Native Backend, Future)

| Algorithm | Complexity | Pros | Cons | Conclusion |
|---|---|---|---|---|
| Tree covering (Sethi–Ullman) | O(N) | Optimal for tree IR; simple | DAG sharing requires prior treeification | **Adopted** |
| DAG covering | NP-hard | Can share subexpressions | Complex to implement | Not done |
| Greedy/peephole | O(N) | Simple; catches remaining cases | Not globally optimal | **Used with tree covering** |
| Superoptimization | Exponential | Potentially better | Compile time uncontrollable | Not done |

### A11. C Output Order

| Algorithm | Complexity | Determinism | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| DFS traversal order | O(N) | Depends on start point | Simple | Unstable, hard to reproduce | Not adopted |
| Kahn topological sort | O(N+E) | High (with stable tie-break) | Correct dependencies, reproducible | Requires an explicit graph | **Adopted** |
| Stable sort | O(N log N) | High | Simplest | Does not handle dependencies | Same-level only |

Choice: Kahn topological sort over the type/function dependency graph, with same-level items stably sorted by `TypeId/FunctionId`.

### A12. Bounds-Check Elimination

| Algorithm | Complexity | Capability | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Range analysis | O(N) | Loop variables/constant ranges | Fast, sufficient | Does not handle complex affine expressions | **Adopted** |
| ABCD | O(N²) | Affine expressions | Stronger | Complex to implement | Later |
| Loop versioning | O(N) | Runtime guard + unchecked copy | Preserves semantics, large benefit | Code bloat | **Adopted** |
| PGO speculative deletion | O(1) | Depends on profile | Aggressive | Must not change fatal semantics | Layout hints only |

Order: range analysis first; when it cannot prove, use loop versioning; if still unprovable, keep the `XN_UNLIKELY` check.

### A13. Algorithm Selection Summary

| Node | Candidates | Choice | Main rationale |
|---|---|---|---|
| SSA | Cytron / Braun / AH | Braun | Per-function parallel, single-pass construction |
| Dominator tree | LT / Cooper / Semi-NCA | Cooper | Simple, incremental, fast in practice |
| Data flow | round-robin / worklist / sparse | worklist + bitmap/sparse | Visits only changed nodes |
| Constants | folding / SCCP | SCCP | Branch/phi benefit |
| DCE | mark-sweep / worklist | worklist | Incremental |
| Inlining | greedy / knapsack / ML | greedy + PGO | Controllable |
| Devirtualization | CHA / RTA / VTA | RTA + guard | Precision/cost balance |
| Escape | Steensgaard / Andersen / flow-sensitive | flow-sensitive + budget | Precision/time balance |
| Registers | linear scan / graph coloring | linear scan | Get usable first |
| Instruction selection | tree covering / DAG / greedy | tree covering + peephole | Simple and effective |
| Output | DFS / topological | stable topological | Reproducible |
| Bounds check | range / ABCD / versioning | range + versioning | Preserves semantics |

### Implementation Mapping

| Algorithm/node | Implementation location | Phase |
|---|---|---|
| Braun SSA + Cooper dominator tree | New `src/compiler/mir/` (`build.x`, `dom.x`) | B1 |
| worklist data flow + SCCP + DCE | New `src/compiler/opt/` (`dataflow.x`, `sccp.x`, `dce.x`) | B1–B3 |
| Inlining / RTA devirtualization | `src/compiler/opt/inline.x`, `devirt.x` | B3 |
| Flow-sensitive escape analysis + SROA | `src/compiler/opt/escape.x`, `sroa.x` | B3 |
| Bounds-check range analysis/versioning | `src/compiler/opt/bounds.x` | B3 |
| Stable topological C emission | `src/compiler/codegen/emit_c.x` (replaces the concatenation path in `Codegen.x`) | B0–B1 |
| Linear scan/graph coloring, tree covering | Native backend (future) `src/compiler/backend/` | B5 |

**Fallback conditions**: when any algorithm exceeds its time/memory budget, fall back to a simpler conservative algorithm and emit a `--time-report` hint; semantics must never be changed for the sake of optimization.

## 5. Phased Rollout

| Phase | Deliverable | Acceptance |
|---|---|---|
| B0 | Structured `CBuf` output; prelude split into `xn_prelude.h`; on-demand helpers; stable sorting | C output for existing examples is semantically consistent with the old path; two outputs from the same input are byte-identical |
| B1 | MIR covers scalars/control flow/functions/classes/containers; C emitter generates from MIR | `--emit=mir` is readable; old/new path differential tests all green |
| B2 | Explicit ownership, roots, safepoints, stack maps; GC correctness tests | `test_gc`, `test_hard`, `test_companion` all green; no manual root table |
| B3 | Inlining, devirtualization, escape analysis, bounds-check elimination | Benchmark improvement; MIR verifier error-free |
| B4 | PGO integration (Design 07); optional LTO/`-O3` for the C backend | Self-compilation time and runtime meet targets |
| B5 (optional) | Native x86-64 backend | Differential against the C backend; reproducible fixed point |

## 6. Benchmarks and Acceptance

### 6.1 Benchmark Suite

```text
bench/compile/      1k / 10k / 100k lines of generated code (lexer/parser/types/codegen)
bench/runtime/      fib, nbody, string, map, gc, task
bench/self/         compile itself with xn-s4 (stage1/stage2/stage3)
```

### 6.2 Metrics

| Metric | Collection method | Target |
|---|---|---|
| Front-end throughput | lines/sec, MB/sec | 100k lines < 1.5s (single-threaded) |
| Full compile | `time` | 100k lines < 3s |
| Generated-code runtime | hyperfine | < 10% gap vs hand-written C |
| Binary size | `size` | no more than 15% bloat from templating |
| Peak memory | `/usr/bin/time -l` | < 1.5x source size |
| Self-compilation | stage1/stage2 | Reproducible fixed point; time decreases with each version |
| Determinism | SHA-256 of two builds | Exactly identical |

### 6.3 Correctness Gates

- All existing tests + `src/toolchain/xnull-build.sh examples`;
- `--emit=c` is byte-identical to the old path on the supported subset (prelude differences allowed, function bodies identical);
- The MIR verifier passes after every pass;
- The `repro` command builds twice with identical hashes;
- Self-compilation no longer hangs; stage2/stage3 hashes are identical.

## 7. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| C backend limitations (tail calls, computed goto, stack maps) | Keep the C backend as fallback; enable `musttail` on critical paths when available |
| Ownership/root model errors causing GC crashes | MIR verifier + differential tests + `--gc-stress` |
| C compiler differences causing UB | `-std=c11 -fno-strict-aliasing` baseline; UBSan/ASan CI |
| Code bloat | Inlining budget, hot/cold splitting, on-demand helpers, PGO |
| Self-hosting chicken-and-egg | Old `xn-s4` as oracle; independent switch for the new backend |
| Dual-path drift during migration | Run `verify` differentials at every phase; old path is read-only |

## 8. Open Questions

1. Whether the native backend is worth building depends on whether the C backend can stably meet the performance targets;
2. Whether LTO (`-flto`) should be the default;
3. Debug info: is `#line` enough, or is DWARF needed;
4. Cache granularity for incremental compilation (file/function/module);
5. Baseline matrix for cross-platform C compiler differences (clang/gcc/msvc).
