# XNull Solution Part 2: Object Programming

| Item | Value |
| --- | --- |
| Document number | Part 2 (S2) |
| Document version | 3.4.0 |
| Specification status | Formal |
| Release date | 2026-11-15 |
| Intended audience | XNull language implementations |
| Related parts | Part 1 v3.4.0; Part 3 v3.2.0 |

Versioning rules: revision numbers are used for clarifications that do not change semantics, minor versions for backward-compatible additions, and major versions for breaking changes. See the git history for past versions.

Revision note: 3.4.0 (2026-11-15) retains only the object programming standard; implementation status is not part of this document.

## Decision Summary

- Types are checked by nominal identity; see 0.4 for object kinds and dispatch rules.
- Plain classes use static inheritance: a subclass only reuses the parent's fields and methods and cannot override them; polymorphism is achieved only through protocols.
- Structs have only value semantics: they may carry only value fields, and reference fields, `deinit`, and capturing `self` are forbidden; use `class` when reference semantics, identity, or sharing is required.
- Protocols contain only method signatures; protocol fields, method bodies, default implementations, generic protocols, associated types, generic methods, and constraints are forbidden.
- Data enum cases are unique instances within the process; simple enums are integer values; singletons are unique instances within the process; no enum or singleton implements protocols.
- `switch` over an enum is checked for exhaustiveness: without `default`, all cases must be covered; with `default`, the requirement is waived.
- Source code does not express reference strength, addresses, pointers, or memory policies, and there are no `weak` modifiers or memory policy annotations.
- Generics are instantiated by type arguments; `out` / `in` are used only on classes; a bare generic is treated as `Box<Any>`.
- `factory` is an instance-free creation namespace that can bind to a `class` / `struct` in the same package or across packages; within the same package it retains access to the target's private constructors, while across packages it may use only the target's public members.
- The canonical internal name of a private field is uniformly `_name`. There are only two declarations, `Int _name` and `private Int name`, and they map to the same field; `private Int _name` is a compile error. Inside the class only the bare `_name` may be written; `self._name` and the bare `name` are both illegal, and local variables/parameters must not have the same name as `_name`. External access to either `name` or `_name` reports a private access error.
- Tuples are the built-in value type of Part 1, 2.11; a tuple whose elements are all values may be used as a `struct` field, whereas a tuple field containing reference elements cannot be a `struct` field.
- No accessor pattern: fields are read and written directly; getter/setter accessor patterns and property syntax are forbidden (7.3); computation and validation use verb methods.
- Primary constructor (6.3): `class Worker(final Int id)` declares fields and a constructor in the class header, with parameters bound to same-named fields; `class` only, and it is not mixed with other constructors.
- Unified function rules: methods follow the same set of explicit function rules as top-level functions, constructors, and lambdas (Part 1, 7.10).

## 0. Specification Basis

### 0.1 Scope

This Solution specifies the XNull object model: type declarations, inheritance, protocols, structs, enums, singletons, factory types, extensions, annotations, generic types and methods, member resolution, dispatch, and object lifetimes.

This Solution does not specify:

- Lexical structure, basic types, expressions, statements, closure syntax, packages and imports, and the entry point; see Part 1.
- The basic semantics of `Result`, `try`, and `defer` / `errdefer`; see Part 1, Section 10.
- Error observation, cancellation, timeouts, and `ErrorKind` policies; see the Error Handling specification.
- C ABI, IPC, and cross-language ownership; see Part 7.
- Object memory policies and storage layout; see Part 3.

### 0.2 Relationship with Part 1

Part 1 defines the basic syntax and type system; this Solution adds on top of it:

- Type declarations and object identity;
- The boundary between value semantics and reference semantics;
- Static inheritance of plain classes and protocol polymorphism;
- Protocol method signature contracts and implementation checking;
- The factory creation namespace, same-package private constructor access, and cross-package public construction;
- Generic type instantiation and variance;

This Solution uses Part 1's rules for type assignability, expressions, statements, closures, and the entry point. Where the two conflict, this Solution's specific provisions on object semantics prevail; basic syntax continues to follow Part 1.

### 0.3 Normative Language and Conformance

**MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used with RFC 2119 semantics.

An implementation MUST accept every source program that satisfies the "MUST" clauses of this Solution and produce the observable behavior specified by this Solution; source programs that violate "MUST NOT" clauses MUST be rejected with a diagnostic that includes a source location.

An implementation MAY provide extensions, but extensions MUST be explicitly enabled; default builds MUST NOT depend on extensions. The same source program, the same implementation version, and the same options MUST produce the same diagnostics and runtime results.

### 0.4 Object Model Summary

| Kind | Instance | Inheritance | Protocol implementation | Dispatch | Identity |
| --- | --- | --- | --- | --- | --- |
| `class` | Reference object | Single parent class; field/method reuse only | Allowed | Static for class-type receivers; dynamic for protocol-type receivers | Yes |
| `struct` | Value | Forbidden | Forbidden | Static | No |
| `protocol` | None | Inherits protocols | Not applicable | Dynamic | No |
| Simple `enum` | Integer value | Forbidden | Forbidden | Static | No |
| Data `enum` | Enum case object | Forbidden | Forbidden | Static | Yes |
| `singleton` | Unique global instance | Forbidden | Forbidden | Static | Yes |
| `factory` | None | Forbidden | Forbidden | Static methods | No |
| `extension` | None | Forbidden | Forbidden | Merged into the target type; static invocation | No |
| `@annotation` | None | Forbidden | Forbidden | Not applicable | No |

Only `class`, `struct`, data `enum`, and `singleton` produce actual objects or values. `protocol`, `factory`, `extension`, and `@annotation` do not produce independent objects. Class inheritance of `class` does not produce class-hierarchy polymorphism; dynamic dispatch is used only when calling through a protocol type.

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

- Type declarations can only be at package top level; nested types, local types, and anonymous types are not supported.
- The declaration prefix consists of annotations and modifiers, in the order `{ Annotation } { Modifier }`.
- Type names and `factory` names are unique within a package; they MUST NOT conflict with predefined type names, other type names, `factory` names, or type parameters.
- A file MAY declare multiple types; declaration order does not affect visibility.
- Type declarations MAY forward-reference each other; see 1.5 for recursion limits.
- Using `PascalCase` for type names is the canonical style, but naming does not participate in semantics.
- The `{` of a type header, `factory` header, method header, constructor header, and `deinit` header MUST be on the same line as the header; a line break triggers automatic semicolon insertion.

### 1.2 Type Kinds

| Keyword | Semantics | Instantiable | Usable as a parent type |
| --- | --- | --- | --- |
| `class` | Reference type; single inheritance reuses fields/methods, can implement protocols | `new` | Yes |
| `struct` | Pure value type; contains only value fields, copyable | `new` | No |
| `protocol` | Nominal method signature contract | No | Yes (protocol inheritance) |
| `enum` | Closed enum; simple enum or data enum | No | No |
| `singleton` | Preloaded unique instance | No | No |
| `factory` | Creation namespace bound to a target type | No | No |
| `extension` | Adds methods to an existing type | No | No |
| `@annotation` | Compile-time annotation type | No | No |

### 1.3 Nominal Types and Type Identity

- Types are checked by declaration identity, not structural matching. Two classes are incompatible even if their fields and methods are exactly the same.
- Type identity is determined by "declaration + type argument list"; import aliases do not change identity.
- Two same-named types MUST NOT be declared in the same package; same-named types in different packages are different types.
- Different argument lists of a generic type are different types: `Box<Int>` and `Box<String>` differ.
- Variance conversions hold only when the declaration permits them; otherwise generic types are invariant.
- A type parameter is a type only inside its declaration; it cannot be referenced outside the declaration.
- A bare generic name `Box` is equivalent to `Box<Any>`; this is erasure, not an "unknown type".
- Class inheritance only reuses fields and methods and does not establish overridable dynamic type slots; a subclass method cannot override a same-signature parent method.
- Protocols are the only entry point for polymorphism; only protocol-type receivers select implementations by runtime type.
- Member access uniformly uses dot syntax: `.` and `?.`; there is no `->`, address-of operator, pointers, smart pointers, or dereference syntax. "Reference" in this Solution refers only to the object model's implicit handle/holding semantics; see Part 1, 0.7.
- Source code has no concept of weak references, address-of operators, pointers, or reference strength; memory reclamation is the runtime's responsibility and is not a source-level type.
- `factory` is a creation namespace, not a value type or reference type; it MUST NOT appear in variables, parameters, fields, generic arguments, `is` / `as`, or `Object`.

### 1.4 Declaration Location and Order

- Type declarations and `factory` MUST be at package top level; they MUST NOT be written inside function bodies, control bodies, classes, or other types.
- Declaration order within a package is irrelevant; types, functions, and fields MAY reference each other.
- Cross-package references MUST go through `import` or a fully qualified name.
- Type visibility is specified by Part 1, 4.5 and this Solution, 7.3.

### 1.5 Recursive Types

- Reference recursion is permitted: `class Node { Node? next; }`.
- Container recursion is permitted: `class Tree { Tree[] children; }`.
- Value-containment recursion is forbidden: `struct S { S value; }` and `struct S { S? value; }` both have infinite size and MUST be reported as errors.
- A struct cannot break recursion through containers, reference fields, or nullable fields; use `class` when a recursive structure is needed, for example `class Node { Node? next; }`.
- Inheritance cycles are forbidden: `class A : B` together with `class B : A` is a compile error.
- Protocol inheritance cycles are forbidden.
- Recursive generic instantiation MUST terminate; the compiler MUST detect infinite expansion and report an error.

### 1.6 Modifiers

