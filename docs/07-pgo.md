# XNull Profile-Guided Optimization (PGO) Detailed Design

> Status: design draft v1 · 2026-11-15
> Scope: `src/compiler/` MIR, `src/runtime/`, `src/toolchain/`, `src/cli/`
> Related: Design 01 (backend), Design 04 (inlining/devirtualization), Design 05 (GC/ARC), Design 06 (parallel compilation)
> Algorithm selection: every implementation node lists candidate algorithms, complexity, pros/cons and the rationale for the choice; see the "Algorithm Selection and Comparison" section.

## 1. Conclusion

XNull currently has no PGO at all:

- The build is fixed at `cc -O2`;
- Code generation does not read any runtime profile;
- Inlining/devirtualization can only rely on static heuristics;
- Hot spots in self-hosting/XDK scenarios are not fed back to the compiler.

The goal of PGO is not "one more optimization switch", but to feed **the execution frequency of real workloads** back to the MIR layer:

- Hot call sites are inlined first;
- Hot protocol types are devirtualized with guards first;
- Hot/cold branch layout;
- Hot/cold function separation;
- Bounds check/exception path outlining;
- Native backend register allocation weights.

Two layers are recommended:

| Layer | Content | Role |
|---|---|---|
| XNull PGO | MIR instrumentation, collects function/edge/call/type frequencies | Drives inlining, devirt, layout |
| C backend PGO | `cc -fprofile-generate/use` | Supplements the C compiler's own layout/register optimization |

The first version only implements XNull PGO; C-layer PGO is an optional switch.

## 2. Current State and Problems

### 2.1 Build

`src/toolchain/xnull-build.sh`:

```bash
cc -std=c11 -O2 -pthread -I ... -o out generated.c runtime/*.c
```

No profile input/output.

### 2.2 Compiler

- `Codegen.x` has no hot/cold marking;
- Function/block order follows traversal order;
- Inlining/devirtualization (Design 04) has no frequency information;
- Protocol call sites do not know the actual type distribution;
- Branches have no `likely/unlikely`;
- No `__builtin_expect`/`XN_HOT`/`XN_COLD`.

### 2.3 Runtime

- `rt_stats` only has allocation/GC counts, with no execution frequency;
- Tasks/synchronization have counters, but they are unrelated to compile-time optimization;
- No profile buffer/dump interface.

### 2.4 Self-hosting

- `xn-s4.c` is a frozen artifact; self-compilation is still pending (E4);
- No flow for "run stage1 on itself to collect a profile, then build stage2";
- Fixed-point verification requires reproducibility; PGO builds change the hash, so the canonical and PGO artifacts must be distinguished.

## 3. Goals and Non-Goals

### 3.1 Goals

| Metric | Target |
|---|---|
| Real workload runtime | -5% to -20% |
| Compiler self-compilation time | -10% to -30% |
| Code size | +0% to +15% |
| Compile time (with profile) | within +10% |
| Profile overhead (generation phase) | 2–10x (training builds only) |
| Correctness | Semantics fully identical to no PGO |
| Reproducibility | Same profile + same source => same output |

### 3.2 Non-Goals

- No sampling-based production profiler (first version);
- No cross-machine profile migration (can be supported, but requires version matching);
- No ML model prediction;
- No language semantics changes;
- Users are not required to enable PGO by default.

## 4. Overall Flow

```text
① Training build
   xnull build --profile-generate -o app.prof app.x
   ./app <workload>
   → app.prof

② Optimized build
   xnull build --profile-use app.prof -o app app.x

③ Verification
   xnull build --no-pgo -o app.base app.x
   compare output/tests/benchmarks
```

Inside the compiler:

```text
HIR/MIR
  → insert counters (--profile-generate)
  → C output + profile runtime
  → run
  → profile data
  → read/merge/verify
  → drive inline/devirt/layout
  → C output (--profile-use)
```

## 5. Profile Model

### 5.1 Collected Data

