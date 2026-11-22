# XNull Solution Part 3: Annotations

| Item | Value |
| --- | --- |
| Document number | Part 3 (S3) |
| Document version | 1.0.0 |
| Specification status | Formal; open decisions are listed in §14 and are not frozen |
| Release date | 2026-11-23 |
| Intended audience | XNull language, compiler, XDK, toolchain, and IDE implementations |
| Related parts | Part 0; Part 1 v3.4.0; Part 2 v3.6.0; Part 4 v3.2.0; Part 5 v1.2.0; Part 6 v1.3.0; Part 7 v3.0.0; Part 8 v2.2.0; Part 9 v2.0.0; Part 10 v5.3.0 |

Versioning rules: revision numbers are used for clarifications that do not change semantics, minor versions for backward-compatible additions, and major versions for breaking changes. Historical versions are in the git history.

Revision note: 1.0.0 (2026-11-23) establishes the independent annotation solution. Part 2 §12 remains the object-model syntax summary; this document is the complete annotation contract.

## Decision Summary

- Annotations are compile-time declarations. They provide static checks, build-time code generation, and read-only metadata; they are not runtime reflection.
- Protocols express behavior. Annotations express declarative metadata, mapping intent, and generation intent. Annotations do not replace protocols or explicit APIs.
- XNull annotation syntax is unchanged from Part 2 §12: `@annotation`, `@Name`, positional arguments, 11 targets, three retention policies. This document defines the complete execution model and the boundary between language, package, toolchain, and runtime.
- The compiler owns annotation parsing, target/retention/repeatable checks, constant evaluation, built-in checks, A8 derived members, and the static registry. Domain packages own their domain annotations and build-time generators.
- Only `Runtime` annotations enter the compiler-generated `AnnotationRegistry`. There is no classpath scanning, reflection, dynamic loading, dynamic proxy, or runtime processor.
- `@Value`, `@Data`, `@Copy`, `@Builder`, and `@Delegate` are implemented in the compiler with explicit limitations (§5.7). Domain annotations remain `planned` until their package processor and generated artifacts exist.
- Derived members, generated types, generated registration tables, and diagnostics are versioned API. Removing an annotation, changing its target/retention, or changing generated behavior is a breaking change.

## 0. Specification Basis

### 0.1 Scope

This Solution specifies:

- the annotation execution model beyond the syntax summary in Part 2 §12;
- the fit between annotations and XNull's object model, protocols, error model, memory model, and limited generics;
- built-in annotations, derived annotations, domain annotations, and processor boundaries;
- the build-time processor lifecycle and runtime `AnnotationRegistry` boundary;
- the mandatory annotation surface for public API documentation;
- compatibility rules, examples, acceptance criteria, and open decisions.

### 0.2 Non-Goals

This Solution does not specify:

- object model and type declaration semantics (Part 2);
- memory strategy, ARC/GC, resource cleanup, or FFI ownership (Part 4);
- `Result`, `try`, `Error`, `ErrorKind`, or boundary conversion (Part 5);
- task, cancellation, or synchronization semantics (Part 6);
- XDK package catalog and API naming (Part 7);
- CLI/build/FFI implementation mechanics (Part 8);
- IDE/editor behavior (Part 9);
- project manifest syntax (Part 10);
- an implementation of the compiler, processors, generators, or tests.

### 0.3 Normative Language

**MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are used with RFC 2119 semantics.

An implementation MUST reject programs that violate a MUST/MUST NOT clause with a stable diagnostic and source location. Extensions MUST be explicitly enabled and MUST NOT change the meaning of standard annotations. The same source, compiler version, processor set, and options MUST produce deterministic diagnostics and generated output.

### 0.4 Terminology

| Term | Meaning |
| --- | --- |
| Annotation declaration | `@annotation Name { ... }`, a compile-time type |
| Annotation use | `@Name`, or `@Name(arg1, arg2, ...)` in a declaration position |
| Built-in annotation | A compiler-recognized annotation such as `@ReadOnly` or `@Override` |
| Derived annotation | An A8 annotation that generates members: `@Value`/`@Data`/`@Copy`/`@Builder`/`@Delegate` |
| Domain annotation | An annotation owned by an XDK package, such as `@HttpRoute` or `@Sql` |
| Processor | A build-time component that validates annotations and/or emits source |
| Generated source | Compiler/processor output carrying a generated marker |
| Registry | The compiler-generated, read-only `AnnotationRegistry` for `Runtime` annotations |
| `implemented` | Code and tests exist for the stated behavior |
| `reserved` | Recognized, but no semantics beyond recognition is promised |
| `planned` | Contract exists, implementation does not |
| `open` | A decision without recorded owner sign-off |

### 0.5 Status Rule

The status of a feature is determined by executable evidence, not by this document's prose. A domain annotation MUST NOT be documented as `implemented` until all four exist:

1. the annotation type is declared in its owning package;
2. the processor/generator is registered in a build manifest;
3. generated source or metadata is produced and tested;
4. a scenario exercises declaration, generation, diagnostics, and runtime behavior.

## 1. Positioning and Boundaries

### 1.1 Compile-Time Metadata and Generation

An annotation is a compile-time declaration. Its values are compile-time constants. The compiler may:

- validate targets, retention, repeatability, arguments, and built-in rules;
- expose immutable annotation elements to build-time processors;
- generate members, types, registration tables, and diagnostics;
- emit a static registry for `Runtime` annotations.

The runtime may query only the generated registry. It MUST NOT discover annotations from class files, source, packages, or module metadata.

### 1.2 Annotation vs Protocol vs Explicit API

| Mechanism | Primary role | Runtime behavior | Replacement rule |
| --- | --- | --- | --- |
| `protocol` | Behavior contract and dynamic dispatch | Yes; protocol dispatch | An annotation MUST NOT replace a protocol |
| Explicit API | Named operations, state, lifecycle, errors | Yes | An annotation MAY remove boilerplate around it, but generated code MUST call the explicit API |
| Annotation | Compile-time metadata, checks, generation intent | No runtime object; optional static registry lookup | An annotation MUST NOT hide a required explicit API |

Examples:

- `@Serializable` may generate a codec, but the codec type and its methods remain explicit public API.
- `@HttpRoute` may generate a route table, but the handler method remains an explicit method with an explicit signature.
- `@Sql` may generate a DAO method body, but the SQL text, parameters, and result type remain visible in source.
- `@Value` may generate `equals`/`toString`/`copy`, but the class, fields, and constructor remain explicit.

### 1.3 Forbidden Behavior

Annotations MUST NOT:

