# XNull Specification, Part 2: Object Programming

> **Translation notice**: This is an English translation of the normative Chinese specification
> 《XNull 解决方案 第 2 部分：对象编程》v3.3.0. The Chinese original prevails in case of any
> divergence. Translation version follows the original's version number.

| Item | Value |
| --- | --- |
| Document ID | Part 2 (S2) |
| Document Version | 3.3.0 |
| Specification Status | Normative |
| Release Date | 2026-11-05 |
| Applies To | XNull compiler, runtime, LSP, tests |
| Companion Document | Part 1 *Core Syntax* v3.3.0 (version numbers sync with the current versions; see the specification index) |

Versioning rule: file names keep the full version number; new versions are saved alongside, never overwriting old ones. The patch number is for semantic-preserving clarifications, the minor version for backward-compatible additions, and the major version for breaking changes. Specification-clause changes must synchronize acceptance items and implementation boundaries.

## Decision Summary

- Types are checked by nominal identity; object kinds and memory/dispatch rules are in 0.4.
- Ordinary classes use static inheritance: subclasses reuse superclass fields and methods only, and cannot override; polymorphism goes through protocol implementation only.
- Structs have pure value semantics: they carry value fields only — reference fields, `deinit`, and capturing `self` are forbidden; use `class` when reference semantics, identity, or sharing are needed.
- Protocols have method signatures only; protocol fields, method bodies, default implementations, generic protocols, associated types, generic methods, and constraints are forbidden.
- Data-enum items are GC singletons; simple enums are inline integers; singletons are GC global roots; no enum or singleton implements protocols.
- Enum `switch` performs exhaustiveness checking: without `default` all items must be covered; with `default` the check is waived.
- Memory management is fully owned by the compiler and runtime: the strategy is adjudicated by the compiler per the Section 15 decision table, and management actions are executed by the runtime; source must not express reference strength, addresses, pointers, or reclamation strategy.
- The language and XDK public APIs provide no weak references; the weak table is a runtime-internal mechanism open only to the FFI contract layer (see the Memory Management spec §16, §19, §22). The former `weak` field modifier is removed; scenarios use replacement patterns (15.8).
- `@arc` / `@gc` are demoted to implementation-internal annotations: they must not appear in source, are for implementation preview only, and are non-committed entries within the implementation boundary (15.1.2).
- Generics are monomorphized before memory analysis; `out` / `in` apply to classes only; bare generics erase to `Box<Any>`.
- A `factory` is an instance-less creation namespace, bindable to same-package or cross-package `class` / `struct`; same-package bindings retain access to the target's private constructors, cross-package bindings may use only the target's public members.
- Private fields have the unified canonical internal name `_name`. Only two declarations exist — `Int _name` and `private Int name` — mapping to the same field; `private Int _name` is a compile error. Inside the class only the bare `_name` is legal; `self._name` and the bare `name` are both illegal, and locals/parameters cannot be named `_name`. External access to `name` and `_name` both report private errors.
- Tuples are the built-in value type of Part 1 2.11; all-value-element tuples may serve as `struct` fields; tuple fields with reference elements cause the owner to be analyzed as GC.
- The no-accessor pattern: fields are read/written directly; the getter/setter accessor pattern and property syntax are forbidden (7.3); computation and validation use verb methods.
- Primary constructors (6.3): `class Worker(final Int id)` declares fields and a constructor in the class header, with parameters binding same-named fields; classes only, not mixed with other constructors.
- Unified function rules: methods, top-level functions, constructors, and lambdas follow one set of explicit function rules (Part 1 7.10).
- The implementation boundary is a release gate, not an "unenforced" list; failing items block release — no silent degradation.

## 0. Specification Foundations

### 0.1 Scope

This document defines XNull's object model: type declarations, inheritance, protocols, structs, enums, singletons, factory types, extensions, annotations, generic types and methods, member resolution, dispatch, object layout, lifecycle, and memory strategy.

This document does not define:

- Lexing, base types, expressions, statements, closure syntax, packages and imports, entry; see Part 1.
- The basic semantics of `Result`, `try`, `defer` / `errdefer`; see Part 1 Section 10.
- Error observation, cancellation, timeouts, and `ErrorKind` policies; see the Error Handling specification.
- The C ABI, IPC, and cross-language ownership; see Part 7.
- The complete XDK package APIs; see Part 6.

### 0.2 Relationship to Part 1

Part 1 defines core syntax and the type system; this document adds:

- Type declarations and object identity;
- The boundary between value semantics and reference semantics;
- Ordinary classes' static inheritance, protocol polymorphism, and vtable dynamic dispatch;
- The protocol method-signature contract and implementation checks;
- The `factory` creation namespace, same-package private-constructor access, and cross-package public construction;
- Generic type instantiation and variance;
- The three memory strategies: ARC / GC / stack.

This document uses Part 1's type assignability, expressions, statements, closures, and entry rules. On conflict, this document's specific object-semantics provisions prevail; core syntax remains governed by Part 1.

### 0.3 Specification Language and Conformance

**MUST**, **FORBIDDEN**, **SHOULD**, and **MAY** are used per RFC 2119.

An implementation must accept all source programs satisfying this document's **MUST** clauses and produce the observable behavior this document defines; programs violating **FORBIDDEN** clauses must be rejected. The grammar may accept semantically illegal constructions, but the type-checking phase must reject them — grammar acceptance must never be treated as legality.

Implementations may provide extensions, but extensions must be explicitly enabled; default builds must not depend on extensions. The same source program, implementation version, and options must produce identical diagnostics and run results.

### 0.4 Object Model Summary

| Kind | Instance | Inheritance | Protocol Conformance | Dispatch | Memory | Identity |
| --- | --- | --- | --- | --- | --- | --- |
| `class` | Reference object | Single superclass; field/method reuse only | Yes | Static for class-typed receivers; dynamic for protocol-typed receivers | ARC / GC; non-escaping pure-value objects may be stack-allocated | Yes |
| `struct` | Value | Forbidden | Forbidden | Static | Inlined value; copied; outside ARC/GC | No |
| `protocol` | None | Inherits protocols | N/A | Implementers' vtable | No allocation | No |
| Simple `enum` | Integer values | Forbidden | Forbidden | Static | Inline integer | No |
| Data `enum` | Item objects | Forbidden | Forbidden | Static | GC | Yes |
| `singleton` | Unique global instance | Forbidden | Forbidden | Static | GC global root | Yes |
| `factory` | None | Forbidden | Forbidden | Static methods | No allocation | No |
| `extension` | None | Forbidden | Forbidden | Merged into target type; static calls | No allocation | No |
| `@annotation` | None | Forbidden | Forbidden | N/A | No allocation | No |

Only `class`, `struct`, data `enum`, and `singleton` produce actual objects or values. `protocol`, `factory`, `extension`, and `@annotation` produce no independent objects. Class inheritance produces no class-hierarchy polymorphism; only calls through protocol-typed receivers use the vtable.

## 1. Type Declarations Overview

### 1.1 Declaration Forms

```x
class Device : Base implements Ready, Secure { }
struct Point { }
protocol Ready { }
enum Color { }
singleton AppInfo { }
factory DeviceFactory for Device {
    static Device create(String name) { ... }
}
extension Device { }
@annotation Marker { }
```

- Type declarations may only sit at package top level; nested types, local types, and anonymous types are unsupported.
- Declarations are prefixed by annotations and modifiers, in the order `{ Annotation } { Modifier }`.
- Type names and `factory` names are unique within a package; conflicts with predefined type names, other type names, `factory` names, or type parameters are forbidden.
- A file may declare multiple types; declaration order does not affect visibility.
- Type declarations may reference each other forward; recursion limits in 1.5.
- `PascalCase` type names are the canonical style, but naming has no semantic effect.
- The `{` of type headers, `factory` headers, method headers, constructor headers, and `deinit` headers must be on the same line as the header; a newline triggers automatic semicolon insertion.

### 1.2 Type Kinds

| Keyword | Semantics | Instantiable | Usable as Supertype |
| --- | --- | --- | --- |
| `class` | Reference type; single-inheritance field/method reuse; may implement protocols | `new` | Yes |
| `struct` | Pure value type; value fields only; copyable | `new` | No |
| `protocol` | Nominal method-signature contract | No | Yes (protocol inheritance) |
| `enum` | Closed enumeration; simple or data | No | No |
| `singleton` | Preloaded unique instance | No | No |
| `factory` | Creation namespace bound to a target type | No | No |
| `extension` | Adds methods to an existing type | No | No |
| `@annotation` | Compile-time annotation type | No | No |

### 1.3 Nominal Types and Type Identity

- Types are checked by declared identity, with no structural matching. Two classes are incompatible even if fields and methods are identical.
- Type identity is determined by "declaration + type-argument list"; import aliases do not change identity.
- Two same-named types cannot be declared in one package; same-named types in different packages are different types.
- Different type-argument lists of a generic type are different types: `Box<Int>` and `Box<String>` differ.
- Variance conversions hold only when the declaration allows them; otherwise generic types are invariant.
- Type parameters are types only inside their declaration; they cannot be referenced outside it.
- A bare generic name `Box` equals `Box<Any>`; this is erasure, not "unknown type."
- Class inheritance reuses fields and methods only, establishing no overridable dynamic type slots; a subclass method cannot override a same-signature superclass method.
- Protocols are the sole polymorphism entry; only protocol-typed receivers select implementations through the vtable.
- Member access uses uniform dot syntax: `.`, `?.`; there is no `->`, address-of, pointer, smart pointer, or dereference syntax. "Reference" in this document means only the object model's implicit handle/holding semantics — see Part 1 0.7.
- Source has no weak references, address-of, pointers, or reference-strength concepts; ARC/GC are runtime strategies, not source-level types.
- A `factory` is a creation namespace, not a value or reference type; it cannot appear in variables, parameters, fields, generic arguments, `is` / `as`, or `Object`.

### 1.4 Declaration Location and Order

- Type declarations and `factory`s must be at package top level; not inside function bodies, control bodies, classes, or other types.
- Declaration order within a package is irrelevant; types, functions, and fields may reference each other.
- Cross-package references must go through `import` or fully qualified names.
- Type visibility is defined by Part 1 4.5 and this document's 7.3.

### 1.5 Recursive Types

- Reference recursion is allowed: `class Node { Node? next; }`.
- Container recursion is allowed: `class Tree { List<Tree> children; }`.
- Value-containment recursion is forbidden: both `struct S { S value; }` and `struct S { S? value; }` are infinite-sized and must be reported as errors.
- Structs cannot break recursion through containers, reference fields, or optional fields; use a `class` for recursive structures, e.g., `class Node { Node? next; }`.
- Inheritance cycles are forbidden: `class A : B` with `class B : A` is a compile error.
- Protocol inheritance cycles are forbidden.
- Recursive generic instantiation must terminate; the compiler must detect infinite expansion and report.

### 1.6 Modifiers

| Modifier | Applies To | Semantics |
| --- | --- | --- |
| `public` | types, members | Public; the default visibility |
| `protected` | types, members | Accessible to the type and its subclasses; at top level equals `private` |
| `private` | types, members | Accessible only within the declaring type |
| `abstract` | classes | The class cannot be instantiated; abstract classes cannot declare abstract methods |
| `final` | classes, methods, fields, locals, parameters | Class not inheritable; method not overridable; field/binding assigned once |
| `static` | members, top-level functions | Type-level member, independent of instances |
| `const` | top-level/static fields | Compile-time constant; implicitly `static`; occupies no instance layout |
| `var` | locals | Type inference; not a field modifier |
| `out` / `in` | class generic parameters | Covariant / contravariant; see 13.2 |

Composition rules:

- An `abstract final` class is illegal.
- `abstract` modifies classes only; methods cannot be written `abstract` — all class methods must have bodies.
- Class methods are non-overridable by default; method-level `final` is legal but redundant and does not change dispatch.
- A `final` class cannot be `abstract`.
- `static` methods cannot use `self` / `super`.
- The language provides no weak-reference modifier; former `weak` field scenarios use the replacement patterns in 15.8.
- Private fields have the unified canonical internal name `_name`. Only two declaration spellings exist, mapping to the same field:
  - `Int _name;`: declared name `_name`, canonical name `_name`;
  - `private Int name;`: declared name `name`, canonical name `_name`.
- `private Int _name;` is a compile error: `private` and the `_` prefix cannot be used together.
- The `name` in a `_name` declaration must be lowerCamelCase; `_`, `__x`, `_1` are illegal. Inside the class the field is referenced only by the bare `_name`; `self._name` and the bare `name` are both compile errors. Locals, parameters, and type parameters cannot be declared with the canonical name `_name` of a private field of the same class. External `name` and `_name` both report private-access errors. `public` / `protected` combined with `_name` is a compile error.
- A `const` field cannot be additionally modified by `final`; `const` already implies `static` and read-only; an explicit `static const` is legal and equivalent.
- Repeating the same modifier is a compile error; visibility modifiers are mutually exclusive.
- Unknown modifiers, or modifiers in the wrong position, are compile errors.
- A `factory` accepts only top-level visibility modifiers; it cannot be `abstract`, `final`, or `static`. Factory methods must be written `static`.

### 1.7 Type Visibility

- Types are public by default.
- Top-level `private` / `protected` types cannot be imported by other packages; visible within the package.
- Top-level `protected` provides no additional inheritance semantics, equal to `private`.
- A `factory`'s visibility is handled as a top-level declaration; factory methods may be `public` / `private`, never `protected`.
- A `factory`'s Target must be visible from the declaring package; cross-package Targets are constrained by their top-level visibility.
- Type and `factory` visibility affects compile-time access only; it changes neither layout nor memory strategy.

## 2. class

### 2.1 Declaration and Semantics

```x
class Device : Base implements Ready, Secure {
    String name = "device";

    Device(String name) {
        self.name = name;
    }

    void rename(final String next) {
        self.name = next;
    }
}
```

