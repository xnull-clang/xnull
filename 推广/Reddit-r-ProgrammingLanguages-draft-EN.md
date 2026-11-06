# Reddit r/ProgrammingLanguages — Draft Post (EN)

> Post the same day as Show HN or the day after. Title ≤ 100 chars. Flair: "Discussion" or per subreddit rules.

## Title

```
XNull: a language where the compiler decides memory strategy (bilingual specs + runnable demo)
```

## Body

---

I've spent the last months designing XNull, a language built on one axiom: **if a behavior isn't determined by the source text and the spec, it doesn't exist.** The complete approved baseline (8 spec parts + capability boundaries + a public conformance ledger) is on GitHub — Chinese originals with English translations.

It's not just specs: a tree-walking interpreter ships with the repo.

```
$ go run ./cmd/xnull run examples/hello.xn
hello, XNull
1 + 2 = 3
```

Every supported and unsupported feature is tracked in a public conformance ledger (101 items, 2 PASS, Unimplemented honestly labeled).

The decisions I most want this community to attack:

**1. Memory strategy is compiler-adjudicated, invisible in source.**
No ownership, no borrow checker, no `Rc`/`Arc`, no weak references, no `@gc` annotations. The compiler classifies every object via a decision table (singleton → GC; data-enum → GC; a class whose methods capture `self` or that has `deinit` → ARC; a class with only value fields that doesn't escape → stack candidate, promoted if it escapes). Mixed ARC↔GC graphs are handled by invariants (every strong ref is counted *or* traced; cycles are statically detected and reclassified to GC). I know this forfeits the control Rust gives you. The bet: most programs don't need that control, and paying for it with lifetime annotations is a bad trade. **Where does this bet fail?**

**2. No accessor pattern, at the syntax level.**
No getters/setters, no properties, no custom `get`/`set`. Public fields are the property access. Computed values must be verb-named methods. The claim: the accessor pattern's costs (encapsulation theater, invariant erosion, IDE noise) outweigh its benefits when the language also makes immutability cheap. **Counterexamples welcome.**

**3. Classes inherit statically; only protocols dispatch dynamically.**
No method overriding. A subclass cannot redeclare a same-signature ancestor method — the compiler rejects it. Polymorphism exists exactly once: through protocol-typed receivers via vtable. The rationale: class-hierarchy overriding is where most "which method actually ran?" bugs come from, and protocols are the concept people actually need. **What patterns does this make impossible that you'd miss?**

**4. Errors are values; nothing else exists.**
`Result<T,E>`, `try` propagation, `defer`/`errdefer` (LIFO, error-only variant included). `throw` is reserved for fatal panics and never unwinds. No exceptions, no checked exceptions, no error monads in disguise.

Also in the spec: generics via monomorphization (no constraints — deliberately), structs as pure value types (value fields only, no `deinit`), data enums with singleton items, exhaustive enum switches. The full "explicitly unsupported" table with rationale is in S1 §0.6 — I consider it the most important section of the whole document.

Repo: https://github.com/xnull-clang/xnull

Status honesty: a tree-walking interpreter is merged — `go run ./cmd/xnull run examples/hello.xn` works today, three examples included. The C runtime (ARC/GC adjudication execution, deinit ordering) is next; the conformance ledger publishes every task including the Unimplemented ones. Roast away — the design survives on being wrong in interesting ways or right in defensible ones, and right now I only have my own arguments to test against.