- introduce runtime reflection, classpath scanning, dynamic class loading, or dynamic proxies;
- execute processors at runtime;
- change control flow, object identity, memory strategy, ownership, or error channels;
- silently register services, routes, codecs, or DI graphs outside generated source;
- bypass type checking, `Result`, `@MustUse`, or resource `close()`;
- replace an explicit API that callers need to discover, test, or configure.

`@arc` and `@gc` are not annotations in this system. Using them is a compile error.

### 1.4 Success Criteria

An annotation design is successful only when:

- the generated code is visible, deterministic, and independently testable;
- a reader can tell which explicit API is being generated or called;
- failure is diagnosable at compile time whenever possible;
- the runtime has no hidden discovery path;
- the annotation can be removed with a mechanical migration to explicit code.

## 2. XNull Constraints and Suitability

### 2.1 Constraints That Shape the Design

| Constraint | Consequence for annotations |
| --- | --- |
| No default parameters, named arguments, or variadic parameters | Annotation arguments are positional; optional trailing fields rely on declaration defaults |
| Protocols are the main abstraction | Behavior stays in protocols; annotations only generate/validate implementations |
| No `async` / `await` | Annotations cannot invent asynchronous control flow or scheduling |
| Limited generics, no generic protocols | `@Builder`/`@Delegate` are non-generic in the current implementation; generic expansion is an open item |
| No runtime reflection | No annotation discovery, class loading, dynamic proxy, or runtime DI |
| No source-level memory policy | `@arc`/`@gc` are illegal; annotations cannot choose ARC/GC/stack |
| Explicit error model | Generated fallible APIs MUST return `Result`; no hidden exceptions |
| Explicit resource lifecycle | Annotations may generate wrappers, but `close()` remains explicit and idempotent |
| Nominal types, no structural typing | Generated types are explicit declarations with stable names |
| Static class inheritance, protocol-only dispatch | Annotations cannot create overridable method slots or class-hierarchy polymorphism |

### 2.2 Suitable Problems

| Problem | Why annotations fit | Typical output |
| --- | --- | --- |
| External name mapping | Field/type metadata is static | JSON/CSV/YAML/TOML/XML mapping |
| Repetitive generated members | Rules are uniform and local | `equals`/`toString`/`copy`/`withX` |
| Declarative routing/binding | Paths and parameter roles are static | Route table, binder functions |
| SQL/row mapping | SQL text and column names are static | DAO method body, row mapper |
| FFI layout | Layout rules are compile-time | Layout checks, offsets, alignment diagnostics |
| Test/job discovery | Declaration is static | Generated test manifest or job table |
| Capability manifests | Names and descriptions are static | Tool/resource/prompt tables |
| Validation rules | Constraints are static | Validator functions and error paths |

### 2.3 Unsuitable Problems

| Problem | Why annotations do not fit | Use instead |
| --- | --- | --- |
| Runtime service location | Requires discovery and mutable registries | Explicit constructor/parameter injection |
| Dynamic routing changes at runtime | Route set is not static | Explicit router API |
| Transaction/retry/circuit-breaker behavior | Changes control flow and policy at runtime | Explicit wrappers/combinators |
| Distributed scheduling | Requires persistence and coordination | Explicit scheduler/service |
| Memory strategy selection | Forbidden by language | Compiler/runtime rules in Part 4 |
| Security authorization | Requires runtime policy and context | Explicit authorization API + audit |
| Lazy dependency graphs | Hides construction order and lifecycle | Explicit factories/constructors |

### 2.4 Suitability Decision Table

| Question | If yes | If no |
| --- | --- | --- |
| Is the information known at compile time and constant? | Candidate for annotation | Use explicit runtime API |
| Does it only generate/validate local declarations? | Candidate | Use protocol/service |
| Can generated code be read and tested as ordinary source? | Candidate | Reject the annotation |
| Does it need runtime discovery, reflection, or dynamic loading? | Reject | Candidate |
| Does it change control flow, memory, or error channels? | Do not use an annotation; use explicit API | Candidate |

## 3. Syntax and Semantics

Part 2 §12 is the syntax summary. This section is the complete contract.

### 3.1 Declaration

```x
@annotation Marker {
    final String name = "";
    final Int priority = 0;
}
```

- An annotation declaration is a compile-time type; no runtime annotation object is produced.
- Fields MUST be `final`.
- Field types MUST be compile-time constant types: `Bool`, integer types, `Float`/`Double`, `Char`, `String`, simple enums, constant arrays of those types, nested annotation types, and `Type`/`TypeRef` references.
- A field MAY have a compile-time constant initializer. A field without one is required at every use site.
- Annotations MUST NOT declare methods, constructors, `deinit`, static members, generic parameters, inheritance, or protocol implementations.
- Annotations cannot be `new`-ed or passed as runtime values.

### 3.2 Usage

```x
@Marker
class Device { }

@Marker("device", 2)
class Router { }
```

- Usage forms are `@Name` and `@Name(arg1, arg2, ...)`.
- Arguments are positional and bind in field declaration order.
- Trailing optional fields may be omitted; intermediate fields cannot be skipped.
- Named arguments, variadic arguments, and runtime expressions are not supported.
- Arguments MUST be compile-time constants assignable to the field types.
- Extra arguments, missing required arguments, and type mismatches are compile errors.

### 3.3 Targets

The 11 targets are:

| Target | Applies to |
| --- | --- |
| `Package` | package declaration |
| `Type` | class, struct, enum, singleton, factory, annotation, extension |
| `Annotation` | `@annotation` declaration (meta-annotation) |
| `TypeParameter` | type parameter declaration |
| `Field` | field declaration |
| `Method` | method declaration |
| `Constructor` | constructor declaration |
| `Deinit` | `deinit` declaration |
| `Parameter` | method/constructor parameter |
| `TypeUse` | field type, parameter type, return type, local variable type |
| `EnumItem` | enum item |

An annotation without `@Target` may be used on declaration targets but not on `TypeUse`. `TypeUse` MUST be explicit. Block annotations `@tasks`/`@arena` are owned by Part 6 and are not members of the 11 generic declaration targets.

### 3.4 TypeUse

Type-use annotations use prefix form:

```x
@NonEmpty List<String> names;
```

They are recorded as `AnnotationTarget.TypeUse`, not as declaration annotations. The target name is derived from the enclosing declaration:

- field: `<owner>#<field>`;
- parameter: `<owner>#<method>(<paramTypes>)#<index>`;
- return: `<owner>#<method>(<paramTypes>)#return`;
- local: `<owner>#<method>(<paramTypes>)#local:<name>`.