| Modifier | Applicable position | Semantics |
| --- | --- | --- |
| `public` | Types, members | Public; default visibility |
| `protected` | Types, members | Accessible within the type and its subclasses; at top level equivalent to `private` |
| `private` | Types, members | Accessible only within the declaring type |
| `abstract` | Classes | Class cannot be instantiated; an abstract class cannot declare abstract methods |
| `final` | Classes, methods, fields, local variables, parameters | Class cannot be inherited; method cannot be overridden; field/binding is assigned only once |
| `static` | Members, top-level functions | Type-level member, independent of instances |
| `const` | Top-level fields, static fields | Compile-time constant; implicitly `static`; occupies no instance field |
| `var` | Local variables | Type inference; not a field modifier |
| `out` / `in` | Generic parameters of classes | Covariant / contravariant; see 13.2 |

Combination rules:

- An `abstract final` class is illegal.
- `abstract` can only modify classes; methods cannot be written `abstract`, and all class methods MUST have a method body.
- Class methods are non-overridable by default; method-level `final` is legal but redundant and does not change dispatch.
- A `final` class cannot be `abstract`.
- `static` methods cannot use `self` / `super`.
- The language provides no weak reference modifier.
- The canonical internal name of a private field is uniformly `_name`. There are only two declaration forms, and they map to the same field:
  - `Int _name;`: declared name `_name`, canonical name `_name`;
  - `private Int name;`: declared name `name`, canonical name `_name`.
- `private Int _name;` is a compile error: `private` and the `_` prefix MUST NOT be used together.
- In a `_name` declaration, name MUST be lowerCamelCase; `_`, `__x`, and `_1` are illegal. Inside the class the field can only be referenced as the bare `_name`; `self._name` and the bare `name` are both compile errors. Local variables, parameters, and type parameters MUST NOT be declared with the canonical name `_name` of a private field of the same class. External `name` and `_name` both report a private access error. `public` / `protected` appearing together with `_name` is a compile error.
- A `const` field MUST NOT also be modified with `final`; `const` already implies `static` and read-only; explicitly writing `static const` is legal and equivalent.
- Repeating the same modifier is a compile error; visibility modifiers are mutually exclusive.
- An unknown modifier, or a modifier used in the wrong position, is a compile error.
- `factory` accepts only top-level visibility modifiers; it cannot be `abstract`, `final`, or `static`. Factory methods MUST be written `static`.

### 1.7 Type Visibility

- Types are public by default.
- Top-level `private` / `protected` types cannot be imported by other packages; they are visible within the same package.
- Top-level `protected` provides no additional inheritance semantics and is equivalent to `private`.
- The visibility of a `factory` is handled as a top-level declaration; factory methods may be written `public` / `private` but not `protected`.
- A `factory`'s Target MUST be visible from the declaring package; a cross-package Target is constrained by its top-level visibility.
- The visibility of types and `factory` affects only compile-time access.

## 2. Class

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

- `class` declares a reference type; variables hold object references, and multiple variables can point to the same object.
- Classes support single inheritance; the parent class is written after `:`, at most one. Inheritance only reuses the parent's fields and concrete methods and does not produce class-hierarchy polymorphism.
- Protocols are written after `implements`, and there may be multiple.
- When there is no parent class, write only `implements`; when there are no protocols, write only `:`.
- References to all classes are compatible with the reference root `Object`; `Object` is the implicit reference root and does not enter the source inheritance chain. `super` cannot be used when there is no explicit parent class. `Object` has no user-visible members and cannot be `new`ed.
- Classes can implement protocols; a class that implements a protocol, and its subclasses, support protocol dynamic dispatch. Class-type receivers still dispatch statically; only protocol-type receivers use dynamic dispatch.
- Classes do not accept memory policy annotations.
- Classes can be generic; variance is allowed only for `out` / `in` type parameters.
- Classes can be `abstract` or `final`; an `abstract` class cannot be instantiated and cannot declare abstract methods; see 2.6 for the rules.
- See Section 6 for a class's instance fields, methods, constructors, and `deinit`.

### 2.2 Fields

- Instance fields belong to the object, one per instance; see 6.1 for field declarations, default values, `final` / `const`, and initialization order.
- Field names MUST be unique along the inheritance chain; field hiding is forbidden.
- Private fields are modified with `private` or declared with a leading underscore `_name`; the canonical name is uniformly `_name`, and inside the class only the bare `_name` may be written, while `self._name` and the bare `name` are both compile errors. See 5.7 and 7.4 for access rules.

### 2.3 Methods

- See 6.2, 6.8, and 7.3 for method declarations, signatures, overloading, `final` / `static`, and visibility; methods cannot be written `abstract`.
- Instance methods can access `self` and instance fields; static methods cannot.
- All class methods dispatch statically; protocol-type receivers dispatch dynamically; `super` dispatches statically; see 5.6.
- See 5.7 for resolution of unqualified names in method bodies.

### 2.4 Constructors

- A constructor has the same name as the class and no return type; see 6.3 for overloading, visibility, `final` field assignment, and `self` publication restrictions; see 6.3 for the primary constructor form in the class header.
- When no constructor is declared, a no-argument constructor is generated; with an explicit parent class it calls `super()`.
- With an explicit parent class, an explicit `super(...)` MUST be the first action; field initializers run after `super` and before the constructor body.
- Inside a constructor, `self.method()` dispatches statically to the current class.
- See 2.7 for the rules of `new C(args)`.

### 2.5 Inheritance

- Single inheritance; a parent class may itself have a parent class; the inheritance chain ultimately reaches `Object`.
- A parent class cannot be `final`.
- A subclass inherits the parent's fields and methods (subject to visibility) for reuse; no new dispatch slots are produced.
- A subclass MUST NOT declare a field with the same name as the parent; field names are unique across the entire inheritance chain.
- A subclass MUST NOT declare a method with the same signature as any ancestor instance method; a same signature is a compile error, including ancestor `private` methods. Return type, visibility, and `final` do not change this rule.
- A subclass MAY declare a same-named method with a different parameter list, forming an overload; overloading does not change the static binding of parent methods.
- All class methods are statically bound; there is no "subclass overrides parent" semantics. Calls through either the parent or the subclass static type select the inherited method corresponding to that static type.
- `@Override` cannot mark class inheritance methods; it is used only for protocol implementation checking.
- A subclass can continue to implement protocols; inherited public instance methods can satisfy protocol requirements, and protocol implementations propagate along the inheritance chain.
- A subclass can call `super(...)`, `super.method()`, and accessible `super.field`.
- A subclass constructor MUST complete parent construction; see 6.4 for the `deinit` chain.

### 2.6 Abstract Classes and final Classes

- An abstract class cannot be `new`ed; it may declare constructors for subclasses to call, in order to share fields, methods, and construction logic.
- An abstract class cannot declare abstract methods; every instance method in an abstract class MUST have a method body.
- An abstract class can implement protocols, but it MUST also provide concrete implementations of all protocol methods; otherwise it MUST NOT declare `implements`, and concrete subclasses declare the protocol and implement it.
- A `final` class cannot have subclasses; a `final` method is legal but redundant, because class methods are non-overridable anyway.
- A `final` method can satisfy protocol requirements.
- An `abstract final` class is illegal.
- An abstract class can have static members and concrete methods.

### 2.7 Class Instantiation

```x
Device device = new Device("camera-01");
```

- `new` returns a class reference; object identity is determined at creation.
- `new` creates an object; at the language level it is always reference semantics.
- Arguments to `new` are resolved by constructor overload; no matching constructor is a compile error.
- Out of memory is a panic; when a constructor panics, the object is not published and the process terminates.
- `new` cannot be used on `abstract` classes, `protocol`, `enum`, `singleton`, or `@annotation`.

### 2.8 Classes and Object

- All reference types can be assigned to `Object`; an `Object` variable can hold classes, protocols, singletons, data enum cases, closures, arrays, `String`, and library reference types.
- `Object` cannot be instantiated directly.
- The value of `Object` can be `null`; assigning `null` to `Object` is legal.
- Recovering a concrete type from `Object` MUST use `as` / `as?`; failure is a panic or `null`.
- A value type MUST be boxed as `Any` before entering `Object`.
- `Object`'s `==` / `===` are both reference identity comparisons.

## 3. Struct

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

- `struct` declares a pure value type; each value is stored inline, and assignment, argument passing, and returning copy the entire value.
- Structs do not participate in inheritance and do not implement protocols; they cannot write a parent class or `implements`.
- Structs can have instance fields, instance methods, static members, and constructors; they cannot declare `deinit`.
- A struct cannot capture `self` in methods or closures; structs have only value fields, so memory policy or weak reference field issues do not arise.
- Structs can be generic; generic parameters are invariant, and `out` / `in` are not supported.
- Every type argument of a struct MUST be a value field type per 3.2; reference types, `Result`, or other non-value-field type arguments are rejected during type checking.
- Structs cannot be `abstract` or `final`; they cannot serve as a parent class or as a protocol type.
- When reference semantics, object identity, shared state, protocol polymorphism, or `deinit` is required, `class` MUST be used.

### 3.2 Value Field Restrictions

Struct instance fields MUST be value fields. The permitted field types are limited to:

- `Bool`, `Byte`, `Short`, `Int`, `Long`, `UByte`, `UShort`, `UInt`, `ULong`, `Int128`, `UInt128`;
- `Float`, `Double`, `Char`;
- simple enums;
- another `struct` that satisfies the restrictions of this section;
- `T?`, where `T` is one of the above value field types; the optional MUST be inline and MUST NOT introduce a reference.
- a tuple `(T1, T2, ...)`, if and only if every element type is a value field type permitted by this section (Part 1, 2.11).

The following types cannot be struct instance fields:

- `String`, `T[]`, library reference types;
- `Any`, `Object`, protocols, function types, `class`, data enums, singletons;
- `Result`;
- tuples containing reference elements;
- the nullable type `T?` where `T` is not a permitted value field type;
- any `struct` containing reference fields or recursive value containment.

