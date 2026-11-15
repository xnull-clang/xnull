# XNull GC / ARC Tuning Detailed Design

> Status: Design Draft v1 · 2026-11-15
> Scope: `src/runtime/rt.c`, `rt_gc.c`, `rt_gc.h`, `rt.h`, `rt_policy.c`, `rt_weak.c`, `xrt_abi.c`
> Related: Design 01 (backend), Design 03 (containers), Design 04 (inlining/devirtualization), Design 07 (PGO)
> Algorithm selection: each implementation node lists candidate algorithms, complexity, pros and cons, and the rationale for the choice; see the "Algorithm Selection and Comparison" section.

## 1. Conclusions

The current runtime is a "correct single-threaded skeleton", but not a high-performance implementation:

- `rt_header` measures **64 bytes**; `rt_string` measures **72 bytes**, plus the byte contents;
- One `malloc` per object; no size class / TLAB;
- The ARC reference count is `atomic_int_fast64_t`; every retain/release is an atomic operation;
- GC is a global singly linked list + STW mark-sweep, recursive marking, and a linear array for the root set;
- A full collection is triggered every 1024 GC allocations;
- Strings are GC objects; the GC list contains every string, and each is linked on allocation;
- ARC scan-list unregistration is a linear search;
- No generations, no card table, no concurrent marking, no compaction.

Goals:

- Object header from 64 B down to 16 B (ARC) / 24 B (GC-side metadata split out);
- `rt_string` from 72 B down to 24 B + bytes;
- Allocation throughput up 2–4x;
- Heap memory down 40–60%;
- p99 STW pause < 10 ms (1 GB heap);
- Self-compilation time down by more than 30%;
- Does not change S3's ARC/GC mixed-graph invariants or DET-01 semantics.

## 2. Status Quo and Quantification

### 2.1 Object Header

`src/runtime/rt.h`:

```c
typedef struct rt_header {
    rt_kind             kind;        /* 4 B + padding */
    const rt_type      *type;        /* 8 B */
    atomic_int_fast64_t refcount;    /* 8 B */
    int                 terminated;  /* 4 B */
    int                 marked;      /* 4 B */
    struct rt_object   *gc_next;     /* 8 B */
    struct rt_object   *scan_next;   /* 8 B */
    int                 in_scan_list;/* 4 B + padding */
    struct rt_weak_slot *weak_head;  /* 8 B */
} rt_header;
```

Measured:

```text
sizeof(rt_header) = 64
sizeof(rt_object) = 64
sizeof(rt_string) = 72
```

Problems:

- Every ARC object also carries GC's `gc_next/scan_next/marked` fields;
- Every GC object also carries ARC's `refcount/terminated` fields;
- A string with 5 bytes of content still needs a 72 B header — 14x memory amplification;
- `weak_head` costs 8 B per object, and the vast majority of objects have no weak references;
- The `malloc` header/alignment adds another 8–16 B.

### 2.2 Allocation

`rt_gc.c:alloc_sized`:

```c
rt_object *o = malloc(sizeof(rt_header) + payload);
memset(o, 0, sizeof(rt_header) + payload);
...
if (kind == RT_KIND_GC) { o->hdr.gc_next = g_gc_list; g_gc_list = o; }
else if (type->scan != NULL) { ... scan list ... }
```

Problems:

- One `malloc` per allocation;
- `memset` of the entire payload every time (even if it is overwritten immediately);
- All GC objects go into a global singly linked list;
- All ARC objects holding GC references go into the scan list;
- No size classes, no per-thread cache, no bump allocator.

### 2.3 ARC

`rt.c`:

```c
atomic_fetch_add_explicit(&h->refcount, 1, memory_order_relaxed);
...
if (atomic_fetch_sub_explicit(&h->refcount, 1, memory_order_acq_rel) == 1) { ... }
```

Problems:

- Single-threaded programs also pay the cost of atomic instructions;
- `rt_release` checks `kind`/`terminated` every time;
- Finalization chain: weak slot clearing → scan-list unregistration (linear) → deinit → quarantine;
- `rt_scan_unregister` walks the scan list linearly;
- `rt_quarantine_flush` only frees at the next GC, so peak memory is high.

### 2.4 GC

`rt_gc.c`:

- Global `g_gc_list`;
- Global `g_scan_list`;
- Global root dynamic array; `rt_gc_root_add` does a linear duplicate check;
- `mark_ref` recursively calls `type->scan`;
- `sweep` is two-phase: deinit first, then release/free;
- No card table / write barrier / generations / concurrency;
- No allocation budget; generated code triggers `rt_gc_collect` once every 1024 allocations.

### 2.5 Policy

The DET-01 decision table in `rt_policy.c` returns `VALUE/ARC/GC/NA_GC`, but "stack candidate" still returns ARC for now; actual stack allocation relies on codegen's escape analysis (not yet complete). This causes many objects that could be stack-allocated to go into ARC.

## 3. Goals and Non-Goals

### 3.1 Goals

| Metric | Current | Target |
|---|---|---|
| ARC object header | 64 B | 16 B |
| GC object header | 64 B | 24 B (including side metadata) |
| `rt_string` | 72 B + bytes | 24 B + bytes |
| Allocation throughput | Baseline | 2–4x |
| Memory for 1M small objects | Baseline | -50% |
| p99 STW | Unbounded | < 10 ms (1 GB heap) |
| Self-compilation time | E4 hangs | Fixed point + 30% reduction |
| Semantics | S3 invariants | Fully preserved |

### 3.2 Non-Goals

- Do not change DET-01's decision outcomes;
- Do not introduce a user-visible GC API;
- Do not do compacting GC in the first version (it would move objects and break ARC raw pointers);
- Do not do fully concurrent GC (STW first + optional concurrent marking);
- Do not change the stable ABI signatures in `xrt.h` (internal headers may change). `xrt_type` itself is part of the ABI surface; if its fields must change, bump the major version per `XRT_ABI_VERSION` and keep an adaptation layer in `xrt_abi.c`.

## 4. Object Layout Restructuring

### 4.1 ARC Object Header

Target 16 B:

```c
typedef struct {
    const rt_type *type;     /* 8 B: type descriptor (with deinit/scan/flags) */
    uint32_t       refcount; /* 4 B: atomic or non-atomic, depending on flags */
    uint8_t        kind;     /* 1 B: ARC/GC */
    uint8_t        flags;    /* 1 B: atomic/pinned/has_finalizer/... */
    uint16_t       aux;      /* 2 B: reserved/small type ID */
} rt_header;                 /* 16 B */
```

- `type` holds `payload_size/deinit/scan`;
- `refcount` is `uint32_t` by default; atomic mode uses `_Atomic uint32_t` or compiler built-in atomics;
- The `ATOMIC` bit in `flags` decides whether retain/release use atomics or plain add/subtract;
- Single-threaded/thread-local objects are non-atomic by default;
- Shared objects (tasks, globals, FFI cross-thread) are marked `ATOMIC` at creation.

### 4.2 GC-Side Metadata

GC fields should not be embedded in every ARC object. GC objects use a side table:

```c
typedef struct {
    uint32_t mark;          /* mark bit/age */
    uint32_t flags;
    rt_object *next;        /* GC list */
    rt_object *scan_next;   /* only for ARC objects holding GC references */
} rt_gc_meta;
```

- GC objects are registered in the `g_gc_meta` hash table/page table at allocation;
- ARC objects are registered in the scan list only when they hold GC references;
- Alternatively: the GC object header uses 24 B (16 B core + 8 B `next`), with the mark bit in flags;
- Recommendation: **GC object header 24 B**, ARC object header 16 B, both sharing the first 16 B layout.