Type-use annotations MUST NOT be used on generic type arguments, expressions, control bodies, or type parameter declarations.

### 3.5 Disambiguation

At a declaration prefix, an annotation binds according to its declared targets:

- only `TypeUse`: binds to the following type use;
- only declaration targets: binds to the declaration;
- both `TypeUse` and declaration targets: compile error; split or narrow the annotation.

A declaration-only annotation is never reinterpreted as a type-use annotation.

### 3.6 Retention

| Retention | Compiler | Build output | Runtime |
| --- | --- | --- | --- |
| `Source` | Visible to processors | Not retained | Not queryable |
| `Binary` | Visible to processors | Tool/IDE metadata | Not queryable |
| `Runtime` | Visible to processors | Compiler-generated static registry | Queryable through `AnnotationRegistry` |

Default retention is `Binary`.

`Runtime` is not reflection. The compiler emits a static table; the runtime does not read class files, source, packages, or module metadata.

### 3.7 Repeatable

- `@Repeatable` allows multiple uses on the same target.
- Uses preserve source order.
- The compiler records a one-based `repeatIndex` per annotation type/target.
- Repeating a non-repeatable annotation is a compile error.
- `@Repeatable` on a non-annotation declaration or with arguments is a compile error.

### 3.8 Diagnostics

Annotation syntax/semantic errors use stable codes:

| Code | Meaning | Status |
| --- | --- | --- |
| `AN0001` | Unknown annotation | implemented |
| `AN0002` | Annotation not allowed on this target | implemented |
| `AN0003` | Duplicate annotation without `@Repeatable` | implemented |
| `AN0004` | Missing required argument | implemented |
| `AN0005` | Too many arguments | implemented |
| `AN0006` | Argument type mismatch | implemented |
| `AN0007` | Argument is not a compile-time constant | implemented |
| `AN0008` | Invalid annotation field/default | implemented |
| `AN0009` | Invalid `@Target` | implemented |
| `AN0010` | Invalid `@Retention` | implemented |
| `AN0011` | Invalid `@Repeatable` | implemented |
| `AN0012` | `@ReadOnly` write violation | implemented |
| `AN0013` | `@Override` signature mismatch | implemented |
| `AN0014` | Use of deprecated declaration | implemented (warning) |
| `AN0015` | Invalid/unsupported `@SuppressWarnings` code | implemented (warning) |
| `AN0016` | Processor not enabled/unknown | planned |
| `AN0017` | Processor phase/round violation | planned |
| `AN0018` | Generated declaration conflict | planned |
| `AN0019` | Registry version mismatch | planned |
| `AN0020` | Annotation used on unsupported declaration/expression/block | implemented |
| `AN0021` | A8 requires a class; `@Value` requires final fields | implemented |
| `AN0022` | Constructor parameters do not match fields | implemented |
| `AN0023` | Generated method conflicts with existing method | implemented |
| `AN0024` | Generated builder class already exists | implemented |
| `AN0025` | Generic `@Builder` is not supported | implemented |
| `AN0026` | `@Delegate` method conflict | implemented |
| `AN0027` | `@Delegate` target is not a class | implemented |
| `AN0028` | `@Delegate` target is generic | implemented |

Domain processors use reserved ranges:

- `AN0100`–`AN0199`: processor manifest, scheduling, generation, and registry plumbing;
- `AN1000`–`AN1999`: domain-specific diagnostics, allocated per package and recorded in the package annotation contract.

A domain diagnostic code is not stable until it appears in the package's annotation table and generated-source tests.

### 3.9 Restrictions

Annotations MUST NOT be used:

- on expressions;
- in control bodies;
- on generic type arguments;
- on type parameter declarations (`TypeUse` is a type-use position, not a type-parameter declaration);
- as runtime values;
- to change memory strategy or object model rules.

## 4. Built-in Annotations

### 4.1 Complete Table

| Annotation | Purpose | Target | Retention | Enforcement | Diagnostics | Example | Counterexample | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `@Target` | Restrict annotation targets | Annotation | Binary | Yes | `AN0009` | `@Target(Field)` | `@Target(Expr)` | implemented |
| `@Retention` | Select retention | Annotation | Binary | Yes | `AN0010` | `@Retention(Runtime)` | `@Retention(Class)` | implemented |
| `@Repeatable` | Allow repeated use and preserve order | Annotation | Binary | Yes | `AN0011` | repeated `@Tag` | repeating non-repeatable | implemented |
| `@ReadOnly` | Field is externally read-only | Field | Binary | Yes | `AN0012` | `@ReadOnly Int count` | external write | implemented |
| `@WriteOnly` | Mark write-only field | Field | Binary | Recognition only | — | `@WriteOnly String secret` | treating it as a security boundary | implemented (recognition) |
| `@Override` | Require a matching protocol method | Method | Binary | Yes | `AN0013` | `@Override String describe()` | marking a superclass method | implemented |
| `@Deprecated` | Warn on use | Declaration | Binary | Yes (warning) | `AN0014` | `@Deprecated void old()` | comment-only deprecation | implemented |
| `@SuppressWarnings` | Suppress named diagnostics | Declaration | Source | Yes | `AN0015` | `@SuppressWarnings("AN0014")` | suppressing unknown/unsupported code | implemented |
| `@MustUse` | Result must be used | Type/Method | Binary | Language rule | — | `@MustUse Result` | treating it as a user annotation | implemented (rule) |
| `@Immediate` | Reserved execution hint | Declaration | Binary | No | `AN0020` for illegal combinations | — | relying on scheduling semantics | reserved |
| `@NoAlloc` | Reserved allocation hint | Declaration | Binary | No | `AN0020` | — | claiming allocation guarantee | reserved |
| `@Pure` | Reserved purity hint | Method | Binary | No | `AN0020` | — | optimizing based on it | reserved |
| `@Sendable` | Reserved cross-task hint | Type/Method | Binary | No | `AN0020` | — | treating it as a safety proof | reserved |
| `@tasks` | Structured task scope | Block (Part 6; outside the 11 generic targets) | Source | Part 6 semantics | Part 6 diagnostics | `@tasks { ... }` | using it as a normal declaration annotation | planned (Part 6) |
| `@arena` | Region allocation scope | Block (Part 6; outside the 11 generic targets) | Source | Part 6 semantics | Part 6 diagnostics | `@arena { ... }` | using it on a declaration | planned (Part 6) |

### 4.2 Notes

- `@WriteOnly` is recognized but not enforced. It MUST NOT be described as a security boundary.
- `@MustUse` is a language rule, not an `@annotation` declaration. It cannot be used as a general-purpose user annotation.
- Reserved annotations MUST NOT change semantics before their contracts and checks are frozen.
- `@tasks`/`@arena` are block annotations owned by Part 6; their syntax and semantics are not redefined here.

