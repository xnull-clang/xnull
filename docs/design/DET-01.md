# DET-01 — Memory Strategy Decision Table

| Item | Value |
| --- | --- |
| ID | DET-01 |
| Status | Authoritative design entry (normative for strategy selection) |
| Date | 2026-11-21 |
| Scope | Compiler selection of stack / ARC / GC per declared type and instance |
| Supersedes | README prose and `src/runtime/rt_policy.c` comments are non-normative references; this page is the design authority |

> This page exists because “README says DET-01” is not a specification. The
> table below is the checkable rule; implementation and tests must match it.

---

## 1. Decision inputs

The compiler evaluates these inputs after monomorphization and before code
generation:

| Input | Meaning |
| --- | --- |
| declaration kind | `struct`, `class`, `singleton`, `protocol`, simple `enum`, data `enum` |
| field kinds | value-only, concrete references, `Any`/`Object`/protocol/generic/`Result`/tuple-with-reference |
| reference cycle | whether class strong references form a cycle |
| `deinit` | whether the class declares a finalizer |
| self capture | whether a method captures `self` |
| escape | `none` / `argument` / `return` / `field` / `closure` / `unknown` |

Source code MUST NOT express reference strength or memory strategy.

---

## 2. Decision table

Rules are evaluated in order; the first match wins. A result is final for the
given inputs.

| Order | Condition | Strategy | Storage / action |
| ---: | --- | --- | --- |
| 1 | `singleton` | GC root | Heap; permanent root |
| 2 | `protocol` | No instance strategy | Analyzed as GC for conformance |
| 3 | Simple `enum` | Value | Inline integer |
| 4 | Data `enum` | GC | Heap; enum case is a GC root |
| 5 | Class strong-reference field contains `Any`, `Object`, a protocol, an unmonomorphized generic, a tuple containing references, or `Result` | GC | Heap |
| 6 | Class strong references form a cycle | GC | Heap |
| 7 | Class has `deinit`, or a method captures `self` | ARC | Heap; counted |
| 8 | Class has only value fields | Stack candidate | Stack if escape is `none`; otherwise promoted per S3 §6 |
| 9 | Remaining acyclic class references | ARC | Heap; counted |

Conservative rule: if acyclicity or field concreteness cannot be proven, the
result is GC (rule 5/6), never ARC by guess.

Determinism rule: the same source, implementation version, and compilation
options MUST produce the same table result. Rule order MUST NOT depend on hash
iteration order, source file order, or scheduling.

---

## 3. Positive examples

### 3.1 Struct value

```text
struct Point { Int x; Int y }
```

Rule 0 (struct): value/inline. Copies are independent; no ARC/GC count changes.

### 3.2 Simple enum

```text
enum Color { Red, Green, Blue }
```

Rule 3: inline integer. No heap object.

### 3.3 Data enum

```text
enum Shape { Circle(Double radius), Rect(Double width, Double height) }
```

Rule 4: GC. Cases carry payload references and are GC roots.

### 3.4 Stack candidate

```text
class Token { Int kind; Int offset }
static Int use() {
    Token token = new Token(1, 2)
    return token.kind
}
```

Rule 8: only value fields and `escape = none`; stack allocation is legal.
If `token` is returned or stored in a field, escape promotes it to heap; its
strategy becomes ARC (rule 9) unless a later rule matched first.

### 3.5 ARC with finalizer

```text
class Guard {
    deinit { }
}
```

Rule 7: ARC. The finalizer runs when the count reaches zero; timing is
deterministic relative to the last release, but not globally ordered.

### 3.6 GC due to `Any` field

```text
class Box { Any payload }
```

Rule 5: GC. A concrete-only ARC decision would be unsound because `Any` can
hide references.

### 3.7 GC due to cycle

```text
class Node { Node? next }
```

Rule 6: GC when analysis proves a strong-reference cycle. An all-ARC cycle
must be reclassified as GC or rejected; it must not leak silently.

---

## 4. Negative examples

### 4.1 Source annotation

```text
@arc class Cache { }       // compile error
class Cache { weak Node? n } // compile error
```

Source code cannot choose the strategy; DET-01 is compiler-owned.

### 4.2 Relying on reclamation timing

```text
class Temp { deinit { print("freed") } }
```

Printing from `deinit` and expecting a specific wall-clock moment is invalid.
GC reclamation timing is nondeterministic; only the ordering rules in S3 apply.

### 4.3 Inferring strategy from identity

Two references to the same stack object are still identical; stack allocation
does not change identity. Code must not use address-like observations to infer
whether an object is stack/ARC/GC.

### 4.4 Treating `Result` as a value escape hatch

A class field of type `Result<T, E>` triggers rule 5 (GC) conservatively even
when `T`/`E` are concrete; `Result` may hide a reference.

---

## 5. Enforcement

- The runtime decision executor is `rt_decide_policy` in `src/runtime/rt_policy.c`.
- `src/runtime/test_rt.c` covers the table rows exercised by the runtime
  executor.
- The compiler must produce the same determination for the same inputs; a
  mismatch is a compiler bug, not a policy choice.
- `check_layers.py` G1/G2 does not decide strategy; it verifies that the
  capability row exists and its symbols are closed.
- `AUDIT.md` records the review result; this page is the authority for the
  table itself.

---

## 6. Change control

Changing a row, its order, or a conservative fallback requires:

1. a spec change in S3 §4 (or an S6/S3 errata page);
2. an update to this page with positive and negative examples;
3. a runtime/compiler test update;
4. an AUDIT note with reviewer and date.
