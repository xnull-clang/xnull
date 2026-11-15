# XNull Inlining and Devirtualization Detailed Design

> Status: Design draft v1 · 2026-11-15
> Scope: `src/compiler/codegen/`, MIR optimization layer, protocol dispatch, runtime type descriptors
> Related: Design 01 (backend), Design 05 (GC/ARC), Design 07 (PGO)
> Algorithm selection: each implementation node lists candidate algorithms, complexity, pros and cons, and the rationale for the choice; see the "Algorithm Selection and Comparison" section.

## 1. Conclusions

XNull has a language design that is very well suited to devirtualization:

- Classes do not support override-based inheritance, so methods are naturally final;
- Polymorphism is expressed only through protocols;
- Protocol calls currently go through `__vtable[slot]` indirect calls;
- Class objects that implement protocols carry `void **__vtable`, and type checks use `strcmp(typeName, ...)`.

Therefore there is a lot of room for optimization:

1. **Class method calls should inherently be direct calls**, with no vtable needed;
2. **Protocol calls** can be devirtualized through concrete type propagation, sealed protocols, RTA, and PGO type profiles;
3. **Inlining** can further eliminate `retain/release`, bounds checks, and `is/as` checks;
4. **Type checks** should change from `strcmp` to `TypeId` comparison.

Goal: on real workloads such as the compiler/XDK, reduce the share of indirect calls to below 10%, improve runtime by 10–25%, and keep code size growth within 10%.

## 2. Current State

### 2.1 Classes and Protocols

```x
protocol Shape {
    Int area()
}

class Circle implements Shape {
    Int r
    Int area() { return 3 * self.r * self.r }
}

static Int main() {
    Shape s = new Circle(2)
    print(s.area())
    return 0
}
```

Current codegen:

```c
typedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;
typedef void *xn_proto_Shape;

/* call */
((int64_t (*)(void *))((xn_vt_obj *)(s))->__vtable[0])(s)
```

Problems:

- The static type of `Shape s` is a protocol, so even if the actual type is `Circle`, the call still goes through an indirect call;
- Every object that implements a protocol carries a `__vtable` pointer (8 B/object);
- vtable slots are allocated in protocol method order, but there is no globally stable ID;
- `is/as` use `xn_any_is`:

```c
static int xn_any_is(xn_Any *b, const char *typeName) {
    return b != NULL && b->typeName != NULL &&
           strcmp(b->typeName, typeName) == 0;
}
```

`strcmp` is expensive on hot paths.

### 2.2 Inlining

Currently there is no MIR and no inlining pass. All function calls are carried through to C, and `cc -O2` decides whether to inline. Problems:

- The C compiler cannot see XNull's ownership/protocol semantics;
- It cannot do devirt based on XNull type information;
- `retain/release` cannot be paired and eliminated across call boundaries;
- Bounds checks cannot be eliminated based on XNull loop information;
- PGO cannot feed back into the XNull layer.

### 2.3 Global State

`Codegen.x` has a large amount of mutable global state (`ESC_EXPR_N`, `STAGE_T`, the `unq` table, etc.), which is bad for parallelism and bad for decomposing the compiler into passes. Inlining/devirtualization must be built on immutable HIR/MIR.

## 3. Goals and Non-Goals

### 3.1 Goals

| Metric | Target |
|---|---|
| Class method calls | 100% direct calls |
| Protocol call devirtualization rate | Compiler/XDK workloads ≥ 90% |
| Indirect call share | < 10% |
| Inlining rate (hot functions) | ≥ 60% of call sites |
| Runtime | -10% to -25% |
| Code size | +0% to +10% |
| Compile time | Within +15% |
| Semantics | Completely unchanged |

### 3.2 Non-Goals

- No JVM-level polymorphic inline caches (first version);
- No whole-program LLVM-level optimization;
- Do not change protocol semantics/observable behavior of dynamic dispatch;
- Do not sacrifice diagnostics/debug information for performance.

## 4. Type and Call Representation