| Data | Granularity | Use |
|---|---|---|
| Function entry count | FunctionId | Hot/cold functions, inline budget |
| Basic block count | BlockId | Block ordering, cold block outlining |
| Edge count | (pred, succ) | Branch probability, block layout |
| Call site count | CallSiteId | Inlining decisions |
| Call target count | (CallSiteId, FunctionId) | Indirect call devirtualization |
| Protocol type count | (CallSiteId, TypeId) | guard devirt |
| Allocation site count | AllocSiteId | GC/allocation optimization |
| Branch count | BranchId | `likely/unlikely` |

First-version priority: function entry, call sites, protocol types, branches. Edge counts are used for block layout.

### 5.2 Stable IDs

The biggest engineering problem with PGO is "the profile and the source version do not line up". IDs must be stable:

```c
typedef struct {
    uint64_t build_id;      /* compiler version + source tree hash */
    uint32_t function_id;   /* stable FunctionId */
    uint32_t block_id;      /* stable block ID within a function */
    uint32_t call_site_id;  /* MIR call site ID */
    uint32_t type_id;       /* stable TypeId */
} ProfileKey;
```

Rules:

- `FunctionId` = hash(`module path` + `function name` + `signature`);
- Overloads/generic instances: add `type args` to the hash;
- `BlockId` uses source span + structural path, not the traversal ordinal;
- `CallSiteId` uses `(function_id, span, callee name)`;
- `TypeId` uses `(module path, type name)`;
- After major source changes IDs may mismatch; validate `build_id`/coverage when loading the profile, and on mismatch fall back with a warning.

### 5.3 Profile File Format

A dual format is recommended: binary + human-readable JSON:

```text
XNPROF\0
version: u32
build_id: u64
flags: u32
function_count: u32
functions: [FunctionProfile]
strings: [name table]
```

```c
typedef struct {
    uint32_t function_id;
    uint64_t entry_count;
    uint32_t block_count;
    BlockProfile *blocks;
    uint32_t call_count;
    CallProfile *calls;
    uint32_t type_count;
    TypeProfile *types;
} FunctionProfile;

typedef struct {
    uint32_t block_id;
    uint64_t count;
} BlockProfile;

typedef struct {
    uint32_t call_site_id;
    uint32_t callee_id;     /* 0 = unknown/indirect */
    uint64_t count;
} CallProfile;

typedef struct {
    uint32_t call_site_id;
    uint32_t type_id;
    uint64_t count;
} TypeProfile;
```

- Little-endian, fixed width;
- String table placed at the end, for easier diagnostics;
- Compression (zstd) optional;
- JSON for debugging/merge tools;
- File header contains `build_id`/compiler version/target triple.

### 5.4 Counter Implementation

Insert into the generated C:

```c
/* every function entry */
XN_PROF_INC(xn_prof_fn_123);

/* every branch */
if (XN_PROF_LIKELY(cond)) { ... } else { ... }

/* every call site */
XN_PROF_INC(xn_prof_call_456);
callee(...);

/* protocol call site */
XN_PROF_TYPE(xn_prof_type_789, obj->type_id);
```

Implementation approach:

- Static array + `__attribute__((section("xnull_prof")))`;
- Counters are `uint64_t`, atomic add or thread-local;
- Write the file at process exit (`atexit`);
- `--profile-generate` links `rt_profile.c`;
- Sampling/low-frequency paths can be disabled to reduce overhead.

### 5.5 Multithreading

- Per-thread local counters, merged at exit;
- Or atomic add (simple but slow);
- The compiler's parallel build (Design 06) uses thread-local counters, merged at the end;
- Profile merging is counter summation, order-independent.

## 6. Usage

### 6.1 Inlining (Design 04)

```text
hot(site) = call_count(site) / max(1, entry_count(caller))
inline_score = hot(site) * (1 + devirt_gain + arc_gain) / cost(callee)
```

- Hot call sites get a larger inline budget;
- Cold call sites are not inlined, reducing code size;
- Hot small functions are marked `always_inline`;
- Cold functions are marked `XN_COLD` and placed in `.text.unlikely`.

### 6.2 Devirtualization (Design 04)

Type profile:

```text
Circle: 92%
Square: 7%
Other:  1%
```