Struct instance fields are checked recursively by declared type; value-containment cycles are already forbidden in 1.5. After instantiation, a generic struct's fields are checked according to the substitution result; if any instance field contains a reference type, it is a compile error. Static fields are not subject to 3.2 and are handled as type-level storage per 7.1. Structs have no "copyability decision" branch; every legal struct is a copyable value.

### 3.3 Copy Semantics

- Assignment, argument passing, returning, storing into an array/container, and struct field initialization all copy the entire value; the copy is independent of the original.
- Modifying the copy does not affect the original; there are no `struct` variables that share the same field storage.
- Structs have no object identity; `==` compares field by field; `===` is the same as `==`.
- Cannot be used as a key in library maps/sets (see the library API for key restrictions).
- Fields are stored by value.
- When a closure captures a struct variable, the storage of the captured variable is shared, but no object identity is produced.
- Copying a struct does not call `deinit`.

### 3.4 Methods and self

- A struct's `self` refers to the receiver value's storage slot; it is not an object reference.
- When a method writes `self.field` or calls a writing method on `self`, the method is considered a "writing method".
- A writing method requires an assignable receiver: a local variable, a writable field, or an array/library container element. Calling a writing method on a temporary value or a read-only location is a compile error.
- Read-only methods can be used on any receiver.
- A `final` field cannot be written after initialization; writing methods cannot bypass this either.
- Struct methods do not support `super`; structs have no parent class.
- All struct methods dispatch statically.
- Struct methods MUST NOT capture `self` in closures; use `class` when the receiver needs to be captured.

### 3.5 Constructors

- A struct constructor has the same name as the struct and no return type; it can be overloaded.
- `new Point(1, 2)` creates a struct value; the value is copied on assignment or return.
- When no constructor is declared, a no-argument constructor is generated: it runs the field initializers and ends.
- A `final` field MUST be assigned exactly once, in an initializer or in the constructor body.
- Structs have no `deinit`; resource cleanup is performed explicitly by the code that holds the value.
- Struct construction failure is handled per Part 1's error rules; it produces no observable object identity.

### 3.6 struct vs class

| Dimension | `struct` | `class` |
| --- | --- | --- |
| Semantics | Pure value type; always copied | Reference type |
| Fields | Only scalars, simple enums, `struct`, or their nullable values | Any legal field |
| Assignment/argument passing | Copies the entire value | Passes an object handle, does not copy the object |
| Identity | None | Has object identity |
| Inheritance | Forbidden | Single parent class; field/method reuse only |
| Protocols | Forbidden | Allowed; protocol-type receivers dispatch dynamically |
| Dispatch | Static | Static for class types; dynamic for protocol types |
| Lifetime | Follows the value or container that holds it | The object is finalized after it becomes unreachable (see Part 3) |
| Typical uses | Coordinates, sizes, colors, ranges, pure-value configuration snapshots | Entities, services, shared state, polymorphism, objects that need `deinit` |

Selection rule: use `struct` when independent copies are needed and all fields are value types; use `class` when identity, sharing, protocol polymorphism, lifetime callbacks, or reference fields are needed.

## 4. Protocol protocol

### 4.1 Declarations

```x
protocol Ready {
    Bool ready();
}

protocol Secure : Ready {
    Bool secure();
}
```

- A protocol is a nominal method-signature contract; only classes that declare `implements` implement the protocol.
- A protocol can inherit one or more protocols, written after `:`, separated by commas.
- A protocol cannot inherit a class; a protocol inheritance cycle is a compile error.
- A protocol cannot be instantiated and cannot be `new`ed.
- The protocol itself does not allocate an object; a variable of protocol type holds a reference to a concrete implementing object.
- A protocol can only declare instance method signatures; fields, method bodies, and default implementations in a protocol body are all illegal.
- Protocols do not support generic parameters, associated types, static methods, constructors, `deinit`, generic methods, or type constraints.
- A protocol can be empty; any class can `implements` an empty protocol.

### 4.2 Method Signatures

- Protocol methods are public by default; `private` / `protected` cannot be written.
- Protocol methods write only the signature, terminated by `;`, with no method body.
- Implementing classes must provide methods with the same signature; the protocol itself generates no implementation.
- Protocol methods cannot be `static`, `final`, `abstract`, or generic.
- A protocol cannot declare fields, properties, constructors, or `deinit`.
- Protocol methods cannot access fields, because a protocol has no fields.

### 4.3 Implementation Checking

When a class implements a protocol:

- All methods of the class and its parent protocols must have implementations.
- Implementing methods must be instance methods, publicly visible, with exactly the same signature: same name, parameter types, and return type.
- Public instance methods inherited from a parent class can satisfy protocol requirements; subclasses inherit that protocol implementation.
- Extension methods cannot serve as protocol implementations; protocol implementations must come from class declarations or inherited methods.
- A class cannot defer protocol implementation through abstract methods; an abstract class can declare `implements` only when it provides all implementations.
- A class can implement multiple protocols; duplicate requirements with the same signature and the same return type are satisfied by a single method.
- If two protocols require the same name and parameters but different return types, the class cannot implement both, and an error must be reported.
- A class may have extra methods; this does not affect implementation checking.
- Merely having the same members without writing `implements` does not constitute implementation.

`@Override` is optional; if written, it must correspond to a method with the same signature in the protocol, otherwise an error is reported. `@Override` cannot mark a parent class method, because class inheritance has no overriding.

### 4.4 Protocol Types and Assignability

- A protocol type is a reference type; variables can be `null`.
- A class to an implemented protocol is an implicit upcast; a subclass inherits its parent class's protocol implementations.
- A protocol to a parent protocol is an implicit upcast.
- A protocol to a class, or a class to an unimplemented protocol, must be explicit `as` / `as?`.
- A protocol variable strongly holds the concrete object; the protocol itself does not produce a wrapper object.
- A protocol variable can be assigned to `Object`; it can be boxed as `Any`.
- A class field can be declared as protocol type `P?`, assigned an implementing object or `null`. A protocol itself cannot declare fields.
- Calling a method through a protocol variable dispatches by runtime type; only methods declared by the protocol can be called.
- Calling a method on the same object through a class type variable is still statically dispatched, and does not change because the object implements a protocol.

### 4.5 Protocols and Holding

- A protocol has no instances and does not allocate an object separately.
- A protocol variable strongly holds the implementing object; do not treat it as a "borrowed view" and omit lifetime management.
- When a protocol type is used as a field, container element, `Any`, or closure capture, it still strongly holds the implementing object.

### 4.6 Protocol Restrictions

- Generic protocols are not supported.
- Associated types, protocol generic methods, `where` clauses, and type constraints are not supported.
- Protocol static requirements are not supported.
- Protocol fields, properties, and storage semantics are not supported.
- Protocol default implementations, method bodies, and protocol extensions are not supported.
- `new` on a protocol is not supported.
- A protocol as a parent class is not supported.
- Structs, enums, and singletons implementing protocols are not supported.

## 5. Inheritance, Protocol Implementation, and Dispatch

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

Must be rejected:

- `class C : P` where `P` is a protocol: the parent class cannot be a protocol.
- `class C implements Base` where `Base` is a class: only protocols can be implemented.
- The parent class is a `final` class.
- The parent class is a `struct`, `enum`, `singleton`, `@annotation`, or `extension`.
- Inheritance cycles or protocol inheritance cycles.
- Directly `implements` a duplicate protocol; duplicate implementations inherited through a parent class are allowed, and only one implementation is kept.
- A protocol inherits a class.
- A struct declares `implements`.
- An enum, singleton, extension, or annotation declares inheritance or implementation.
- A subclass declares a method with the same signature as any ancestor instance method; class inheritance only reuses, and overriding is not allowed.
- A subclass declares a field with the same name as an ancestor.

### 5.2 Assignability and Conversion

- `Sub` can be assigned to `Base` when `Sub` inherits `Base`.
- `C` can be assigned to `P` when `C` declares `implements P` or inherits from a class that implements `P`.
- `P` can be assigned to `Q` when `P` inherits `Q`.
- Classes, protocols, singletons, data enum items, closures, arrays, and containers can be assigned to `Object`.
- Value types must be boxed as `Any` before they can be assigned to `Any` / `Object`.
- Parent class to subclass, protocol to class, and `Object` to a concrete type require explicit `as` / `as?`.
- `as` panics on failure; `as?` returns `null` on failure.
- `is` checks the dynamic type or protocol implementation; `null` returns `false`.
- Conversion from a class to a parent class does not change the dispatch mode; calls through the parent class static type still select the parent class method.
- Conversion from a class to a protocol enables protocol dynamic dispatch; after converting back to a class type, static dispatch is restored.
- Structural conversion is not supported; having the same members does not mean the types are compatible.

### 5.3 Method Reuse and Overloading

Reuse:

- A subclass directly inherits parent class instance methods; inherited methods keep their original signature, visibility, and implementation.
- A subclass cannot declare a method with the same signature as any ancestor instance method; overriding, covariant returns, and `@Override` class-inheritance checks do not exist.
- When a parent class method and a subclass method have the same signature, the compiler must reject the subclass declaration, rather than selecting a different implementation based on static type.
- Method-level `final` is legal but redundant; all class methods are non-overridable.
- `private` methods are not inherited by subclasses, but the method signature still occupies the name in the inheritance chain; a subclass cannot declare a method with the same signature.
- `@Override` can only mark protocol implementations; marking a parent class method or failing to find a protocol method reports an error.

Overloading:

- A method signature consists of the name and the parameter type list; return type, parameter names, `final`, and visibility do not participate in the signature.
- Within the same type, two instance methods cannot have the same signature; nor can an instance method and a static method have the same signature.
- A subclass can declare a method with the same name and a different parameter list, forming an overload; a declaration with the same signature is rejected.
- At call time, candidates are collected by the static type of the receiver: methods declared by the current type and inherited methods participate together in overload resolution.
- When multiple candidates apply, it is an ambiguity error; when there are no candidates, it is a compile error.

### 5.4 super