### 4.1 TypeId

Each type is assigned a stable `u32 TypeId`:

```c
typedef uint32_t TypeId;

typedef struct {
    TypeId   id;
    uint32_t name_off;      /* for diagnostics */
    uint16_t kind;          /* class/struct/enum/protocol/... */
    uint16_t flags;         /* sealed / final / nullable */
    uint32_t parent;        /* 0 (no inheritance) */
    uint32_t field_n;
    uint32_t method_n;
    uint32_t protocol_n;
    const ProtocolImpl *protocols;
} TypeInfo;
```

- TypeIds are assigned in the sema phase in sorted order by `(module path, type name)`, guaranteeing determinism;
- Runtime object headers store the TypeId (see Design 05) and no longer store `const char *typeName`;
- `is` = compare TypeId or look up the protocol implementation bitmap;
- `as` = `is` + value extraction.

### 4.2 Protocol Slots

```c
typedef struct {
    uint16_t protocol_id;
    uint16_t method_id;
    uint16_t slot;          /* globally stable slot */
    uint16_t flags;
} ProtocolSlot;
```

- Slots are assigned in sorted order by `(protocol name, method signature)`;
- The vtable is `const void *slots[protocol_method_count]`;
- Classes fill in the vtable when they implement a protocol;
- The call site knows the `slot` and needs only a single indirect jump;
- If devirtualized, it calls the concrete function directly.

### 4.3 Call-Site Representation

MIR:

```c
typedef struct {
    uint16_t op;            /* CALL / CALLVIRT */
    uint16_t flags;         /* tail / cold / devirt_guard */
    TypeId   recv_type;     /* static type */
    uint32_t callee;        /* direct: FunctionId; virt: protocol slot */
    uint32_t argc;
    MnId     args;          /* ChildRange */
    uint32_t type_profile;  /* PGO: TypeProfileId */
} MnCall;
```

`CALLVIRT` additionally records:

- `proto_id`, `slot`;
- `candidate_set` (RTA result, may be empty);
- `guard` (type guard for speculative devirtualization).

## 5. Devirtualization Algorithms

### 5.1 Class Methods: Direct Calls

XNull classes do not support inheritance, so:

- `Circle.area` is final;
- `area` on `Circle*` directly calls `xn_Circle_area`;
- No vtable is needed;
- Only protocol variables require dynamic dispatch.

This is the first layer, at almost zero cost.

### 5.2 Concrete Receiver Propagation (local type flow)

Perform type propagation on MIR:

```text
Circle c = new Circle(2)
Shape s = c
s.area()
```

- The TypeId of `c` = Circle;
- The only assignment source of `s` is Circle;
- The receiver candidate set of `s.area()` = {Circle};
- Call `Circle.area` directly.

Implementation:

- Each SSA value carries a `TypeSet` (a small set, at most N TypeIds);
- Assignments/phi/call return values are unioned;
- Unknown sources (parameters, fields, FFI) fall back to the static type;
- Iterate to a fixed point.

### 5.3 Sealed Protocols

If a protocol is implemented only within the current compilation unit/module, and there is no `open`/dynamic loading:

```text
sealed protocol Shape
class Circle implements Shape
class Square implements Shape
```

- All implementors are known;
- The call-site candidate set = {Circle, Square};
- If only one is instantiated (RTA), call directly;
- If there are several, generate a switch:

```c
switch (obj->type_id) {
  case TID_Circle: return Circle_area(obj);
  case TID_Square: return Square_area(obj);
  default: return vtable_call(obj);
}
```

- A switch is cheaper than an indirect call, and each branch can be inlined.

### 5.4 RTA (Rapid Type Analysis)

- Starting from `main`/entry points/exported functions, collect the TypeIds of all objects allocated with `new`;
- Collect all protocol implementations;
- For each protocol call site, the candidate set = classes that have been instantiated and implement the protocol;
- If the candidate set is 1, call directly;
- If it is 0, this indicates dead code/an error; report a diagnostic or keep the virtual call;
- If it is 2–4, use a switch;
- If it is > 4, keep the vtable or use a PGO primary target + guard.