```c
typedef struct {
    const rt_type *type;     /* 8 */
    uint32_t       refcount; /* 4 (unused for GC objects) */
    uint8_t        kind;     /* 1 */
    uint8_t        flags;    /* 1 (mark/age/pinned) */
    uint16_t       aux;      /* 2 */
    /* Appended for GC objects: */
    struct rt_object *next;  /* 8, GC objects only */
} rt_gc_object;              /* 24 B */
```

### 4.3 Strings

```c
typedef struct {
    rt_header hdr;           /* 16 B */
    uint32_t  len;           /* 4 B: number of UTF-8 bytes */
    uint32_t  hash;          /* 4 B: cached hash, 0 means not computed */
    char      bytes[];       /* len + 1, NUL-terminated */
} rt_string;                 /* 24 B + bytes */
```

- Down from 72 B to 24 B;
- `hash` is cached for Map/Set (Design 03);
- Strings are still GC objects, but with a smaller header;
- Small strings may optionally use SSO (short strings inlined into the object), but that increases object size; not in the first version;
- String literals can live in a read-only section and not be allocated (`rt_string_literal`), reducing startup allocations.

### 4.4 Weak References

`weak_head` moves from every object to a side table:

```c
typedef struct {
    void *target;
    rt_weak_slot *slots;
} rt_weak_entry;
```

- Only objects that actually create weak references are registered;
- The vast majority of objects save 8 B;
- Weak slot clearing still follows finalization chain ordering.

## 5. Allocator

### 5.1 Size Classes

```text
16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768,
1024, 1536, 2048, 3072, 4096, 6144, 8192, 12288, 16384
```

- Small objects (≤ 16 KB) go through size classes;
- Large objects use `malloc`/`mmap` directly;
- One free list per size class;
- Pages (64 KB) are split into fixed-size slots;
- Allocation O(1): pop the head of the free list;
- Free O(1): push back onto the free list;
- In-page bitmap marks free/used (optional, for debugging).

### 5.2 TLAB

One TLAB (Thread-Local Allocation Buffer) per thread:

```c
typedef struct {
    char   *start;
    char   *cur;
    char   *end;
    size_t  size_class;
} rt_tlab;
```

- On allocation `cur += size`, pointer bumping;
- When the TLAB is exhausted, grab a new page from the global size class;
- Returned on thread exit;
- Single-threaded programs such as the compiler have almost zero atomic operations;
- Multithreaded programs get an independent TLAB per thread.

### 5.3 Initialization

```c
void *rt_alloc(rt_kind kind, const rt_type *type, size_t payload) {
    size_t total = header_size(kind) + payload;
    rt_header *h = tlab_alloc(total);
    h->type = type;
    h->refcount = 1;
    h->kind = kind;
    h->flags = default_flags(kind);
    if (kind == RT_KIND_GC) gc_register(h);
    return h;
}
```

- Only initialize the header; do not `memset` the whole payload;
- The caller is responsible for initializing fields (codegen knows the layout);
- Debug mode may fill with `memset(0xCD)`, off in production;
- `rt_string_alloc` only writes `len/hash/bytes[len]` and does not memset again.

## 6. ARC Tuning

### 6.1 Non-Atomic Reference Counting

```c
static inline void rt_retain(void *obj) {
    rt_header *h = obj;
    if (h->flags & RT_FLAG_ATOMIC) {
        atomic_fetch_add_explicit((_Atomic uint32_t *)&h->refcount, 1, memory_order_relaxed);
    } else {
        h->refcount++;
    }
}
```

- Thread-local objects are non-atomic by default;
- Cross-thread shared objects (tasks, channels, globals) are marked `ATOMIC`;
- The branch is predictable and far cheaper than an atomic instruction;
- Must guarantee: once an object is shared, all subsequent retain/release go through the atomic path; flags are fixed at creation.

### 6.2 Deferred Release

```c
typedef struct {
    void *objs[64];
    uint32_t n;
} rt_defer_queue;

static inline void rt_release(void *obj) {
    if (--refcount == 0) rt_defer_queue_push(obj);
}

void rt_safepoint(void) {
    rt_defer_queue_flush();  /* unified deinit/free */
    ...
}
```