- `super(...)` is used for parent class construction; it must be the first action of the constructor.
- `super.method()` calls the direct parent class implementation; static dispatch; class inheritance has no subclass overriding.
- `super.field` accesses the parent class field; subject to visibility restrictions; parent class private fields are inaccessible.
- `super` cannot be used when there is no explicit parent class.
- `super` cannot be used in static methods.
- `super` cannot appear inside closures; when parent class behavior is needed, call `super.method()` inside the method, and do not capture `super` into a closure.

### 5.5 Construction and Finalization Chains

See 6.5 for the complete order of construction and finalization. Inheritance-related rules:

- During construction, parent class construction completes first, then the current class's field initializers execute, and finally the constructor body executes.
- The object cannot be published before construction completes.
- `deinit` executes the derived class first, then along the parent class chain; an explicit `super.deinit()` takes over the remaining chain.

### 5.6 Dispatch Model

Dispatch falls into two categories:

| Category | Applies to | Rule |
| --- | --- | --- |
| Static dispatch | classes, structs, simple enums, data enums, singletons, constructors, static methods, `super` | Select the implementation by static type or explicit type name |
| Dynamic dispatch | protocol type receivers | Select the implementation by runtime type |

Key rules:

- Class inheritance does not produce dynamic dispatch.
- All instance method calls on class type receivers are statically dispatched, including `self.method()`.
- Classes that implement protocols (directly or through inheritance) support protocol dynamic dispatch; dynamic dispatch covers only the methods required by the protocol.
- Calls to protocol methods on class type receivers are still statically dispatched; dynamic dispatch is used only when the static type of the receiver is a protocol.
- A subclass cannot override a parent class method; protocol implementations are provided by class declarations or inherited methods, and the subclass inherits the same implementation.
- `super.method()` always statically calls the direct parent class implementation.
- Inside a constructor, `self.method()` statically dispatches to the current class, avoiding calls to the runtime type whose construction is incomplete.
- Inside `deinit`, `self.method()` statically dispatches to the current class, avoiding access to already-released derived class fields.
- Protocol type receivers can only call methods declared by the protocol; calls dispatch by runtime type.
- `Any` receivers must first be `as`-converted to a concrete type or protocol before calling.
- Extension methods are merged into the target type's static method set; extension methods do not participate in dynamic dispatch and cannot serve as protocol implementations.

Class inheritance static dispatch example:

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

`Derived` inherits `Base.f` and does not override it; `value.f()` selects `Base.f` according to the static type `Base`, so `x` is `1`.

Protocol dynamic dispatch example:

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

The static type of `value` is the protocol `Value`, so `value.get()` selects `Two.get` by runtime type, and `x` is `2`. If `value` is converted back to the `One` / `Two` class type, calls return to static dispatch.

### 5.7 Member Resolution

Inside an instance method, constructor, or `deinit`, unqualified names are resolved in the following order:

1. Local variables, parameters, type parameters;
2. Accessible instance fields in the current class and its ancestors;
3. Instance methods of the current class and its ancestors (for unqualified calls);
4. Static members of the current class and its ancestors;
5. Top-level declarations of the current package, imported symbols, and fully qualified names.

Rules:

- Instance fields can be accessed unqualified: `count = 1;` is equivalent to `self.count = 1;`.
- When a local variable or parameter has the same name as a field, the local name takes precedence and shadows the field; to access the shadowed field, write `self.field`.
- Assignment, reading, write methods, and constructors follow the same shadowing rules; the resolution order must not switch based on lvalue/rvalue.
- Fields and methods cannot have the same name; name conflicts within the same type and inheritance chain are compile errors.
- Field names are unique across the entire inheritance chain, including `private` fields; a subclass cannot declare a field with the same name.
- The canonical name of a private field is uniformly `_name`; both `private name` and `_name` map to that field. Inside the class, only the bare `_name` can be written; `self._name` and bare `name` are compile errors. Private fields are accessible only inside the declaring class; externally, both `name` and `_name` report a private error. Subclasses cannot access parent class private fields, but the field's base name still occupies the name in the inheritance chain.
- The canonical name `_name` of a private field of the current class cannot be reused by a local variable, parameter, or type parameter of the same class; otherwise it is a compile error.
- If the current class or an ancestor declares a field with the same name but it is not accessible in the current context, an unqualified reference reports a visibility error and does not fall back to an outer symbol with the same name.
- Parent class `protected` fields are accessed per the rules of 7.3; `super.field` accesses the parent class field.
- `super.method()` accesses the direct parent class; `super.field` accesses the parent class field.
- Static contexts have no `self` / `super`; unqualified names resolve only to static members, top-level declarations, and imports.

## 6. Members, Construction, and Destruction

### 6.1 Fields

```x
class Worker(final Int id) {     // Primary constructor: declares and binds a field of the same name
    Int _retries = 0;
    Node? parent = null;
}
```

- Field declaration: `[visibility] [static] [final | const] Type name [= expression]`.
- Instance field default values:

| Type | Default value |
| --- | --- |
| `Bool` | `false` |
| integer | 0 |
| `Float` / `Double` | 0.0 |
| `Char` | `'\0'` |
| reference type | `null` |
| value type `T?` | `null` |
| `struct` | recursive zero value by field; must be explicitly initialized when it contains fields without default values |
| simple enum | no default value; must be explicitly initialized or assigned |
| `Result` | no default value; must be explicitly initialized or assigned |
| `final` field | must be assigned exactly once |

- Field initializers execute after parent class construction completes and before the constructor body, in declaration order.
- Field initializers cannot reference `self`, other instance fields, or constructor parameters; they can reference constants, static members, and top-level functions.
- `final` fields: when there is an initializer, they cannot be assigned again in the constructor body; when there is no initializer, they must be assigned exactly once on every construction path.
- `const` fields are implicitly `static` and read-only; they must have a compile-time constant initializer; they do not occupy instance fields.
- The language does not provide weak reference fields.
- Instance field types must satisfy the value field restrictions of 3.2.
- Static fields belong to the type, not to instances; see 7.1 for the rules.
- Field names must be unique across the entire inheritance chain; field hiding is forbidden.
- Private fields are declared with the `private` modifier, or with a leading underscore as `_name`; the canonical name is uniformly `_name`, and inside the class only the bare `_name` can be written; `self._name` and bare `name` are compile errors; see 5.7 and 7.4.

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
- The return type must precede the method name; write `void` when there is no return value.
- Methods follow the same set of function rules as top-level functions, constructors, and lambdas (Part 1, 7.10): parameters have only a type and a name (may write `final`), default parameters, named arguments, and variadic parameters are not supported; braced body; explicit return type. The differences unique to methods are the receiver and the dispatch mode (5.6).
- Instance methods can access `self`, instance fields, and instance methods; static methods cannot.
- All normal paths of a non-`void` method must return a value; paths terminated by `throw` do not need to.
- Methods cannot be written `abstract`; all class methods must have a body.
- `final` methods are legal but redundant, because class methods are inherently non-overridable.
- Methods can be overloaded; see 6.8 for signature rules.
- For resolution of unqualified names in method bodies, see 5.7.
- Struct methods must not capture `self` in closures; when the receiver needs to be captured, use `class` instead.
- Instance methods on class type receivers are statically dispatched; protocol type receivers use dynamic dispatch, see 5.6.

### 6.3 Constructors

- A constructor name is the same as the type name; no return type is written; it can be overloaded; `public` / `protected` / `private` can be written.
- **Primary constructor**: the constructor form written in the class header `class Worker(final Int id, final String name) { }`, which is shorthand for "declare a field of the same name + declare a constructor of the same name":
  - Primary constructor parameters must be written `final`; each parameter simultaneously declares a field of the same name, and the field type is the parameter type;
  - The binding action is equivalent to assigning each parameter to the field of the same name in declaration order after `super(...)` and before the primary constructor body; `final` fields are therefore assigned exactly once;
  - The primary constructor body can be omitted or contain ordinary statements; the body can read fields that have already been bound;
  - When there is a primary constructor, no parameterless constructor is generated, and no other constructors can be declared (ordinary constructors and primary constructors are not mixed);
  - Fields declared by the primary constructor follow the general field rules (6.1): default visibility, `final` assigned exactly once, field names unique across the inheritance chain;
  - Primary constructor visibility follows constructor rules: public by default, and it may be left unwritten before the parameter list — when a private constructor is needed, use the ordinary constructor form instead;
  - Only `class` supports primary constructors; `struct` / `singleton` / `enum` / `factory` do not.
- For class constructor rules, see 2.4; for struct constructor rules, see 3.5.
- When there is no constructor, a parameterless constructor is generated; when there is a constructor, it is not generated.
- When there is an explicit parent class, explicit `super(...)` must be the first action; when there is no explicit call, `super()` is inserted; when the parent class has no accessible parameterless constructor, it is a compile error. When there is no explicit parent class, `super` is not inserted, and the implicit `Object` root is handled by the runtime.
- Field initializers execute after `super(...)` and before the constructor body.
- `final` fields must be assigned exactly once; field initializers and the constructor body cannot both assign.
- A constructor can execute `return;` to end early, but all `final` fields must already be assigned on every path; `return value` is not allowed.
- Before construction completes, `self` cannot be passed as a value, captured, stored in a container or field; member access is allowed. Instance methods called through `self` are also subject to the same publication restriction, and the called method must not pass `self` out.
- Inside a constructor, `self.method()` statically dispatches to the current class.
- When a constructor panics, the object is not published and the process terminates; `deinit` is not executed.
- `new` instantiates per 2.7 / 3.5.

### 6.4 deinit

```x
class Worker {
    void deinit() {
        self.parent = null;
    }
}
```