### 5.5 Speculative Devirtualization (guarded devirt)

For polymorphic call sites, use a type guard + direct call:

```c
if (obj->type_id == TID_Circle) {
    return Circle_area(obj);          /* hot path, can be inlined */
} else {
    return vtable_call(obj, SLOT_area); /* cold fallback */
}
```

- Guard cost: one TypeId comparison (predictor-friendly);
- Suitable for call sites where PGO shows that one type accounts for > 80%;
- Two-level guards (top-2) are possible;
- No more than 2 guards, to avoid code bloat;
- Guard failure goes to the generic vtable; semantics are unchanged.

### 5.6 Type-Check Optimization

Current:

```c
strcmp(typeName, "Circle") == 0
```

Change to:

```c
obj->type_id == TID_Circle
```

Protocol check:

```c
/* TypeInfo stores a protocol bitmap or implementation table */
(type_protocol_mask(obj->type_id) & PROTO_SHAPE) != 0
```

- `is` compiles to a bit test;
- `as` compiles to a bit test + value extraction;
- `Any` boxing stores the TypeId, not a string;
- Look up the table only when diagnostics/`typeName()` need it.

### 5.7 Object Headers and vtables

Currently every protocol object carries a `void **__vtable`. Proposal:

- Objects with no protocol implementation: no vtable pointer outside the object header;
- Objects with a protocol implementation: put the vtable pointer in an object-header extension, or in TypeInfo:

```c
typedef struct {
    rt_header hdr;
    TypeId    type_id;
    /* no vtable pointer */
} XnObject;

/* on a protocol call: type_info(type_id)->vtable[slot] */
```

- Pros: saves 8 B per object; there is only one copy of the vtable (per type);
- Cons: a protocol call incurs one extra TypeInfo load (can be cached);
- If the type is known, call directly without loading the vtable.

Recommendation: keep the in-object vtable pointer in the first version to minimize changes; move it to TypeInfo in the second phase, together with the TypeId optimization.

## 6. Inlining Design

### 6.1 Benefits of Inlining

Inlining is not an end in itself; the benefits come from subsequent optimizations:

- Eliminate call overhead;
- Make `retain/release` pairs visible, and thus eliminable;
- Make the concrete type of the protocol receiver visible, and thus devirtualize;
- Propagate constant arguments, eliminating branches/bounds checks;
- Make `new` objects non-escaping, enabling stack allocation/SROA;
- Fold tag checks for `Result`/`Option`.

### 6.2 Inlining Decisions

Cost model:

```text
cost(callee) = instruction_count
             + 4 * call_count_in_callee
             + 8 * has_loop
             + 16 * has_try_defer
             - 8 * is_tiny
             - 4 * is_hot
benefit(caller, site) = profile_count(site) * (1 + devirt_gain + arc_gain)
inline if benefit > threshold * cost
```

Simplified first version:

- Function body ≤ 20 MIR instructions: always inline;
- ≤ 60: inline if the call site is hot (PGO) or the caller is small;
- Recursion: unroll at most 1 level, depth limit 8;
- Contains `try/defer`: do not inline by default unless tiny;
- FFI/variadic: do not inline;
- `#[inline(always)]`: force (with budget protection);
- `#[inline(never)]`: forbid (debugging/cold code).

### 6.3 Inlining Implementation

Do it on MIR:

1. Copy the callee's blocks/insts into the caller;
2. Parameter mapping: `param` -> argument SSA values;
3. Return value mapping: `return` -> new phi/assignment;
4. Source locations keep the callee span, and add an `inlined_from` marker;
5. Remove unreachable blocks;
6. Run `SROA/DCE/ARC opt`.

Notes:

- Do not inline `noreturn`/fatal paths;
- Do not inline debug-sensitive functions where inlining would change the stack trace (can use `#[inline(never)]`);
- If code size exceeds the budget after inlining, roll back.