- Batched releases reduce branching and cache thrashing;
- Flush immediately when the `defer` queue is full;
- Finalization-chain ordering is still executed at flush time; semantics unchanged;
- Suited to the compiler's many temporary objects.

### 6.3 Borrowing and Moving

- The compiler annotates `borrow`/`owned` on MIR;
- `borrow` parameters are not retained;
- Return values are `owned +1`; the caller decides whether to release;
- Move semantics: after `let y = x`, `x` is no longer used, avoiding retain/release;
- After inlining/escape analysis, many retain/release pairs are deleted outright (Design 04).

### 6.4 Finalization Chain Optimization

Current:

```c
h->terminated = 1;
rt_weak_clear_slots(obj);
rt_scan_unregister(obj);   /* linear */
deinit(obj);
rt_quarantine_push(obj);
```

Change to:

- `rt_scan_unregister` uses a doubly linked list, O(1);
- Weak slot clearing is done only when `weak_head != NULL`;
- `deinit` is called only when `type->deinit != NULL`;
- The quarantine reclaims in batches by size class;
- The `terminated` flag reuses a bit in `flags` instead of a separate 4 B.

## 7. GC Design

### 7.1 Generational Strategy

Recommend **non-moving generational mark-sweep**:

- **Nursery (young generation)**: bump allocation; objects are allocated here;
- **Old (old generation)**: entered after survivors are promoted;
- **Minor GC**: scans only the nursery + references from the old generation into the nursery (card table/remembered set);
- **Major GC**: whole-heap mark-sweep;
- Objects do not move; ARC raw pointers stay safe;
- Promotion condition: survived one minor GC, or size exceeds a threshold.

Why not copying GC:

- Objects would be moved, and raw pointers in ARC/FFI/on the stack would need updating;
- XNull has a mixed ARC and GC graph; moving would break invariants;
- A non-moving implementation is safer; get generational benefits first.

### 7.2 Card Table / Remembered Set

- Old generation is divided into 512 B cards;
- When an old-generation object writes a reference to a young-generation object, the card is marked dirty;
- Minor GC scans dirty cards;
- Write barrier:

```c
static inline void rt_write_barrier(void *obj, void *value) {
    if (obj_is_old(obj) && value_is_young(value)) mark_card(obj);
}
```

- The first version can do STW minor GC only, with the write barrier just marking cards;
- Concurrent marking uses an SATB (snapshot-at-the-beginning) barrier.

### 7.3 Marking

- Explicit mark stack/work queue, not recursive;
- Tri-color marking: white/gray/black;
- Roots: global roots, task roots, ARC scan list, thread stack maps;
- Stack maps are generated by the compiler (Design 01); the C stack is not scanned;
- Mark bits live in the object header flags or a side bitmap;
- Large-object/page-level bitmaps reduce cache misses.

### 7.4 Sweeping

- Sweep by page/size class;
- Dead objects: clear weak slots → deinit → return to size class;
- Lazy sweep spreads out pauses;
- Large objects are freed immediately;
- Statistics: alloc/free/live/pause.

### 7.5 GC Triggering

Do not trigger every 1024 allocations:

```c
heap_growth = live_bytes * 2;          /* target */
if (allocated_since_gc > heap_growth * 0.5) minor_gc();
if (old_growth > threshold) major_gc();
```

- Based on bytes allocated, not object count;
- Adaptive: adjust the next threshold based on survival rate;
- Maximum heap limit `XNULL_GC_MAX_HEAP`;
- Trigger early under low memory;
- Provide `xrt_gc_collect()` for explicit triggering (testing/diagnostics).

### 7.6 Safepoints

- Allocation points;
- Loop back-edges;
- Calls that may block;
- `xrt_safepoint()` polls a flag;
- STW: start marking after all threads reach a safepoint;
- The first version is single-threaded and collects directly; thread coordination is added in the multithreaded phase.