## 5. Derived Annotations (A8)

A8 derived annotations are implemented by the compiler. They generate explicit members; they do not generate runtime reflection or hidden behavior.

### 5.1 Common Rules

- Target is a `class` only. `struct`, `enum`, `protocol`, and `annotation` are rejected with `AN0021`.
- The class constructor parameters MUST match instance fields in order and type (`AN0022`).
- Generated members MUST NOT conflict with existing members (`AN0023`).
- Generated declarations carry a generated marker and are deterministic.
- Failure is atomic: no partial generated member set is retained.
- Generated code is ordinary XNull source; it can be read, tested, and audited.

### 5.2 `@Value`

| Item | Contract |
| --- | --- |
| Preconditions | `class`; all instance fields `final`; constructor matches fields |
| Generates | `equals(other)`, `toString()`, `copy()` |
| Does not generate | `hash()`, accessors, setters, deep copy, runtime reflection |
| Diagnostics | `AN0021` non-class/non-final; `AN0022` constructor mismatch; `AN0023` method conflict |
| Status | implemented; shallow validation (final-field check only) |

`@Value` validation is intentionally shallow in the current implementation. It does not prove that every reference field is value-comparable. Generated equality compares fields with the language's field equality rules; a type that needs a deeper comparison MUST implement it explicitly or wait for the open decision in §14.

### 5.3 `@Data`

| Item | Contract |
| --- | --- |
| Preconditions | `class`; constructor matches fields |
| Generates | `equals(other)`, `toString()`, `copy()` |
| Does not generate | `hash()`, accessors, setters, deep copy |
| Diagnostics | `AN0021` non-class; `AN0022` constructor mismatch; `AN0023` method conflict |
| Status | implemented; `hash()` is not generated |

### 5.4 `@Copy`

| Item | Contract |
| --- | --- |
| Preconditions | `class`; constructor matches fields |
| Generates | `copy()` and one `with<Field>(value)` per instance field |
| Diagnostics | `AN0022`; `AN0023` conflict with existing method |
| Status | implemented |

### 5.5 `@Builder`

| Item | Contract |
| --- | --- |
| Preconditions | non-generic `class`; constructor matches fields |
| Generates | `<Type>Builder` with `with<Field>(value)`, `build()`; missing required fields panic at `build()` |
| Diagnostics | `AN0022`; `AN0024` builder class exists; `AN0025` generic class |
| Status | implemented; non-generic only |

### 5.6 `@Delegate`

| Item | Contract |
| --- | --- |
| Preconditions | `class`; one or more fields annotated `@Delegate`; target is a non-generic class |
| Generates | forwarding instance methods for the target's instance methods |
| Does not generate | static forwarding, protocol inference, dynamic proxy |
| Diagnostics | `AN0026` method conflict; `AN0027` target not a class; `AN0028` generic target |
| Status | implemented; non-generic only |

### 5.7 Implementation Range and Limits

| Feature | Implemented | Limit |
| --- | --- | --- |
| `@Value` | yes | class only; final fields; shallow validation; no `hash()` |
| `@Data` | yes | class only; no `hash()`; no accessors |
| `@Copy` | yes | class only; constructor must match fields |
| `@Builder` | yes | non-generic class only |
| `@Delegate` | yes | non-generic target class only |
| Generated code marker | yes | generated members carry an A8 marker |
| Atomic failure | yes | diagnostics prevent partial expansion |
| Generic expansion | no | open decision |

These limits are API-visible. A future implementation MUST NOT silently change generated names, member sets, or diagnostics.

### 5.8 Examples

```x
@Value
class Point {
    final Int x
    final Int y

    Point(Int x, Int y) {
        self.x = x
        self.y = y
    }
}
```

Generated API (conceptual, deterministic):

```x
Bool equals(Point other)
String toString()
Point copy()
```

```x
@Builder
class ServerOptions {
    final String host
    final Int port

    ServerOptions(String host, Int port) {
        self.host = host
        self.port = port
    }
}
```

Generated: `ServerOptionsBuilder.withHost(String)`, `withPort(Int)`, `build()`. Missing fields cause `build()` to panic with a stable message.

## 6. Domain Annotations and Processor Model

### 6.1 Ownership and File Layout

- Domain annotations belong to the package that owns the capability, not to `xdk.annotations`.
- Each annotation is a PascalCase type in its own file, e.g. `HttpRoute.x`.
- The processor is a build-time type, not a runtime package type.
- Generated source goes to `<package>/generated/<Name>Generated.x` and carries a generated marker.
- The build manifest explicitly lists enabled processors. Dependencies do not auto-enable processors.

### 6.2 Categories

| Category | Examples | Why |
| --- | --- | --- |
| Must generate code | `@Serializable`/`@JsonName`, `@HttpRoute`/`@Header`/`@Query`, `@Sql`/`@Param`/`@Row`, `@Packed`/`@Align`, `@CliCommand`/`@Option`/`@Arg`, `@TestCase`/`@Scheduled` | The mapping or registration is static and mechanical |
| Compile-time validation | `@Validate`/`@Min`/`@Max`/`@Pattern`/`@Email` | Rules can be checked before runtime |
| Prefer explicit API | `@Retryable`, `@Cacheable`, `@CacheEvict`, `@Metered`, `@Traced`, `@Audited` | They change control flow/wrapping; explicit wrappers are easier to test and reason about |
| Deferred | annotations depending on unimplemented packages or runtime facilities | No processor, generated artifact, or scenario yet |

The full 93-entry catalog and 75-package adoption matrix are maintained in:

- [`design/ANNOTATION-CATALOG.md`](design/ANNOTATION-CATALOG.md)
- [`design/ANNOTATION-ADOPTION.md`](design/ANNOTATION-ADOPTION.md)

This Solution defines the model; the catalog defines each annotation's exact fields and status; the adoption matrix defines each package's intended use.

### 6.3 75-Package Analysis

The 75 packages/package groups split into four adoption classes:

| Class | Packages (examples) | Annotation use | Status |
| --- | --- | --- | --- |
| Language/compiler | `xdk.annotations` | meta-model, registry, processor contract | 14 types implemented |
| Core value/API | `xdk.errors`, `xdk.runtime`, `xdk.meta`, `xdk.bytes`, `xdk.text`, `xdk.collections`, `xdk.math`, `xdk.time`, `xdk.io`, `xdk.fs`, `xdk.sys`, `xdk.log`, `xdk.config`, `xdk.cli`, `xdk.execution` | A8 derived members, `@Override`, `@Deprecated`, `@Deprecated` migration | A8/compiler implemented; domain annotations planned |
| Domain codegen | `xdk.net.http`, `xdk.net.websocket`, `xdk.jwt`, `xdk.sql`, `xdk.codec`, `xdk.yaml`, `xdk.toml`, `xdk.xml`, `xdk.validate`, `xdk.cli`, `xdk.device`, `xdk.serial`, `xdk.gpu`, `xdk.tensor`, `xdk.linalg`, `xdk.db`, `xdk.api`, `xdk.mcp`, `xdk.ml`, `xdk.agent` | package-owned annotations + build-time generators | planned |
| Explicit-API-first | `xdk.cache`, `xdk.resilience`, `xdk.metrics`, `xdk.trace`, `xdk.audit`, `xdk.schedule`, `xdk.test` | annotations only where generation/validation is clearly local; otherwise explicit API | mixed planned |

The complete 75-row matrix is Appendix B. A package MUST NOT claim a domain annotation is implemented merely because it appears in Appendix B; the package must satisfy §0.5.

### 6.4 Processor Architecture Options

| Option | Description | Advantages | Disadvantages |
| --- | --- | --- | --- |
| A. Compiler-only | Every annotation is handled inside the compiler | Simple, deterministic, one pipeline | Compiler release for every domain change; poor package ownership; compiler bloat |
| B. Full processor scheduler | General `AnnotationProcessor` plugin scheduler with discovery and dependency graph | Extensible; uniform contract; ecosystem processors | Complex; plugin discovery/security; risk of “runtime-like” magic; overkill before domain packages exist |
| C. Hybrid (recommended) | Language/A8 built into compiler; domain packages use build-time generators listed explicitly in the manifest, sharing the `AnnotationProcessor` contract and phases | Keeps compiler core small; package ownership; no runtime discovery; deterministic manifest | Requires a manifest schema and generator sandbox; processor dependencies are build-time only |

Recommendation: **Option C**. The compiler remains the only authority for annotation syntax, targets, retention, built-ins, A8, and the registry. Domain packages provide build-time generators that are explicitly enabled and sandboxed. A general plugin discovery mechanism is not required for the first implementation.

This recommendation is `OPEN` until the owner signs it (§14, OPEN-1). Option B remains a valid future extension if ecosystem processors require a stable scheduler.

### 6.5 Processor Phases

```text
Resolve → Validate → Generate (fixed point) → Finalize
```

- **Resolve**: read declarations and annotation sets; resolve types and symbols.
- **Validate**: check targets, constants, semantic constraints, conflicts, and generated-name availability.
- **Generate**: produce source/declarations; generated declarations enter the next round.
- **Finalize**: emit final metadata/diagnostics; MUST NOT generate new declarations.

A processor declares supported phases. The scheduler calls only declared phases, in order. `Generate` may run multiple rounds until no new declarations are produced.

### 6.6 Manifest, Sandbox, Determinism, Atomicity

| Rule | Requirement |
| --- | --- |
| Manifest | Explicit processor list, options, and output root; no implicit dependency activation |
| Sandbox | Read-only input AST/element view; no network, arbitrary file writes, processes, reflection, or runtime loading |
| Determinism | Same input + processor set + options + compiler version = byte-identical output and stable diagnostic order |
| Atomicity | Any error rolls back the whole processor batch; no half-generated files or half-modified AST |
| Cache | Input hash + processor identity/version + options participate in the incremental cache |
| Output | Generated source only under the declared output root, with `generated` marker |
| Diagnostics | Stable codes; source locations where applicable; no absolute paths/timestamps/random values |
| Security | Generated code is ordinary source and is reviewed/tested like handwritten code |

### 6.7 Runtime Registry

- Only `Runtime` annotations enter the registry.
- Registry format is versioned; the current compiler uses version 1.
- The registry is immutable after construction and safe for concurrent reads.
- Queries return empty sets for missing targets, not `null`.
- Runtime query APIs are in `xdk.annotations`; no other package may implement a competing registry.
- `Source` and `Binary` annotations are not queryable at runtime.
- Registry entries preserve repeat order and one-based `repeatIndex`.

### 6.8 Status

Domain processors are `planned`. The compiler currently implements annotation parsing, built-ins, A8, and the static registry. A package annotation is not `implemented` until its processor, generated artifact, diagnostics, and scenario exist.

## 7. Relationship with Other Parts

| Part | Owns | S3 relationship |
| --- | --- | --- |
| Part 0 | Capability map, application boundaries | S3 adds the annotation capability row; does not change application boundaries |
| Part 1 | Lexical structure, types, expressions, statements, generics, error core | S3 uses its syntax and type rules; does not redefine them |
| Part 2 | Object model, declarations, protocols, structs, enums, visibility, annotation syntax summary | S3 owns the complete annotation execution model; Part 2 §12 is a summary and points here |
| Part 4 | Memory strategies, ARC/GC, lifecycle, FFI ownership | S3 cannot change memory strategy; `@arc`/`@gc` are illegal |
| Part 5 | `Result`, `try`, `Error`, `ErrorKind`, error observation | Generated fallible APIs use `Result`; S3 does not redefine errors |
| Part 6 | Tasks, cancellation, timeouts, synchronization | `@tasks`/`@arena` block semantics belong to Part 6; S3 only defines annotation syntax boundary |
| Part 7 | XDK package catalog, package ownership, API naming | Domain annotations are owned by XDK packages; S3 defines the model, not package APIs |
| Part 8 | Toolchain, build, CLI, FFI contracts | Processors are build-time toolchain inputs; S3 defines their contract, Part 8 implements the build |
| Part 9 | IDE/editor contract | IDE reads annotation metadata and generated-source navigation; S3 defines what is exposed |
| Part 10 | Project manifest, dependencies, repositories, resources | Processor enablement/options are manifest inputs; S3 does not define manifest syntax |

Rules:

- S3 MUST NOT redefine object model, memory, error, task, XDK, toolchain, IDE, or manifest semantics.
- When a domain annotation generates an API, the API's names/lifecycle/errors follow the owning Part and S7 XDK package contract.
- When an annotation interacts with a block/scope (`@tasks`/`@arena`), Part 6 owns the semantics; S3 owns only the annotation syntax target and retention boundary.

## 8. API Documentation Annotation Surface

### 8.1 Annotation Is API Contract

For a public type or member, its annotation surface is part of the API contract. The following are breaking changes:

- removing an annotation that generated a public member;
- changing `@Target`/`@Retention`;
- changing a field default that changes generated behavior;
- changing generated names, signatures, or diagnostic codes;
- changing a processor from explicit to implicit, or vice versa.