### 6.4 Post-Inlining Cleanup

| pass | Effect |
|---|---|
| SROA | Break small `new` objects into scalars |
| DCE | Delete unused fields/branches |
| ARC opt | Delete paired retain/release |
| constprop | Fold constant arguments |
| devirt | Direct call once the receiver type is determined |
| bounds-check | Eliminate checks once loop ranges are determined |
| CFG simplify | Merge blocks/remove empty jumps |

## 7. Escape Analysis and Stack Allocation

### 7.1 Escape States

```text
NoEscape     Used only within the current function; can be stack-allocated/SROA'd
ArgEscape    Passed out as an argument, but the callee does not save it
GlobalEscape Stored into a global/field/closure/task; must be heap-allocated
```

### 7.2 Uses

- `new Circle(2)` does not escape: allocate on the stack, and fields become scalars;
- Non-escaping ARC objects: delete retain/release;
- Non-escaping protocol objects: devirt + inline;
- Escape to the GC heap: per the DET-01 policy;
- Escape to a task/closure: must be heap/root-registered.

### 7.3 Relationship to DET-01

DET-01 decides "this type uses stack/ARC/GC"; escape analysis decides "whether this instance really needs the heap". The two do not conflict:

```text
policy(type) = ARC
escape(instance) = NoEscape
=> stack allocation + delete ARC
```

Must guarantee: stack-allocated objects cannot be captured by GC roots/tasks/closures; otherwise fall back to heap allocation.

## 8. Coordination with ARC Optimization

ARC optimization reaches its maximum benefit only after inlining/devirtualization:

- `retain(x); ...; release(x)` on the same object with no escape => delete;
- Function parameter `borrow` does not retain;
- Return value `owned` retains only when the caller needs it;
- `new` + immediate `release` => stack allocation/SROA;
- Container push/pop retain/release are eliminated in pairs;
- Releases crossing `try/defer` must be kept (cleanup paths).

## 9. Pass Order and Budgets

```text
HIR -> MIR
  -> build callgraph / RTA / type flow
  -> bottom-up inline (budget)
  -> devirt (CHA/RTA/guards)
  -> constprop
  -> DCE
  -> escape analysis
  -> SROA
  -> ARC opt
  -> CSE / LICM
  -> bounds-check elimination
  -> CFG simplify
  -> codegen
```

Iterate 2–3 rounds, until nothing changes or the budget is reached.

Budgets:

- `--inline-budget=N` (default based on function size);
- `--devirt-budget=N` (number of guards);
- Stop inlining when code size growth > 15%;
- Degrade when compile time growth > 25%.

## 10. PGO Interface

Reserved for Design 07:

```c
typedef struct {
    uint32_t call_site;     /* MIR call site id */
    uint32_t target;        /* TypeId / FunctionId */
    uint64_t count;
} TypeProfileEntry;

typedef struct {
    uint32_t call_site;
    uint32_t callee;
    uint64_t count;
} CallProfileEntry;
```

Uses:

- Hot call sites get inlining priority;
- Hot types get guard priority;
- Cold functions marked `XN_COLD`;
- Polymorphic sites choose top-1/top-2 guards;
- Branch layout/block ordering.

## 11. Benchmarks and Acceptance

### 11.1 Benchmarks

```text
bench/devirt/protocol_single     single-implementation protocol, 1e8 calls
bench/devirt/protocol_poly2      two implementations, 50/50
bench/devirt/protocol_poly8      eight implementations
bench/devirt/any_is              is/as hot path
bench/inline/tiny_calls          small function calls
bench/inline/arc_pairs           retain/release pairs
bench/real/compiler              compiler self-hosting
bench/real/xdk                   XDK scenario
```

### 11.2 Metrics

| Metric | Collection | Target |
|---|---|---|
| Indirect call count | MIR statistics/runtime count | -90% |
| Inlining rate | MIR statistics | Hot call sites ≥ 60% |
| Runtime | hyperfine | -10% to -25% |
| Code size | `size` | +0% to +10% |
| Compile time | `time` | Within +15% |
| Devirtualization correctness | Differential testing | 100% identical |