- A `class` declares a reference type; variables hold object references, and multiple variables may point at the same object.
- Classes support single inheritance; the superclass follows `:`, at most one. Inheritance reuses the superclass's fields and concrete methods only, producing no class-hierarchy polymorphism.
- Protocols follow `implements` and may be multiple.
- With no superclass, write only `implements`; with no protocols, write only `:`.
- All class references are compatible with the reference root `Object`; `Object` is the implicit reference root and does not enter the source-level inheritance chain. Without an explicit superclass, `super` cannot be used. `Object` has no user-visible members and cannot be `new`-ed.
- Classes may implement protocols; implementing classes and their subclasses carry a protocol vtable. Class-typed receivers still dispatch statically; only protocol-typed receivers use the vtable.
- Classes accept no memory-strategy annotations; `@arc` / `@gc` are implementation-internal annotations, not source-level entries (see 15.1.2).
- Classes may be generic; variance is limited to `out` / `in` type parameters.
- Classes may be `abstract` or `final`; an `abstract` class cannot be instantiated and cannot declare abstract methods; rules in 2.6.
- Class instance fields, methods, constructors, and `deinit` are in Section 6.

### 2.2 Fields

- Instance fields belong to the object, one per instance; field declarations, defaults, `final` / `const`, and initialization order are in 6.1.
- Field names must be unique along the inheritance chain; field hiding is forbidden.
- Private fields are declared with the `private` modifier or with the `_name` leading-underscore spelling; the canonical name is `_name`, referenced inside the class only by the bare `_name` — `self._name` and the bare `name` are both compile errors. Access rules in 5.8, 7.4.
- Field layout in 15.3.

### 2.3 Methods

- Method declarations, signatures, overloads, `final` / `static`, and visibility in 6.2, 6.8, 7.3; methods cannot be written `abstract`.
- Instance methods may access `self` and instance fields; static methods cannot.
- All class methods dispatch statically; protocol-typed receivers dispatch dynamically; `super` dispatches statically; see 5.6.
- Unqualified-name resolution in method bodies in 5.8.

### 2.4 Constructors

- Constructors share the class name and declare no return type; overloads, visibility, `final` field assignment, and `self`-publication restrictions in 6.3; the class-header primary-constructor form in 6.3.
- With no declared constructor, a no-argument constructor is generated; with an explicit superclass it calls `super()`.
- With an explicit superclass, an explicit `super(...)` must be the first action; field initializers run after `super` and before the constructor body.
- Inside a constructor, `self.method()` statically dispatches to the current class.
- `new C(args)` rules in 2.7.

### 2.5 Inheritance

- Single inheritance; a superclass may itself have a superclass; the chain ultimately reaches `Object`.
- The superclass cannot be `final`.
- Subclasses inherit superclass fields and methods (subject to visibility) for reuse, creating no new dispatch slots.
- Subclasses cannot declare fields with superclass names; field names are unique along the whole chain.
- Subclasses cannot declare methods with the same signature as any ancestor's instance method; same-signature is a compile error, including ancestors' `private` methods. Return type, visibility, and `final` do not change this rule.
- Subclasses may declare same-named methods with different parameter lists, forming overloads; overloading does not alter the superclass method's static binding.
- Class methods are all statically bound; there is no "subclass overrides superclass" semantics. Calling through a superclass or subclass static type selects the inherited method corresponding to that static type.
- `@Override` cannot mark class-inherited methods; it serves protocol-implementation checks only.
- Subclasses may continue implementing protocols; inherited public instance methods can satisfy protocol requirements, and protocol conformance passes down the chain.
- Subclasses may call `super(...)`, `super.method()`, and accessible `super.field`.
- Subclass constructors must complete superclass construction; the `deinit` chain in 6.4.

### 2.6 Abstract and Final Classes

- Abstract classes cannot be `new`-ed; they may declare constructors for subclass use, to share fields, methods, and construction logic.
- Abstract classes cannot declare abstract methods; every instance method in an abstract class must have a body.
- An abstract class may implement protocols, but only by providing concrete implementations of all protocol methods; otherwise it must not declare `implements` — a concrete subclass declares the protocol and implements it.
- `final` classes have no subclasses; `final` methods are legal but redundant, since class methods are non-overridable anyway.
- `final` methods may satisfy protocol requirements.
- An `abstract final` class is illegal.
- Abstract classes may have static members and concrete methods.

### 2.7 Class Instantiation

```x
Device device = new Device("camera-01");
```

- `new` returns a class reference; object identity is fixed at allocation.
- `new` allocates per the memory strategy: stack, ARC, or GC; at the language level it is always reference semantics.
- Non-escaping local objects with only value fields, no `deinit`, and no captured `self` may be stack-allocated; this is an optimization and does not change reference semantics.
- `new`'s arguments resolve per constructor overload; no matching constructor is a compile error.
- Allocation failure is a panic; a panicking constructor means the object is never published and the process terminates.
- `new` cannot be applied to `abstract` classes, `protocol`, `enum`, `singleton`, or `@annotation`.

### 2.8 Classes and Object

- All reference types are assignable to `Object`; an `Object` variable may hold class, protocol, singleton, data-enum item, closure, array, container, `String`, `Text`, `Bytes`, `StringBuilder`, etc., references.
- `Object` cannot be instantiated directly.
- `Object`'s value may be `null`; assigning `null` to `Object` is legal.
- Recovering a concrete type from `Object` must use `as` / `as?`; failure is a panic or `null`.
- Value types must be boxed as `Any` before entering `Object`.
- Both `==` and `===` on `Object` are reference-identity comparison.

## 3. struct

### 3.1 Declaration and Semantics

```x
struct Point {
    Int x = 0;
    Int y = 0;

    Int sum() {
        return self.x + self.y;
    }
}
```

- A `struct` declares a pure value type; each value is stored inline, and assignment, parameter passing, and returning copy the entire value.
- Structs do not participate in inheritance and do not implement protocols; no superclass or `implements` may be written.
- Structs may have instance fields, instance methods, static members, and constructors; they cannot declare `deinit`.
- Structs cannot capture `self` in methods or closures; structs have only value fields — no memory-strategy or weak-reference field issues exist.
- Structs may be generic; generic parameters are invariant — no `out` / `in`.
- Every type argument of a struct must be a value-field type per 3.2; reference types, `Result`, and other non-value-field type arguments are rejected at type checking.
- Structs cannot be `abstract` or `final`; they cannot be superclasses or protocol types.
- When reference semantics, object identity, shared state, protocol polymorphism, or `deinit` is needed, a `class` must be used.

### 3.2 Value-Field Restrictions

Struct instance fields must be value fields. Allowed field types are limited to:

- `Bool`, `Byte`, `Short`, `Int`, `Long`, `UByte`, `UShort`, `UInt`, `ULong`, `Int128`, `UInt128`;
- `Float`, `Double`, `Char`;
- Simple enums;
- Another `struct` satisfying this section's restrictions;
- `T?`, where `T` is a value-field type above; optional values must be inlined and must not introduce references;
- Tuples `(T1, T2, ...)` if and only if every element type is a value-field type allowed by this section (Part 1 2.11).

The following cannot be struct instance fields:

- `String`, `T[]`, `List`, `Set`, `Map`, `Text`, `Bytes`, `StringBuilder`;
- `Any`, `Object`, protocols, function types, `class`, data enums, singletons;
- `Result`;
- Tuples with reference elements;
- Optional types `T?` where `T` is not an allowed value-field type;
- Any `struct` containing reference fields or recursive value containment.

Struct instance fields are checked recursively by declared type; value-containment cycles are forbidden in 1.5. Generic structs have fields checked after instantiation by the substituted result; any instance field containing a reference type is a compile error. Static fields are exempt from 3.2 and handled as type-level storage per 7.1. Structs have no "copyability adjudication" branch — all legal structs are copyable values.

### 3.3 Copy Semantics