- `deinit` can appear only in `class` or `singleton`; `struct`, `enum`, `factory`, and `protocol` cannot declare `deinit`.
- `deinit` cannot be `static`, cannot have parameters, must return `void`, and cannot have visibility modifiers.
- Each class or singleton has at most one `deinit`; it cannot be overloaded.
- `deinit` cannot be called explicitly, except for calling `super.deinit()` inside `deinit`.
- A derived class `deinit` automatically calls the parent class `deinit` by default; an explicit `super.deinit()` takes over the remaining parent class chain, and the compiler must not automatically call the parent class `deinit` again.
- Fields are still valid when `deinit` executes; after the `deinit` chain completes, the runtime releases reference fields that are still non-null.
- Setting a reference field to `null` in `deinit` can release that field early; the runtime will not release it again.
- Inside `deinit`, `self.method()` statically dispatches to the current class.
- `deinit` cannot publish `self`, cannot store `self` in globals/containers/closures, and cannot return `self`; object resurrection is forbidden.
- `deinit` is called after the object becomes unreachable; the exact timing is specified by the memory management specification, and source code must not depend on it.
- Process exit, `panic`, and `throw` do not guarantee that `deinit` is called; resources such as files, handles, and task groups must be explicitly closed at the point of use.
- A singleton's `deinit` is not a cleanup guarantee; the singleton lifetime follows the process.

### 6.5 Initialization Order Summary

Object construction:

1. When there is an explicit parent class, call the parent class constructor.
2. Execute the current class's instance field initializers in declaration order.
3. Execute the constructor body (after `super(...)`).
4. Construction completes, and `self` can be published.

Struct construction:

1. Evaluate initializers in field declaration order.
2. Write field values into the receiver storage.
3. Construction completes; the value may be copied on assignment/passing/return.

Object finalization:

1. Execute the derived class `deinit`.
2. Execute the parent class `deinit` chain (explicit or automatic).
3. Release the remaining reference fields.

Program startup:

1. Top-level fields and static fields are zeroed.
2. Execute top-level/static field initializers in package dependency order.
3. Initialize singletons in package dependency order.
4. Call `main`.

### 6.6 Failure Handling

- Running out of memory is a panic; the process terminates.
- On constructor `panic` / `throw`, the object is not published, `deinit` is not executed, and the process terminates.
- `panic` / `throw` in `deinit` terminates the process directly; the remaining cleanup is not guaranteed.
- `deinit` must not depend on the `deinit` order of other objects; cross-object cleanup must be explicitly coordinated.
- Resource cleanup uses explicit closing or the structured cleanup mechanism of the error handling specification; `deinit` serves only as a last resort.

### 6.7 Name Resolution and Private Fields

For name resolution, see 5.7; for declaration and access of private fields, see 7.4. Fields and methods cannot have the same name. Instance fields can be accessed unqualified; when a local variable or parameter has the same name, it shadows a public field, and `self.field` is used to access the public field; private fields can only be written with the bare canonical name `_name`, and `self._name` cannot be used; `super.field` accesses a parent class public field.

### 6.8 Overloading and Signatures

A signature consists of:

- Method name;
- Parameter type list;
- Instance or static category.

Not part of the signature:

- Return type;
- Parameter names;
- `final` parameter modifier;
- Visibility;
- Generic parameter names;
- Method body.

Rules:

- Within the same type, two instance methods cannot have the same signature; an instance method and a static method cannot have the same signature.
- Different return types do not constitute an overload; changing only the return type is a compile error.
- Different parameter counts or types can be overloaded.
- A subclass cannot declare an instance method with the same signature as an ancestor; different parameter lists constitute an overload.
- The number of type parameters of a generic method is not used to distinguish overloads; resolution is by parameter types only.
- Overload resolution failure, ambiguity, or no candidates is a compile error.
- `@Override` can only correspond to a method with the same signature in a protocol; marking a parent class method or failing to find a protocol method is a compile error.

## 7. Static Members and Visibility

### 7.1 Static Fields

```x
class Counter {
    static Int count = 0;
    static final Int limit = 10;
    static const Int start = 0;
}
```

- Static fields belong to the type and do not depend on instances; one per type.
- Static fields are zeroed at program startup, then initialized in package/file/declaration order; the rules are the same as Part 1, 4.3.
- Static fields are initialized at program startup and persist until the process ends.
- Static fields cannot use the class's generic parameters; `static T value` is a compile error.
- `static final` fields must be initialized once at the declaration; the language does not provide static initialization blocks, so later assignment is not supported. `static const` requires a compile-time constant.
- Static fields are accessed through the type name: `Counter.count`; accessing through an instance `counter.count` is a compile error.
- Static field initializers can read already-initialized static fields; reading a not-yet-initialized field yields the zero value.
- Structs, data enums, and singletons can have static fields; simple enums, protocols, extensions, and annotations cannot have static fields.

### 7.2 Static Methods

- Static methods do not depend on instances; they cannot use `self` / `super`.
- Static methods can access static fields, static methods, top-level declarations, and imported symbols; they cannot access instance fields or instance methods.
- Static methods do not participate in dynamic dispatch; a subclass static method with the same name hides the parent class static method, and calls resolve by explicit type name.
- Static methods can be overloaded; signature rules are the same as 6.8.
- Static methods can be generic methods; for type parameter rules, see 13.
- Static methods cannot be `abstract`; `final` has no additional semantics for static methods.

### 7.3 Visibility

- Members are public by default; `public` / `protected` / `private` can be written.
- `public`: accessible anywhere the type is visible.
- `protected`: accessible in the declaring type and its subclasses; must be accessed through `self`, `super`, or an expression whose static type is the current class/a subclass; protected members of another instance cannot be accessed through a parent class type reference.
- `private`: accessible only inside the declaring type; subclasses cannot access. The canonical name of a private field is `_name`; the two declarations `_name` and `private name` map to that field, and `private _name` is a compile error. Inside the class, only the bare `_name` can be written; `self._name` is illegal. Externally, both `name` and `_name` report a private error. A `factory` bound to Target in the same package gains creation access to Target's private constructors and private static members per 10.3; this is the only exception.
- Class methods cannot be overridden, so there is no rule for "overriding reduces visibility"; protocol implementation methods must be public.
- Constructors can have visibility; `new` is constrained by constructor visibility.
- Static members follow the same visibility rules.
- Visibility is only a compile-time check; it does not change field storage or object identity.
- There is no package-level private visibility; non-subclasses in the same package cannot access `protected` members.
- **No accessor pattern**: classes do not provide a getter/setter accessor method pattern, nor custom property get/set syntax; public fields are the default property access, and field access itself is property access.
- Only when computed values, validation, logging, lazy initialization, or exposure of private state is needed should explicit verb methods be written (6.2); method names express behavior, not access; this is not a default requirement for field access.
- The standard library containers' `get` / `set` / `at` are verb methods of the collection API (Part 1, 9.1) and do not belong to the accessor pattern.

### 7.4 Private Fields and Canonical Names

The base name of a private field is the name after removing one leading `_`; the canonical internal name is uniformly `_name`. There are only two declaration forms, and they map to the same field:

- `Int _name;`: declaration name `_name`, base name `name`, canonical name `_name`;
- `private Int name;`: declaration name `name`, base name `name`, canonical name `_name`.

`private Int _name;` is a compile error: `private` and the `_` prefix cannot be used together.

For example, the base name of `private Int limit = 10;` is `limit`, and the canonical name is `_limit`; inside the class only `_limit` can be written. Writing `self._limit` or bare `limit` is a compile error. External access to `account.limit` and `account._limit` both report a private error.

Rules:

- In an `_name` declaration, `name` must be lowerCamelCase; in `private name`, `name` follows ordinary field naming. The base name cannot begin with an underscore; `_`, `__x`, and `_1` cannot be used as base names.
- `_name` applies to instance fields and static fields; it does not apply to methods, constructors, local variables, parameters, or type names.
- `private Int _name;` is a compile error; an explicit `private` can only declare `name`, and the `_` prefix can only be used for an `_name` declaration without `private`.
- `public` / `protected` appearing together with `_name` is a compile error.
- Inside the declaring class, only the bare canonical name `_name` can be written for reading and writing; `self._name` and bare `name` are compile errors.
- A local variable, parameter, or type parameter in the same class cannot use the canonical name `_name`; a declaration with the same name is a compile error, to avoid the private field losing its accessible name.
- Parent class private fields are inaccessible in subclasses; `super._name` also cannot bypass private visibility.
- Field base names are unique across the entire inheritance chain; public `x`, `_x`, and `private x` all occupy the base name `x`, and cannot be declared at the same time.
- A subclass cannot access parent class private fields; the base name of a parent class private field still occupies the name in the inheritance chain.
- For `private final Int id;`, write `_id = id` in the constructor; the base name is `id`, the canonical name is `_id`, and `self._id` cannot be used.
- Private fields do not produce extra fields.

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

The canonical names of `balance`, `retries`, and `limit` are `_balance`, `_retries`, and `_limit`, respectively; inside the class only the canonical names are written, and `balance`, `retries`, and `limit` do not access the private fields. External access to `account.balance`, `account._balance`, `account.retries`, `account._retries`, `account.limit`, and `account._limit` all report private errors.

### 7.5 @ReadOnly

- `@ReadOnly` can only be used on fields.
- Public/protected fields are externally readable and not writable; they remain writable inside the declaring type.
- Private fields are inherently inaccessible externally; `@ReadOnly` does not change private access rules, and they remain writable inside the declaring type.
- `@ReadOnly` does not change the object model.
- `@ReadOnly` cannot be used on local variables, parameters, or methods.

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

- Enums fall into two kinds: simple enums and data enums.
- Simple enum: items have no constructor arguments and no fields, methods, constructors, `deinit`, or static members.
- Data enum: items carry constructor arguments; the enum declares fields, constructors, and methods.
- All items of the same enum must use the same form; `Item`, `Item(args)`, and `Item = value` cannot be mixed.
- Enums cannot be generic; cannot declare a parent class or `implements`; cannot be `abstract`; they are implicitly `final`.
- Enums do not implement any protocol; an enum value cannot be assigned to a protocol type, and enum methods cannot be called through a protocol type receiver.
- Enum items are closed; `new` is not possible externally, and they can only be accessed through `Enum.Item`.
- Data enums can declare fields, constructors, instance methods, static fields, and static methods; simple enums have only items.
- Enum declarations can only be at the package top level.