### 11.3 Correctness

- All protocol/`is`/`as` tests;
- Dynamic dispatch semantics tests: multiple types alternating at the same call site;
- Guard-failure fallback tests;
- Debug information/stack traces acceptable after inlining;
- GC stress + inlining/stack allocation combinations;
- Self-hosting fixed point does not regress.

## Algorithm Selection and Comparison (by Optimization Node)

> Notation: N = number of functions/instructions, E = number of call edges, S = size of the candidate type set at a call site.
> Selection criteria for optimization algorithms: precision, compile time, code size, parallelizability; if any of these gets out of control, fall back to a conservative algorithm.

### A1. Call Graph Construction

| Algorithm | Complexity | Precision | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| CHA (Class Hierarchy Analysis) | O(N) | Low | Fast, simple | All implementations considered reachable; devirtualization is conservative | Baseline |
| RTA (Rapid Type Analysis) | O(N) | Medium-high | Only looks at instantiated types; good precision/cost balance | Requires the global `new` set | **Adopted** |
| VTA (Variable Type Analysis) | O(N²) | High | Distinguishes variables; higher precision | Slow, high memory | Fallback for large projects |
| 0-CFA | O(N³) | High | Flow-insensitive, theoretically complete | Uncontrollable compile time | Not doing |
| k-CFA | Higher | Highest | Context-sensitive | Even slower | Not doing |

Choose RTA: XNull classes cannot be inherited, and protocol implementations are limited; RTA's set of "instantiated types" is already precise enough. Enable VTA only for modules where it yields a clear precision benefit.

### A2. Type-Flow Propagation

| Algorithm | Complexity | Precision | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Iterative dataflow | O(N·H) | Medium | Simple, general | Slow convergence | Alternative |
| SSA worklist | O(N+E) | Medium-high | Processes only changed values, fits MIR naturally | Requires SSA | **Adopted** |
| Constraint solving (set constraints) | O(N³) | High | Expresses complex types | Heavy implementation | Not doing |
| Type inference (Hindley–Milner style) | O(N log N) | High | Global inference | Mismatch with an explicitly typed language | Not adopted |

Choose SSA worklist: MIR is already in SSA, `TypeSet` propagates along def-use edges, and unknown sources (parameters/fields/FFI) take the static-type upper bound.

### A3. Devirtualization Strategies

| Strategy | Per-call overhead | Precision | Code size | Applicable | Verdict |
|---|---|---|---|---|---|
| Direct call (single candidate) | 0 | Highest | Smallest | S=1 | **Adopted** |
| `switch(type_id)` | 1 comparison + jump | High | Medium | S=2–4 | **Adopted** |
| Guarded devirt (top-1/2) | 1–2 comparisons | Depends on profile | Controllable | Hot polymorphic sites | **Adopted** |
| Polymorphic inline cache (PIC) | 1–3 comparisons | High | Medium | Dynamic-language style | Alternative |
| Full vtable | 1 indirect jump | Dynamic | Smallest | S large/unknown | Fallback |
| Inline cache (monomorphic) | 1 comparison | Medium | Small | Hot monomorphic | Can be folded into guarded |

Selection: after RTA produces the candidate set, S=1 → direct call; S=2–4 → switch; S>4 with a PGO primary type → top-2 guard; otherwise vtable. Guard failure must fall back; semantics are unchanged.

### A4. Inlining Algorithms

| Algorithm | Complexity | Code size | Benefit | Compile time | Verdict |
|---|---|---|---|---|---|
| Greedy bottom-up | O(N·budget) | Controllable | Stable | Low | **Adopted** |
| Top-down | O(N·budget) | Prone to bloat | Good context | Medium | Alternative |
| Knapsack/ILP | NP-hard | Theoretically optimal | Highest | Uncontrollable | Not doing |
| Genetic/ML | Training cost | Unpredictable | Possibly high | High | Not doing |
| Inline tiny only | O(N) | Smallest | Limited | Lowest | Baseline |

