# Show HN Draft — XNull

> Post on **Tuesday–Thursday, 8:00–10:00 AM ET**. Submit as a link post to the repo, then immediately add the first comment below. Reply to every technical comment within the hour.

## Title options (pick one, ≤80 chars)

1. `Show HN: XNull – a language where the compiler decides memory management`
2. `XNull: a language designed for predictability — full specs published (CN/EN)`
3. `Show HN: XNull – no overriding, no accessors, errors as values (specs inside)`

Recommend #1 or #3 — a runnable demo exists now (tree-walking interpreter; real outputs embedded below).

## First comment (post immediately after submitting)

---

Hi HN — I'm the author of XNull.

XNull is a programming language designed around one rule: **a program's behavior must be determined by its source text plus the spec — nothing else.** The full specifications (8 parts, approved baseline) are published in the repo, in both Chinese and English.

And unlike most spec-first projects, you can run it today:

```
$ go run ./cmd/xnull run examples/hello.x
hello, XNull
1 + 2 = 3
```

A tree-walking interpreter ships with the repo, tracked item-by-item in a public conformance ledger (101 items, 2 PASS, Unimplemented honestly labeled).

Three decisions that shape everything:

1. **The compiler decides memory management.** Source code never expresses reference strength — no ownership annotations, no smart-pointer types, no `weak` fields. The compiler adjudicates ARC vs. GC vs. stack per an explicit decision table (S2 §15.1, criterion DET-01), and the runtime executes it. Deterministic by construction: same source + same compiler version and options = same adjudication.

2. **No accessor pattern.** There are no getters or setters — not "discouraged", *not expressible*. Fields are fields; behavior is behavior. Computed values are verb-named methods.

3. **Errors are values, period.** `Result<T,E>` with `try` propagation and `defer`/`errdefer` for cleanup. No exceptions, no unwinding, no hidden control flow. Every error path is visible in the signature.

   One real run of the cleanup semantics (block exit, LIFO, ok vs error path):

   ```
   $ go run ./cmd/xnull run examples/defer-cleanup.x
   A
   B
   C
   inner cleanup
   D
   cleanup 2
   cleanup 1
   ---
   ok path: 5
   defer: run exits
   ---
   errdefer: error path
   defer: run exits
   recovered: neg
   ```

   `inner cleanup` fires when its block exits (not at function exit); `cleanup 2` runs before `cleanup 1` (LIFO); the ok path never executes `errdefer`; the error path runs `errdefer` then `defer`, and the propagated error is readable after `try`.

Also deliberately absent: method overriding (polymorphism is protocols-only), abstract methods, reflection, operator overloading, named arguments. Every rejection is documented with its rationale in the spec — we think the *rejected* ideas are the interesting part, and we're happy to defend any of them.

**Status honesty**: a tree-walking interpreter just landed: `go run ./cmd/xnull run examples/hello.x` runs today, with three examples in `examples/` (hello, Result/try, defer/errdefer). The C runtime — executing the ARC/GC decision table, deinit ordering — is the next milestone. The conformance ledger publishes every task, Unimplemented included. The specs are the primary artifact. Criticism of the design is exactly what we want; we tried to preempt criticism of premature claims by publishing the status up front.

Ask me anything — especially about the decisions you think are wrong.

## Reply playbook (pre-prepared)

| Attack | Response |
|---|---|
| "Just use Rust" | "Rust's ownership puts lifetime burden on the author; XNull's thesis is the compiler can adjudicate strategy deterministically without source-level annotations. Trade-off: less control, more predictability of *what you wrote means*. Happy to dig into where each wins." |
| "ARC/GC hybrid is undecidable / will leak" | "S2 §15.6 invariants: every strong reference is either counted or traced — never neither. Cycles are detected statically and reclassified as GC. It's conservative, not clever." |
| "No overriding = verbose" | "In practice protocol polymorphism covers the dynamic cases; static reuse covers the rest. The spec shows the same example dispatched both ways (S2 §5.6). Genuinely curious where you'd get stuck." |
| "Chinese-first specs = niche" | "All 10 documents ship with English translations; English is the primary public version. Bilingual from day one." |
| "Where's the compiler?" | "A tree-walking interpreter ships today — `go run ./cmd/xnull run examples/hello.x`. The C backend is the next milestone. The conformance ledger (101 items, Unimplemented included) lets you watch the roadmap move instead of trusting a README." |
| "700 lines is a toy" | "It's a deliberately scoped interpreter: the semantics this design is argued on — `try` propagation, `defer`/`errdefer` LIFO, byte-identical deterministic output across runs (tested). Objects and generics come next; the ledger says exactly what's in and out." |