### 8.2 Mandatory Fields

Every public API document MUST include:

| Field | Requirement |
| --- | --- |
| Type/member | Canonical name and signature |
| Available annotations | Annotation names, including “none” |
| Target/retention | Exact `@Target` and `@Retention` |
| Owner/processor | Owning package and processor name |
| Generated artifacts | Members, types, files, output path |
| Diagnostics | Stable codes and severity |
| Status | `implemented`, `reserved`, `planned`, or `open` |
| Counterexample | At least one forbidden use or failure mode |

### 8.3 Template

```markdown
### Annotation Surface

| Item | Value |
| --- | --- |
| Type/member | `Type.member(...)` |
| Available annotations | `@Foo`, `@Bar` |
| Target / retention | `Field` / `Source` |
| Owner / processor | `xdk.example` / `ExampleAnnotationProcessor` |
| Generated artifacts | `generated/TypeFoo.x`: `foo()`; members `a`, `b` |
| Diagnostics | `AN1001` missing field; `AN1002` duplicate name |
| Status | `planned`; processor not implemented |
| Counterexample | `@Foo` on a method |
```

### 8.4 Status Vocabulary

| Status | Meaning in API docs |
| --- | --- |
| `implemented` | Annotation and processor/generation have tests |
| `reserved` | Recognized; no generated API and no runtime semantics |
| `planned` | Contract is written; processor/generation is absent |
| `open` | Decision or owner sign-off is missing |

A document MUST NOT use “supported” without one of these statuses.

### 8.5 Examples

Implemented (A8):

```markdown
| Available annotations | `@Value` |
| Target / retention | `Type` / `Source` |
| Owner / processor | compiler A8 |
| Generated artifacts | `equals`, `toString`, `copy` |
| Diagnostics | `AN0021`, `AN0022`, `AN0023` |
| Status | implemented; no `hash()` |
```

Planned (HTTP):

```markdown
| Available annotations | `@HttpRoute`, `@Header`, `@Query`, `@Body`, `@StatusCode` |
| Target / retention | `Method`/`Parameter` / `Source` |
| Owner / processor | `xdk.net.http` / `HttpAnnotationProcessor` |
| Generated artifacts | `generated/routes.x`: route table and binder functions |
| Diagnostics | `AN1101` empty path; `AN1102` duplicate route; `AN1103` unsupported binding |
| Status | planned; processor not implemented |
```

### 8.6 Review Rules

- A public API document without an annotation surface is incomplete.
- “None” is a valid annotation surface, but it must be explicit.
- Planned annotations MUST NOT be described with present-tense behavior.
- Generated artifacts MUST have a stable path/name or a documented naming rule.
- Diagnostics MUST be stable codes, not free-form messages only.

## 9. Compatibility and Versioning

### 9.1 Annotation API

The following are API:

- annotation type name and package;
- `@Target` set;
- `@Retention`;
- field names, types, order, and defaults;
- processor name, phases, generated names, and generated member sets;
- diagnostic codes and severity;
- registry format and query semantics.

### 9.2 Compatible Changes

- adding a new annotation;
- adding a new optional trailing field with a default;
- adding a new target (unless it creates ambiguity with `TypeUse`);
- adding a new diagnostic code;
- adding generated members that do not conflict with existing names;
- adding a new processor behind explicit manifest enablement.

### 9.3 Breaking Changes

- removing/renaming an annotation;
- removing/tightening targets or retention;
- removing/reordering fields or changing defaults;
- changing generated names/signatures/visibility;
- changing diagnostic codes or severity;
- changing processor activation from explicit to implicit;
- making `Runtime` metadata depend on reflection or class loading.

### 9.4 Deprecation

- `@Deprecated` MUST be used for public annotation/API migration.
- A deprecated annotation remains recognized for at least one minor version.
- A deprecated annotation that no longer generates code MUST still parse and produce a deprecation warning.
- Removal requires a major version and a migration table.

### 9.5 Registry Versioning

- The registry format carries a version; current version is 1.
- The runtime MUST reject mismatched versions rather than silently misread metadata.
- Registry ordering is stable: target key, annotation type name, repeat index.
- Registry entries from `Source`/`Binary` retention MUST NOT appear.

### 9.6 No Implicit Semantic Change

An annotation MUST NOT change the meaning of an existing declaration unless the annotation is present. Adding an annotation to a type must not change unrelated types, call sites, or runtime behavior beyond the documented generated contract.

## 10. Examples and Counterexamples

Each example shows declaration → generated/explicit API → runtime behavior. No example uses reflection, scanning, or runtime processors.

### 10.1 CLI

```x
@CliCommand("deploy", "Deploy an artifact")
class DeployCommand {
    @Option("--env", "-e") String env = "dev"
    @Arg("artifact") String artifact
}
```

Generated: a command tree node and parser binder. Runtime: parser reads `argv` and writes fields; no global command registry. Counterexample: a global parser discovered by scanning packages.

### 10.2 Serialization

```x
@Serializable
class UserDto {
    @JsonName("user_id") final Long id
    @JsonName("display_name") final String name
}
```

Generated: `UserDtoJsonCodec` with `encode`/`decode`. Runtime: caller invokes the explicit codec; no reflection over fields. Counterexample: runtime field scanning or dynamic class loading.

### 10.3 Validation

```x
@Validate
class SignupForm {
    @Email String email
    @Min(18) @Max(120) Int age
    @Pattern("^[a-z0-9_]+$") String handle
}
```

Generated: `SignupFormValidator.validate(value)` returning `Result<Unit, ErrorGroup>`. Runtime: explicit validator call; error paths are stable. Counterexample: validation hidden inside a serializer or DI container.

### 10.4 HTTP Routing

```x
class UserApi {
    @HttpRoute("/users/{id}", HttpMethod.Get)
    @StatusCode
    HttpResponse getUser(@Query("id") Long id, @Header("Accept") String accept) {
        // explicit handler body
    }
}
```

Generated: a route table and parameter binder; the handler body stays explicit. Runtime: server dispatches to the generated binder then calls the method. Counterexample: scanning handler classes at startup.

### 10.5 SQL Row Mapping

```x
@Row
class UserRow {
    @Column("user_id") final Long id
    @Column("display_name") final String name
}

class UserDao {
    @Sql("SELECT user_id, display_name FROM users WHERE user_id = :id")
    Result<UserRow, Error> find(@Param("id") Long id) {
        // explicit fallback or generated body
    }
}
```