## 8. Mixed-Graph Invariants

Must preserve 1–6 from `rt_gc.h`:

1. A strong reference is either counted (ARC) or traced (GC);
2. ARC holds a GC reference → registered in the scan list at allocation; it is a root while alive;
3. GC holds an ARC reference → mark-reachable; release the ARC when sweeping dead GC objects;
4. Weak references do not constitute strong references;
5. Cycles with at least one GC node are reclaimed by GC; all-ARC cycles are reclassified by compiler analysis;
6. ARC unregisters from the scan list and clears GC references before finalization; sweeping only handles references that were live during the object's lifetime.

New constraints:

- Old-generation → young-generation references must be written to the card table;
- If an ARC-scanned object points to a young-generation GC object, it must also be in the remembered set;
- Stack maps must be precise and must not miss roots;
- GC must not be triggered during `deinit` (or it must be at a safepoint).

## 9. Stack Allocation and Regions

### 9.1 Stack Allocation

- Objects whose escape analysis result is `NoEscape`;
- Object size is fixed and there is no `deinit`;
- Does not enter the GC/ARC roots;
- codegen emits `alloca`/C stack variables directly;
- Reduces allocation and reclamation.

### 9.2 Regions (Arena)

- The compiler's internal AST/IR uses arenas (Design 02);
- The language level may optionally have `region`/`arena` syntax (future);
- Regions are freed as a whole, not GC'd per object;
- Must not escape outside the region;
- Suited to request-level/phase-level temporary objects.

## 10. Strings in Depth

Strings are the largest source of allocations in the compiler workload:

- `rt_string` header 72 → 24 B;
- `hash` caching so Map lookups do not rehash;
- Literals in a read-only section; `rt_string_literal` does not allocate;
- SSO for small strings (optional, phase 2): `len <= 7` inlined into the object;
- String concatenation uses `StringBuilder`/preallocation instead of repeated `xn_concat` (Design 03);
- `substring` may return a slice (sharing the underlying buffer + offset/len), but that extends the original string's lifetime; the first version copies, later versions decide based on profile;
- Identifiers use an interner and do not enter the GC heap (Design 02).

## 11. Metrics and Tooling

### 11.1 Runtime Statistics

```c
typedef struct {
    uint64_t allocs, frees, bytes;
    uint64_t gc_minor, gc_major, gc_freed;
    uint64_t arc_retains, arc_releases, arc_atomic_ops;
    uint64_t pause_ns_max, pause_ns_total;
    uint64_t heap_live, heap_capacity;
} rt_stats;
```

- `xrt_stats_get` already exists;
- Add pause distribution (p50/p95/p99);
- Add top-N allocations by type (debugging);
- Off by default; enabled with `XNULL_GC_STATS=1`.

### 11.2 Tools

```text
--gc-stats          one-line summary
--gc-trace          output reason/duration/heap before and after for each GC
--gc-stress         GC on every allocation (testing)
--alloc-profile     statistics by allocation site
```

## Algorithm Selection and Comparison (by Runtime Node)

> Notation: N = number of objects, L = number of live objects, H = heap size, T = number of threads.
> GC/ARC algorithm choice is a pick-two-of-four among pause, throughput, memory, and implementation complexity; XNull's hard constraint is: ARC raw pointers mean objects must not move.

### A1. Memory Management Paradigm

| Approach | Throughput | Pause | Cycle reclamation | Memory | Implementation | Conclusion |
|---|---|---|---|---|---|---|
| Pure ARC | High (no scanning) | None | No (needs cycle detection) | Medium | Low | Not adopted |
| Pure tracing GC | High (batched) | Yes | Yes | Medium-high | Medium | Not adopted |
| ARC + tracing GC hybrid | Medium-high | Yes (GC part) | Yes | Medium | High | **Current/adopted** |
| Region/arena | Highest | None | Whole-region release | Possibly high | Medium | Compiler internals |
| Manual malloc/free | Highest | None | N/A | Low | Low | Not adopted |