- Generate a guard for the top-1 type:
  ```c
  if (obj->type_id == TID_Circle) return Circle_area(obj);
  return vtable_call(obj, SLOT_area);
  ```
- A second guard can be added for top-2;
- If top-1 < 60%, keep the vtable;
- If the type distribution is uniform (megamorphic), do not add a guard;
- Guard failure must fall back; semantics unchanged.

### 6.3 Branch Layout

- Edge counts -> branch probability;
- Hot successor fall-through;
- Cold successor jumps to a cold block;
- `XN_LIKELY/XN_UNLIKELY` wrap conditions;
- Exception/error paths marked cold;
- `switch` sorts cases by frequency (does not affect semantics).

### 6.4 Block/Function Layout

- Hot functions are placed first, cold functions in `.text.unlikely`;
- Hot blocks contiguous, fewer jumps;
- Cold block outlining;
- Loop alignment (`-falign-loops` or hand-written `__attribute__((aligned))`);
- The first version only does function/block ordering, no complex outlining.

### 6.5 Bounds Checks

- Hot loop + range analysis already proved safety => remove the check;
- Cannot be proven, but the profile shows out-of-bounds has never occurred => keep the check, but outline it with `XN_UNLIKELY`;
- No "speculative bounds check removal" (semantics require it to be fatal).

### 6.6 ARC/GC

- Hot allocation sites: choose a faster size class / TLAB;
- Hot `retain/release` pairs: eliminated after inlining (Design 04);
- Hot string concatenation: pre-allocate;
- Cold finalization paths outlined;
- Allocation-site profile can guide GC thresholds (optional).

### 6.7 Native Backend (Future)

- Register allocation spill weight = execution frequency;
- Instruction scheduling along hot paths;
- Hot block alignment;
- Cold block separation.

## 7. Profile Merging and Verification

### 7.1 Merging

```bash
xnull profile merge a.prof b.prof -o merged.prof
```

- Counts with the same key are summed;
- `build_id` must match;
- Missing types/functions are ignored with a warning;
- Supports weighted scaling (different workloads).

### 7.2 Verification

On load:

1. Check magic/version;
2. Check `build_id`;
3. Check function/call site coverage;
4. Coverage < 80% => warn and degrade to static heuristics;
5. TypeId/FunctionId in the profile not found => ignore;
6. Count is 0/overflow => saturate.

### 7.3 Reproducibility

- Same source + same profile => same C output;
- Profile file included in the build input hash;
- Output does not embed timestamps/paths;
- `--profile-use` does not change semantics, only layout/inlining decisions;
- Maintain a `--no-pgo` canonical build for fixed-point verification.

## 8. Self-hosting PGO

The self-hosting compiler is the ideal PGO workload: compiling itself.

Flow:

```text
1. Build stage1 with the current trusted compiler (no PGO)
2. Use stage1 to compile a corpus (the compiler itself/XDK/examples), collect profile
3. Rebuild stage1-pgo with the profile
4. Build stage2-pgo with stage1-pgo
5. Build stage2-base with stage1 (no PGO)
6. Compare functional tests of stage2-pgo and stage2-base
7. Fixed point: stage2-pgo recompiles itself => stage3-pgo, hashes match (within PGO builds)
```

Notes:

- PGO build hashes differ from no-PGO ones and cannot be compared directly;
- Fixed-point verification has two chains: canonical (no PGO) and pgo (with profile);
- The profile must match the source version;
- Early self-hosting (E4 pending) does not do PGO yet; fix correctness first;
- PGO only optimizes the compiler itself and does not change the semantics of user programs.

## 9. C-layer PGO (Optional)

In addition to XNull PGO, the C compiler can also perform PGO:

```bash
# training
cc -fprofile-generate -O2 generated.c runtime/*.c -o app.train
./app.train workload
# use
cc -fprofile-use -O2 generated.c runtime/*.c -o app
```

Pros:

- Leverages clang/gcc's mature block layout/register allocation;
- Zero compiler changes.

Cons:

- The profile corresponds to the generated C, not the XNull source;
- Function names/inlining decisions live at the C layer and are invisible to the XNull layer;
- Large cross-platform/compiler differences;
- Reproducibility depends on the cc version.

Recommendation:

- Off by default;
- `--c-pgo` explicitly enables it;
- Can be combined with XNull PGO, but validate the gains first;
- CI only runs benchmarks; C PGO is not a release default.

## 10. CLI and Workflow

```text
xnull build --profile-generate -o app app.x
xnull build --profile-use app.prof -o app app.x
xnull build --profile-use app.prof --profile-report -o app app.x
xnull profile merge a.prof b.prof -o merged.prof
xnull profile show app.prof
xnull profile diff a.prof b.prof
xnull build --no-pgo -o app.base app.x
```

`--profile-report` output:

```text
profile: app.prof  build=abc123  coverage=96%
hot functions:
  parse_expr        12.4%
  codegen_stmt      9.8%
  map_get           7.1%
devirt:
  Shape.area        92% Circle -> guard
  Error.describe    71% IoError -> guard
inline:
  accepted 1284 / 2100 sites
```

## 11. Acceptance and Benchmarks

### 11.1 Benchmarks

```text
bench/pgo/compiler      self-compilation
bench/pgo/xdk           XDK scenario
bench/pgo/json          JSON parsing
bench/pgo/http          HTTP service
bench/pgo/nbody         CPU-intensive
```

### 11.2 Metrics

| Metric | Target |
|---|---|
| Runtime | -5% to -20% |
| Self-compilation time | -10% to -30% |
| Code size | +0% to +15% |
| Compile time (use) | within +10% |
| Training overhead | 2–10x (training only) |
| Profile size | < 10 MB (compiler workload) |
| Coverage | > 80% |
| Output determinism | Same profile, same output |
| Semantics | Fully identical to no PGO |

### 11.3 Correctness

- Differential testing of `--profile-use` vs. `--no-pgo`;
- Fallback tests for profile mismatch/corruption/empty file;
- Multithreaded profile merge tests;
- Guard failure path tests;
- Fixed-point tests for both self-hosting chains (canonical/pgo);
- All existing tests pass under PGO builds.

## Algorithm Selection and Comparison (by PGO Node)

> Notation: N = number of functions, E = number of edges, S = number of samples, P = number of profile entries.
> PGO algorithm selection criteria: signal quality, training overhead, reproducibility, side effects on code size.

### A1. Profile Collection

| Approach | Overhead | Precision | Coverage | Pros | Cons | Conclusion |
|---|---|---|---|---|---|---|
| Instrumentation counting | 2–10x | Exact | Complete | Edges/types/calls all collectable | Slow training | **Adopted in v1** |
| Sampling (perf/sample) | <5% | Statistical | Depends on sample rate | Usable in production | Weak edge/type signal | Later |
| Hybrid (instrumentation + sampling) | Medium | High | Complete | Balances both | Complex to implement | Later |
| Hardware counters | Low | Medium | Limited | Non-intrusive | Platform-dependent | Not planned |

Choice: instrumentation — the compiler/XDK are controllable training workloads, and the training overhead is acceptable; sampling is left for production environments.

### A2. Counter Layout

| Scheme | Write overhead | Merging | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Global atomics | High | None | Simple | Contention/slow | Not adopted |
| Per-thread local | Lowest | Sum at exit | Fast, contention-free | Memory/merging | **Adopted** |
| Sharded atomics | Medium | Sum | Compromise | Still contention | Alternative |
| Per-site static array | Low | Merge by ID | Good cache behavior | Requires stable IDs | **Used in conjunction** |

Choice: per-thread local arrays + merge by ID at exit; near-zero overhead for single-threaded training.

### A3. Profile Merging

| Algorithm | Result | Pros | Cons | Conclusion |
|---|---|---|---|---|
| Direct sum | Total frequency | Simple, commutative | Long training dominates | **Default** |
| Max | Peak | Robust to anomalies | Loses frequency | Not adopted |
| Weighted sum | Controllable weights | Balances multiple workloads | Weights must be determined | **Used for multi-workload** |
| Statistical normalization | Probability | Suitable for branches | Loses absolute hotness | Used for branch probability |
| Quantiles | Distribution | Noise-resistant | Complex to implement | Not planned |