### 8.2 Simple Enums

- Items are written directly as names; an optional `= integer-literal`, where the integer literal can have a leading `-`.
- When no value is written, values start at 0 and increment; an explicit value sets the current item, and subsequent bare items continue incrementing.
- Explicit values must be integers within the `Int` range; duplicate values, overflow, and out-of-range values are compile errors.
- A simple enum is an independent nominal type, represented internally as `Int`; it cannot be implicitly assigned to `Int`, nor used in arithmetic with `Int`.
- Simple enums support `==` / `!=` / `===` / `!==`, comparing by underlying value.
- Simple enums support `<` / `<=` / `>` / `>=`, comparing by underlying value.
- Simple enums support `switch`; `case Color.Red` compares by underlying value.
- Simple enums are value types; variables, parameters, fields, and array elements are stored by value.
- Fields of simple enum type have no default value; fields must be explicitly initialized or assigned in the constructor.
- Simple enum items can be used in `const` initializers.
- Interpolated strings format a simple enum as the item name.

### 8.3 Data Enums

- Data enum items must carry constructor arguments: `Ready(0, "ready")`.
- A data enum must declare fields and a constructor; fields must be `final`; the constructor has the same name as the enum.
- Data enum constructors are implicitly private and can only be called by enum item declarations; `new` is not possible externally.
- Data enum fields are initialized at construction; all paths must assign the `final` fields.
- Data enum instances are immutable: fields are `final`, and methods cannot write fields; static fields can be mutable.
- Data enum items are singleton objects provided by the compiler; each item is constructed once at program startup.
- Data enum item arguments are evaluated at startup in item declaration order; item arguments can reference preceding items, constants, and static members, but cannot reference later items.
- If evaluation of data enum item arguments panics, the program terminates.
- Data enums support instance methods, static fields, and static methods; `deinit` is not supported.
- Data enums do not participate in inheritance or protocol implementation; methods are statically dispatched.
- Data enum items have object identity; `==` / `===` compare by identity; all references to the same item are equal, and different items are not equal.
- Interpolated strings: if the data enum declares `String toString()`, call that method; otherwise format as the item name.

### 8.4 Enum Items and Initialization

- Item names are unique within the enum; the underlying values of a simple enum are unique.
- The number and types of data enum constructor arguments must match the constructor signature; a mismatch is a compile error.
- Data enum items are constructed at startup in declaration order; they become externally usable only after all items have been constructed.
- Item initialization cannot reference later items that have not yet been constructed; the compiler must check direct and indirect forward references.
- Data enum items persist for the lifetime of the process.
- The enum type itself cannot create instances; simple enums have no object identity; data enum item identity is provided by the compiler.

### 8.5 Comparison, switch, and Formatting

- The `switch` `case` uses `==` semantics; simple enums by underlying value, data enums by identity.
- The `case` expressions of an enum `switch` must be item constants of that enum, such as `Color.Red` or `Status.Ready`; arbitrary expressions cannot be enum `case`s.
- When an enum `switch` has no `default`, it must cover all items of that enum, each exactly once; omission, duplication, or unknown items are compile errors.
- When an enum `switch` has a `default`, the `default` is considered to cover the remaining items, and no exhaustiveness requirement applies; there is at most one `default`, and it must be last.
- A non-enum `switch` does not check exhaustiveness; when nothing matches and there is no `default`, the `switch` is exited directly.
- Enums do not support pattern matching; when fields of a data enum need to be inspected, first `switch` to the item, then read the fields or use methods.
- Simple enums support ordering comparisons; data enums do not support ordering comparisons.
- The type of the simple enum `Color.Red` is `Color`; it cannot be directly compared with or assigned to `Int`.
- Data enums cannot use `is` to check subtypes; `is Status` only checks whether the value is of that enum type.
- Data enum items cannot be `new`ed; they cannot be created by reflection.
- Enums do not participate in `Object` inheritance; simple enums must be boxed as `Any` to enter `Object`; data enum items are references and can be assigned to `Object`.
- Enums do not implement protocols; protocol type variables cannot hold enum values.

## 9. singleton

### 9.1 Declaration and Access

```x
singleton AppInfo {
    final String name = "XNull";
}
```

- `singleton` declares a preloaded, globally unique instance.
- `instance` is an implicit read-only field provided automatically by the compiler, and its type is the singleton type; only `singleton` has this field.
- `instance` cannot be declared manually; a manual declaration is a compile error.
- External code accesses the unique instance through `AppInfo.instance`; inside the singleton, fields and methods are accessed through `self`.
- `instance` cannot be reassigned and cannot be `null`.
- A singleton cannot be `new`-ed; it cannot inherit and cannot implement protocols; it is implicitly `final` and cannot be subclassed.
- A singleton cannot be generic and cannot be `abstract`.
- A singleton may have instance fields, instance methods, static fields, and static methods.
- A singleton cannot declare constructors; fields are initialized by initializers or default values, and the compiler constructs the instance.
- A singleton may declare `deinit`, but it is not guaranteed to be called at process exit; it must not be relied upon to clean up resources.

### 9.2 Initialization

- Singleton instances are preloaded at program startup, after top-level/static field initialization and before `main`.
- Singletons are initialized in package dependency order, file order, and declaration order.
- Singleton fields are zeroed first, then field initializers are executed.
- Singleton initializers may reference already initialized top-level fields, static fields, and preceding singletons; they must not reference later singletons.
- If singleton initialization panics, the program terminates and `main` is not called.
- Singleton instances finish construction before `main`; `main` sees fully initialized instances.
- A singleton's static fields are initialized together with other static fields.

### 9.3 Restrictions

- Generic singletons are not supported.
- Inheritance, protocol implementations, constructors, and subclassing are not supported.
- Manual declaration of `instance` is not supported.
- `new` is not supported.
- Concurrent access to singleton fields is not synchronized.
- Singleton initialization order is deterministic; forward references across singletons are compile errors.

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

- `factory` declares a creation namespace bound to a target type; it has no instance and allocates no object.
- `factory` can only appear at package top level; it cannot be nested.
- The Target of `for Target` must be a `class` or `struct` declaration visible in the current package or another package; a generic target is written as the bare type name `Box`, without type arguments.
- The Target may be an abstract class; factory methods return concrete subclass instances upcast to the target type.
- The Target cannot be a `protocol`, `enum`, `singleton`, `@annotation`, another `factory`, an array, a container, a function type, `Object`, `Any`, a nullable type, or a generic instantiation.
- When creation per a protocol is needed, bind an implementing class and have factory methods return that protocol or a superclass; the protocol itself is not used as the Target.
- A `factory` name occupies the top-level type namespace within its declaring package; it must not have the same name as another type in that package; it cannot be used as a type.
- `factory` is public by default; `public` / `private` / `protected` may be written; top-level `protected` is equivalent to `private`.
- `factory` cannot be written `abstract`, `final`, `static`, or `const`; it is implicitly non-instantiable and non-inheritable.
- `factory` cannot declare fields, constructors, `deinit`, instance methods, a superclass, or protocol implementations.
- `factory` is a stateless creation namespace; when caching or shared state is needed, use `singleton` or top-level static fields.
- The same Target may have multiple `factory` declarations, distributed within the same package or across different packages; each factory's access rights are determined by package boundaries.
- A same-package `factory` gains access to the Target's private constructors and private static members; a cross-package `factory` may only access the Target's public members.
- A cross-package Target must be visible from the package containing the `factory`; invisible types and non-public top-level types cannot be Targets.
- The effective visibility of a factory method is the stricter of the `factory` type's visibility and the method's visibility.
- When the Target's visibility is lower than the factory method's effective visibility, the method's return/parameter signature must not expose the Target; a public superclass, protocol, or `Object` may be returned.
- `factory` may carry declaration annotations; `@Override` is illegal; other annotations only act as compile-time markers.

### 10.2 Factory Methods

```x
factory BoxFactory for Box {
    static Box<T> create<T>(final T value) {
        return new Box<T>(value);
    }
}

Box<Int> box = BoxFactory.create(1);
```

- Factory methods MUST be written `static`; they cannot use `self` / `super` and cannot access instance fields.
- Factory methods are public by default; `public` / `private` may be written; `protected`, `abstract`, and `final` cannot be written.
- Methods may be overloaded; method-level generic parameters may be declared.
- Allowed base return types R:
  - Target instance: `Device`; generic target `Box<T>` / `Box<Int>`, etc.;
  - For a class Target, it may return a superclass, protocol, or `Object` to which the Target is assignable;
  - For a struct Target, only the Target may be returned.
- The return type may be `R`, `R?`, `Result<R, E>`, or `Result<R?, E>`; E must not be `void`.
- Returning `void`, arrays, containers, `Any`, or unrelated types is prohibited.
- Factory methods may return new objects, cached objects, singletons, `null` (when the Target is optional), or `Err`.
- Factory methods may use `try`, `defer`, and `errdefer`; `Result` follows `@mustUse`.
- Factory methods do not observe errors automatically; callers handle them with `try` or `Result` members.
- Factory methods may call private methods of the same `factory`, top-level functions, and public methods of other `factory` declarations.
- Factory methods cannot serve as the entry `main`; the entry point must be a top-level `main`.

### 10.3 Access and Creation

- When a `factory` is in the same package as the Target, it automatically gains private creation access to the Target:
  - It may call the Target's private constructors;
  - It may access the Target's private static fields/methods;
  - It must not access the Target's private instance fields/methods; after construction it may only operate through public members;
  - It must not access the Target's `protected` instance members (`factory` is not a subclass).