Hybrid chosen: DET-01 already decides stack/ARC/GC, and the runtime executes those decisions; pure ARC cannot reclaim cycles, and pure GC would put most short-lived objects through scanning as well.

### A2. GC Algorithms

| Algorithm | Pause | Throughput | Memory | Moves objects | Pros | Cons | Conclusion |
|---|---|---|---|---|---|---|---|
| Mark-sweep | Medium | Medium | Medium (fragmentation) | No | Simple, non-moving | Fragmentation | **Adopted** |
| Mark-compact | Long | Medium | Low | Yes | No fragmentation | Breaks ARC raw pointers | Not adopted |
| Copying | Medium | High | 2x | Yes | Fast allocation | Moves objects | Not adopted |
| Reference counting | None | Medium | Medium | No | Immediate reclamation | Cycles/atomic overhead | ARC portion only |
| Region | None | Highest | High | No | Batched release | Lifetime restrictions | Compiler internals |

Non-moving mark-sweep chosen: ARC/FFI/the stack may hold raw pointers to GC objects; moving would require whole-heap pointer updates, so the first version does not do it. Later, compaction can be done on an "isolated heap with no ARC references".

### A3. Generational Strategy

| Strategy | Young-gen collection | Object movement | Write barrier | Complexity | Conclusion |
|---|---|---|---|---|---|
| Non-generational | Whole heap | No | None | Low | Baseline |
| Copying young gen | Fast | Yes | Card table/remembered set | Medium-high | Not adopted |
| Non-moving young gen | Medium | No | Card table | Medium | **Adopted** |
| Generational + compacting old gen | Fast | Yes | Card table | High | Later |

Non-moving generational chosen: the young generation uses bump allocation + mark-sweep, and survivors are promoted to the old generation; nothing moves, avoiding ARC pointer invalidation. The card table records old→young references.

### A4. Write Barriers

| Barrier | Semantics | Overhead | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Dijkstra incremental update | New reference is shaded gray | Every write | Suited to incremental marking | Needs gray protection | Alternative |
| Yuasa deletion barrier | Old reference is shaded gray | Every write | Suited to concurrency | Needs SATB | Alternative |
| SATB | References at snapshot start | Every write | Standard for concurrent marking | Complex to implement | Adopted in the concurrent phase |
| Card table | Marks by page | Only on cross-generational writes | Cheap | Coarse-grained | **Adopted for generational** |
| No barrier | None | 0 | Fastest | STW only | Single-threaded baseline |

Choice: use the card table (512 B/card) in the generational phase; layer SATB on top in the concurrent marking phase. In the single-threaded/STW phase, barriers can be turned off to reduce constants.

### A5. Marking Algorithms

| Algorithm | Complexity | Stack | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Recursive DFS | O(L) | C stack | Simplest | Stack overflow on deep chains | Not adopted |
| Explicit-stack DFS | O(L) | Heap stack | No overflow, decent cache behavior | Needs a dynamic stack | **Adopted** |
| BFS queue | O(L) | Queue | Level-order, parallel-friendly | Poor cache behavior | Parallel alternative |
| Parallel marking | O(L/T) | Per-thread stacks | Fast | Synchronization/load balancing | Later |

Explicit-stack DFS chosen: object graphs are usually deep and narrow, so DFS has good locality; when the stack is full it overflows to the heap. In the parallel phase, each thread gets a local mark stack + work stealing.

### A6. Allocators

| Algorithm | Allocation | Free | Fragmentation | Pros | Cons | Conclusion |
|---|---|---|---|---|---|---|
| `malloc/free` (current) | Medium | Medium | Medium | General-purpose | Lock/metadata overhead | Retired |
| free-list | Fast | Fast | Medium | Simple | External fragmentation | Alternative |
| size class | Very fast | Fast | Low | O(1), good cache behavior | Internal fragmentation | **Adopted** |
| bump/TLAB | Fastest | Batched | Low | Pointer bumping | Needs whole-block reclamation | **Adopted** |
| Region | Fastest | Batched | High | No per-object work | Lifetime | Compiler internals |