Choice: sum by default; weight normalization for multiple workloads; probability for branches/types.

### A4. Stable IDs

| Scheme | Stability | Rename | Edit robustness | Cost | Conclusion |
|---|---|---|---|---|---|
| Symbol name hash | Medium | Mismatch | Poor | Low | Baseline |
| Content hash (function body) | High | Mismatch | Medium | Medium | **Adopted (primary)** |
| AST structural hash | High | Mismatch | Medium-high | Medium-high | Alternative |
| Source span + signature | Medium | Preserved | Medium | Low | **Auxiliary** |
| UUID | Highest | Preserved | Good | Requires maintenance | Not planned |

Choice: `FunctionId = hash(module path + signature + normalized body)`; mismatches after edits are caught by coverage verification, and 100% matching is not pursued.

### A5. Inlining Decision

| Algorithm | Benefit | Code size | Compile time | Explainability | Conclusion |
|---|---|---|---|---|---|
| Fixed threshold | Medium | Small | Low | High | Baseline |
| Cost model + PGO | High | Medium | Medium | High | **Adopted** |
| Knapsack/ILP | Highest | Optimal | High | Medium | Not planned |
| ML prediction | Possibly high | Uncontrollable | Training cost | Low | Not planned |

### A6. Devirtualization Choice

| Algorithm | Guards | Hit rate | Code size | Pros | Cons | Conclusion |
|---|---|---|---|---|---|---|
| Top-1 guard | 1 | High (skewed) | Small | Simple | Poor for polymorphism | **Default** |
| Top-2 guard | 2 | Higher | Medium | Covers bimodal | Code bloat | **When skew is low** |
| Decision tree | log S | High | Medium | Adaptive | Complex to implement | Later |
| PIC | 1–3 | High | Medium | Dynamic | Runtime state | Alternative |
| Full vtable | 0 | Dynamic | Smallest | General | Indirect | Fallback |

Choice: top-1 primary; add a second guard when top-1 < 60% and top-2 is clearly significant; otherwise vtable.

### A7. Block Layout

| Algorithm | Complexity | Benefit | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Source order | 0 | 0 | Simple | Hot blocks scattered | Baseline |
| Greedy chain | O(E log E) | Medium-high | Simple | Suboptimal | Alternative |
| Pettis–Hansen | O(E log E) | High | Classic, edge profile | Medium implementation effort | **Adopted** |
| Optimal layout | NP-hard | Highest | Theoretical | Infeasible | Not planned |
| ML layout | Training | Possibly high | Adaptive | Unexplainable | Not planned |

### A8. Function Layout

| Algorithm | Complexity | Benefit | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Source order | 0 | 0 | Simple | Hot functions scattered | Baseline |
| Hot/cold separation | O(N) | Medium | Simple, stable | Coarse granularity | **Adopted** |
| Graph partitioning | O(N²) | High | Global | Complex | Later |
| Call-chain ordering | O(N log N) | Medium | Improves i-cache | Requires call graph | Alternative |

### A9. Profile Verification

| Scheme | Mismatch detection | Overhead | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Exact build_id | High | 0 | Simple | Any change mismatches | **Primary verification** |
| Coverage threshold | Medium | Low | Tolerates small changes | May miss mismatches | **Auxiliary** |
| Fuzzy matching (names) | Low | Medium | Tolerates renames | May mismatch | Alternative |
| No verification | 0 | 0 | None | Dangerous | Not adopted |

Choice: exact `build_id` verification + coverage > 80%; on mismatch, warn and fall back to static heuristics.

### A10. Profile Compression

| Scheme | Compression ratio | Speed | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Raw fixed-length | 1x | Fastest | Simple | Large | Baseline |
| Varint | 2–4x | Fast | No dependencies | Small implementation | **Adopted** |
| zstd | 5–10x | Medium | General | Library dependency | Optional |
| Custom columnar | 5–15x | Fast | Tailored to profile | Complex to implement | Later |