Choose greedy bottom-up + budget + PGO weights: inline small functions first, then use profiles to decide hot call sites; recursion depth is limited to avoid explosion.

### A5. Inlining Cost Model

| Model | Inputs | Precision | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Instruction-count threshold | callee size | Low | Simple | Ignores hotness | Baseline |
| Call-frequency weighting | profile count | Medium | Focuses on hot paths | Requires PGO | **Adopted** |
| Cache-aware | instruction count + cache line | High | Realistic | Hard to model | Later |
| Code-size budget | global budget | Medium | Prevents bloat | Not locally optimal | **Used together** |

Formula:

```text
score = profile_count(site) * (1 + devirt_gain + arc_gain)
      / (callee_cost + call_overhead)
inline if score > threshold && code_budget_left
```

### A6. Escape Analysis

| Algorithm | Complexity | Precision | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Steensgaard | O(N α(N)) | Low | Fast, scalable | Merges too much; misjudges escape | Fallback for very large functions |
| Andersen | O(N³) | High | Precise | Slow, high memory | Not in the first version |
| Flow- and field-sensitive | O(N²) worst case | High | Can prove fields do not escape | Complex to implement | **Adopted (within budget)** |
| Connection analysis | O(N²) | Medium-high | Fits object graphs | Hard to tune | Alternative |

Selection: flow-sensitive, field-sensitive, with a per-function budget; above 5k instructions, degrade to Steensgaard. Escape results are used only for "can be stack-allocated/can delete ARC"; when uncertain, conservatively heap-allocate.

### A7. SROA / Scalar Replacement

| Algorithm | Complexity | Benefit | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Full SROA | O(N²) | High | Breaks up aggregates | Compile time | Adopted within budget |
| Small objects only | O(N) | Medium | Fast | Limited coverage | Baseline |
| Aggregate reconstruction | O(N log N) | Medium-high | Fits arrays | Complex implementation | Later |
| None | 0 | 0 | No risk | No benefit | Fallback |

Selection: apply SROA only to objects that "do not escape, have ≤ 8 fields, and have no deinit"; otherwise keep them.

### A8. ARC Elimination

| Algorithm | Complexity | Precision | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Pair matching | O(N) | Medium | Simple, fast | Weak across branches | **Foundation** |
| Live-variable dataflow | O(N·H) | High | Across branches/loops | Requires CFG | **Adopted** |
| Ownership type system | Compile time | Highest | Static guarantee | Large language changes | Not adopted |
| Reference-count immutability | O(N) | Medium | Fits functional style | Not general | Alternative |

Selection: live variables + pair matching; after inlining, `retain/release` are often in the same block and can be deleted by pairing; cross-block cases are proven with liveness.

### A9. Bounds-Check Elimination

| Algorithm | Complexity | Capability | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Range analysis | O(N) | Constants/loop variables | Fast | Does not handle affine | **Adopted** |
| ABCD | O(N²) | Affine | Strong | Complex | Later |
| Loop versioning | O(N) | Runtime guard | Preserves semantics | Code bloat | **Adopted** |
| PGO speculative elimination | O(1) | profile | Aggressive | Cannot change fatal | Hints only |

### A10. Code Layout

| Algorithm | Complexity | Benefit | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Source order | 0 | 0 | Simple | Hot code scattered | Baseline |
| Hot/cold splitting | O(N) | Medium | Simple, stable | Coarse granularity | **Adopted** |
| Pettis–Hansen | O(N log N) | High | Classic block layout | Requires edge profile | **Adopted with PGO** |
| Graph partitioning | O(N²) | High | Can be global | Complex | Later |
| Greedy chains | O(N log N) | Medium-high | Simple | Not optimal | Alternative |

### A11. Algorithm Selection Summary