Choice of size class + TLAB: small objects are bucketed into 16/24/32/.../16K classes, with per-thread TLAB pointer bumping; large objects go directly to mmap.

### A7. ARC Atomicity

| Strategy | Single-threaded cost | Multithreaded safety | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Always atomic | High | Yes | Simple | Slow | Not adopted |
| Never atomic | Lowest | No | Fastest | Data races | Not adopted |
| Per-object flag | Low (branch) | Yes | Balances both | Flag fixed at creation | **Adopted** |
| Per-thread/epoch | Low | Yes | Batched | Complex to implement | Later |

Flag chosen: thread-local objects are non-atomic by default; cross-task/global/FFI shared objects are marked `ATOMIC` at creation. The branch is predictable and far cheaper than atomic instructions.

### A8. Deferred Release

| Strategy | Release latency | Batched | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Immediate release (current) | 0 | No | Timely memory | Branch/cache thrashing | Retired |
| Deferred queue | To safepoint | Yes | Batched, less thrashing | Memory peak | **Adopted** |
| Epoch reclamation | To epoch | Yes | Suited to concurrency | Complex to implement | Later |
| No release | ∞ | - | None | Leaks | Not adopted |

Deferred queue chosen: when `release` drops to 0, enqueue on a thread-local queue; deinit/free are done together at a safepoint; flush immediately when the queue is full.

### A9. Cycle Reclamation

| Algorithm | Can reclaim cycles | Cost | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| Static DET-01 reclassification | At compile time | 0 runtime | No runtime overhead | Only handles analyzable cycles | **First choice** |
| Bacon–Rajan synchronous cycle collection | Yes | Medium | Classic, precise | Needs counters/buffers | Alternative |
| Backup tracing | Yes | High | General | Requires whole-heap scanning | Already covered by GC |
| Do nothing | No | 0 | Simple | Leaks | Not adopted |

Choice: DET-01 classifies known strong-reference cycles as GC; GC handles cycles with at least one GC node; pure ARC cycles are reclassified by compiler analysis or reported as errors. The runtime does not implement Bacon–Rajan separately unless profiling proves a large number of ARC cycles.

### A10. Weak References

| Algorithm | Per-object overhead | Clearing | Pros | Cons | Conclusion |
|---|---|---|---|---|---|
| In-object chain (current) | 8 B/object | Walk the chain | Simple | Wasted for the vast majority of objects | Retired |
| Side table | 0 (no weak refs) | Table lookup | Saves memory | Lookup overhead | **Adopted** |
| Global weak table | 0 | Full-table scan | Simple | Slow | Not adopted |

### A11. String Representation

| Representation | Per-string overhead | Concatenation | Slicing | Pros | Cons | Conclusion |
|---|---|---|---|---|---|---|
| Header + bytes (current) | 72 B + bytes | O(N) | Copy | Simple | Header too large | Optimize to 24 B |
| Header + bytes + hash | 24 B + bytes | O(N) | Copy | Fast Map lookup | 4 B extra | **Adopted** |
| SSO (≤7/15 B) | 24 B inline | O(N) | Copy | Zero allocation for small strings | Branching/larger objects | Phase 2 |
| Rope | Nodes | O(1) concat | O(log N) | Large text | Slow random access | Not adopted |
| Slice (shared buffer) | 16 B | O(N) | O(1) | Zero-copy | Extends the original string's lifetime | Per profile |

### A12. Algorithm Selection Summary