Generated: a row mapper and parameter binder. Runtime: driver returns `SqlResult`; the mapper constructs `UserRow`; no reflection. Counterexample: runtime ORM scanning of field names.

### 10.6 FFI Layout

```x
@Packed
@Align(8)
@NativeLayout
class CHeader {
    @Align(4) Int code
    Long payload
}
```

Generated: layout checks, offsets, and alignment diagnostics. Runtime: the same layout is used by the FFI binding; no dynamic layout probing. Counterexample: guessing C layout at runtime.

### 10.7 Tests and Scheduling

```x
class UserTests {
    @Before void setUp() { }
    @TestCase("find missing") void findMissing() { }
    @After void tearDown() { }
}

class Jobs {
    @Scheduled("0 */5 * * * *") void refreshCache() { }
}
```

Generated: test manifest and job table. Runtime: test runner/scheduler queries the generated table; no naming-convention scan. Counterexample: discovering tests by method-name prefixes.

### 10.8 Counterexamples

| Counterexample | Why it is invalid |
| --- | --- |
| Runtime annotation scanning | Forbidden; no reflection/classpath scanning |
| Annotation-only DI container | Hides construction/lifecycle; not XNull |
| `@Retry` changing control flow invisibly | Use an explicit retry wrapper/combinator |
| `@Packed` on a class with reference fields | Layout is not representable; reject |
| `@Value` on a `struct` | A8 requires a class; struct already has value semantics |
| `@Builder` on a generic class | Currently unsupported (`AN0025`) |
| `@Delegate` to a generic class | Currently unsupported (`AN0028`) |
| `@TestCase` used to discover tests by reflection | Generated manifest is the only discovery path |

## 11. Acceptance Criteria

A conforming implementation MUST satisfy:

1. Annotation syntax, 11 targets, three retentions, repeatable order, and diagnostics match §3.
2. Built-in annotations match §4, including enforcement status.
3. A8 generated members and diagnostics match §5 and §14 status.
4. Domain annotations have an owner, target, retention, processor, generated artifact, diagnostics, and status; planned annotations are not described as implemented.
5. Processor phases, manifest enablement, sandbox, determinism, atomicity, and output layout match §6.
6. Runtime metadata is read only through the generated registry; no reflection/scanning/dynamic loading.
7. Public API docs contain the annotation surface template in §8.
8. Compatibility rules in §9 are enforced.
9. Examples in §10 can be validated by a future compiler/processor implementation without changing their meaning.
10. Documentation links, part numbers, and file names match the 11-part structure (Part 0 + Parts 1–10).

## 12. Migration from Part 2 §12 and the Annotation Design Docs

- Part 2 §12 remains the object-model syntax summary. It points here for the complete model.
- `ANNOTATION-SYSTEM.md` is the design/implementation overview; it must defer to this Solution for normative annotation semantics.
- `ANNOTATION-CATALOG.md` is the per-annotation catalog; it must defer to this Solution for the model and status vocabulary.
- `ANNOTATION-ADOPTION.md` is the 75-package adoption matrix; it must defer to this Solution for processor architecture and status rules.
- `ANNOTATION-PLAN.md` is the implementation plan; it may describe work items but must not redefine annotation semantics.
- On conflict, this Solution wins for annotation semantics; Part 2 wins for object-model syntax; Part 8 wins for build/toolchain mechanics.

## 13. Security and Safety

- Annotation arguments are compile-time constants; no runtime expression evaluation.
- Processors are sandboxed build-time code; no network, arbitrary file writes, process execution, reflection, or class loading.
- Generated source is untrusted until reviewed/tested; it carries a generated marker and a deterministic origin.
- `@WriteOnly` is not a security boundary. `@ReadOnly` is a compile-time write check, not a runtime access-control mechanism.
- `@Deprecated` is a warning, not a removal mechanism.
- Runtime registry data is metadata, not authority; authorization and secrets must not depend on annotations.
- Diagnostic messages MUST NOT include secrets, absolute paths, timestamps, or random values.

## 14. Open Decisions

The following decisions are explicitly `OPEN`; they are not frozen by this document.

| ID | Decision | Current state | Recommended | Owner sign-off |
| --- | --- | --- | --- | --- |
| OPEN-1 | Processor architecture A/B/C | §6.4 analysis | C: compiler A8 + package build-time generators | pending |
| OPEN-2 | Domain diagnostic allocation | Ranges proposed in §3.8 | Allocate per package in `AN1000–AN1999` and record in catalog | pending |
| OPEN-3 | `@Value`/`@Data` `hash()` generation | Not generated | Keep un generated until a hash contract exists | pending |
| OPEN-4 | Generic `@Builder` | `AN0025` | Support only non-generic classes in 1.x; revisit with generic expansion | pending |
| OPEN-5 | Generic `@Delegate` | `AN0028` | Support only non-generic target classes in 1.x | pending |
| OPEN-6 | `@Value` deep field validation | Shallow final-field check | Add value-comparability checks after a field-comparison contract exists | pending |
| OPEN-7 | Runtime retention for CLI/MCP/device manifests | Mixed Runtime/Source | Prefer generated static manifests; use Runtime only for runtime discovery APIs | pending |
| OPEN-8 | Domain annotation API stability before implementation | Planned | Freeze each annotation when its package implementation starts | pending |

An `OPEN` item MUST NOT be described as implemented, frozen, or guaranteed in package docs.

## Appendix A: Core Diagnostic Codes

| Range | Owner | Meaning |
| --- | --- | --- |
| `AN0001`–`AN0028` | Compiler/annotation front end | Syntax, target, retention, built-ins, A8 |
| `AN0100`–`AN0199` | Toolchain/processor scheduler | Manifest, phases, generation, registry plumbing |
| `AN1000`–`AN1999` | Domain packages | Package-specific annotation diagnostics |

## Appendix B: 75-Package Adoption Matrix

The matrix is maintained in [`design/ANNOTATION-ADOPTION.md`](design/ANNOTATION-ADOPTION.md). It has 75 rows: 1 annotations package + 15 core + 9 network + 17 platform + 24 utils + 9 solutions. Each row records declared annotations, consumed annotations, processor, generated artifacts, concrete type/member points, and status.

The following table is the full 75-row package matrix. The authoritative per-package details are in the adoption document.

| Class | Packages | Status |
| --- | --- | --- |
| annotations | `xdk.annotations` | 14 types implemented; registry implemented |
| core value/API | 15 packages | A8/compiler implemented; domain annotations planned |
| network/data | 9 packages | domain annotations planned |
| platform/compute | 17 packages | domain annotations planned |
| utils | 24 packages | A8/compiler implemented; domain annotations planned |
| solutions | 9 packages | domain annotations planned |