| Node | Candidates | Choice | Main rationale |
|---|---|---|---|
| Call graph | CHA / RTA / VTA / CFA | RTA | Precision/cost |
| Type flow | iterative / SSA worklist / constraints | SSA worklist | Fits MIR |
| Devirtualization | direct / switch / guard / PIC | direct+switch+guard | Tiered by S |
| Inlining | greedy / top-down / ILP | greedy+budget+PGO | Controllable |
| Cost model | threshold / frequency / cache | frequency-weighted | Hot paths |
| Escape | Steensgaard / Andersen / flow-sensitive | flow-sensitive+budget | Precision/time |
| SROA | full / small-object / aggregate | small-object SROA | Benefit/cost |
| ARC | pairing / liveness / ownership | liveness+pairing | General |
| Bounds | range / ABCD / versioning | range+versioning | Preserves semantics |
| Layout | source / hot-cold / Pettis-Hansen | hot-cold+PGO | Simple and effective |

### Implementation Mapping

| Algorithm/Node | Implementation Location | Phase |
|---|---|---|
| TypeId + protocol slots | `src/runtime/rt.h`, `src/compiler/codegen/` | D0 |
| RTA + type flow | New `src/compiler/opt/callgraph.x`, `typeflow.x` | D2–D3 |
| switch/guarded devirt | New `src/compiler/opt/devirt.x` | D3–D6 |
| Greedy inlining + cost model | New `src/compiler/opt/inline.x` | D4 |
| Flow-sensitive escape analysis + SROA | `src/compiler/opt/escape.x`, `sroa.x` | D5 |
| ARC liveness/pair elimination | `src/compiler/opt/arc.x` | D5 |
| Bounds-check range/versioning | `src/compiler/opt/bounds.x` | D5 |
| Hot/cold layout + PGO guard | `src/compiler/opt/layout.x`, `design07` | D6 |

**Fallback conditions**: when the inlining budget is exhausted, escape analysis times out, the RTA candidate set is > 8, or the profile is missing, everything falls back to conservative paths (vtable + heap allocation + keeping checks in place).

## 12. Phased Rollout

| Phase | Deliverable | Acceptance |
|---|---|---|
| D0 | TypeId + protocol slots + `is/as` switched to TypeId | Semantics unchanged; `strcmp` disappears |
| D1 | Direct calls for class methods; protocol calls keep the vtable | Zero indirect class calls |
| D2 | Type flow + single-implementation protocol devirt | 100% direct in single-implementation scenarios |
| D3 | RTA + switch devirt | Indirect calls drop sharply in multi-implementation scenarios |
| D4 | Inlining pass + cleanup | Hot-function inlining rate meets target |
| D5 | Escape analysis + stack allocation + ARC elimination | ARC operations decrease |
| D6 | PGO guard + hot/cold layout | Real-workload improvement |
| D7 | Move vtable to TypeInfo (optional) | Object header shrinks |

## 13. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Devirtualization changes dynamic dispatch semantics | Call directly only when the candidate set is definite; fall back on guard failure |
| Inlining causes code bloat | Budget + hot/cold splitting + PGO |
| Inlining causes compile-time explosion | Depth limit + budget + parallelism (Design 06) |
| Escape analysis misjudges | Conservative: heap-allocate when uncertain; GC/ASan tests |
| Type flow is imprecise | Keep the virtual call when the candidate set is empty; do not assume |
| Protocol dynamic loading/plugins | Whole-program devirt only for sealed protocols; open protocols keep the vtable |
| Debug information loss | Preserve `inlined_from`/span; inlining can be disabled under `-g` |
| Self-hosting compiler uses protocols heavily | Profile the compiler itself first; enable in phases |

## 14. Open Questions

1. Should protocols be allowed to be implemented across compilation units (this determines the scope of sealed)?
2. Is a user annotation `#[inline]` needed?
3. Are dynamic loading/plugins within the language scope?
4. Is it worth implementing inline caches for polymorphic call sites (not in the first version)?
5. Whether the vtable goes in the object header or in TypeInfo depends on measurements of object size vs. call frequency.