- `new Target(...)` inside a same-package `factory` can select a private constructor; this is the core purpose of same-package factories.
- `factory` is not a subclass of the Target and cannot call the Target's `protected` constructors or `protected` instance members.
- A cross-package `factory` may only call the Target's public constructors, public static fields, and public static methods; it cannot call private or protected members.
- Factory methods may create subclass instances, but may only call public subclass constructors; the result is upcast to the Target on return.
- A factory cannot access private constructors of other types, including private constructors of Target subclasses.
- When the Target has a private constructor, only the Target itself and same-package `factory` declarations bound to the Target can construct it; cross-package factories cannot construct it.
- When multiple same-package `factory` declarations bind the same Target, each has private creation access; when finer granularity is needed, keep only one `factory` and route other creation through private methods.
- A cross-package `factory` depends on the Target's public creation entry points; when the Target has no public constructor or public static factory, a cross-package factory cannot create instances and can only return existing objects or `Err` from its methods.
- When the Target is a `struct`, `factory` returns struct values; value copying follows 3.3, and private constructor access is still granted only to same-package factories.
- `factory` methods may return a superclass, protocol, or `Object`; the returned object is still constructed by the concrete Target or a subclass.

### 10.4 Types and Restrictions

- `factory` is not a value type, reference type, or object type; it cannot be used as a variable, parameter, field, generic argument, or container element; it cannot be used with `is` / `as` / `as?`; it cannot be assigned to `Object` / `Any`.
- `new Factory` is a compile error; a `factory` can only be invoked statically via `Factory.method(...)`.
- `factory` is not a type, has no instances, and does not call `deinit`.
- Factory methods are themselves static methods; they do not use `self` and do not participate in dynamic dispatch.
- `factory` cannot be extended by `extension`; it cannot be an `extension` target, a supertype, a protocol implementer, or be replaced by a `singleton`.
- `factory` can be imported; it is called via `Factory.method`; visibility follows top-level declarations.
- `factory` cannot declare generic parameters; a generic target is written using its bare name, and instances are produced by the factory method's type parameters.

### 10.5 Restrictions and Diagnostics

The compiler MUST reject:

- a `factory` with the same name as a type or another `factory` in the current package;
- a Target that is not a visible `class` / `struct`;
- a Target that is a `protocol`, `enum`, `singleton`, `@annotation`, `factory`, array, container, function type, `Object`, `Any`, nullable type, or generic instantiation;
- a cross-package Target that is not visible from the package containing the `factory`;
- a `factory` that declares fields, constructors, `deinit`, instance methods, a superclass, or protocols;
- a factory method missing `static`, or using `self` / `super`, or accessing instance fields;
- a factory method with `protected` / `abstract` / `final`;
- a factory method return type outside the set allowed in 10.2;
- a factory method whose effective visibility is higher than the Target's visibility and whose signature exposes the Target;
- a cross-package factory accessing the Target's private or protected constructors, static members, or instance members;
- a same-package factory accessing the Target's `protected` instance members;
- using `factory` as a type/value, `new` on a factory, `is` / `as` on a factory;
- a `Result` error type of `void`;
- duplicate factory method signatures;
- calling a Target private constructor outside the Target itself and same-package `factory` declarations bound to the Target.

### 10.6 Example

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

- `Device`'s constructor is private; external code cannot use `new`; the same-package `DeviceFactory` is the only creation entry point.
- Factory methods return `Device`; callers do not hold a `factory` object.
- `open` returns `Result<Device, DeviceError>`; callers use `try`.
- A cross-package factory bound to the same `Device` may only use a `public` constructor or a `public` static creation method; the private constructor access in the example above does not extend to other packages.
- A cross-package `factory` declaration must still be at package top level, references the Target through `import` or a fully qualified name, and is subject to the Target's top-level visibility.

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

`Device`'s constructor is public, so the `DeviceFactory` in package `app` can call it across packages. If `Device`'s constructor is changed to `private`, a same-package factory can still call it, but a cross-package factory cannot; a cross-package factory must instead use the Target's public static creation methods.

## 11. extension

### 11.1 Declaration

```x
extension Device {
    String label() {
        return self.name;
    }
}
```

- `extension` can only add methods; it cannot add fields, constructors, `deinit`, or static methods.
- The target type must be a non-generic `class`, `struct`, `singleton`, or data `enum` declared in the same package.
- It cannot extend protocols, annotations, simple enums, extensions themselves, or predefined types.
- It cannot extend generic types or generic instantiations.
- Extension methods are public by default; `private` / `protected` cannot be written.
- Extension methods may be overloaded; duplicate declarations with the same name and parameters are compile errors.
- An extension method must not conflict with an existing method with the same signature on the target type or a superclass; the same signature is a compile error.
- Extension methods cannot be overridden by subclasses of the target type; a same-signature declaration in a subclass is a compile error, and class inheritance only reuses the method.
- Extension declaration order is irrelevant; all extensions in the same package participate in resolution together.

### 11.2 Method Resolution and Dispatch

- Extension methods participate in normal method resolution and overloading; extension methods on class-type receivers are dispatched statically.
- Extension methods do not participate in protocol dispatch; even if the target class implements a protocol, an extension method cannot serve as a protocol implementation.
- Extension methods are inherited by subclasses; a subclass cannot declare a same-signature method to override an extension method, and the same signature is a compile error.
- An extension method cannot serve as a protocol implementation; protocol requirements must be satisfied by class-declared or inherited methods.
- A protocol-type receiver cannot call extension methods that are not declared in the protocol; the value must first be converted to a concrete type.
- Same name and parameters among extension methods, or between an extension method and a target method, is a duplicate definition and must be reported as an error.
- Extension methods cannot change the target type's fields or object identity.

### 11.3 Access and Dispatch

- Extension methods may only access the target's public members; `protected` / `private` members are inaccessible, even when the extension is in the same package as the target.
- `self` is a borrowed view of the target object; the target's lifetime is determined by the original owner.
- When a class extension method captures `self` in a closure, a strong hold is established according to the closure capture rules.
- Struct extension methods follow the struct write rules: a mutating method requires the receiver to be assignable; `self` must not be captured in a closure.
- Extension methods do not add fields.
- Extension methods are merged into the target type's static method set and do not participate in dynamic dispatch.
- Singleton/data enum extension methods obey their immutability: data enum fields are `final`, and fields cannot be written.

### 11.4 Restrictions

- Extending with fields, constructors, `deinit`, or static methods is not supported.
- Extending protocols, annotations, or predefined types is not supported.
- Extending generic types is not supported; generic extension methods are not supported.
- Cross-package extensions are not supported.
- Using extensions to implement protocols is not supported.
- An extension method cannot have the same signature as an existing inherited method and cannot be overridden.

## 12. annotation

### 12.1 Declaration

```x
@annotation Marker {
    final String name = "";
}
```

- `@annotation` declares a compile-time annotation type; no runtime object is generated.
- Annotations may only declare `final` fields; field types must be compile-time constant types: `Bool`, integer, `Float`, `Double`, `Char`, `String`, simple enums.
- Annotation fields must have compile-time constant initializers.
- Annotations cannot have methods, constructors, `deinit`, static members, generic parameters, inheritance, or protocol implementations.
- Annotation declarations do not produce runtime instances.
- Annotation types exist only at compile time; they cannot be `new`-ed and cannot be passed as values.

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

- Usage forms: `@Name` or `@Name(arg1, arg2, ...)`; arguments are bound in field declaration order.
- Arguments must be compile-time constants; their types must be assignable to the field types; omitted trailing fields use the initializer from the declaration site.
- Extra arguments are compile errors; intermediate fields cannot be skipped; named arguments are not supported.
- Annotations may be applied to type declarations, fields, methods, constructors, `deinit`, parameters, and enum items.
- Annotations cannot be used on expressions, type parameters, type arguments, or control bodies; the block annotation semantics of `@tasks` / `@arena` are defined in Part 5 (§2.3).
- An unknown annotation is a compile error; an annotation must resolve to an `@annotation` type in the same package or an imported one, or to a built-in annotation.
- Using the same annotation repeatedly on the same target is a compile error; `@Repeatable` is reserved but has no effect.
- Annotations do not affect control flow or the object model; memory strategy annotations are not part of the language annotation system.

### 12.3 Built-in Annotations

| Annotation | Target | Enforced | Semantics |
| --- | --- | --- | --- |
| `@ReadOnly` | Field | Yes | Read-only externally; writable inside the declaring type |
| `@Override` | Method | Yes | Must correspond to a protocol method with the same signature; cannot mark superclass methods |
| `@WriteOnly` | Field | No | Recognized but not enforced |
| `@Target` | Annotation | No | Recognized but not enforced |
| `@Retention` | Annotation | No | Recognized but not enforced |
| `@Repeatable` | Annotation | No | Recognized but not enforced |
| `@Deprecated` | Declaration | No | Recognized but not enforced |
| `@SuppressWarnings` | Declaration | No | Recognized but not enforced |
| `@Immediate` / `@NoAlloc` / `@Pure` / `@Sendable` | Reserved | No | Reserved; does not change semantics |

The memory strategy annotations `@arc` / `@gc` are not members of the language annotation system; using them in source code is a compile error.

### 12.4 Restrictions

- An `@annotation` declaration is only a compile-time type and does not generate a runtime object.
- Language annotations only perform compile-time checks or recognition; `@arc` / `@gc` are not part of the language annotation system.
- Annotation arguments must be compile-time constants; runtime expressions are not evaluated.
- Reflection, runtime annotation queries, annotation processors, and code generation are not supported.
- Annotation inheritance, repeated annotations, default arguments, and named arguments are not supported.

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
- Generic parameters are names only; constraints, `where` clauses, default types, variadic parameters, and associated types are not supported.
- Type parameter names are unique within the same generic declaration; a method type parameter must not have the same name as a type parameter of its enclosing class.
- A generic class may inherit a generic superclass or implement non-generic protocols.
- Generic structs do not participate in inheritance or protocols; every type argument must be a value field type per 3.2.
- Protocols do not support generic parameters, generic methods, associated types, or type constraints inside protocols.
- Singletons, enums, annotations, and extension targets do not support generics.
- Extension methods do not support generics.
- Bare generic names are erased to `Any`: `Box` is equivalent to `Box<Any>`.