- Assignment, parameter passing, returning, storing into arrays/containers, and struct-field initialization all copy the entire value; copies are independent of the original.
- Modifying a copy does not affect the original; no `struct` variable shares field storage.
- Structs have no object identity; `==` compares field by field by value; `===` equals `==`.
- They cannot be `Map` / `Set` keys (Part 1 9.5's key restrictions).
- Fields are stored inline by value; layout in 3.6.
- When a closure captures a struct variable, the cell holds that struct value; the outer variable and the closure share the cell, but no object identity is produced.
- Struct copying triggers no ARC/GC and calls no `deinit`.

### 3.4 Methods and self

- A struct's `self` denotes the receiver value's storage slot; it is not an object reference.
- A method writing `self.field` or calling a write method on `self` is treated as a "write method."
- Write methods require an assignable receiver: local variables, writable fields, array/List elements. Calling a write method on a temporary or read-only position is a compile error.
- Read-only methods work on any receiver.
- `final` fields cannot be written after initialization; write methods cannot bypass this either.
- Struct methods do not support `super`; structs have no superclass.
- All struct methods dispatch statically; structs have no vtable.
- Struct methods must not capture `self` in closures; switch to a `class` when capturing the receiver is needed.

### 3.5 Constructors

- Struct constructors share the struct's name and declare no return type; they may be overloaded.
- `new Point(1, 2)` creates a struct value; the value is copied on assignment or return.
- With no declared constructor, a no-argument constructor is generated: it runs the field initializers and finishes.
- `final` fields must be assigned exactly once in an initializer or the constructor body.
- Structs have no `deinit`; resource cleanup is done explicitly by the code holding the value.
- Struct construction failure follows Part 1's error rules; no observable object identity is produced.

### 3.6 Layout and ABI

- Fields are laid out in declaration order, each 8-byte aligned.
- Scalar value fields occupy one 8-byte slot; nested struct fields are inlined, sized up to a multiple of 8 bytes.
- Structs have no object header, no vtable pointer, no ARC/GC header.
- Struct methods do not enter the vtable; there is no dynamic dispatch.
- Language semantics copy by value; the ABI may pass "address + sret". "Address" here is a compiler-internal calling-convention term, not source-level address-of/pointer syntax; when the ABI passes an address, the callee must still copy per language semantics and must not expose the address as shared identity.

### 3.7 struct vs class

| Dimension | `struct` | `class` |
| --- | --- | --- |
| Semantics | Pure value; always copies | Reference type |
| Fields | Scalars, simple enums, `struct`s, or their optional values only | Any legal fields, subject to memory strategy |
| Assignment/Passing | Copies the entire value | Passes the object handle, no object copy |
| Identity | None | Object identity |
| Inheritance | Forbidden | Single superclass; field/method reuse only |
| Protocols | Forbidden | Yes; protocol-typed receivers dispatch dynamically |
| Dispatch | Static | Static for class types; dynamic for protocol types |
| Memory | Inlined/copied; outside ARC/GC | ARC/GC; non-escaping pure-value objects may be stack-optimized |
| Lifetime | Follows the value or container holding it | Follows reference counts / GC reachability |
| Typical Use | Coordinates, sizes, colors, ranges, pure-value configuration snapshots | Entities, services, shared state, polymorphism, objects needing `deinit` |

Selection rule: use `struct` when independent copies are needed and all fields are value types; use `class` when identity, sharing, protocol polymorphism, lifetime callbacks, or reference fields are needed.

## 4. protocol

### 4.1 Declaration

```x
protocol Ready {
    Bool ready();
}

protocol Secure : Ready {
    Bool secure();
}
```

- A protocol is a nominal method-signature contract; only classes declaring `implements` conform to it.
- A protocol may inherit one or more protocols, written after `:`, comma-separated.
- Protocols cannot inherit classes; protocol inheritance cycles are compile errors.
- Protocols cannot be instantiated or `new`-ed.
- Protocols themselves allocate no objects; protocol-typed variables hold references to concrete implementing objects.
- Protocols may declare only instance-method signatures; fields, method bodies, and default implementations in a protocol body are all illegal.
- Protocols do not support generic parameters, associated types, static methods, constructors, `deinit`, generic methods, or type constraints.
- A protocol may be empty; any class may `implements` an empty protocol.

### 4.2 Method Signatures

- Protocol methods are public by default; `private` / `protected` cannot be written.
- Protocol methods are signatures only, terminated by `;`, with no method body.
- Implementing classes must provide same-signature methods; the protocol itself generates no implementation.
- Protocol methods cannot be `static`, `final`, `abstract`, or generic.
- Protocols cannot declare fields, properties, constructors, or `deinit`.
- Protocol methods cannot access fields, because protocols have none.

### 4.3 Implementation Checks

When a class implements a protocol:

- All methods of the class's protocols and their parent protocols must be implemented.
- Implementing methods must be instance methods, publicly visible, with exactly identical signatures: same name, parameter types, return type.
- Public instance methods inherited from superclasses can satisfy protocol requirements; the subclass inherits that protocol implementation.
- Extension methods cannot serve as protocol implementations; protocol implementations must come from class declarations or inherited methods.
- A class cannot defer protocol implementation through abstract methods; an abstract class may declare `implements` only when it provides all implementations.
- A class may implement multiple protocols; repeated requirements with identical signatures and return types are satisfied by one method.
- Two protocols requiring the same name and parameters but different return types cannot be implemented by one class and must be reported as errors.
- A class may have extra methods; this does not affect the implementation check.
- Merely having identical members without writing `implements` is not conformance.

`@Override` is optional; when written it must correspond to a same-signature protocol method, otherwise an error. `@Override` cannot mark superclass methods, since class inheritance has no overriding.

### 4.4 Protocol Types and Assignability

- Protocol types are reference types; variables may be `null`.
- Class to implemented protocol is an implicit upcast; subclasses inherit the superclass's protocol conformance.
- Protocol to parent protocol is an implicit upcast.
- Protocol to class, and class to non-implemented protocol, require explicit `as` / `as?`.
- Protocol variables strongly hold concrete objects: ARC objects are retained, GC objects become roots; the protocol itself creates no wrapper objects.
- Protocol variables may be assigned to `Object` and boxed as `Any`.
- Class fields may be declared as protocol type `P?`, assigned implementing objects or `null`. Protocols themselves cannot declare fields.
- Calls through protocol variables go through the vtable; only protocol-declared methods may be called.
- Calls through class-typed variables to the same object's methods still dispatch statically, unchanged by the object's protocol conformance.

### 4.5 Protocol Memory Rules

- Protocols have no instances and allocate no objects on their own.
- Conforming classes and their subclasses carry a protocol vtable header for dynamic dispatch of protocol-typed receivers; the vtable header is layout and does not decide ARC/GC.
- Concrete objects' memory strategies are still decided by the field graph and the Section 15 decision table.
- When a protocol type is a field, the reference graph is imprecise and the owning type is treated as GC.
- When a protocol type appears in containers, `Any`, closure environments, or task environments, the related objects are treated as GC.
- Protocol variables are strong holders; do not treat them as "borrowed views" and skip lifetime management.

### 4.6 Protocol Restrictions

- No generic protocols.
- No associated types, protocol generic methods, `where` clauses, or type constraints.
- No protocol static requirements.
- No protocol fields, properties, or storage semantics.
- No protocol default implementations, method bodies, or extended protocols.
- No `new`-ing protocols.
- No protocols as superclasses.
- No structs, enums, or singletons implementing protocols.

## 5. Inheritance, Protocol Conformance, and Dispatch

### 5.1 Legal Inheritance Forms

| Declaration | `:` | `implements` |
| --- | --- | --- |
| `class` | 0 or 1 class | 0 or more protocols |
| `protocol` | 0 or more protocols | Forbidden |
| `struct` | Forbidden | Forbidden |
| `enum` | Forbidden | Forbidden |
| `singleton` | Forbidden | Forbidden |
| `extension` | Forbidden | Forbidden |
| `@annotation` | Forbidden | Forbidden |

Must reject:

- `class C : P` where `P` is a protocol: a superclass cannot be a protocol.
- `class C implements Base` where `Base` is a class: only protocols may be implemented.
- A `final` superclass.
- A superclass that is `struct`, `enum`, `singleton`, `@annotation`, or `extension`.
- Inheritance cycles or protocol inheritance cycles.
- Directly `implements`-ing a duplicate protocol; duplicates inherited through superclasses are allowed, keeping a single implementation.
- A protocol inheriting a class.
- A struct declaring `implements`.
- Enums, singletons, extensions, and annotations declaring inheritance or conformance.
- A subclass declaring an instance method with the same signature as any ancestor's; class inheritance only reuses, overriding is not allowed.
- A subclass declaring a field with an ancestor's name.

### 5.2 Assignability and Conversions

- `Sub` is assignable to `Base` when `Sub` inherits `Base`.
- `C` is assignable to `P` when `C` declares `implements P` or inherits from a class implementing `P`.
- `P` is assignable to `Q` when `P` inherits `Q`.
- Classes, protocols, singletons, data-enum items, closures, arrays, and containers are assignable to `Object`.
- Value types must be boxed as `Any` before being assignable to `Any` / `Object`.
- Superclass to subclass, protocol to class, and `Object` to concrete type require explicit `as` / `as?`.
- `as` failure panics; `as?` failure returns `null`.
- `is` checks dynamic type or protocol conformance; `null` returns `false`.
- Class-to-superclass conversions do not change dispatch; calls through the superclass static type still select the superclass method.
- Class-to-protocol conversions enable protocol vtable dispatch; converting back to a class type restores static dispatch.
- No structural conversions; identical members do not imply compatibility.

### 5.3 Method Reuse and Overloading

Reuse:

- Subclasses directly inherit superclass instance methods; inherited methods keep their original signature, visibility, and implementation.
- Subclasses cannot declare instance methods with the same signature as any ancestor's; there is no overriding, covariant returns, or `@Override` class-inheritance checks.
- When a superclass method and a subclass method have the same signature, the compiler must reject the subclass declaration rather than selecting different implementations by static type.
- Method-level `final` is legal but redundant; all class methods are non-overridable.
- `private` methods are not inherited by subclasses, but their signatures still occupy chain names; subclasses cannot declare same-signature methods.
- `@Override` may only mark protocol implementations; marking superclass methods or failing to find a protocol method is an error.

Overloading:

- A method signature consists of the name and the parameter-type list; return type, parameter names, `final`, and visibility do not participate in the signature.
- Two instance methods in one type cannot have identical signatures; nor may an instance method and a static method.
- Subclasses may declare same-named methods with different parameter lists, forming overloads; same-signature declarations are rejected.
- Calls collect candidates by the receiver's static type: the current type's declared methods and inherited methods jointly participate in overload resolution.
- Multiple applicable candidates is an ambiguity error; no candidates is a compile error.

### 5.4 super

- `super(...)` invokes superclass construction; it must be the constructor's first action.
- `super.method()` calls the direct superclass's implementation; static dispatch; class inheritance has no subclass overriding.
- `super.field` accesses superclass fields; subject to visibility; superclass private fields are inaccessible.
- Without an explicit superclass, `super` cannot be used.
- `super` cannot be used in static methods.
- `super` cannot appear inside closures; when superclass behavior is needed, call `super.method()` inside the method — do not capture `super` into a closure.

### 5.5 Construction and Destruction Chains

The full ordering of construction and destruction is in 6.5. Inheritance-related rules:

- Construction completes the superclass first, then the current class's field initializers, then the constructor body.
- The object cannot be published before construction completes.
- `deinit` runs the derived class first, then up the superclass chain; an explicit `super.deinit()` takes over the remaining chain.

### 5.6 The Dispatch Model

Dispatch has two categories:

| Category | Applies To | Rule |
| --- | --- | --- |
| Static dispatch | Classes, structs, simple enums, data enums, singletons, constructors, static methods, `super` | Implementation selected by static type or explicit type name |
| Dynamic dispatch | Protocol-typed receivers | Runtime implementation selected via vtable slots |

Key rules:

- Class inheritance produces no vtable.
- Instance-method calls on class-typed receivers all dispatch statically, including `self.method()`.
- Classes implementing protocols (directly or via inheritance) carry a protocol vtable; the vtable holds only protocol-required method slots.
- Class-typed receivers calling protocol methods still dispatch statically; the vtable is used only when the receiver's static type is a protocol.
- Subclasses cannot override superclass methods; protocol implementations come from class declarations or inherited methods, and subclasses inherit the same implementation.
- `super.method()` always statically calls the direct superclass's implementation.
- Inside a constructor, `self.method()` statically dispatches to the current class, avoiding calls into an incompletely constructed runtime type.
- Inside `deinit`, `self.method()` statically dispatches to the current class, avoiding access to released derived-class fields.
- Protocol-typed receivers may call only protocol-declared methods; dynamically dispatched via vtable.
- `Any` receivers must first `as` to a concrete type or protocol before calling.
- Extension methods merge into the target type's static method set; they do not enter the vtable and do not participate in protocol conformance.

Static-dispatch example:

```x
class Base {
    Int f() { return 1; }
}

class Derived : Base {
    Int g() { return 2; }
}

Base value = new Derived();
Int x = value.f();
```

`Derived` inherits `Base.f` with no override; `value.f()` selects `Base.f` by static type `Base`, so `x` is `1`.

Dynamic-dispatch example:

```x
protocol Value {
    Int get();
}

class One implements Value {
    Int get() { return 1; }
}

class Two implements Value {
    Int get() { return 2; }
}

Value value = new Two();
Int x = value.get();
```

`value`'s static type is protocol `Value`; `value.get()` selects `Two.get` via the vtable, so `x` is `2`. Casting `value` back to the class types `One` / `Two` restores static dispatch.

### 5.7 vtable Layout

- Conforming class objects place a protocol vtable pointer at the payload's start; fields follow the vtable pointer.
- The vtable contains only protocol method slots — not ordinary class methods, static methods, constructors, `deinit`, or extension methods.
- The vtable is indexed by protocol method signature; the same signature maps to the same slot program-wide.
- When one implementation signature is required by multiple protocols, the slot is shared; different implementing classes place their own implementations in the same slot.
- Subclasses cannot override protocol implementations; inherited slots stay unchanged; subclasses adding protocols append the corresponding slots.
- Slot assignment must be deterministic: the same program, implementation version, and compilation options produce the same slots.
- The allocation header holds the type descriptor; `is` / `as` use the type descriptor to check dynamic type and protocol conformance.
- Classes not implementing protocols have no vtable pointer; their dynamic type checks rely on the type descriptor in the allocation header; stack objects use static type checks.
- vtable slot numbering is an implementation detail, never exposed to source; cross-module ABI needs stable slot rules.
- The memory strategy does not affect vtable presence; the vtable is decided solely by protocol-conformance relations.

### 5.8 Member Resolution

Inside instance methods, constructors, or `deinit`, unqualified names resolve in this order:

1. Local variables, parameters, type parameters;
2. Accessible instance fields of the current class and its ancestors;
3. Instance methods of the current class and its ancestors (for unqualified calls);
4. Static members of the current class and its ancestors;
5. The current package's top-level declarations, imported symbols, fully qualified names.

Rules:

- Instance fields may be accessed unqualified: `count = 1;` equals `self.count = 1;`.
- When a local or parameter shares a field's name, the local name wins and shadows the field; access the shadowed field via `self.field`.
- Assignment, reading, write methods, and constructors follow the same shadowing rules; resolution order must not switch on lvalue/rvalue.
- Fields and methods cannot share names; name conflicts within one type and its chain are compile errors.
- Field names are unique along the entire inheritance chain, including `private` fields; subclasses cannot declare same-named fields.
- Private fields' canonical name is `_name`; both `private name` and `_name` map to that field. Inside the class only the bare `_name` is legal — `self._name` and the bare `name` are compile errors. Private fields are accessible only inside the declaring class; external `name` and `_name` both report private errors. Subclasses cannot access superclass private fields, but the field's base name still occupies the chain's namespace.
- The current class's private-field canonical name `_name` cannot be reused by same-class locals, parameters, or type parameters; otherwise a compile error.
- If the current class or an ancestor declares a same-named field inaccessible in the current context, the unqualified reference reports a visibility error and does not fall back to an outer same-named symbol.
- Superclass `protected` fields are accessed per 7.3's rules; `super.field` accesses superclass fields.
- `super.method()` accesses the direct superclass; `super.field` accesses superclass fields.
- Static contexts have no `self` / `super`; unqualified names resolve only static members, top-level declarations, and imports.

## 6. Members, Construction, and Destruction

### 6.1 Fields

```x
class Worker(final Int id) {     // primary constructor: declares and binds the same-named field
    Int _retries = 0;
    Node? parent = null;
}
```

- Field declaration: `[visibility] [static] [final | const] Type name [= expression]`.
- Instance-field defaults:

| Type | Default |
| --- | --- |
| `Bool` | `false` |
| Integers | 0 |
| `Float` / `Double` | 0.0 |
| `Char` | `'\0'` |
| Reference types | `null` |
| Value-type `T?` | `null` |
| `struct` | recursively zero per field; fields without defaults must be explicitly initialized |
| Simple enums | no default; must be explicitly initialized or assigned |
| `Result` | no default; must be explicitly initialized or assigned |
| `final` fields | must be assigned exactly once |

- Field initializers run in declaration order after superclass construction and before the constructor body.
- Field initializers cannot reference `self`, other instance fields, or constructor parameters; they may reference constants, static members, and top-level functions.
- `final` fields: with an initializer they cannot be assigned again in the constructor body; without one they must be assigned exactly once on every construction path.
- `const` fields are implicitly `static` and read-only; they must have compile-time-constant initializers and occupy no instance layout.
- The language provides no weak-reference fields; former `weak` field scenarios use bidirectional strong references (cycles reclaimed by strategy classification) or the ID/registry pattern — see 15.8.
- Instance-field types must satisfy 3.2's value-field restrictions.
- Static fields belong to the type, not instances; rules in 7.1.
- Field names must be unique along the whole inheritance chain; field hiding is forbidden.
- Private fields are declared with the `private` modifier or the `_name` spelling; the canonical name is `_name`, referenced inside the class only by the bare `_name` — `self._name` and the bare `name` are compile errors; see 5.8, 7.4.

### 6.2 Methods

```x
class Counter {
    Int value = 0;

    Int next(final Int step) {
        self.value = self.value + step;
        return self.value;
    }
}
```

- Method declaration: `[visibility] [static] [final] ReturnType name(parameters) Block`.
- The return type precedes the method name; write `void` when there is none.
- Methods, top-level functions, constructors, and lambdas follow one set of function rules (Part 1 7.10): parameters have only type and name (may be `final`), no default parameters, named arguments, or variadic parameters; brace bodies; explicit return types. Methods' unique difference is the receiver and dispatch (5.6).
- Instance methods may access `self`, instance fields, and instance methods; static methods cannot.
- All normal paths of non-`void` methods must return values; paths terminated by `throw` need not.
- Methods cannot be written `abstract`; all class methods must have bodies.
- `final` methods are legal but redundant, since class methods are non-overridable anyway.
- Methods may be overloaded; signature rules in 6.8.
- Unqualified-name resolution in method bodies in 5.8.
- When a class method captures `self` in a closure, the receiver must be heap-allocated; stack allocation is forbidden.
- Struct methods must not capture `self` in closures; switch to a `class` when capturing the receiver is needed.
- Instance methods on class-typed receivers dispatch statically; protocol-typed receivers use the vtable — see 5.6.

### 6.3 Constructors

- Constructor names equal the type name; no return type; may be overloaded; may be written `public` / `protected` / `private`.
- **Primary constructor**: the class-header constructor form `class Worker(final Int id, final String name) { }`, an abbreviation of "declare same-named fields + declare a same-named constructor":
  - Primary-constructor parameters must be `final`; each parameter simultaneously declares a same-named field with the parameter's type;
  - The binding is equivalent to, after `super(...)` and before the primary constructor body, assigning each parameter to its same-named field in declaration order; `final` fields are thereby assigned exactly once;
  - The primary-constructor body may be omitted or contain ordinary statements; the body may read the bound fields;
  - With a primary constructor, no no-argument constructor is generated and no other constructors may be declared (ordinary and primary constructors do not mix);
  - Primary-constructor-declared fields follow the general field rules (6.1): default visibility, `final` assigned exactly once, field-name uniqueness along the chain;
  - The primary constructor's visibility follows constructor rules: public by default, written before the parameter list or omitted — use the ordinary constructor form when a private constructor is needed;
  - Only `class` supports primary constructors; `struct` / `singleton` / `enum` / `factory` do not.
- Class constructor rules in 2.4; struct constructor rules in 3.5.
- With no constructor, a no-argument constructor is generated; with constructors, none is generated.
- With an explicit superclass, an explicit `super(...)` must be the first action; when absent, `super()` is inserted — a superclass without an accessible no-argument constructor is a compile error. Without an explicit superclass, no `super` is inserted; the implicit `Object` root is handled by the runtime.
- Field initializers run after `super(...)` and before the constructor body.
- `final` fields must be assigned exactly once; a field initializer and the constructor body cannot both assign.
- Constructors may `return;` early, but on every path all `final` fields must be assigned; they cannot `return value`.
- Before construction completes, `self` must not be passed as a value, captured, or stored into containers or fields; member access is allowed. Instance methods called through `self` are under the same publication restriction — the callee must not pass `self` out.
- Inside a constructor, `self.method()` statically dispatches to the current class.
- A panicking constructor means the object is never published and the process terminates; no `deinit` runs.
- `new` instantiates per 2.7 / 3.5.

### 6.4 deinit

```x
class Worker {
    void deinit() {
        self.parent = null;
    }
}
```

- `deinit` may appear only in `class` or `singleton`; `struct`, `enum`, `factory`, and `protocol` cannot declare `deinit`.
- `deinit` cannot be `static`, cannot take parameters, must return `void`, and cannot have visibility modifiers.
- Each class or singleton has at most one `deinit`; it cannot be overloaded.
- `deinit` cannot be called explicitly, except `super.deinit()` inside `deinit`.
- A derived class's `deinit` by default automatically calls the superclass's `deinit`; an explicit `super.deinit()` takes over the remaining superclass chain, and the compiler must no longer auto-call the superclass `deinit`.
- Fields are still valid while `deinit` runs; the runtime releases still-non-null reference fields after the `deinit` chain completes.
- Setting a reference field to `null` inside `deinit` releases that field early; the runtime will not double-release.
- Weak references to the object are cleared before `deinit`; weak fields inside `deinit` may already be `null`.
- Inside `deinit`, `self.method()` statically dispatches to the current class.
- `deinit` must not publish `self`, store `self` into globals/containers/closures, or return `self`; object resurrection is forbidden.
- ARC objects call `deinit` deterministically when the count reaches zero; GC objects call it during sweep, at an uncertain time.
- Process exit, `panic`, and `throw` do not guarantee `deinit`; files, handles, task groups, etc. must be explicitly closed at their use points.
- A singleton's `deinit` is not a cleanup guarantee; singleton lifetimes follow the process.

### 6.5 Initialization-Order Summary

Object construction:

1. Allocate and zero the memory.
2. Install the type descriptor; conforming classes install the protocol vtable pointer.
3. With an explicit superclass, call the superclass constructor.
4. Run the current class's instance-field initializers in declaration order.
5. Run the constructor body (after `super(...)`).
6. Construction complete; `self` may be published.

Struct construction:

1. Evaluate initializers in field-declaration order.
2. Write field values into the receiver's storage.
3. Construction complete; the value may be copied on assignment/passing/return.

Object destruction:

1. Clear weak references.
2. Run the derived class's `deinit`.
3. Run the superclass `deinit` chain (explicit or automatic).
4. Release remaining reference fields.
5. Reclaim the memory.

Program startup:

1. Runtime and GC initialization.
2. Top-level and static fields zeroed.
3. Top-level/static field initializers run in package-dependency order.
4. Singletons initialize in package-dependency order.
5. `main` is called.

### 6.6 Failure Handling

- Allocation failure is a panic; the process terminates.
- A constructor's `panic` / `throw` means the object is not published, no `deinit` runs, and the process terminates.
- `panic` / `throw` inside `deinit` terminates the process directly; the remaining cleanup is not guaranteed.
- `deinit` must not depend on other objects' `deinit` ordering; cross-object cleanup must be explicitly coordinated.
- Resource cleanup uses explicit closing or the Error Handling specification's structured cleanup mechanism; `deinit` is only a last resort.

### 6.7 Name Resolution and Private Fields

Name resolution is in 5.8; private-field declaration and access in 7.4. Fields and methods cannot share names. Instance fields may be accessed unqualified; when a local or parameter shares a public field's name it shadows the field — use `self.field` to reach the public field; private fields can only be written as the bare canonical name `_name`, never `self._name`; `super.field` accesses superclass public fields.

### 6.8 Overloads and Signatures

A signature consists of:

- The method name;
- The parameter-type list;
- Instance or static category.

Not part of the signature:

- The return type;
- Parameter names;
- The `final` parameter modifier;
- Visibility;
- Generic parameter names;
- The method body.

Rules:

- Two instance methods in one type cannot share a signature; nor an instance and a static method.
- Different return types do not constitute an overload; changing only the return type is a compile error.
- Different parameter counts or types may overload.
- Subclasses cannot declare instance methods with an ancestor's signature; different parameter lists form overloads.
- Generic methods' type-parameter counts do not distinguish overloads; resolution is by parameter types only.
- Failed, ambiguous, or candidate-less overload resolution is a compile error.
- `@Override` may only correspond to a protocol's same-signature method; marking a superclass method or finding no protocol method is a compile error.

## 7. Static Members and Visibility

### 7.1 Static Fields

```x
class Counter {
    static Int count = 0;
    static final Int limit = 10;
    static const Int start = 0;
}
```

- Static fields belong to the type, independent of instances; one per type.
- Static fields are zeroed at program startup, then initialized in package/file/declaration order; rules identical to Part 1 4.3.
- Static fields are global roots: ARC references are retained, GC references traced.
- Static fields cannot use the class's generic parameters; `static T value` is a compile error.
- A `static final` field must be initialized once at declaration; the language provides no static initializer blocks, so post-hoc assignment is unsupported. `static const` requires a compile-time constant.
- Static fields are accessed via the type name: `Counter.count`; accessing `counter.count` via an instance is a compile error.
- A static field initializer may read already-initialized static fields; reading a not-yet-initialized one yields the zero value.
- Structs, data enums, and singletons may have static fields; simple enums, protocols, extensions, and annotations cannot.

### 7.2 Static Methods

- Static methods do not depend on instances; they cannot use `self` / `super`.
- Static methods may access static fields, static methods, top-level declarations, and imported symbols; not instance fields or instance methods.
- Static methods do not participate in dynamic dispatch; a subclass's same-named static method hides the superclass's, and calls resolve by explicit type name.
- Static methods may be overloaded; signature rules as in 6.8.
- Static methods may be generic; type-parameter rules in 13.
- Static methods cannot be `abstract`; `final` has no additional meaning for static methods.

### 7.3 Visibility

- Members are public by default; `public` / `protected` / `private` may be written.
- `public`: accessible wherever the type is visible.
- `protected`: accessible to the declaring type and its subclasses; must be accessed through `self`, `super`, or expressions whose static type is the current class/subclass; a protected member of another instance must not be accessed through a superclass-typed reference.
- `private`: accessible only within the declaring type; not by subclasses. Private fields' canonical name is `_name`; both `_name` and `private name` declarations map to the field, and `private _name` is a compile error. Inside the class only the bare `_name` is legal; `self._name` is illegal. External `name` and `_name` both report private errors. A same-package Target-binding `factory` gains Target private-constructor and private-static-member creation access per 10.3 — the sole exception.
- Class methods cannot be overridden, so no "override reduces visibility" rule exists; protocol-implementation methods must be public.
- Constructors may carry visibility; `new` is constrained by constructor visibility.
- Static members follow the same visibility rules.
- Visibility is a compile-time check only; it changes neither field layout, ARC/GC strategy, nor retain/release.
- There is no package-private visibility; same-package non-subclasses cannot access `protected` members.
- **No-accessor pattern**: classes provide no getter/setter accessor-method pattern and no custom property get/set syntax; public fields are the default property access — field access itself is property access.
- Only computed values, validation, logging, lazy initialization, or private state exposed outward warrant explicit verb methods (6.2); method names express behavior, not access; this is not the default requirement for field access.
- The standard library containers' `get` / `set` / `at` are verb methods of the collection APIs (Part 1 9.1), not accessor patterns.

### 7.4 Private Fields and Canonical Names

A private field's base name is the name after removing one leading `_`; the canonical internal name is uniformly `_name`. Only two declaration spellings exist, mapping to the same field:

- `Int _name;`: declared name `_name`, base name `name`, canonical name `_name`;
- `private Int name;`: declared name `name`, base name `name`, canonical name `_name`.

`private Int _name;` is a compile error: `private` and the `_` prefix cannot be used together.

For example, `private Int limit = 10;` has base name `limit` and canonical name `_limit`; inside the class only `_limit` may be written. Writing `self._limit` or the bare `limit` are compile errors. External access to `account.limit` and `account._limit` both report private errors.

Rules:

- The `name` in a `_name` declaration must be lowerCamelCase; the `name` in `private name` follows ordinary field naming. Base names must not start with an underscore; `_`, `__x`, `_1` cannot be base names.
- `_name` applies to instance and static fields; not to methods, constructors, locals, parameters, or type names.
- `private Int _name;` is a compile error; explicit `private` may declare only `name`, and the `_` prefix serves only `_name` declarations without `private`.
- `public` / `protected` combined with `_name` is a compile error.
- Within the declaring class, the canonical name `_name` is the only read/write spelling; `self._name` and the bare `name` are compile errors.
- Same-class locals, parameters, or type parameters cannot use the canonical name `_name`; same-named declarations are compile errors, preventing the private field from losing an accessible name.
- Superclass private fields are inaccessible in subclasses; `super._name` cannot bypass private visibility either.
- Field base names are unique along the entire chain; public `x`, `_x`, and `private x` all occupy base name `x` and cannot be declared simultaneously.
- Subclasses cannot access superclass private fields; the superclass private field's base name still occupies the chain's namespace.
- `private final Int id;` is written in the constructor as `_id = id`; the base name is `id`, the canonical name `_id`, and `self._id` cannot be used.
- Private fields produce no extra fields, storage, or layout slots; there is exactly one field in memory.
- Private fields that are reference fields still participate in ARC/GC scanning and retain/release.

```x
class Account {
    private Int balance;
    Int _retries = 0;
    private Int limit = 10;

    Account(Int balance) {
        _balance = balance;
    }

    void deposit(Int amount) {
        Int next = _balance + amount;
        _balance = next;
        _retries = _retries + 1;
    }

    Int retryCount() {
        return _retries;
    }

    Int maxAllowed() {
        return _limit;
    }
}
```

`balance`, `retries`, `limit` have canonical names `_balance`, `_retries`, `_limit` respectively; inside the class only the canonical names are written, and `balance`, `retries`, `limit` do not access the private fields. External access to `account.balance`, `account._balance`, `account.retries`, `account._retries`, `account.limit`, `account._limit` all report private errors.

### 7.5 @ReadOnly

- `@ReadOnly` applies to fields only.
- Public/protected fields are externally readable and not writable; writable within the declaring type.
- Private fields are externally inaccessible anyway; `@ReadOnly` does not change private access rules and the declaring type remains writable.
- `@ReadOnly` affects neither layout, ARC/GC, nor reference counts.
- `@ReadOnly` cannot be applied to locals, parameters, or methods.

### 7.6 Visibility and Memory

- `public` / `protected` / `private` affect compile-time access only.
- Fields participate in layout, ARC/GC scanning, and retain/release regardless of visibility.
- `final` / `@ReadOnly` are compile-time restrictions and change no runtime memory.

## 8. enum

### 8.1 Forms

```x
enum Color { Red, Green, Blue }
enum Code { A = 1, B = 2, C = 4 }

enum Status {
    Ready(0, "ready"),
    Failed(1, "failed");

    final Int code;
    final String label;

    Status(Int code, String label) {
        self.code = code;
        self.label = label;
    }
}
```

- Enums come in two kinds: simple and data.
- Simple enums: items have no constructor arguments, and no fields, methods, constructors, `deinit`, or static members.
- Data enums: items carry constructor arguments; the enum declares fields, constructors, and methods.
- All items of one enum must use the same form; mixing `Item`, `Item(args)`, and `Item = value` is forbidden.
- Enums cannot be generic; they cannot declare superclasses or `implements`; they cannot be `abstract`; they are implicitly `final`.
- Enums implement no protocols; enum values cannot be assigned to protocol types, and enum methods cannot be called through protocol-typed receivers.
- Enum items are closed; they cannot be `new`-ed externally and are accessed only via `Enum.Item`.
- Data enums may declare fields, constructors, instance methods, static fields, and static methods; simple enums have only items.
- Enum declarations sit at package top level only.

### 8.2 Simple Enums

- Items are written by name; optionally `= integer-literal`, which may carry a leading `-`.
- Without values, items increment from 0; an explicit value sets the current item, and subsequent bare items continue incrementing.
- Explicit values must be integers within `Int` range; duplicates, overflow, and out-of-range are compile errors.
- A simple enum is an independent nominal type with an underlying `Int` representation; it cannot be implicitly assigned to `Int` or arithmetically combined with `Int`.
- Simple enums support `==` / `!=` / `===` / `!==`, comparing by underlying value.
- Simple enums support `<` / `<=` / `>` / `>=`, comparing by underlying value.
- Simple enums support `switch`; `case Color.Red` compares by underlying value.
- Simple enums allocate no objects, stay outside ARC/GC, and produce no retain/release; variables, parameters, fields, and array elements store them inline by value.
- Simple-enum fields have no defaults; fields must be explicitly initialized or assigned in constructors.
- Simple-enum items may serve `const` initializers.
- Interpolated strings format simple enums by item name.

### 8.3 Data Enums

- Data-enum items must carry constructor arguments: `Ready(0, "ready")`.
- Data enums must declare fields and constructors; fields must be `final`; the constructor shares the enum's name.
- Data-enum constructors are implicitly private, callable only by item declarations; they cannot be `new`-ed externally.
- Data-enum fields initialize at construction; all paths must assign `final` fields.
- Data-enum instances are immutable: fields are `final` and methods cannot write fields; static fields may be mutable.
- Data-enum items are compiler-provided singleton objects; each item is constructed once at program startup.
- Data-enum item arguments evaluate at startup in item-declaration order; item arguments may reference earlier items, constants, and static members — never later items.
- A panic during data-enum item argument evaluation terminates the program.
- Data enums support instance methods, static fields, and static methods; `deinit` is unsupported.
- Data enums do not participate in inheritance or protocol conformance; methods dispatch statically.
- Data-enum items have object identity; `==` / `===` compare by identity; all references to the same item are equal, different items are not.
- When data-enum fields are references, GC traces them; data-enum objects are GC-managed and do not use ARC counts.
- Interpolated strings: if the data enum declares `String toString()`, that method is called; otherwise the item name is formatted.

### 8.4 Enum Items and Initialization

- Item names are unique within an enum; simple enums' underlying values are unique.
- Data-enum constructor-argument counts and types must match the constructor signature; mismatch is a compile error.
- Data-enum items construct at startup in declaration order; the enum becomes externally available only after all items are constructed.
- Item initialization cannot reference not-yet-constructed later items; the compiler must check direct and indirect forward references.
- Enum items are global roots; data-enum items persist for the process lifetime.
- The enum type itself cannot create instances; simple enums have no object identity; data-enum identity is provided by the compiler.

### 8.5 Comparison, switch, and Formatting

- `switch`'s `case` uses `==` semantics: underlying value for simple enums, identity for data enums.
- Enum-`switch` `case` expressions must be that enum's item constants, e.g., `Color.Red` or `Status.Ready`; arbitrary expressions cannot serve as enum `case`s.
- An enum `switch` without `default` must cover all of the enum's items, each exactly once; missing, duplicate, or unknown items are compile errors.
- An enum `switch` with `default` treats `default` as covering the remaining items, with no exhaustiveness requirement; at most one `default`, which must come last.
- Non-enum `switch` does not check exhaustiveness; with no match and no `default`, the `switch` simply exits.
- Enums do not support pattern matching; to check data-enum fields, `switch` to the item first, then read fields or use methods.
- Simple enums support ordering comparisons; data enums do not.
- Simple-enum `Color.Red` has type `Color`; it cannot be directly compared or assigned with `Int`.
- Data enums cannot use `is` for subtype checks; `is Status` only checks whether the value is of that enum type.
- Data-enum items cannot be `new`-ed or reflectively created.
- Enums do not participate in `Object` inheritance; simple enums need boxing as `Any` to enter `Object`; data-enum items are references and are assignable to `Object`.
- Enums implement no protocols; protocol-typed variables cannot hold enum values.

### 8.6 Memory Rules

- Simple enums inline as `Int`: variables, parameters, fields, array elements, and container elements are all integer values.
- Simple enums allocate no objects, stay outside ARC/GC, produce no retain/release, and register no GC roots.
- Data-enum items are GC objects; the enum type itself produces no extra objects.
- Data-enum items are global roots persisting for the process lifetime; fields are traced as GC references.
- Data enums do not use ARC reference counts; they have no `deinit`.
- When data-enum fields are ARC references, GC is responsible for keeping and releasing them; specifics in 15.6.

## 9. singleton

### 9.1 Declaration and Access

```x
singleton AppInfo {
    final String name = "XNull";
}
```

- A `singleton` declares a preloaded, globally unique instance.
- `instance` is an implicit read-only field automatically provided by the compiler, of the singleton's type; only `singleton`s own this field.
- `instance` cannot be declared manually; a manual declaration is a compile error.
- Externally, the unique instance is accessed via `AppInfo.instance`; inside the singleton, fields and methods are accessed through `self`.
- `instance` cannot be reassigned and cannot be `null`.
- Singletons cannot be `new`-ed, inherited, or implement protocols; implicitly `final` and non-subclassable.
- Singletons cannot be generic or `abstract`.
- Singletons may have instance fields, instance methods, static fields, and static methods.
- Singletons cannot declare constructors; fields are initialized by initializers or defaults, and the compiler handles constructing the instance.
- A singleton may declare `deinit`, but it is not guaranteed to run at process exit; do not depend on it for resource cleanup.

### 9.2 Initialization

- Singleton instances preload at program startup, after top-level/static field initialization and before `main`.
- Singletons initialize in package-dependency, file, and declaration order.
- Singleton fields are zeroed first, then field initializers run.
- Singleton initializers may reference already-initialized top-level fields, static fields, and earlier singletons; not later ones.
- A panic during singleton initialization terminates the program; `main` is never called.
- Singleton instances complete construction before `main`; `main` sees fully initialized instances.
- A singleton's static fields initialize together with the other static fields.

### 9.3 Memory Rules

- `instance` is a global GC root persisting for the process lifetime, not reclaimed as an ordinary local object.
- Singleton instances always use GC semantics.
- Callers hold only a holding view of `instance`; they need not — and should not — perform retain/release on it.
- Singleton fields follow ordinary field rules; reference fields keep target objects until process end.
- To release objects held by singleton fields, explicitly `clear()` or set `null`.
- A singleton captured by closures or tasks is still the same global instance, never copied.
- A singleton's `deinit` is not a cleanup guarantee; files, handles, and task groups should be explicitly closed at use points.

### 9.4 Restrictions

- No generic singletons.
- No inheritance, protocol conformance, constructors, or subclassing.
- No manual `instance` declaration.
- No `new`.
- Singleton-field concurrent access is unsynchronized; use `xdk.sync` when synchronization is needed.
- Singleton initialization order is deterministic; cross-singleton forward references are compile errors.

## 10. factory

### 10.1 Declaration and Target

```x
factory DeviceFactory for Device {
    static Device create(final String name) {
        return new Device(name);
    }

    static Result<Device, DeviceError> open(final String path) {
        ...
    }
}
```

- A `factory` declares a creation namespace bound to one target type; it has no instances and allocates no objects.
- A `factory` may only sit at package top level; nesting is forbidden.
- The Target of `for Target` must be a `class` or `struct` declaration visible in the current or another package; generic targets are written as the bare type name `Box`, without type arguments.
- The Target may be an abstract class; the factory method returns concrete subclass instances upcast to the target type.
- The Target cannot be a `protocol`, `enum`, `singleton`, `@annotation`, another `factory`, an array, a container, a function type, `Object`, `Any`, an optional type, or a generic instantiation.
- To create by protocol, bind an implementing class and have the factory method return that protocol or superclass; the protocol itself is never a Target.
- A `factory` name occupies the declaring package's top-level type namespace; it must not share a name with other types in the package and cannot be used as a type.
- A `factory` is public by default; `public` / `private` / `protected` may be written; top-level `protected` equals `private`.
- A `factory` cannot be `abstract`, `final`, `static`, or `const`; it is implicitly non-instantiable and non-inheritable.
- A `factory` cannot declare fields, constructors, `deinit`, instance methods, superclasses, or protocol conformance.
- A `factory` is a stateless creation namespace; use a `singleton` or top-level static fields when caching or shared state is needed.
- One Target may have multiple `factory`s, in the same or different packages; each factory's access rights are determined by package boundaries.
- A same-package `factory` gains the Target's private-constructor and private-static-member access; a cross-package `factory` may access only the Target's public members.
- Cross-package Targets must be visible from the `factory`'s package; invisible types and non-public top-level types cannot be Targets.
- A factory method's effective visibility is the stricter of the `factory` type's visibility and the method's visibility.
- When the Target's visibility is below the factory method's effective visibility, the method's return/parameter signatures must not expose the Target; return a public superclass, protocol, or `Object` instead.
- A `factory` may carry declaration annotations; `@Override` is illegal; other annotations are compile-time markers only.

### 10.2 Factory Methods

```x
factory BoxFactory for Box {
    static Box<T> create<T>(final T value) {
        return new Box<T>(value);
    }
}

Box<Int> box = BoxFactory.create(1);
```

- Factory methods must be `static`; they cannot use `self` / `super` or access instance fields.
- Factory methods are public by default; `public` / `private` may be written; `protected`, `abstract`, and `final` cannot.
- Methods may be overloaded and may declare method-level generic parameters.
- Allowed return base types R:
  - Target instances: `Device`; generic targets `Box<T>` / `Box<Int>` etc.;
  - A class Target may return any superclass, protocol, or `Object` the Target is assignable to;
  - A struct Target may return only the Target.
- The return type may be `R`, `R?`, `Result<R, E>`, or `Result<R?, E>`; `E` cannot be `void`.
- Returning `void`, arrays, containers, `Any`, or unrelated types is forbidden.
- Factory methods may return new objects, cached objects, singletons, `null` (when the Target is optional), or `Err`.
- Factory methods may use `try`, `defer`, `errdefer`; `Result` obeys `@mustUse`.
- Factory methods do not observe errors automatically; callers handle with `try` or `Result` members.
- Factory methods may call the same `factory`'s private methods, top-level functions, and other `factory`s' public methods.
- Factory methods cannot serve as the `main` entry; the entry must be a top-level `main`.

### 10.3 Access and Creation

- When the `factory` shares the Target's package, it automatically gains the Target's private creation access:
  - It may call the Target's private constructors;
  - It may call the Target's private static fields/methods;
  - It cannot access the Target's private instance fields/methods; after construction, only public members may be used;
  - It cannot access the Target's `protected` instance members (a `factory` is not a subclass).
- `new Target(...)` inside a same-package `factory` may hit private constructors; this is the same-package factory's core purpose.
- A `factory` is not the Target's subclass and cannot call the Target's `protected` constructors or `protected` instance members.
- A cross-package `factory` may call only the Target's public constructors, public static fields, and public static methods; never private or protected members.
- Factory methods may create subclass instances, but may call only the subclass's public constructors; returns upcast to the Target.
- Factories cannot access other types' private constructors, including Target subclasses'.
- When the Target has private constructors, only the Target itself and same-package Target-binding `factory`s can construct; cross-package factories cannot.
- When multiple same-package `factory`s bind one Target, each has private creation access; for finer granularity keep one `factory` and route other creation through private methods.
- A cross-package `factory` depends on the Target's public creation entries; when the Target has no public constructor or public static factory, the cross-package factory cannot create instances and can only return existing objects or `Err` from its methods.
- When the Target is a `struct`, the `factory` returns a struct value; value copying follows 3.3, and private-constructor access is still granted only to same-package factories.
- A `factory` method may return a superclass, protocol, or `Object`; the returned object is still constructed by the concrete Target or subclass.

### 10.4 Types, Memory, and Restrictions

- A `factory` is not a value, reference, or object type; it cannot be a variable, parameter, field, generic argument, or container element; it cannot be used with `is` / `as` / `as?`; it cannot be assigned to `Object` / `Any`.
- `new Factory` is a compile error; a `factory` is only invoked statically via `Factory.method(...)`.
- A `factory` has no object layout, type descriptor, vtable, or ARC/GC lifecycle; it allocates no memory and calls no `deinit`.
- Factory methods are static methods themselves — no `self`, no vtable dispatch; calls create no `factory` object.
- Objects created by factory methods allocate per the Target's normal memory strategy (stack/ARC/GC).
- A `factory`'s static methods introduce no additional global roots; objects created within them follow normal rules.
- A `factory` cannot be extended by `extension`; it cannot be an `extension` target, supertype, protocol implementer, or be replaced by a `singleton`.
- A `factory` can be `import`-ed; invoked via `Factory.method`; visibility follows top-level declaration.
- A `factory` cannot declare generic parameters; generic targets use the bare name, with instances produced by the factory method's type parameters.

### 10.5 Restrictions and Diagnostics

The compiler must reject:

- A `factory` sharing a name with the current package's types or other `factory`s;
- A Target that is not a visible `class` / `struct`;
- A Target that is a `protocol`, `enum`, `singleton`, `@annotation`, `factory`, array, container, function type, `Object`, `Any`, optional type, or generic instantiation;
- A cross-package Target invisible from the `factory`'s package;
- A `factory` declaring fields, constructors, `deinit`, instance methods, superclasses, or protocols;
- A factory method missing `static`, or using `self` / `super` or accessing instance fields;
- A factory method written `protected` / `abstract` / `final`;
- A factory method return type outside 10.2's allowed set;
- A factory method whose effective visibility exceeds the Target's and whose signature exposes the Target;
- A cross-package factory accessing the Target's private or protected constructors, static members, or instance members;
- A same-package factory accessing the Target's `protected` instance members;
- Using a `factory` as a type/value, `new`-ing a factory, or `is` / `as` on a factory;
- A `Result` error type of `void`;
- Duplicate factory-method signatures;
- Calling the Target's private constructor outside the Target itself and its same-package Target-binding `factory`s.

### 10.6 Examples

```x
class Device {
    final String name;

    private Device(final String name) {
        self.name = name;
    }
}

factory DeviceFactory for Device {
    static Device create(final String name) {
        return new Device(name);
    }

    static Result<Device, DeviceError> open(final String path) {
        ...
    }
}

Device device = DeviceFactory.create("camera-01");
```

- `Device`'s constructor is private; external `new` is impossible; the same package's `DeviceFactory` is the sole creation entry.
- The factory method returns `Device`; callers hold no `factory` object.
- `open` returns `Result<Device, DeviceError>`; callers use `try`.
- When a cross-package factory binds the same `Device`, it may use only the `public` constructor or `public` static creation methods; the private-constructor access above does not extend to other packages.
- A cross-package `factory`'s declaration still sits at package top level, references the Target via `import` or fully qualified names, and is constrained by the Target's top-level visibility.

Cross-package example:

```x
package devices

class Device {
    final String name;

    Device(final String name) {
        self.name = name;
    }
}
```

```x
package app

import devices.Device

factory DeviceFactory for Device {
    static Device create(final String name) {
        return new Device(name);
    }
}
```

`Device`'s constructor is public, so the `app` package's `DeviceFactory` may call it cross-package. If `Device`'s constructor were changed to `private`, the same-package factory could still call it but a cross-package factory could not; the cross-package factory must switch to the Target's public static creation methods.

## 11. extension

### 11.1 Declaration

```x
extension Device {
    String label() {
        return self.name;
    }
}
```

- An `extension` may only add methods — never fields, constructors, `deinit`, or static methods.
- The target type must be a non-generic `class`, `struct`, `singleton`, or data `enum` declared in the same package.
- Protocols, annotations, simple enums, extensions themselves, predefined types, and XDK types cannot be extended.
- Generic types and generic instantiations cannot be extended.
- Extension methods are public by default; `private` / `protected` cannot be written.
- Extension methods may be overloaded; duplicate same-name same-parameter declarations are compile errors.
- Extension methods must not conflict with same-signature methods already in the target type or its superclasses; same-signature is a compile error.
- Extension methods cannot be overridden by the target type's subclasses; a subclass's same-signature declaration is a compile error — class inheritance only reuses methods.
- Extension declaration order is irrelevant; all extensions in a package jointly participate in resolution.

### 11.2 Method Resolution and Dispatch

- Extension methods participate in normal method resolution and overloading; on class-typed receivers they dispatch statically.
- Extension methods do not enter the vtable; even when the target class conforms to a protocol, extension methods do not participate in protocol dispatch.
- Extension methods are inherited by subclasses; subclasses cannot declare same-signature methods to override extension methods — same-signature is a compile error.
- Extension methods cannot serve as protocol implementations; protocol requirements must be met by class declarations or inherited methods.
- Protocol-typed receivers cannot call extension methods not declared in the protocol; convert to the concrete type first.
- Same-name same-parameter duplication between extension methods, or between an extension method and a target method, is a duplicate definition and must be reported.
- Extension methods cannot change the target type's layout or memory strategy.

### 11.3 Access and Memory

- Extension methods may access only the target's public members; `protected` / `private` members are inaccessible even when the extension shares the target's package.
- `self` is a borrowed view and does not additionally retain the target object; the target's lifetime is decided by its original holder.
- When a class extension method captures `self` in a closure, a strong hold is established per the closure-capture rules; the target's lifetime is kept by the closure environment.
- Struct extension methods follow struct write rules: write methods require assignable receivers; `self` must not be captured in closures.
- Extension methods create no extra objects, add no fields, and change no layout.
- Extension methods merge into the target type's static method set, do not enter the vtable, and do not allocate separately.
- Singleton/data-enum extension methods respect their immutability: data-enum fields are `final` and cannot be written.

### 11.4 Restrictions

- No extension fields, constructors, `deinit`, or static methods.
- No extending protocols, annotations, predefined types, or XDK types.
- No extending generic types; no generic extension methods.
- No cross-package extensions.
- No implementing protocols via extensions.
- Extension methods cannot share a signature with existing inherited methods and cannot be overridden.

## 12. annotation

### 12.1 Declaration

```x
@annotation Marker {
    final String name = "";
}
```

- An `@annotation` declares a compile-time annotation type; it generates no runtime objects.
- Annotations may declare only `final` fields; field types must be compile-time constant types: `Bool`, integers, `Float`, `Double`, `Char`, `String`, simple enums.
- Annotation fields must have compile-time-constant initializers.
- Annotations cannot have methods, constructors, `deinit`, static members, generic parameters, inheritance, or protocol conformance.
- Annotation fields occupy no runtime layout; annotation declarations produce no instances.
- Annotation types exist only at compile time; they cannot be `new`-ed or passed as values.

### 12.2 Usage

```x
@Marker
class Device { }
```

Annotation arguments support positional arguments only:

```x
@Marker("x")
class Device { }
```

- Usage forms: `@Name` or `@Name(arg1, arg2, ...)`; arguments bind in field-declaration order.
- Arguments must be compile-time constants; types must be assignable to the field types; omitted trailing fields use their declared initializers.
- Extra arguments are compile errors; intermediate fields cannot be skipped; named arguments are unsupported.
- Annotations may apply to type declarations, fields, methods, constructors, `deinit`, parameters, and enum items.
- Annotations cannot apply to expressions, type parameters, type arguments, or control bodies; the block-annotation semantics of `@tasks` / `@arena` are defined by Part 5 (§2.3).
- Unknown annotations are compile errors; annotations must resolve to same-package or imported `@annotation` types, or built-in annotations.
- Reusing the same annotation on one target is a compile error; `@Repeatable` has no effect in v3.0.0.
- Annotations do not affect control flow, layout, allocation, or reference counts; memory-strategy annotations are implementation-internal and outside the language's annotation system (15.1.2).

### 12.3 Built-in Annotations

| Annotation | Target | Enforced | Semantics |
| --- | --- | --- | --- |
| `@ReadOnly` | fields | yes | Externally read-only; writable within the declaring type |
| `@Override` | methods | yes | Must correspond to a same-signature protocol method; cannot mark superclass methods |
| `@WriteOnly` | fields | no | Recognized but not enforced |
| `@Target` | annotations | no | Recognized but not enforced |
| `@Retention` | annotations | no | Recognized but not enforced |
| `@Repeatable` | annotations | no | Recognized but not enforced |
| `@Deprecated` | declarations | no | Recognized but not enforced |
| `@SuppressWarnings` | declarations | no | Recognized but not enforced |
| `@tasks` / `@arena` | blocks | parsing | Semantics defined by the XDK task/memory specifications |
| `@Immediate` / `@NoAlloc` / `@Pure` / `@Sendable` | reserved | no | Reserved; do not change semantics |

The memory-strategy annotations `@arc` / `@gc` are not members of the language's annotation system; using them in source is a compile error. Their semantics as implementation-internal annotations are in 15.1.2; memory-strategy adjudication from source relies solely on the Section 15 decision table.

### 12.4 Memory and Restrictions

- Annotation usage allocates no memory, stays outside ARC/GC, and produces no runtime objects.
- An `@annotation` declaration is only a compile-time type; it generates no annotation instances.
- Language annotations only perform compile-time checks or recognition; `@arc` / `@gc` are implementation-internal annotations (15.1.2), outside the language's annotation system.
- Annotation fields produce no runtime storage; annotation arguments evaluate no runtime expressions.
- No reflection, runtime annotation queries, annotation processors, or code generation.
- No annotation inheritance, repeated annotations, default arguments, or named arguments.
- Annotations cannot change object layout.

## 13. Generic Types and Generic Methods

### 13.1 Declaration

```x
class Box<T> {
    T value;
}

struct Pair<A, B> {
    A first;
    B second;
}

class Util {
    U convert<U>(U value) {
        return value;
    }
}
```

- Generic classes/structs declare `<...>` type parameters after the type name.
- Generic methods declare `<...>` type parameters after the method name.
- Generic parameters are names only; no constraints, `where` clauses, default types, variadic parameters, or associated types.
- Type-parameter names are unique within one generic declaration; a method's type parameters must not clash with the enclosing class's.
- Generic classes may inherit generic superclasses or implement non-generic protocols.
- Generic structs do not participate in inheritance or protocols; every type argument must be a value-field type per 3.2.
- Protocols do not support generic parameters, generic methods, associated types, or intra-protocol type constraints.
- Singletons, enums, annotations, and extension targets do not support generics.
- Extension methods do not support generics (v3.0.0).
- Bare generic names erase to `Any`: `Box` equals `Box<Any>`.

### 13.2 Variance

Variance may be declared only on class generic parameters:

```x
class Producer<out T> { }
class Consumer<in T> { }
```

- `out T`: covariant. `Producer<Derived>` is assignable to `Producer<Base>`.
- `in T`: contravariant. `Consumer<Base>` is assignable to `Consumer<Derived>`.
- Unannotated type parameters are invariant; only identical arguments are compatible.
- Struct generic parameters are invariant; generic methods have no variance.
- Variance is meaningful only for reference-type arguments; value-type arguments have no subtyping and must be identical.

Position rules:

| Position | `out T` | `in T` | Invariant `T` |
| --- | --- | --- | --- |
| Method return type | allowed | forbidden | allowed |
| Method parameter type | forbidden | allowed | allowed |
| Constructor parameters | allowed | allowed | allowed |
| `final` fields | allowed | forbidden | allowed |
| Mutable fields | forbidden | forbidden | allowed |
| `T?` | preserved | preserved | preserved |
| `T[]` | forbidden | forbidden | allowed |
| `List<T>` / `Set<T>` / `Map<...,T>` | forbidden | forbidden | allowed |
| Generic argument `G<T>` | only when G's parameter is `out` | only when G's parameter is `in` | allowed |
| Function-type parameter position | forbidden | allowed | allowed |
| Function-type return position | allowed | forbidden | allowed |

Rules:

- Constructor parameters are not variance positions; construction checks by concrete arguments.
- `out T` may appear in return types and `final` fields; not in method parameters, mutable fields, arrays, or invariant containers.
- `in T` may appear in method parameters; not in return types or any fields.
- Mutable fields make the type parameter invariant.
- Variance conversions allocate no objects and change no representation; the compiler must verify layout and vtable-slot compatibility.
- Variance violations are compile errors; silent runtime conversions are forbidden.

### 13.3 Instantiation and Inference

```x
Box<Int> box = new Box<Int>(1);
Box<Int> inferred = new Box(1);
```

- Generic type-argument counts must match the declaration.
- `new` may write type arguments explicitly; when omitted they infer from the constructor arguments.
- When constructor arguments cannot uniquely determine the type arguments, write them explicitly.
- Type arguments cannot be `void` or unbound type parameters.
- Nested generics using `>>` parse as two `>`s; the lexer/parser must support this.
- `Box<Int>?` is an optional reference; for reference types `T?` and `T` are the same type.
- Generic class inheritance: `class Child<T> : Base<T>`, `class IntChild : Base<Int>`; superclass arguments must be concretized.
- A bare superclass `Base` is treated as `Base<Any>`.
- Generic classes implementing protocols: protocols are non-generic; method signatures must match exactly after type-argument substitution.
- Every concrete instance of a generic struct must satisfy 3.2: `Pair<Int, Int>` is legal, `Pair<String, Int>` is rejected because a field contains a reference type.
- A generic struct's type parameters must not be instantiated with non-value-field type arguments, even when the parameter does not appear in fields; structs provide no reference-fallback branch.

### 13.4 Monomorphization

- Generic types and methods monomorphize after type checking and before memory analysis.
- Each distinct type-argument list generates an independent type/function instance; instances have independent layouts and memory strategies; only conforming class instances generate protocol vtables.
- Residual type parameters after monomorphization are compile errors; uninstantiated templates do not enter memory analysis.
- Bare generics `Box` / `Box<Any>` erase to `Any`; when fields contain `Any`, the owner enters GC.
- When generic instance fields contain `Any` / protocols / undetermined types, the owner is analyzed as GC (15.1 rule 7).
- Generic methods generate functions per instance; local objects choose stack/ARC/GC by concrete type.
- Recursive monomorphization must terminate; infinite expansion is a compile error; implementations may use a depth cap but must diagnose exceeding it.
- Cross-package generic instantiation needs templates or intermediate representations; the toolchain must guarantee instantiation points can access generic bodies.
- No runtime type arguments; `is T` / `as T` check by concrete type after monomorphization.
- `new T()` is a compile error; `T` is not a runtime-constructible type.
- Static members cannot use the class's type parameters; `static T value` is a compile error.
- Generic closures are unsupported; use generic functions when generic behavior is needed.

### 13.5 Generic Memory

- Monomorphization precedes memory analysis; each instance is adjudicated independently.
- Every instance of a generic struct must contain value fields only; there is no "some arguments copyable, others not" branch.
- Generic-class fields with concrete references are analyzed by reference; with `Any` / protocols, as GC.
- Generic methods' locals choose strategies by concrete type.
- Protocol vtables are generated per conforming class instance; non-conforming instances have no vtable.
- Variance affects type-compatibility checks only; it changes neither layout nor reclamation strategy.

### 13.6 Restrictions

- No type constraints, `where` clauses, default type arguments, or variadic type parameters.
- No generic protocols, protocol generic methods, associated types, or intra-protocol type aliases.
- No generic singletons, enums, or annotations.
- No generic extension targets or generic extension methods.
- No generic structs using non-value-field type arguments.
- No generic closures.
- No `new T()`.
- No static members using class type parameters.

## 14. The Memory Form of Closures

### 14.1 Representation

A closure is neither a `struct` nor an ordinary function pointer, but a callable GC object:

```c
typedef struct {
    void* fn;
    void* env;
} xnull_closure;
```

- Function types (`Int()`, `Int(Int)`) are static types; the closure value is that type's runtime object.
- `fn` is a compile-time-generated lambda function pointer; all lambda functions carry an implicit `env` parameter.
- `env` is an independent GC block holding captured variables.
- Calling a closure first loads `fn` and `env`, then passes `env + arguments`.
- The closure object, `env`, and cells are all GC-managed.

### 14.2 Capture

| Closure Form | env Contents | Capture Mode | Memory |
| --- | --- | --- | --- |
| No captures | empty env | none | the closure object is GC; no extra variable storage |
| Captures locals | cell pointers | by reference | locals promoted to GC cells |
| Captures parameters | cell pointers | by reference | parameters promoted to GC cells |
| Captures class `self` | self handle | strong hold | env stores the instance handle; not promoted to a cell; structs forbidden |
| Nested closures | cell pointers | share outer cells | inner and outer closures share one cell |
| Task closures | env / capture graph | cross-thread sharing | the runtime performs shared marking; env is registered as an external root |

Rules:

- Locals, parameters, and `self` may be captured.
- Captured locals/parameters are promoted to GC cells; all later reads/writes go through the cell.
- After the closure returns, the outer variable remains valid, because the cell is held by the closure environment.
- Multiple closures capturing the same variable share one cell; mutations are mutually visible.
- No by-value capture syntax.
- Captured variables need not be `final`.
- Capturing `self` stores a strong hold; ARC objects are retained, GC objects traced; borrowed during the call. Struct methods cannot capture `self`.
- Capturing a struct variable stores the struct value in the cell; the outer variable and the closure share the cell; mutations are mutually visible but produce no object identity.
- Structs contain no reference fields, so closure environments never indirectly hold reference objects through struct captures.

### 14.3 Lifetime

- The closure object, `env`, and cells are all GC objects.
- Closure unreachable → env unreachable → captured ARC references released.
- Cycles between closures and env/cells are reclaimed by GC.
- When closures are returned, stored in fields, or in containers, GC keeps their environments alive.
- When closures enter `xdk.tasks`, the reachable-environment graph is shared-marked and env is a cross-thread root; removed at task dispose.
- Closure identity compares by reference; calling a `null` closure is a panic.
- When a class method captures `self` in a closure, the receiver cannot be stack-allocated and must be heap-allocated (ARC/GC); struct methods are forbidden from capturing `self`.
- When a closure environment holds reference fields, the environment itself is GC; on environment release its ARC references are released and GC references reclaimed by tracing.

### 14.4 Tasks

- Once a closure enters `xdk.tasks`, env is a cross-thread root; the runtime must guarantee env's reachability for the task's lifetime.
- At task dispose the root is removed; afterwards env is reclaimed per normal GC rules.
- `@Sendable` is retained in v3.0.0 but not enforced; the runtime performs no data-race checks.
- Objects shared across tasks must be synchronized by callers; the language provides no implicit thread safety.
- Singleton capture does not copy the instance; all tasks see the same global instance.

### 14.5 Calling Convention

- Closure call: load `fn` and `env`; check arguments against the function type; call `fn(env, args...)`.
- Non-capturing closures still carry the `env` parameter; `env` may be an empty block.
- Closures returning reference types pass per return-value rules; returning structs uses by-value/pointer + sret rules.
- Closures cannot be passed directly as C function pointers; crossing FFI requires explicit trampolines and lifetime contracts (see Part 7 §5).

## 15. Object Lifetime and Memory

### 15.1 Strategy Adjudication

Memory strategy applies only to `class` and `singleton`; `struct`s and simple enums are values and stay outside ARC/GC.

| Order | Condition | Strategy |
| ---: | --- | --- |
| 1 | `singleton` | GC global root |
| 2 | `protocol` | no instances; analyzed as GC |
| 3 | Simple `enum` | stack / inline integer |
| 4 | Data `enum` | GC |
| 5 | Class strong-reference fields containing `Any`, `Object`, protocols, unmonomorphized generics, tuples with reference elements, or `Result` in the current implementation | GC |
| 6 | Class strong references forming cycles | GC |
| 7 | Class methods capturing `self` or the class having `deinit` | ARC |
| 8 | Class with only value fields | class object is a stack candidate, promoted per 14.2 upon escape |
| 9 | All other acyclic class references | ARC |

Adjudication inputs come entirely from post-monomorphization source structure: kind, field-type graph, reference-cycle analysis, escape classification, `deinit` presence, `self` capture. Adjudication is deterministic; the same source program, implementation version, and compilation options must produce the same adjudication (DET-01).

#### 15.1.1 Adjudication Conservatism

- When a reference cycle contains at least one GC node, the cycle is reclaimed by GC; all-ARC strong-reference cycles are reclassified as GC by memory analysis.
- When analysis is incomplete or invisible boundaries exist (FFI, XDK calls, task submission), escape must be assumed.
- Adjudication must not silently accept unanalyzable objects; unanalyzable objects fall into GC.

#### 15.1.2 Internal Strategy Annotations (Within the Implementation Boundary, Non-Committed Entries)

`@arc` / `@gc` are retained as implementation-internal annotations:

- They must not appear in source; the language's annotation system (Section 12) does not include them — source usage is a compile error.
- For implementation preview and tuning experiments only: `@arc` means forced ARC (subject to the original conditions: `class`, concrete strong-reference fields, no cycles), `@gc` means forced GC.
- Non-committed entries: they are not language features, do not enter the acceptance matrix, and implementations may remove or change them in any version.
- Long-term tuning needs should be expressed through implementation-side compilation options (Memory Management spec §23), never solidified into source syntax.

Notes:

- Ordinary classes default to ARC/GC; pure-value, non-escaping local class objects may be stack-allocated.
- Structs are always values, copied per 3.3; there are no reference-fallback, ARC/GC, or `deinit` branches.
- Struct fields can only be 3.2's allowed value fields; reference fields, `Any`, protocols, function types, data enums, singletons, and classes cannot appear in structs.
- Classes with `deinit` are not stack-allocated.
- Generics monomorphize before memory analysis; each instance is adjudicated independently.

### 15.2 Escape Analysis

Escape analysis applies to class objects only; structs pass, return, and store by value — they never become references due to escape and are never heap-promoted.

An object escapes when any condition holds:

- It leaves the current function as a return value;
- It is stored into a field, static field, global field, or container;
- It is captured by a closure;
- It is passed to an unknown function, XDK boundary, or FFI;
- It is shared across tasks;
- It is assigned to a possibly-escaping variable.

Escape classification:

| Category | Meaning | Allocation Effect |
| --- | --- | --- |
| `none` | only local reads, field reads/writes, and conditions | stack-allocatable |
| `return` | leaves only as a return value | promoted to ARC; GC retained when fields already require GC |
| `other` | stored into containers/fields, closure-captured, passed as argument, reassigned | promoted to GC |

Stack allocation is an optimization and does not change language semantics: the object still has identity, references still point at the same object — only the lifetime is limited to the lexical scope. Once an object escapes, the compiler must switch to heap allocation and cannot copy the object.

### 15.3 Layout

Allocation header:

- All heap objects share a uniform allocation header: object kind (ARC / GC), type descriptor, ARC count or GC mark, scan information.
- The type descriptor serves `is` / `as`, protocol checks, and `Any` unboxing.
- Stack objects have no heap allocation header; the compiler must retain dynamic type information when `is` / `as` is needed, or omit it when statically provable.

Object payload:

- Conforming classes: the payload's start is a pointer to the protocol vtable; fields follow.
- Non-conforming classes: fields start at the payload's start, with no vtable pointer.
- Structs: fields start at the value-storage start, with no object header, vtable pointer, or ARC/GC header.
- Fields are 8-byte aligned; superclass fields first, subclass fields after.
- Scalar value fields occupy one 8-byte slot; struct fields are inlined, sized up to a multiple of 8; reference fields occupy one pointer slot.
- Tuple values are inlined: value elements occupy scalar or inline slots per their type; reference elements occupy pointer slots and are registered for scanning; tuples produce no object headers or vtable pointers.
- Simple enums occupy one slot as `Int`; data-enum items are GC objects.
- Closure objects are `{ fn, env }` — two pointers; `env` is a GC block.
- `Any` boxed objects contain the allocation header, type descriptor, and value payload.

vtable:

- The vtable holds only protocol method slots; the same signature maps to the same slot program-wide; inherited implementations reuse slots; new protocols append slots.
- Ordinary class methods, static methods, constructors, `deinit`, and extension methods never enter the vtable.
- Slot assignment must be deterministic; cross-module ABI needs stable slot rules.
- The vtable header does not decide ARC/GC; the reclamation strategy is decided by the allocation header and the type's strategy.

### 15.4 ARC

- ARC objects carry reference counts; retain increments, release decrements.
- At count zero: clear weak references → call `deinit` → release reference fields → reclaim memory.
- ARC objects may hold ARC references and GC references; ARC references are managed by retain/release; GC references are kept through the mixed-graph rules.
- Weak references do not increase counts; they are set to `null` when targets are released; weak operations must be atomic under concurrency.
- ARC cycles are avoided by memory analysis: when a cycle is detected, GC is used.
- ARC counts must be atomic under task concurrency; single-threaded implementations may optimize to non-atomic.
- When ARC objects are global roots or stack roots, their GC reference fields must be scanned by GC.

### 15.5 GC

- GC uses mark–sweep; object lifetimes are decided by reachability.
- Roots include: stack slots, top-level/static fields, singletons, closure envs, task external roots, ARC scan lists.
- GC objects may hold GC references and ARC references; GC references are traced; ARC references are released when objects die.
- Reference cycles are reclaimed by GC; GC objects' `deinit` runs at sweep, at an uncertain time.
- GC may trigger at allocation points or safepoints; implementations may use generational/incremental strategies, but roots and write barriers must remain correct.
- GC does not guarantee `deinit` at process exit; critical resources must be explicitly closed.

### 15.6 The Mixed Reference Graph

Invariants:

1. Every strong reference either increments an ARC count or is traced by GC; no strong reference is neither counted nor traced.
2. When an ARC object holds GC references, that ARC object is registered as a GC-scan object while alive; GC treats its GC reference fields as roots.
3. When a GC object holds ARC references, GC marks the ARC targets reachable; when the GC object dies it releases those ARC references.
4. Weak references do not increase counts and do not prevent reclamation; they are cleared when targets die.
5. A cyclic strong-reference graph containing at least one GC object is reclaimed by GC; all-ARC strong-reference cycles are avoided or rejected by analysis.
6. ARC objects clear their GC references on release to avoid dangling; GC objects release their ARC references at sweep to avoid leaks.

Correctness conditions:

- No premature release: ARC targets are not released before count zero; GC targets are not swept before unreachability.
- No dangling: weak references clear when targets die; strong references always prevent release.
- No leaks: GC reclaims cycles; ARC references are released at GC sweep.
- No double release: after an ARC field is set to `null` it is not released again; GC sweep processes only still-live references.

### 15.7 Lifetime and deinit

- Allocation: zeroed; the allocation header and type descriptor installed; conforming classes install the protocol vtable.
- Construction: superclass construction → field initialization → constructor body.
- Publication: after construction completes, `self` may escape.
- Use: reference counts or GC reachability keep the object.
- Release: ARC count zero or GC sweep.
- `deinit`: weak references cleared first; derived class to superclass; fields released after the chain completes.
- Resurrection forbidden: `deinit` must not store `self` into globals/containers/closures, nor return `self`.
- Process exit: singletons and global objects are not guaranteed `deinit`; explicitly close resources.
- `panic` / `throw`: no stack unwinding, no `deinit` guarantee; the process terminates.

### 15.8 Weak References (Runtime-Internal Mechanism)

The language and XDK public APIs provide no weak references; source has no `weak` modifier or weak-reference types. The weak table is retained as a runtime-internal mechanism:

- The weak table is maintained by the runtime; entries are open only to the FFI contract layer and runtime internals (see the Memory Management spec §16, §19, §22).
- Weak references do not increase reference counts; they are removed from the weak table before target finalization.
- Weak operations must be atomic, avoiding reads of finalized targets.

Replacement patterns for former `weak` field scenarios:

- Tree / parent-child bidirectional references: use direct bidirectional strong references; when strong-reference cycles appear, the owner falls into GC per Section 15.1 and the cycle will not leak.
- Observers / listeners: an event list + explicit deregistration; or ID + registry resolution where the target may be gone — return `null` / `Err` for the caller to handle explicitly.
- Caches: strong references + explicit invalidation policies (capacity, expiry); cache semantics stay explicit.

### 15.9 Threads and Sharing

- ARC counts must be atomic under task concurrency; single-threaded implementations may optimize to non-atomic.
- GC uses safepoints and root scanning; implementations may pause all mutators.
- Runtime-internal weak-table operations must be atomic, avoiding reads of finalized targets.
- Concurrent reads/writes of object fields are unsynchronized; data races are program errors and this document defines no results for them.
- Cross-task closure envs are registered as external roots; removed at task dispose.
- Singletons and static fields complete initialization before `main` — publication is safe.
- `@Sendable` is retained in v3.0.0 but not enforced; use `xdk.sync` when thread safety is needed.

### 15.10 Memory Diagnostics

Compile time must report:

- Residual type parameters from generic monomorphization;
- Struct recursive value containment or reference fields;
- Structs using non-value-field-type generic arguments;
- Source usage of the memory-strategy annotations `@arc` / `@gc`;
- External access to private fields (both `name` and `_name` rejected), `private` combined with the `_` prefix, `self._name` inside the class, base-name access to private fields inside the class, same-class locals/parameters reusing `_name`, field hiding, duplicate chain base names;
- Subclasses declaring instance methods with ancestors' signatures;
- Protocol fields, protocol method bodies, generic protocols, associated types, or protocol generic methods;
- Missing protocol implementations or signature mismatches;
- Enum `switch`es missing, duplicating, or containing unknown items;
- Factories accessing non-public members cross-package, or binding invisible Targets;
- `final` fields assigned twice or not assigned;
- `self` escaping before construction completes;
- Non-`void` methods missing returns;
- Illegal extension targets, duplicate methods, or same-signature conflicts;
- Illegal annotation targets, arguments, or types.

Runtime must report:

- Allocation failures, stack overflow;
- Null-reference dereference;
- Array/List/Set subscript out-of-bounds;
- Type-cast failures (`as`);
- Integer division by zero, out-of-range shifts;
- Explicit `throw`.

`xdk.runtime` may provide allocation statistics, GC metrics, and leak diagnostics; these are not part of language semantics.

## 16. Implementation Boundary

This section defines v3.0.0's release gates, not a capability-gap list. Every item below must be implemented in the compiler, runtime, and LSP; any item failing blocks the build from claiming conformance to this specification. Implementations must not substitute compile-time checks with "accept first, diagnose later," silent degradation, runtime fallbacks, or documentation claims.

| ID | Release Gate | On Failure |
| --- | --- | --- |
| BND-01 | Member-level `public` / `protected` / `private` visibility fully enforced; cross-package per top-level and member rules | Compile error; reporting "not yet implemented" is forbidden |
| BND-02 | Class inheritance reuses fields/methods only; subclass same-signature methods, field hiding, `abstract` instantiation, inheriting `final` classes all rejected | Compile error |
| BND-03 | Class-typed receivers statically dispatched; only protocol-typed receivers go through vtables; memory strategy does not affect vtables; constructors, `deinit`, `super` statically dispatched | Behavioral deviation from Section 5 fails |
| BND-04 | Structs contain only 3.2 value fields; reference instance fields, `deinit`, captured `self`, non-value-field-type generic arguments all rejected | Compile error |
| BND-05 | Protocols have method signatures only; fields, method bodies, default implementations, generic protocols, associated types, protocol generic methods, constraints all rejected; implementation checks cover parent protocols | Compile error |
| BND-06 | Enums do not implement protocols; enum `switch` checks exhaustiveness, duplicates, unknown items, and `default` placement per 8.5 | Compile error |
| BND-07 | Singletons do not inherit, implement protocols, or `new`; `instance` read-only and a GC root | Compile error |
| BND-08 | Factories bind same-package or cross-package; same-package gains private-constructor access; cross-package accesses public members only; Target must be visible; factories are not types | Compile error |
| BND-09 | Private fields written only as `private name` or `_name`; `private _name` rejected. Canonical name `_name`, only the bare `_name` inside the class, `self._name` and bare `name` both rejected; external `name` and `_name` both rejected; fields unique per base name along the chain | Compile error |
| BND-10 | Memory strategy decided by the 15.1 decision table; source use of `@arc` / `@gc` rejected; the mixed reference graph satisfies the 15.6 invariants | Compile error or runtime-invariant failure |
| BND-11 | Structs copied by value; class object identity unchanged by optimization; vtables contain only protocol slots; address + sret ABI must not expose shared identity | Behavioral deviation from Sections 3, 5, 15 fails |
| BND-12 | Generics monomorphized before memory analysis; residual type parameters, generic protocols, generic structs' non-value-field-type arguments all rejected | Compile error |
| BND-13 | Extensions only for same-package non-generic targets; methods only; never enter vtables; must not serve as protocol implementations or override existing methods | Compile error |
| BND-14 | All forbidden constructions must produce diagnostics with source locations; the compiler must not crash, silently accept, or fail only at runtime | The negative case fails |
| BND-15 | Part 1 v3.0.0's `Result` / `try`, `defer` / `errdefer`, `new T[count]`, labeled control, and enum exhaustiveness integration passes acceptance | Integration acceptance fails |

Implementations may internally adopt different layouts, slot numbering, and optimization strategies, but must satisfy the observable semantics above. Acceptance must include positives, negatives, and cross-package cases; negatives must assert specific diagnostics, never merely "compilation failed."

## 17. Object-Oriented Keyword Memory Summary

### 17.1 Type Keywords

| Keyword | Memory Semantics | Dispatch |
| --- | --- | --- |
| `class` | Reference type; ARC/GC; non-escaping pure-value local objects may be stack-optimized; reference semantics unchanged | Static for class types; dynamic for protocol types |
| `struct` | Pure value type; copied by value and inlined; outside ARC/GC | Static |
| `protocol` | Method signatures only; no instances; protocol variables are strong-holding views of concrete objects; implementers carry a protocol vtable header | Dynamic (implementers' vtable) |
| Simple `enum` | Inlined as integer; no allocation, outside ARC/GC | Static |
| Data `enum` | Items are GC objects; items are global roots; no ARC counts | Static |
| `singleton` | `instance` is a global GC root persisting for the process lifetime; implements no protocols | Static |
| `factory` | No instances, no layout, no ARC/GC; may bind Targets cross-package; declares only static factory methods | Static |
| `extension` | Adds no fields, changes no layout, creates no objects; methods merge into the static method set | Static |
| `@annotation` | Compile-time type only; generates no runtime objects and allocates no memory | N/A |

### 17.2 Members and Modifiers

| Keyword | Memory Semantics |
| --- | --- |
| `static` | Type-level member, independent of `self`; reference fields are global roots; not an instance-ownership unit |
| `public` / `protected` / `private` | Compile-time visibility only; changes neither layout, ARC/GC, nor retain/release; `private` fields and `_name` private fields produce no extra storage; canonical name `_name`, used as `_name` inside the class |
| `final` | Compile-time restriction; fields/variables bind once; class methods are non-overridable anyway — method-level `final` is redundant |
| `abstract` | Classes only; the type has no instances; abstract methods unsupported; no extra allocation |
| `deinit` | Class/singleton only; allocates no extra objects; called at ARC count zero or GC sweep; for releasing fields/resources |

### 17.3 Usage and Access

| Keyword | Memory Semantics |
| --- | --- |
| `new` | Allocates per the type's strategy: stack / ARC / GC; `struct` yields a value, `class` a reference object; enums/protocols/singletons cannot be `new`-ed |
| `self` | A borrowed view of the current instance or value storage; struct methods' capture restricted; no extra retain |
| `super` | A borrowed view of superclass construction/members; creates no superclass copies; static dispatch |
| `implements` | Protocol-conformance relation available only to classes; introduces a protocol vtable header; changes no field-ownership strategy |
| `instance` | An implicit read-only field owned only by `singleton`s; a global root persisting for the process lifetime |

### 17.4 Annotations and Generics

| Keyword | Memory Semantics |
| --- | --- |
| `@arc` / `@gc` | Implementation-internal annotations (15.1.2); must not appear in source; not members of the language's annotation system |
| `@ReadOnly` | Compile-time write restriction; changes neither layout nor reclamation strategy |
| `@Override` | Checks protocol-method implementation only; cannot mark superclass methods; no memory effect |
| Other annotations | Recognized only; change no layout, allocation, or reference counts |
| Generic types / methods | Monomorphized before memory analysis; each concrete instance has independent layout and strategy; residual `T` errors; bare generics erase to `Any` and may enter GC; generic protocols and associated types unsupported |

### 17.5 Summary

- Only `class` / `struct` / data `enum` / `singleton` produce actual type objects or their values.
- `protocol`, `factory`, `extension`, `@annotation`, `@Override`, and visibility modifiers produce no independent objects.
- A `factory` has no layout or lifetime, providing only static creation methods; created class objects are reclaimed per class strategy, struct returns copied by value.
- What actually decides a class's reclamation: the field graph, reference cycles, presence of `Any` / protocols, escape, presence of `deinit`, and `self` capture.
- Structs stay outside ARC/GC; reference instance fields, `deinit`, and captured `self` are all forbidden.
- Simple enums are integers; data enums and singletons are GC; protocols provide only method signatures and holding views; class types dispatch statically, protocol types dynamically.
- An enum `switch` without `default` must exhaust all enum items; non-enum `switch` requires no exhaustiveness.

## 18. Acceptance

| ID | Verification Point | Pass Condition |
| --- | --- | --- |
| TYPE-01 | Nominal types | Same members, different declarations incompatible; import aliases do not change identity; different generic arguments are different types |
| INH-01 | Inheritance and interfaces | Single superclass, multiple protocols; illegal `:` / `implements` rejected; inheritance and protocol cycles rejected; subclass same-signature methods rejected |
| DISP-01 | Dispatch | The class-inheritance example statically yields `1`; the protocol example dynamically yields `2`; memory strategy does not affect vtables; `super` statically dispatched |
| STRUCT-01 | Structs | Only value fields accepted; reference fields, optional reference fields, `deinit`, captured `self`, non-value-field-type generic arguments rejected; copies independent; recursive value containment rejected |
| PCTOR-01 | Primary constructors | Class-header parameters bind same-named fields and run in declaration order after `super(...)`; `final` fields assigned exactly once; mixing with non-primary constructors, non-`final` parameters, non-`class` use all rejected |
| PROTO-01 | Protocols | Method signatures only; fields/method bodies/default implementations/generic protocols/associated types/protocol generic methods rejected; implementation checks cover parent protocols; protocol variables strongly hold and call only protocol methods |
| ENUM-01 | Enums | Simple-enum values unique, inlined, allocation-free; data-enum items singletons, GC, immutable; enums implement no protocols; `switch` without `default` exhausts all items; duplicate/unknown items rejected |
| FACTORY-01 | Factory types | Same-package Targets access private constructors; cross-package Targets access public members only; invisible cross-package Targets rejected; generic bare names, return constraints, non-type usage, illegal declarations rejected |
| INT-01 | v3.0.0 integration | `Result` / `try` / `defer` semantically correct when combined with object types and factories; enum-`switch` exhaustiveness rules correct |
| SINGLE-01 | Singletons | `instance` auto-provided and read-only; no `new`; no protocol implementation; initialization completes before startup; forward references rejected |
| EXT-01 | Extensions | Same-package non-generic targets; methods only; duplicate/same-signature/protocol-implementation violations rejected; extensions do not enter vtables |
| ANN-01 | Annotations | Compile-time fields and parameters; target restrictions; no runtime objects; `@Override` corresponds to protocols only; source use of `@arc` / `@gc` rejected |
| GEN-01 | Generics | Monomorphization, variance positions, bare-generic erasure, recursive termination; generic protocols/associated types/generic structs' non-value-field-type arguments rejected |
| MEM-01 | Memory | Class strategy-adjudication order correct; source use of `@arc` / `@gc` rejected; structs stay outside ARC/GC; stack/ARC/GC behavior per 15; `deinit` order correct |
| MEM-02 | Mixed graph | ARC↔GC references neither dangle nor leak; weak references cleared; cycles reclaimed by GC; all-ARC cycles avoided |
| TUPLE-01 | Tuple memory | All-value-element tuple fields legal and inlined-copied; reference-element tuple `struct` fields rejected; in classes that field makes the type GC (15.1 rule 5) |
| FIELD-01 | Field access | `private name` and `_name` fields both treated as private, `private _name` rejected; canonical name `_name`, only the bare `_name` inside the class, `self._name` and bare `name` both rejected; external `name` / `_name` both rejected; same-class locals/parameters using `_name` rejected; field hiding rejected |
| GATE-01 | Release gates | All gates of Section 16 pass; negatives assert diagnostics; no silent degradation |
| NEG-01 | Negatives | Every forbidden construction has a diagnostic; the compiler never crashes or silently accepts |
| DET-01 | Determinism | Same source, implementation version, and options produce identical layout decisions, slots, and run results |

## Appendix A: Type-Declaration Grammar

This appendix uses EBNF; `{ X }` means zero or more, `[ X ]` optional. The base expression and statement grammars are in Part 1 Appendix A.

```ebnf
TypeDecl          = { Annotation } { TypeModifier } TypeDeclBody ;
TypeModifier      = "public" | "protected" | "private" | "abstract" | "final" ;
TypeDeclBody      = ClassDecl | StructDecl | ProtocolDecl | EnumDecl
                  | SingletonDecl | FactoryDecl | ExtensionDecl | AnnotationDecl ;

ClassDecl         = "class" Identifier [ GenericParams ]
                    [ "(" ParamList ")" ]
                    [ ":" TypeRef ]
                    [ "implements" TypeRef { "," TypeRef } ]
                    "{" { Member } "}" ;
StructDecl        = "struct" Identifier [ GenericParams ]
                    "{" { Member } "}" ;
ProtocolDecl      = "protocol" Identifier
                    [ ":" TypeRef { "," TypeRef } ]
                    "{" { ProtocolMember } "}" ;
EnumDecl          = "enum" Identifier "{" EnumBody "}" ;
EnumBody          = [ EnumItem { "," EnumItem } [ ";" ] ] { Member } ;
EnumItem          = { Annotation } Identifier
                    [ "(" [ ArgList ] ")" | "=" [ "-" ] IntegerLiteral ] ;
SingletonDecl     = "singleton" Identifier "{" { Member } "}" ;
FactoryDecl       = "factory" Identifier "for" TypeRef "{" { FactoryMember } "}" ;
FactoryMember     = { Annotation } [ "public" | "protected" | "private" ] "static"
                    Type Identifier [ GenericParams ]
                    "(" [ ParamList ] ")" Block ;
ExtensionDecl     = "extension" TypeRef "{" { ExtensionMember } "}" ;
AnnotationDecl    = "@annotation" Identifier "{" { AnnotationField } "}" ;

Member            = { Annotation } { MemberModifier }
                    ( FieldDecl | MethodDecl | ConstructorDecl | DeinitDecl ) ;
MemberModifier    = "public" | "protected" | "private" | "static"
                  | "final" | "const" ;
FieldDecl         = Type Identifier [ "=" Expression ] [ ";" ] ;
MethodDecl        = Type Identifier [ GenericParams ]
                    "(" [ ParamList ] ")" Block ;
ConstructorDecl   = Identifier "(" [ ParamList ] ")" Block ;
DeinitDecl        = "deinit" "(" ")" Block ;

ProtocolMember    = ProtocolMethod ;
ProtocolMethod    = { Annotation } Type Identifier
                    "(" [ ParamList ] ")" ";" ;
ExtensionMember   = MethodDecl ;
AnnotationField   = "final" Type Identifier "=" Expression [ ";" ] ;

GenericParams     = "<" GenericParam { "," GenericParam } ">" ;
GenericParam      = [ "out" | "in" ] Identifier ;
TypeArgList       = TypeRef { "," TypeRef } ;
ParamList         = Param { "," Param } ;
Param             = { Annotation } [ "final" ] Type Identifier ;
Annotation        = "@" Identifier [ "(" [ ArgList ] ")" ] ;
ArgList           = Expression { "," Expression } ;

Type              = TypeRef ;
TypeRef           = PrimaryType { "[]" | "?" } ;
PrimaryType       = FunctionType | NamedType | TupleType ;
FunctionType      = ReturnType "(" [ TypeRef { "," TypeRef } ] ")" ;
ReturnType        = "void" | NamedType | TupleType ;
TupleType         = "(" TypeRef "," TypeRef { "," TypeRef } ")" ;
NamedType         = QualifiedName [ "<" TypeArgList ">" ] ;
```

The expression grammar inherits Part 1 Appendix A; the `new` expression is already defined in Part 1's `PrimaryExpr` and is not repeated here. Tuple types, tuple literals, and element-access grammar are in Part 1 Appendix A.

Grammar notes:

- `ProtocolDecl`'s `:` accepts only protocols; `ClassDecl`'s `:` accepts only classes; semantic checks must reject the wrong kind.
- `StructDecl`, `EnumDecl`, `SingletonDecl`, `ExtensionDecl`, and `AnnotationDecl` accept neither `:` nor `implements`; the grammar lists no such branches.
- `EnumItem`'s three forms are mutually exclusive; one enum must use a uniform form; simple-enum items cannot carry constructor arguments, and data-enum items cannot carry `= value`.
- `MethodDecl` must have a `Block`; class methods cannot omit bodies. `abstract` is not a `MemberModifier` — `abstract` methods in class declarations are rejected by the grammar.
- `ProtocolMember` accepts only `ProtocolMethod`; protocol fields, method bodies, and default implementations are rejected by the grammar. Protocol methods end with `;`.
- `ExtensionDecl` accepts only methods; fields, constructors, `deinit`, and static methods are rejected by the grammar; semantic checks additionally reject generic targets and generic methods.
- `FactoryDecl`'s Target must be a `class` / `struct` visible in the current or a cross-package scope; generic targets use the bare type name, and type arguments are rejected by semantic checks. Cross-package Targets gain no private-member access through the factory relation.
- `FactoryMember` must be a `static` method; fields, constructors, `deinit`, instance methods, superclasses, and protocol conformance are rejected by grammar or semantic checks.
- A `factory` is not a type; it cannot be used in variables, parameters, fields, generic arguments, `new`, or `is` / `as`. `FactoryDecl` accepts only visibility modifiers — `abstract` / `final` etc. are rejected by semantic checks.
- `AnnotationDecl` accepts only `final` fields; constant restrictions on field types and initializers are enforced by semantic checks.
- `GenericParam`'s `out` / `in` are allowed only on `ClassDecl`'s type parameters; other positions are rejected by semantic checks.
- `ProtocolDecl` does not support `GenericParams`, associated types, or protocol generic methods; the grammar lists none.
- `ClassDecl`'s header `( ParamList )` is the primary constructor: parameters must be `final` (enforced by semantic checks) and each simultaneously declares a same-named field; classes with primary constructors cannot declare other constructors; only `class` is supported — header parameter lists on `struct` / `singleton` / `enum` / `factory` are rejected by the grammar.
- `SingletonDecl`, `EnumDecl`, and `AnnotationDecl` do not support `GenericParams`; the grammar lists none.
- `StructDecl`'s field restrictions are enforced by semantic checks; reference fields, optional reference fields, `deinit`, and captured `self` must be rejected; optional value fields are allowed but must not form recursive value containment. Source occurrences of `weak` or `@arc` / `@gc` are rejected by grammar or semantic checks.
- `FieldDecl` fields named in `_name` form or declared as `private name` are treated as private; `private _name` is rejected by semantic checks. The canonical name is `_name`; only the bare `_name` inside the class — `self._name` and the bare `name` are rejected by semantic checks. Same-class locals, parameters, or type parameters using `_name` are also rejected. `public` / `protected` combined with `_name` is rejected by semantic checks; field names are uniqueness-checked by base name along the inheritance chain.
- `TypeRef`'s `[]` / `?` semantics match Part 1 Appendix A; `T?[]` is "array of optional T", `T[]?` is "optional array".
- Constructions the grammar accepts but that violate semantic rules must be rejected at type checking.