### A11. Algorithm Selection Summary

| Node | Candidates | Choice | Main reason |
|---|---|---|---|
| Collection | Instrumentation / sampling / hybrid | Instrumentation | Complete signal |
| Counters | Atomic / local / sharded | Local + merge | Low overhead |
| Merging | Sum / max / weighted | Sum + weighted | Commutative |
| ID | Name / content / AST / UUID | Content + span | Stability/cost |
| Inlining | Threshold / cost / ILP | Cost + PGO | Controllable |
| Devirtualization | top-1 / top-2 / tree / PIC | top-1/2 | Simple and effective |
| Block layout | Source / greedy / Pettis-Hansen | Pettis-Hansen | Edge profile |
| Function layout | Source / hot-cold / graph partitioning | Hot-cold | Simple |
| Verification | build_id / coverage / fuzzy | build_id + coverage | Safe |
| Compression | Raw / varint / zstd | varint + optional zstd | No dependencies |

### Implementation Mapping

| Algorithm/Node | Implementation location | Phase |
|---|---|---|
| Instrumentation counters + thread-local merging | New `src/runtime/rt_profile.c`, `rt_profile.h` | PGO1 |
| MIR instrumentation points/stable IDs | `src/compiler/mir/`, `src/compiler/profile/ids.x` | PGO0–PGO1 |
| Profile read/write/merge/verify | New `src/compiler/profile/` (`read.x`, `merge.x`, `verify.x`) | PGO1 |
| Inlining/devirtualization use profile | `src/compiler/opt/inline.x`, `devirt.x` | PGO2 |
| Block/function layout + `XN_HOT/COLD` | `src/compiler/opt/layout.x`, `emit_c.x` | PGO3 |
| Self-hosting PGO flow | `src/toolchain/xnull-build.sh`, CI scripts | PGO4 |
| CLI `--profile-*` | `src/cli/xnull` | PGO0 |

**Fallback conditions**: when profile coverage < 80%, build_id mismatches, or type distribution entropy is too high (megamorphic), everything falls back to static heuristics; PGO is not allowed to change semantics.

## 12. Phased Implementation

| Phase | Deliverable | Acceptance |
|---|---|---|
| PGO0 | MIR stable IDs; profile schema; CLI placeholders | IDs stable; tools can read/write |
| PGO1 | Function/call/type counters; `rt_profile.c`; dump/merge | Training runs; coverage > 80% |
| PGO2 | Inlining uses call count; devirt uses type profile | Benchmark improvement; semantics unchanged |
| PGO3 | Branch/block/function layout; `XN_HOT/COLD` | Runtime drops further |
| PGO4 | Self-hosting PGO flow; CI nightly benchmarks | Self-compilation speedup; fixed point |
| PGO5 | C-layer PGO optional; profile compression/sampling | As needed |

## 13. Risks and Mitigation

| Risk | Mitigation |
|---|---|
| Profile/source mismatch | `build_id` + coverage verification; fall back on mismatch |
| Overfitting to training workloads | Merge multiple workloads; keep static heuristics as a fallback |
| Code bloat | Inline budget; cold function separation; size monitoring |
| High training overhead | Training builds only; sampling mode later |
| Reproducibility | Profile included in hash; canonical build kept separately |
| Multithreaded counter contention | Thread-local counters + merging |
| Early self-hosting unavailable | Fix E4 first; PGO later |
| Privacy/path leakage | Profile stores only IDs/counts, no source/paths |
| C-layer PGO platform differences | Off by default; explicit switch |

## 14. Open Questions

1. Do profile files need to be cross-platform (different triples)?
2. Should stable IDs use a content hash or a symbol name? Content hashes are more stable, but renames cause mismatches.
3. Is sampling-based PGO (`perf`/`sample`) needed for production?
4. How should the weights for multi-workload merging be determined?
5. Should PGO be used for GC thresholds/allocation strategy?
6. Does the self-hosting fixed point require PGO builds to be byte-for-byte reproducible as well?