| Node | Candidates | Choice | Main rationale |
|---|---|---|---|
| Paradigm | ARC / GC / hybrid | Hybrid | DET-01 + cycle reclamation |
| GC | Mark-sweep / compacting / copying | Non-moving mark-sweep | ARC raw pointers |
| Generations | Copying / non-moving | Non-moving generational | No object movement |
| Barrier | Dijkstra / Yuasa / SATB / card table | Card table + SATB | Generational/concurrent |
| Marking | Recursive / explicit stack / BFS | Explicit-stack DFS | No stack overflow |
| Allocation | malloc / free-list / size class / TLAB | size class + TLAB | O(1) |
| ARC | atomic / non-atomic / flag | flag | Fast single-threaded, safe when shared |
| Release | immediate / deferred / epoch | Deferred queue | Batched |
| Cycles | Bacon–Rajan / tracing / DET-01 | DET-01 + GC | Zero runtime |
| Weak refs | In-object chain / side table | Side table | Saves 8 B/object |
| Strings | header+bytes / SSO / rope | 24 B header + SSO later | Memory/implementation |

### Implementation Mapping

| Algorithm/node | Implementation location | Phase |
|---|---|---|
| 16B/24B object headers + 24B String | `src/runtime/rt.h`, `rt.c` | G0 |
| size class + TLAB + deferred release | New `src/runtime/rt_alloc.c`, `rt_alloc.h` | G1–G2 |
| Non-atomic/flag ARC + doubly linked scan list | `src/runtime/rt.c`, `rt_gc.c` | G2 |
| Non-moving generational + card table + minor GC | `src/runtime/rt_gc.c`, new `rt_card.c` | G3 |
| Explicit mark stack + lazy sweep | `src/runtime/rt_gc.c` | G1–G3 |
| Concurrent marking SATB | `src/runtime/rt_gc.c`, `rt_barrier.c` | G4 |
| Stack allocation/regions, string literals | `src/compiler/opt/escape.x`, `src/runtime/rt.c` | G5 |

**Fallback conditions**: multithreaded shared objects force atomics; when the GC budget is exceeded, only do minor GC; keep `XNULL_GC_MODE=stw` as a fallback until generational/concurrent is stable.

## 12. Phased Rollout

| Phase | Deliverable | Acceptance |
|---|---|---|
| G0 | Object header split; `rt_string` 24 B; weak-reference side table | All existing tests green; memory down > 30% |
| G1 | size class + TLAB; byte-triggered GC; mark stack | Allocation throughput 2x; no recursion stack overflow |
| G2 | Non-atomic ARC + deferred release + O(1) scan-list unregistration | Lower single-threaded ARC cost; multithreaded correctness |
| G3 | Generational nursery + card table + minor GC | Lower p99 pauses; faster self-compilation |
| G4 | Concurrent marking (SATB) + lazy sweep | Large-heap pause < 10 ms |
| G5 | Stack allocation/regions + string literals/SSO | Lower allocation volume; performance targets met |

## 13. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Header layout changes break ABI | `xrt.h` does not expose the header layout; internal `rt.h` may change; ABI versioning applies only to function signatures |
| Non-atomic ARC used for shared objects | `ATOMIC` flag fixed at creation; tasks/globals force atomics |
| Generational write barrier misses marks | Card table + `--gc-stress` + ASan; STW minor first for safety |
| Moving objects breaks raw pointers | No movement in the first version; compaction deferred |
| Imprecise stack maps | MIR verifier + conservative fallback (do not enable stack allocation) |
| `deinit` reentrancy/resurrection | Preserve finalization-chain ordering; quarantine; resurrection is fatal |
| Performance regression | Benchmarks per phase; feature-flag fallback |
| Self-compilation E4 hangs | Fix correctness first, then performance; GC roots/safepoints take priority |

## 14. Open Questions

1. Should objects be allowed to be shared across tasks, which determines the ARC atomic mode?
2. Is a user API for weak references/finalizers needed?
3. Default generational nursery size (by CPU cache/heap ratio)?
4. Should concurrent marking be done, or STW generational first?
5. SSO threshold for strings (7/15/23 bytes)?
6. Should a `region` language feature be introduced, or only compiler-internal arenas?