| # | Package | Declared domain annotations | Processor / generation | Status |
| ---: | --- | --- | --- | --- |
| 1 | `xdk.annotations` | 无领域注解 | 无（处理器合同由构建期实现） | implemented (14 types + registry) |
| 2 | `xdk.errors` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 3 | `xdk.runtime` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 4 | `xdk.meta` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 5 | `xdk.bytes` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 6 | `xdk.text` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 7 | `xdk.collections` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 8 | `xdk.math` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 9 | `xdk.time` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 10 | `xdk.io` | 无领域注解 | 编译器内建 | A8/compiler; partial adoption |
| 11 | `xdk.fs` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 12 | `xdk.sys` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 13 | `xdk.log` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 14 | `xdk.config` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 15 | `xdk.cli` | `@CliCommand`、`@CliSubcommand`、`@Option`、`@Arg` | CliAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 16 | `xdk.execution` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 17 | `xdk.net` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 18 | `xdk.net.uri` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 19 | `xdk.net.mime` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 20 | `xdk.net.tls` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 21 | `xdk.net.http` | `@HttpRoute`、`@Header`、`@Query`、`@Body`、`@StatusCode` | HttpAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 22 | `xdk.net.websocket` | `@WsHandler` | WebSocketAnnotationProcessor（Validate/Generate） | planned |
| 23 | `xdk.jwt` | `@JwtClaim`、`@JwtHeaderField` | JwtAnnotationProcessor（Validate/Generate） | planned |
| 24 | `xdk.sql` | `@Sql`、`@Param`、`@Row`、`@Column` | SqlAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 25 | `xdk.net.service` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 26 | `xdk.os` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 27 | `xdk.os.host` | 无领域注解 | 编译器内建 | A8/compiler; partial adoption |
| 28 | `xdk.os.cpu` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 29 | `xdk.os.memory` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 30 | `xdk.os.hardware` | `@Packed`、`@Align`、`@NativeLayout` | HardwareLayoutProcessor（Validate/Generate） | planned |
| 31 | `xdk.os.storage` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 32 | `xdk.os.gpu` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 33 | `xdk.os.firewall` | 无领域注解 | 标准 A8 / 审计处理器 | A8/compiler; partial adoption |
| 34 | `xdk.os.container` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 35 | `xdk.os.virt` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 36 | `xdk.os.service` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 37 | `xdk.gpu` | `@GpuKernel` | GpuAnnotationProcessor（Validate/Generate） | planned |
| 38 | `xdk.tensor` | `@TensorOp`、`@TensorSpec` | TensorAnnotationProcessor（Validate/Generate） | planned |
| 39 | `xdk.linalg` | `@LinalgOp` | LinalgAnnotationProcessor（Validate/Generate） | planned |
| 40 | `xdk.geo` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 41 | `xdk.serial` | `@SerialBinding` | SerialAnnotationProcessor（Validate/Generate） | planned |
| 42 | `xdk.device` | `@Device`、`@Gpio`、`@I2cAddress` | DeviceAnnotationProcessor（Validate/Generate） | planned |
| 43 | `xdk.codec` | `@Serializable`、`@JsonName`、`@CsvName` | CodecAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 44 | `xdk.crypto` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 45 | `xdk.compress` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 46 | `xdk.random` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 47 | `xdk.uuid` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 48 | `xdk.stats` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 49 | `xdk.functional` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 50 | `xdk.graph` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 51 | `xdk.reflect` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 52 | `xdk.toml` | `@TomlName` | TomlAnnotationProcessor（Validate/Generate） | planned |
| 53 | `xdk.yaml` | `@YamlName` | YamlAnnotationProcessor（Validate/Generate） | planned |
| 54 | `xdk.xml` | `@XmlName` | XmlAnnotationProcessor（Validate/Generate） | planned |
| 55 | `xdk.validate` | `@Validate`、`@Min`、`@Max`、`@Pattern`、`@Email` | ValidateAnnotationProcessor（Validate/Generate） | planned |
| 56 | `xdk.cache` | `@Cacheable`、`@CacheEvict` | CacheAnnotationProcessor（Validate/Generate） | planned |
| 57 | `xdk.queue` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 58 | `xdk.schedule` | `@Scheduled` | ScheduleAnnotationProcessor（Validate/Generate） | planned |
| 59 | `xdk.event` | 无领域注解 | 标准 A8 / 编译器内建 | A8/compiler; partial adoption |
| 60 | `xdk.resilience` | `@Retryable`、`@CircuitBreakerPolicy`、`@RateLimit`、`@TimeoutPolicy` | ResilienceAnnotationProcessor（Validate/Generate） | planned |
| 61 | `xdk.metrics` | `@Metered` | MetricsAnnotationProcessor（Validate/Generate） | planned |
| 62 | `xdk.trace` | `@Traced` | TraceAnnotationProcessor（Validate/Generate） | planned |
| 63 | `xdk.audit` | `@Audited` | AuditAnnotationProcessor（Validate/Generate） | planned |
| 64 | `xdk.terminal` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 65 | `xdk.i18n` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 66 | `xdk.test` | `@TestCase`、`@Before`、`@After`、`@Benchmark` | TestAnnotationProcessor（Validate/Generate） | planned |
| 67 | `xdk.jsonrpc` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 68 | `xdk.mcp` | `@Tool`、`@ToolParam`、`@Resource`、`@Prompt` | McpAnnotationProcessor（Validate/Generate） | planned |
| 69 | `xdk.ml` | `@ModelSpec`、`@MlPipeline` | MlAnnotationProcessor（Validate/Generate） | planned |
| 70 | `xdk.numerics` | 无领域注解 | 标准 A8 | A8/compiler; partial adoption |
| 71 | `xdk.db` | `@Entity`、`@Table`、`@Id`、`@Transactional` | DbAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 72 | `xdk.api` | `@Api`、`@Operation`、`@Middleware`、`@Inject`、`@Component`、`@Configuration`、`@Bean` | ApiAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 73 | `xdk.agent` | `@AgentReceiver`、`@AgentProcessor`、`@AgentExporter`、`@PipelineSpec` | AgentAnnotationProcessor（Validate/Generate） | planned |
| 74 | `xdk.accel` | 无领域注解 | 无自有处理器；消费 GPU/Tensor 生成物 | A8/compiler; partial adoption |
| 75 | `xdk.embedded` | 无领域注解 | 无自有处理器；消费 Device/Serial/FFI 生成物 | A8/compiler; partial adoption |

A package MUST NOT be marked annotation-complete unless it satisfies §0.5.