### 13.2 Variance

Variance may only be declared on a class's generic parameters:

```x
class Producer<out T> { }
class Consumer<in T> { }
```

- `out T`: covariant. `Producer<Derived>` is assignable to `Producer<Base>`.
- `in T`: contravariant. `Consumer<Base>` is assignable to `Consumer<Derived>`.
- Unannotated type parameters are invariant; only identical arguments are compatible.
- Struct generic parameters are invariant; generic methods have no variance.
- Variance is meaningful only for reference type arguments; value type arguments have no subtype relation and must be the same type.

Position rules:

| Position | `out T` | `in T` | Invariant `T` |
| --- | --- | --- | --- |
| Method return type | Allowed | Prohibited | Allowed |
| Method parameter type | Prohibited | Allowed | Allowed |
| Constructor parameters | Allowed | Allowed | Allowed |
| `final` field | Allowed | Prohibited | Allowed |
| Mutable field | Prohibited | Prohibited | Allowed |
| `T?` | Preserved | Preserved | Preserved |
| `T[]` | Prohibited | Prohibited | Allowed |
| `Box<T>` (user generic) | Prohibited | Prohibited | Allowed |
| Generic argument `G<T>` | Only when G's corresponding parameter is `out` | Only when G's corresponding parameter is `in` | Allowed |
| Function type parameter position | Prohibited | Allowed | Allowed |
| Function type return position | Allowed | Prohibited | Allowed |

Rules:

- Constructor parameters are not variance positions; construction is checked against the concrete arguments.
- `out T` may appear in return types and `final` fields; it must not appear in method parameters, mutable fields, arrays, or invariant containers.
- `in T` may appear in method parameters; it must not appear in return types or any field.
- A mutable field makes the type parameter invariant.
- Variance conversions only affect type compatibility checks and do not change object identity.
- Variance violations are compile errors; silent conversion at runtime is not permitted.

### 13.3 Instantiation and Inference

```x
Box<Int> box = new Box<Int>(1);
Box<Int> inferred = new Box(1);
```

- The number of generic type arguments must match the declaration.
- `new` may specify type arguments explicitly; when omitted, they are inferred from constructor arguments.
- If the constructor arguments cannot uniquely determine the type arguments, the type arguments must be written explicitly.
- A type argument cannot be `void` and cannot be an unbound type parameter.
- When nested generics use `>>`, it is parsed as two `>` characters; the lexical/grammar layer must support this.
- `Box<Int>?` is a nullable reference; for reference types, `T?` is the same type as `T`.
- Generic class inheritance: `class Child<T> : Base<T>`, `class IntChild : Base<Int>`; superclass arguments must be concretized.
- A bare superclass `Base` is treated as `Base<Any>`.
- A generic class implementing a protocol: the protocol is non-generic; method signatures must match exactly after type argument substitution.
- Every concrete instance of a generic struct must satisfy 3.2: `Pair<Int, Int>` is legal, while `Pair<String, Int>` is rejected because a field contains a reference type.
- Generic struct type parameters cannot be instantiated with non-value field type arguments, even if the parameter does not appear in a field; structs provide no reference fallback branch.

### 13.4 Generic Instantiation

- Generic types and generic methods are instantiated per type arguments.
- Each distinct type argument list generates a separate type/function instance.
- Residual type parameters are compile errors.
- The bare generic `Box` / `Box<Any>` is erased to `Any`; when a field contains `Any`, it is treated as a reference type.
- Generic methods generate a function per instance.
- Recursive instantiation must terminate; infinite expansion is a compile error and must not be silently truncated.
- Generic function bodies must be visible at the instantiation point.
- Runtime type arguments are not supported; `is T` / `as T` check against the concrete instantiated type.
- `new T()` is a compile error; `T` is not a runtime-constructible type.
- Static members cannot use the class's type parameters; `static T value` is a compile error.
- Generic closures are not supported; use generic functions when generic behavior is needed.

### 13.5 Restrictions

- Type constraints, `where` clauses, default type arguments, and variadic type parameters are not supported.
- Generic protocols, protocol generic methods, associated types, and type aliases inside protocols are not supported.
- Generic singletons, generic enums, and generic annotations are not supported.
- Generic extension targets and generic extension methods are not supported.
- Generic structs using non-value field type arguments are not supported.
- Generic closures are not supported.
- `new T()` is not supported.
- Static members using class type parameters are not supported.

## 14. Object Lifetime

Object storage and reclamation are specified in Part 3; this section defines only the observable lifetime semantics.

### 14.1 Construction and Publication

- A class object created by `new` must not be published before construction completes: it must not be stored in a field, static field, container, or closure, passed out as an argument, or returned as `self`. A violation is a compile error.
- Construction order: superclass construction completes → the current class's field initializers execute in declaration order → the constructor body.
- `self` may be published only after construction completes.

### 14.2 Finalization and deinit

- `deinit` is declared only on `class` / `singleton`; see 6.4 for the rules.
- Call order: derived class `deinit` → superclass `deinit` chain; fields are released only after the `deinit` chain completes.
- `deinit` is called after the object becomes unreachable; the exact timing is outside this Solution, and source code must not depend on it.
- `deinit` must not resurrect the object: it must not store `self` in a global/container/closure or return `self`.
- `deinit` is not guaranteed to run on process exit, `panic`, or `throw`; resources such as files, handles, and task groups must be closed explicitly at the point of use.

### 14.3 Diagnostics

Compile time MUST report: publication of `self` before construction completes, `deinit` resurrecting the object, illegal `deinit` signatures, and the prohibited constructs listed in Sections 1–14.

Runtime MUST report: null reference dereference, array/library container index out of bounds, failed `as`, integer division by zero, shift out of range, and explicit `throw`.

## Appendix A: Type Declaration Grammar

This appendix uses EBNF; `{ X }` means zero or more occurrences, and `[ X ]` means optional. The base expression and statement grammars are in Part 1, Appendix A.

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

The expression grammar inherits from Part 1, Appendix A; the `new` expression is already defined in Part 1's `PrimaryExpr` and is not repeated in this appendix. The grammars for tuple types, tuple literals, and element access are in Part 1, Appendix A.

Grammar notes:

- The `:` in `ProtocolDecl` accepts only protocols; the `:` in `ClassDecl` accepts only classes; semantic checks MUST reject the wrong kind.
- `StructDecl`, `EnumDecl`, `SingletonDecl`, `ExtensionDecl`, and `AnnotationDecl` do not accept `:` or `implements`; the grammar does not list these branches.
- The three forms of `EnumItem` are mutually exclusive; an enum must use a single form throughout; simple enum items cannot have constructor arguments, and data enum items cannot have `= value`.
- `MethodDecl` must have a `Block`; class methods cannot omit the method body. `abstract` is not a `MemberModifier`, and an `abstract` method written in a class declaration is rejected by the grammar.
- `ProtocolMember` accepts only `ProtocolMethod`; protocol fields, method bodies, and default implementations are rejected by the grammar. Protocol methods end with `;`.
- `ExtensionDecl` accepts only methods; fields, constructors, `deinit`, and static methods are rejected by the grammar; semantic checks then reject generic targets and generic methods.
- The Target of `FactoryDecl` must be a `class` / `struct` visible in the current package or across packages; a generic target is written with its bare type name, and writing type arguments is rejected by semantic checks. Private member access to a cross-package Target is not granted by the factory relationship.
- `FactoryMember` must be a `static` method; fields, constructors, `deinit`, instance methods, superclasses, and protocol implementations are rejected by the grammar or semantic checks.
- `factory` is not a type; it cannot be used for variables, parameters, fields, generic arguments, `new`, or `is` / `as`. `FactoryDecl` accepts only visibility modifiers; `abstract` / `final` and the like are rejected by semantic checks.
- `AnnotationDecl` accepts only `final` fields; the constant restrictions on field types and initializers are enforced by semantic checks.
- `out` / `in` in `GenericParam` are allowed only on type parameters of `ClassDecl`; other positions are rejected by semantic checks.
- `ProtocolDecl` does not support `GenericParams`, associated types, or protocol generic methods; the grammar does not list them.
- The `( ParamList )` in the `ClassDecl` header is the primary constructor: parameters must be written `final` (enforced by semantic checks), and each parameter also declares a field with the same name; a class with a primary constructor cannot declare additional constructors; only `class` supports this, and header parameter lists on `struct` / `singleton` / `enum` / `factory` are rejected by the grammar.
- `SingletonDecl`, `EnumDecl`, and `AnnotationDecl` do not support `GenericParams`; the grammar does not list them.
- The field restrictions on `StructDecl` are enforced by semantic checks; reference fields, nullable reference fields, `deinit`, and capturing `self` MUST be rejected; nullable value fields are allowed, but must not form recursive value containment. The appearance of `weak` or `@arc` / `@gc` in source code is rejected by the grammar or semantic checks.
- A `FieldDecl` field name is treated as private when it takes the `_name` form or is declared as `private name`; `private _name` is rejected by semantic checks. The canonical name is `_name`, and only a bare `_name` may be written inside the class; `self._name` and bare `name` are rejected by semantic checks. Local variables, parameters, or type parameters in the same class that use `_name` are also rejected. `public` / `protected` together with `_name` is rejected by semantic checks; field names are checked for uniqueness along the inheritance chain by base name.
- The semantics of `[]` / `?` in `TypeRef` are the same as in Part 1, Appendix A; `T?[]` is "an array of nullable T", and `T[]?` is "a nullable array".
- A construct accepted by the grammar MUST be rejected if it violates semantic rules.
