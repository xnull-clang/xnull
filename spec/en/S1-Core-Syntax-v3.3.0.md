# XNull Specification, Part 1: Core Syntax

> **Translation notice**: This is an English translation of the normative Chinese specification
> 《XNull 解决方案 第 1 部分：基础语法》v3.3.0. The Chinese original prevails in case of any
> divergence. Translation version follows the original's version number.

| Item | Value |
| --- | --- |
| Document ID | Part 1 (S1) |
| Document Version | 3.3.0 |
| Specification Status | Normative |
| Release Date | 2026-11-05 |
| Applies To | XNull compiler, runtime, LSP, tests |
| Companion Document | Part 2 *Object Programming* v3.3.0 (version numbers sync with the current versions; see the specification index) |

Versioning rule: file names keep the full version number; new versions are saved alongside, never overwriting old ones. The patch number is for semantic-preserving clarifications, the minor version for backward-compatible additions, and the major version for breaking changes. Specification-clause changes must synchronize acceptance items and implementation boundaries.

## Decision Summary

- This document is the normative text for core syntax, using RFC 2119 keywords; capabilities inside the implementation boundary are not guaranteed.
- Statement termination uses automatic semicolon insertion; multi-line expressions must be wrapped in parentheses.
- For reference types, `T?` and `T` are the same type; no flow-sensitive narrowing is provided; unwrapping uses `as` / `??`.
- `&&` / `||` short-circuit; `??` evaluates the right side only when the left side is `null`.
- Numeric types have no implicit conversions; integer overflow wraps; division by zero and out-of-range shifts panic.
- Tuples `(T1, T2, ...)` are built-in value types with at least two elements, accessed by position `t.0`; no destructuring, labels, or tuple methods.
- Unified function rules: top-level functions, methods, constructors, and lambdas follow one set of explicit function rules (7.10) — explicit types, no default parameters, no named arguments, no variadic parameters; brace bodies (lambdas excepted, allowing a single-expression body); overloads per 4.4 and Part 2 6.8.
- Top-level functions are static by default; `static` may be written or omitted (4.1).
- `Map` / `Set` keys are limited to `String`, integers, and simple enums; `Map.get` returns `null` for missing keys; `getOr` provides a default.
- Generic functions are monomorphized; no constraints, default type arguments, or generic closures.
- This version retains `switch`, `Result` / `try` error handling, `defer` / `errdefer`, `new` object construction, and labeled control; unsupported items are explicitly listed in 0.6.
- The general `switch` does not check exhaustiveness; enum-`switch` exhaustiveness is defined by Part 2 8.5.

## 0. Specification Foundations

### 0.1 Scope

This document defines XNull's core syntax and semantics: lexing, the type system, packages and imports, top-level declarations, local variables, statements and control flow, expressions and operators, closures, generic functions, built-in types, the error-handling core, object-construction expressions, XDK imports, and program entry.

This document does not define:

- Type declarations, inheritance, protocols, enumerations, singletons, extensions, and object memory layout; see Part 2.
- Error observation, cancellation, timeouts, and `ErrorKind` policies; the core syntax is in Section 10, the full model in the Error Handling specification.
- FFI, the C ABI, `unsafe` boundaries, and cross-language ownership; see Part 7 and Part 6.
- Runtime semantics of concurrency, asynchrony, and tasks; the language provides no `async` / `await` syntax — use `xdk.tasks`.
- The complete XDK package APIs; see Part 6.
- Project manifests, build systems, and package management; this document defines only entry resolution.

### 0.2 Specification Language

**MUST**, **FORBIDDEN**, **SHOULD**, and **MAY** are used per RFC 2119. **FORBIDDEN** is equivalent to "must not". **SHOULD** means justified exceptions may exist, but exceptions must be documented in implementation notes.

"Implementation boundary" lists capabilities the current implementation does not guarantee or enforce; behavior inside the boundary is not protected by this document. Syntax not listed in the body or in the implementation boundary must not be treated as supported.

### 0.3 Conformance

An implementation must accept all source programs satisfying this document's **MUST** clauses and produce the observable behavior this document defines. Source programs violating **FORBIDDEN** clauses must be rejected with diagnostics carrying source locations.

An implementation may provide extensions not listed here, but extensions must be explicitly enabled; default builds must not depend on extensions, nor use extensions to alter behavior this document defines. The same source program, implementation version, and compilation options must produce the same diagnostics and run results.

### 0.4 Program Model

A program consists of one or more packages. A package consists of one or more source files; a file belongs to exactly one package. Top-level declarations in a package are visible at package scope; cross-package access must go through `import` or fully qualified names.

The program entry is a top-level `static` function named `main`. At startup, packages, top-level fields, static fields, and singletons are initialized first; then the entry is called.

The compilation-unit grammar is in Appendix A. The compiler must process source programs through the semantic phases "lexing → parsing → type checking → monomorphization → memory analysis → code generation"; the phase split does not constrain internal implementation, but each phase's diagnostics must correspond to this document's clauses.

### 0.5 Versioning and Compatibility

This document uses semantic versioning:

| Version Part | Allowed Changes | Disallowed Changes |
| --- | --- | --- |
| Major | Remove syntax, change semantics, change default behavior | — |
| Minor | Add syntax, add built-in members, add diagnostics | Change the meaning of existing programs |
| Patch | Clarify wording, add examples, fix typos | Change specification constraints |

Within the same major version, source programs conforming to the old version must continue to be accepted, with unchanged observable behavior. Implementations must not silently degrade or ignore incompatible specification versions.

### 0.6 Explicitly Unsupported Syntax

The following features are not part of XNull core syntax. Implementations must reject them and must not emulate them with implicit behavior; when these capabilities are needed, use the alternative in the right-hand column.

| Unsupported | Rationale | Alternative |
| --- | --- | --- |
| Named arguments, default parameters, variadic parameters, spread arguments | Call resolution stays explicit and predictable | Build a DTO / configuration `class`, or explicit overloads |
| C-style `for (init; cond; step)` | `while`, `do-while`, `for-in`, and range loops already exist | `while` + explicit state, or range loops |
| `catch` / `finally`, cross-frame exceptions | Errors must propagate explicitly; implicit unwinding is forbidden; `try` is only for `Result` propagation | `Result` + `try` + `defer` / `errdefer`; fatal errors use `throw` |
| Operator overloading, user-defined implicit conversions | Type behavior stays predictable | Named methods; explicit `as` / `as?` |
| Address-of, pointers, smart pointers, weak-reference modifiers, memory-strategy annotations (`@arc` / `@gc`) | Memory management is fully owned by the compiler and runtime; source must not express reference strength or reclamation strategy | Strategy is adjudicated by the compiler per Part 2 15.1; the runtime executes management; FFI goes through the contract (Memory Management spec §19) |
| Custom accessor properties (property get/set syntax) | XNull defaults to direct read/write of public fields; getters/setters are unnecessary | Direct public-field access; methods for computation, validation, and private state |
| User-defined indexers | The container interfaces already provide them | `get` / `set` / `at` |
| Events | No event syntax is introduced | Closure callbacks or explicit observer lists |
| `if` / `switch` expressions, block expressions | The statement/expression boundary stays clear | Ternary expression, or assignment/return inside branches |
| Standalone `{}` statement blocks | Scope is introduced only by function bodies, control bodies, type bodies, and `defer` bodies | Wrap with `if` / `while` / function bodies |
| `match` / pattern matching | The original `switch` is retained; no separate pattern system is introduced | `switch` + `if` + `Result` members |
| Tuple destructuring, tuple labels, tuple methods, one-/zero-element tuples | Tuples stay anonymous, positional, minimal | Element-by-element access; use `class` / `struct` when named fields or behavior are needed |
| `??=` | No null-coalescing-assignment syntax | `if x == null { x = ... }` |
| `?.()` / `?.[]` | Dot syntax retains only optional member access | Null-check with `if`, then call/subscript |
| Function-type arrow `(P) -> R` | The `R(P...)` form is retained | `R(P...)` |
| `async` / `await`, generators, `yield` | Concurrency is the runtime library's job; no function coloring is introduced | `xdk.tasks` + explicit `TaskGroup` / `Context` |
| `unsafe` blocks, raw pointers, inline assembly, macros | XNull source has no address-of, pointer, or smart-pointer syntax; the safety boundary is in XDK / FFI | `xdk.sys`'s `@unsafe` APIs (Part 7 §8); FFI contracts (Part 7) |
| Conditional compilation, macro expansion, runtime reflection | Build-time and metaprogramming are not language core | Project manifests, code generation, XDK reflection packages |
| Package re-export, explicit export lists | Avoid package-surface bloat and implicit dependencies | Public wrapper types / functions, or direct imports |
| Nested types, local types | Type declarations stay at package top level for cross-package resolution | Top-level types + qualified names |
| Static/instance initializer blocks | Initialization order stays predictable | Field initializers + constructors |
| Multiple inheritance, type classes / traits, implicit conformance | Preserve the nominal-type single-inheritance model | Single inheritance + protocols + composition |
| Class-method overriding, class-hierarchy dynamic dispatch | Ordinary classes only reuse fields/methods; polymorphism goes through protocols only | Protocols + implementing classes |
| Abstract methods, class-hierarchy dynamic contracts | Abstract classes mean only "non-instantiable reuse base"; they establish no class-hierarchy contracts | Protocols + concrete classes |
| Structs, enums, singletons implementing protocols | Protocol implementation is limited to `class` | Wrap or compose with a `class` |
| Struct reference instance fields, reference fallback | `struct` carries only value fields and always copies | Declare a `class` when reference semantics are needed |
| Protocol fields, protocol method bodies, protocol default implementations | Protocols keep only method signatures, avoiding implicit conformance | Concrete-class fields/methods + composition |
| Generic protocols, associated types, protocol generic methods | Protocols are non-generic method-signature contracts | Non-generic protocols + concrete types + method overloads |
| Generic constraints, `where` clauses, default type arguments | Type parameters stay simple; constraint solving is avoided | Protocols + overloads + runtime checks |
| Type aliases / newtypes | XNull type identity is decided directly by declarations; no alias layer is introduced | Write the target type directly; declare a `class` / `struct` for independent identity |
| Package-private / `internal` visibility | The visibility model keeps three modifiers | `private` / `protected` + package splitting |
| Implicit numeric promotion, `Bool`↔integer conversion | Avoid silent cross-type behavior | Explicit literal types, XDK numeric conversions |

### 0.7 Dot Syntax and the No-Pointer Model

- Member access, calls, and optional access all use dot syntax: `value.member`, `value.method()`, `value?.member`, `value?.method()`. `->` is only for lambdas, never for member access or pointer dereference.
- There is no address-of `&` (`&` is bitwise AND only), no pointer types `T*`, no dereference `*p`, no explicit reference-type syntax `&T` / `ref T`, no `ref` / `out` parameter modifiers, no pointer arithmetic, no manual `free`.
- `out` / `in` are only for generic variance, not reference-passing modifiers.
- There are no smart-pointer types: `Box<T>`, `Rc<T>`, `Arc<T>`, `Ref<T>`, `Weak<T>` etc. do not exist. ARC, GC, and stack are compiler-and-runtime memory strategies, not source-level types; source code never writes `retain` / `release`.
- Source code has no weak-reference concept; reference strength and reclamation strategy are fully managed by the compiler and runtime and must not be expressed in source; see Part 2 Section 15.
- Classes, protocols, arrays, containers, `String`, and closures are semantically object handles/reference semantics; you cannot take their address, convert them to integers, do pointer arithmetic, or free them manually.
- FFI, raw pointers, and `unsafe` blocks are not part of XNull language syntax; they are defined by Part 7 (FFI) and Part 6 (XDK). XNull source never contains pointer declarations or dereferences.

## 1. Lexical Rules

### 1.1 Source Files

- Source-file extension `.x`, encoding UTF-8.
- A file may begin with a UTF-8 BOM; the BOM does not participate in column counting.
- Newlines may be LF or CRLF; CRLF is normalized to LF in the lexical phase.
- Line and column numbers start at 1. Columns count Unicode scalar values; implementations may use UTF-16 offsets internally, but diagnostics must convert to scalar columns.

### 1.2 Comments

```text
// line comment, to end of line
/* block comment, non-nesting */
/** doc comment, treated as an ordinary block comment */
```

- Comments are equivalent to whitespace and may appear between any two tokens.
- Block comments do not nest; the first `*/` ends them.
- An unterminated block comment is a lexical error.
- Doc comments have no semantic effect; the compiler must not change types, visibility, or code generation because of doc comments.

### 1.3 Identifiers, Keywords, and Reserved Names

Identifiers:

```text
[A-Za-z_][A-Za-z0-9_]*
```

Only ASCII letters, digits, and underscores are used. Naming conventions serve readability and editor highlighting only, with no semantic effect:

- `PascalCase`: types;
- `UPPER_SNAKE_CASE`: constants;
- `lowerCamelCase`: variables, functions, fields.

Keywords grouped by purpose:

| Purpose | Keywords |
| --- | --- |
| Package and import | `package` `import` `as` |
| Visibility and modifiers | `public` `protected` `private` `final` `static` `const` `var` `abstract` |
| Types and objects | `class` `struct` `protocol` `enum` `singleton` `factory` `extension` `implements` `new` `self` `super` `out` `in` |
| Control flow | `if` `else` `while` `do` `for` `switch` `case` `default` `break` `continue` `return` `throw` `try` `goto` `defer` `errdefer` |
| Type operations | `is` |

`true`, `false`, `null` are literal constants, not keywords, but are forbidden as declaration names.

The following names are reserved for the unsupported capabilities in 0.6 and for future versions, forbidden as identifiers:

```text
async await yield unsafe extern macro
```

`@`-prefixed annotations are recognized separately by the lexer and are not keywords.

The following names are predefined type names and must not be shadowed by user types or type parameters:

```text
Bool Byte Short Int Long UByte UShort UInt ULong Int128 UInt128
Float Double Char void
String Object Any List Set Map Result Text StringBuilder Bytes
```

`Array` is the internal representation name of `T[]` and must not be used as a type name in source.

### 1.4 Literals

#### 1.4.1 Integers

```text
0  42  1_000_000
0xFF  0b1010  0o755
42L  42U  42UL
```

- Decimal, `0x` hexadecimal, `0b` binary, and `0o` octal are supported.
- Underscores may appear only between two digits; not after the radix prefix, not at the start or end of the literal, and never consecutively.
- Suffixes are case-insensitive, but the canonical spellings are `L`, `U`, `UL`. Suffixes must not repeat or combine into other forms.
- Suffixes fix the literal type: `L` is `Long`, `U` is `UInt`, `UL` is `ULong`.
- Unsuffixed integers are target-type literals: with an expected numeric type and a representable value, the expected type applies; with no expected type, `Int` applies; a value outside the target type's range is a compile error.
- The expected type of a suffixed literal must equal the suffix type, otherwise a compile error.
- Integer types are `Byte`, `Short`, `Int`, `Long`, `UByte`, `UShort`, `UInt`, `ULong`, `Int128`, `UInt128`; the width of `Int128` / `UInt128` is in the implementation boundary.
- Integer literals carry no sign; the minus sign is a prefix operator, not part of the literal.

#### 1.4.2 Floating Point

```text
1.0  3.14159  1.0e9  2.5e-3  1.0f
```

- Float literals must contain a decimal point or an exponent; digits are required both before and after the point. `1.` and `.5` are not valid float literals.
- Decimal exponents `e` / `E` are supported, with optional `+` / `-`.
- Underscores may appear only between two digits.
- Unsuffixed float literals are target-type literals: with an expected type, that type applies; otherwise `Double`.
- The `f` suffix fixes `Float`; a `Float` expected type and the `f` suffix must agree.
- Floats are IEEE 754 binary32 (`Float`) or binary64 (`Double`); compile-time rounding is round-to-nearest-even.
- No hexadecimal floats, NaN literals, or infinity literals; these values are produced by XDK numeric APIs.

#### 1.4.3 Characters

```text
'a'  '\n'  '\''  '\\'  '\u{1F600}'
```

Character literals use single quotes; the content must be exactly one Unicode scalar value or one escape sequence. Empty character literals, multi-character literals, and cross-line character literals are lexical errors.

`Char` is a 32-bit value type representing Unicode scalar values in `0..0x10FFFF`, excluding surrogates `0xD800..0xDFFF`. `Char` does not participate in arithmetic and supports only equality and code-point-order comparison; conversion to integers is provided by XDK.

Escape sequences:

| Escape | Value |
| --- | --- |
| `\\` | backslash |
| `\'` | single quote |
| `\"` | double quote |
| `\n` | U+000A |
| `\r` | U+000D |
| `\t` | U+0009 |
| `\0` | U+0000 |
| `\xHH` | exactly two hex digits, value 0..255 |
| `\uHHHH` | exactly four hex digits |
| `\u{H...}` | 1 to 6 hex digits; the value must be a valid scalar |

Unknown escapes, insufficient digits, or values outside valid scalar range are lexical errors.

#### 1.4.4 Strings and Interpolation

| Form | Delimiter | Escapes | Multi-line | Interpolation |
| --- | --- | --- | --- | --- |
| Ordinary string | `"..."` | yes | no | no |
| Raw string | `r"..."` | no | no | no |
| Multi-line string | `"""..."""` | yes | yes | no |
| Raw multi-line string | `r"""..."""` | no | yes | no |
| Interpolated string | `$"..."` | yes | no | yes |

- Ordinary strings cannot span lines; an unterminated string is a lexical error.
- Raw strings do not process backslash escapes; backslashes are kept as ordinary characters. A raw string cannot contain its closing delimiter.
- Multi-line string content is kept verbatim: no indentation trimming, no leading/trailing newline removal. Non-raw multi-line strings still process escapes.
- String literals have type `String`. `String` is an immutable UTF-8 byte sequence; `length()` counts bytes.
- In interpolated strings, `{expression}` is an expression; `{{` produces a literal `{`; a `}` outside interpolation is literal. Interpolation expressions must be complete; parentheses may nest; an unterminated interpolation is a lexical error.
- Interpolation expressions must not be `void`. Allowed formatted values: `String`, `Bool`, integers, `Float`, `Double`, `Char`, `null`, simple enums, tuples whose elements are all formattable (formatted as `(a, b)`, elements applying these rules recursively), and types declaring `String toString()`. `Bool` formats as `true` / `false`, integers as decimal, floats as the shortest round-trippable representation, simple enums by item name, `null` as `null`.
- Interpolation evaluates left to right in source order; after all parts are evaluated they are concatenated into a new `String`. Interpolated strings are not constant expressions.
- Adjacent string literals do not auto-concatenate; use `+` or interpolation.

#### 1.4.5 Boolean and Null

`true` and `false` are `Bool` literals. `null` is the null-value literal, with static type of the internal type `Null`; it can only be assigned to reference types or `T?`.

### 1.5 Operators and Punctuation

Operators are recognized by longest match:

```text
<<=  >>=  ...  ..<  ===  !==  ==  !=  <=  >=  <<  >>
&&  ||  ??  ?.  as?  ->  +=  -=  *=  /=  %=  &=  |=  ^=  ++  --
+  -  *  /  %  =  <  >  !  ?  :  &  |  ^  ~  .  ,  ;  @
```

Punctuation: `(` `)` `{` `}` `[` `]`.

`..<` is a half-open range, `...` a closed range. `as?` is one token, not `as` plus `?`. `?.` is one token.

### 1.6 Statement Termination and Newlines

Go-style automatic semicolon insertion:

- The lexer does not produce newline tokens; every token records its starting line.
- At a newline, if the last token is an identifier, literal, `)`, `]`, `}`, `++`, `--`, `return`, `break`, `continue`, or `throw`, a statement end is automatically inserted.
- No statement end is inserted before `else` or before the `while` of `do`.
- An operator at line start is not a continuation; multi-line expressions must be wrapped in parentheses. Relying on line-start tokens like `+`, `.`, `?.` to continue the previous line is forbidden.
- The `{` opening a body must be on the same line as its header; a newline inserts a semicolon at the header's end.
- The value of `return` / `throw` must be on the same line as the keyword; wrap in parentheses to span lines.
- Explicit `;` is still allowed; multiple statements on one line must be `;`-separated.
- Blank lines and comment lines do not trigger statement ends.
- The semicolons of `package` and `import` are optional.

```x
Int a = 1
Int b = 2
a = a + b

Int c = 1; Int d = 2

Int e = (a + b)

Int f = a
Int g = -b
```

- `e` must be written as a parenthesized multi-line expression; `Int f = a` and `Int g = -b` are two statements.
- The conditions and headers of `if` / `else` / `while` / `do` / `for` / `switch` take no parentheses; bodies must be brace bodies.
- Brace bodies appear only at function, type, control-body, lambda, and `defer` / `errdefer` positions, never as standalone statements.

The semicolons of `package` and `import` are optional. The semicolon after a control body is an optional empty statement.

### 1.7 Lexical Diagnostics

The following must produce lexical errors:

- Unterminated block comments, strings, character literals;
- Illegal escapes, illegal scalar values;
- Illegal number formats, misplaced underscores, suffix conflicts;
- Unrecognized characters;
- Illegal interpolation-expression boundaries.

Lexical errors must carry file, line, and column ranges. The lexical phase may continue scanning to report multiple errors, but must not silently treat error tokens as valid.

## 2. The Type System

### 2.1 Type Classification

| Category | Types | Passing Semantics |
| --- | --- | --- |
| Value types | `Bool` `Byte` `Short` `Int` `Long` `UByte` `UShort` `UInt` `ULong` `Int128` `UInt128` `Float` `Double` `Char` | Copied by value |
| Reference types | `String` `Object` `Any` `T[]` `List<T>` `Set<T>` `Map<K,V>` `Text` `StringBuilder` `Bytes` | Passed as object handles |
| Language-level error type | `Result<T,E>` | Value type; see Section 10 |
| Tuple | `(T1, T2, ...)` | Copied by value; see 2.11 |
| User types | Part 2's `class`, `protocol`, `enum`, `singleton`, `struct` | Defined by Part 2 |
| Function types | `R(P1, P2, ...)` | Reference type; values are closures |
| Void type | `void` | Only as a return type or a function type's return type |

`void` cannot be a variable, parameter, field, generic argument, or container element type. `void()` is a valid function type.

`Object` is the reference-type root; all reference types and `Any` can be assigned to `Object`. Value types must be explicitly boxed as `Any` before they can be used as `Object`.

`Any` is the explicit boxing type; both value and reference types can be boxed via `as Any`. An `Any` boxed value is a GC object; unboxing must use `is` / `as` / `as?`.

### 2.2 Value Types and Numeric Semantics

| Type | Width | Signedness |
| --- | ---: | --- |
| `Byte` / `UByte` | 8 | signed / unsigned |
| `Short` / `UShort` | 16 | signed / unsigned |
| `Int` / `UInt` | 32 | signed / unsigned |
| `Long` / `ULong` | 64 | signed / unsigned |
| `Int128` / `UInt128` | nominal 128 | signed / unsigned; see implementation boundary |
| `Float` | 32 | IEEE 754 |
| `Double` | 64 | IEEE 754 |
| `Char` | 32 | Unicode scalar value |
| `Bool` | logical 1 bit | `true` / `false` |

Integer rules:

- Signed integers use two's complement; unsigned integers share the bit patterns, but comparison, division, and right shift are interpreted unsigned.
- `+`, `-`, `*` overflow wraps modulo 2^width and does not panic.
- Integer division truncates toward zero; `%` follows the dividend's sign. A zero divisor panics; `MIN / -1` wraps to `MIN` at the width.
- The right operand of `<<`, `>>` must be an `Int` or an integer literal adaptable to `Int`. At runtime, shift counts below 0 or at/above the width panic; compile-time constant overflow is a compile error.
- Signed `>>` is arithmetic; unsigned `>>` is logical.
- No implicit conversions between numeric types. Binary arithmetic and bitwise operations require identical types on both sides; literals may adapt to the target type. `Int + Long` is a compile error.
- Unary `-` on unsigned integers wraps at the width; `~` inverts all bits for all integer types; unary `+` accepts only numeric types.

Floating-point rules:

- `Float` / `Double` follow IEEE 754; overflow produces infinity, underflow produces 0 or a subnormal, division by zero produces infinity or NaN — no panics.
- NaN `==` anything (including itself) is `false`; `!=` is `true`.
- No language-level float-to-integer conversion; conversion must use XDK numeric APIs.
- Float literals and operations round to nearest, ties to even.

`Char` rules:

- `Char` is an independent value type and does not participate in arithmetic.
- `Char` supports `==`, `!=`, `<`, `<=`, `>`, `>=`, compared by Unicode code point.
- `Char`↔integer conversion is provided by XDK.

### 2.3 Reference Types and Containers

`String` is an immutable UTF-8 byte sequence, passed as an object handle; string literals, `+` concatenation, and interpolation all produce new `String`s. `String.length()` returns the byte count.

`T[]` is a fixed-length one-dimensional array, passed as an object handle, GC-managed. Multi-dimensional arrays are written as consecutive `[]`, semantically nested arrays: `T[][]` equals `Array<Array<T>>`. The language provides no rectangular matrix or `Tensor` type.

`List<T>`, `Set<T>`, `Map<K,V>` come from `xdk.collections`; they are growable containers and require `import xdk.collections` before use. All three are reference types, GC-managed, with invariant type parameters.

`Text`, `Bytes`, `StringBuilder` come from `xdk.text` and require `import xdk.text` before use. `Text` is immutable UTF-8 text; `Bytes` is a mutable byte buffer; `StringBuilder` is a mutable string builder.

`Result<T,E>` is the language-level error type; `Ok` / `Err` are constructors. `Result` is a value type and may appear in variables, parameters, returns, fields, containers, and closures. Core propagation and handling are in Section 10; error observation, cancellation, and timeouts are defined by the Error Handling specification.

### 2.4 Optional Types

- `T?` denotes an optional type.
- For reference types, `T?` and `T` are the same type; reference types already allow `null`.
- For value types, `T?` is an independent optional value type; `null` is a legal value.
- `T??` equals `T?`.
- Non-optional value types cannot receive `null`.
- `null` may be assigned to any reference type or `T?`.
- `?.` returns `null` when the left side is `null`, otherwise accesses the member; when the member is a value type the result type is `T?`, and when it is a reference type the result stays the reference type.
- `??` returns the right side when the left is `null`, otherwise the left. The left must be a reference type or `T?`; the right must be assignable to the left's non-optional type. The right side is evaluated only when the left is `null`.
- Optional unwrapping: when `T` is a value type and `x` is `T?`, `x as T` checks non-null and yields `T`, panicking on `null`; for reference types `T?` equals `T`, and `as T` performs no non-null check. `x as? T` returns `null` on failure; `x ?? fallback` supplies a default.
- This document provides no implicit flow-sensitive narrowing. `if x != null` does not change `x`'s static type; use `as` or `??` when a non-null value is needed.

```x
Int? maybe = 1;
Int value = maybe as Int;

Int? missing = null;
Int fallback = missing ?? 0;

String? name = null;
String display = name ?? "unknown";
```

### 2.5 Function Types

Function types are written "return-type(parameter-types...)"; parameters are types only, with no names:

```x
Int()
Int(String)
Int(Int, Int)
void()
```

- Function types are reference types and default to `null`-able.
- Function types compare by signature equality: parameter and return types must be exactly identical; function types are invariant.
- Closure literals are checked against the target function type: parameter types must match, and every `return` expression must be assignable to the target return type.
- Calling a `null` function value is a panic.

### 2.6 Assignability

`from` is assignable to `to` if and only if one of the following holds:

| Rule | Condition |
| --- | --- |
| Same type | `from` and `to` are exactly identical |
| Error values | both are `Result<T,E>` with the same `T` / `E` |
| Null | `from` is `null`, `to` is a reference type or `T?` |
| Optional promotion | `from` is `T`, `to` is `T?` |
| Subtyping | `from` is a subclass of `to`, or `from` is a class implementing `to`'s protocol; see Part 2 |
| Generic variance | `from` and `to` are instances of the same generic declaration and pass variance checks; see Part 2 |
| Literals | an integer literal representable in the target integer type; a float literal representable in `Float` / `Double`; a string literal to `String` |
| Container literals | the target supplies the element type and every element is assignable |
| Closure literals | the target is a function type, parameters match, and the return is assignable |
| Tuples | same length and identical element types one by one; tuple-literal elements adapt to the target element types |
| Boxing | `from` is any type, `to` is `Any`; must be written explicitly as `as Any` |
| Reference root | `from` is a reference type or `Any`, `to` is `Object` |
| Unboxing | `from` is `Any`, `to` is a concrete type; must be written explicitly as `as` / `as?` |

Forbidden:

- Implicit widening/narrowing between numeric types;
- `Bool`↔integer conversion;
- Implicit string↔numeric conversion;
- Assigning `null` to a non-optional value type;
- Assigning a value type directly to `Object`;
- Structural type matching: types are checked nominally; identical members do not imply compatibility.

### 2.7 Type Inference

- `var` infers the type from the initializer; the initializer must have a unique, definite static type.
- `null`, empty array `[]`, empty Map `[:]`, and closure literals without a target type cannot be used with `var`.
- Integer/float literals default to `Int` / `Double`; with a target type they adapt to it.
- Generic function type arguments may be omitted and inferred per Section 8.
- Return-type context does not participate in generic inference; write explicit type arguments when needed.
- `var` is for local variables only; top-level and member fields must declare explicit types.
- Tuple literals infer element types from the element expressions; each element must have a unique definite static type.

### 2.8 Equality and Ordering

| Operation | Value Types | `String` | Reference Types | `Any` |
| --- | --- | --- | --- | --- |
| `==` / `!=` | by value | by content | default by object identity | by boxed-object identity |
| `===` / `!==` | by value | by object identity | by object identity | by boxed-object identity |

- Both sides of `==` / `!=` must have the same type, or one side `null` and the other a reference type/`T?`.
- Content comparison of reference types must explicitly call the type's `equals` method; `==` never calls user code.
- `===` / `!==` are strict identity comparison: value types compare values, reference types compare references. `null === null` is `true`.
- `Result` provides no `==` / `===`; use `isOk` / `isErr` / `value` / `error`.
- Tuple `==` / `!=` applies element-type equality per element; `===` / `!==` compares identity per element; both sides must be the same tuple type.
- Ordering `< <= > >=` applies only to identical numeric types, `Char`, and simple enums (by underlying value). `String`, containers, and ordinary reference types do not participate in ordering.
- Float NaN rules are in 2.2.

### 2.9 Type Checks and Casts

- `x is T` returns `Bool`. It returns `false` when `x` is `null`. Value-type checks test the exact runtime type; reference-type checks test dynamic type or protocol conformance.
- `x as T` performs upcasts, downcasts, `Any` unboxing, or optional unwrapping. Failure is a panic.
- `x as? T` behaves like `as` but returns `null` on failure; the result type is `T?`.
- `as` / `as?` do not support numeric conversion and do not support `void` targets.
- Upcasts are identity conversions; downcasts check type descriptors at runtime; protocol casts check conformance.
- Unboxing `Any` to a concrete type checks the boxed type; unboxing `Any` to a protocol checks conformance.
- `x as Any` creates a boxed object for value types and wraps the reference for reference types; boxed objects are GC-managed.
- The targets of `is` / `as` / `as?` must be types, not expressions.

```x
Any boxed = 1 as Any;
if boxed is Int {
    Int value = boxed as Int;
}
Int? maybe = boxed as? Int;
```

### 2.10 Any Boxing

- A value type entering `Any` must be boxed; boxing creates a GC object holding a type descriptor and the value.
- Reference types entering `Any` also produce boxed objects; unboxing recovers the original reference.
- `Any`'s `==` / `===` compare boxed-object identity without auto-unboxing. For value comparison, `as` to a concrete type first.
- Boxed values are reclaimed by GC; boxing does not change the original value's lifetime.
- Boxed values cannot directly participate in arithmetic, comparison, or member access; unbox first.

### 2.11 Tuple Types

```x
(Int, String) pair = (1, "a");
(Int, Int, Bool) triple = (1, 2, true);
var inferred = (1, "a");            // (Int, String)

Int first = pair.0;
String second = pair.1;
```

Form and identity:

- Tuple types are written `(T1, T2, ...)`; at least two elements, element types listed one by one, order significant.
- Tuples are built-in anonymous value types with structural identity: tuples of the same length and identical element types are the same type; no declaration needed.
- `(T)` is not a tuple but the parenthesized form of `T`; no one-element or zero-element tuples exist.
- Tuple elements are numbered from 0 by position; elements have no names or labels.
- Tuples may nest: `((Int, String), Bool)` is a valid type.
- Tuples may be variables, parameters, returns, fields, container elements, closure captures, and generic type arguments.
- Tuples cannot be `switch` values, `Map` / `Set` keys, `const` types, or constant expressions.
- Tuples do not participate in meaningful `is` / `as` conversions; same-type `as` is identity, different types are compile errors.
- Struct-field restrictions on tuples and tuple-field memory layout are in Part 2.

Value semantics:

- Assignment, parameter passing, returning, and storing into containers copy the entire tuple; copies are independent of the original.
- Value elements copy by value; reference elements copy the object handle.
- Tuples allocate no object; all-value-element tuples stay outside ARC/GC. Tuples with reference elements participate in memory analysis per Part 2's rules.

Member access:

- Element access is written `pair.0`, `pair.1`; the token after `.` must be an integer literal within range — out of range is a compile error.
- Tuples have no methods, properties, or other members; `pair.length` is a compile error.
- For an optional tuple `T?`, `?.` applies: `pair?.0` returns `null` when `pair` is `null`; the result is `T?` when the element is a value type.
- Tuple elements are assignable positions: `pair.0 = 2;` requires the tuple itself to be in an assignable position.

Assignability and equality:

- No subtyping exists between tuples; `from` is assignable to `to` iff lengths match and element types are identical one by one.
- Tuple literals adapt each element to the target tuple's element types: an `(Int, String)` target accepts `(1, "a")`.
- `==` / `!=` applies element-type equality per element; `===` / `!==` compares identity per element; both sides must be the same tuple type.

Interpolation:

- Tuples may be interpolated, formatted as `(a, b)`; each element is formatted per 1.4.4's rules recursively; any unformattable element is a compile error.

## 3. Packages and Imports

### 3.1 package

```x
package com.acme.order
```

- At most one `package` per file, at the top of the file (comments excepted).
- The semicolon is optional.
- A package name is a dot-separated identifier sequence with no empty segments.
- Without `package`, the file belongs to the default package. The default package cannot be imported by other packages; it serves single-file programs or entry points only.
- User package names must not begin with `xdk`; `xdk.` is a reserved namespace.
- Package names are case-sensitive; naming conventions have no semantic effect.

### 3.2 import

```x
import xdk.text
import xdk.net.http
import com.acme.common.Thing as AcmeThing
import com.other.Thing as OtherThing
```

- `import` must appear after `package` and before other declarations; the semicolon is optional.
- Importing a package `P` brings all of `P`'s public top-level symbols into file scope; it does not bind a package-namespace alias.
- Importing a symbol `P.S` brings only `S` into file scope.
- `import P.S as A` is allowed only when `S`'s simple name conflicts with another already-imported symbol; `A` is a disambiguating alias, not arbitrary renaming. Using `as` in non-conflict situations is a compile error.
- If the simple name is already taken by another import, the new import must use an `as` alias; otherwise a compile error.
- Package imports cannot alias individual symbols within them; when two packages have same-named symbols, switch to selective `import P.S as A`.
- Re-importing the same package or symbol is allowed and creates no new binding; the same simple name from different sources is a conflict.
- Wildcard imports are forbidden; the package alias `import P as Q` is forbidden.
- XDK packages must be imported explicitly; using an XDK type or static entry without importing is a compile error.
- Imports must not execute user code, register global state, or modify process state. XDK import initialization must be side-effect-free, or triggered explicitly by the caller.
- Non-XDK imports must resolve to packages in the current compilation; reliance on undeclared binary packages is not allowed.
- Fully qualified names are always available: `com.acme.common.helper(value)`.

### 3.3 Name Resolution

Names within a file resolve in this order:

1. Local variables, parameters, type parameters;
2. The current package's top-level declarations;
3. Imported symbols;
4. Fully qualified names.

Type-member resolution is in Part 2 5.8; instance fields may be accessed unqualified, with local variables or parameters shadowing fields and `self` / `super` for disambiguation.

- The current package's top-level declarations shadow same-named imports.
- When two imports provide the same simple name and the current package has no same-named declaration, the new import must use an `as` alias, or fully qualified names must be used; two undisambiguated simple names must not coexist.
- Import aliases must be unique and must not conflict with keywords, predefined type names, or the file's top-level declarations.
- A package name's last segment binds no namespace; different packages may share the same last segment, and symbol conflicts are resolved via `as` or fully qualified names.
- Top-level `private` / `protected` symbols cannot be imported by other packages; they are visible within the package.
- Default-package symbols cannot be imported by other packages.

### 3.4 Multi-Package Compilation

- In multi-package compilation, types and top-level functions carry an internal package prefix; same-named types in different packages may coexist.
- Cross-package references must go through `import` or fully qualified names; the compiler must not resolve cross-package symbols by file order.
- The package import graph must be acyclic; a detected cycle is a compile error.
- Declaration order within a package does not affect visibility; functions, types, and top-level fields may reference each other forward (initialization order in 4.3).

### 3.5 Import Diagnostics

The following must be reported as errors:

- Non-existent package or symbol;
- Wildcard use;
- XDK package not explicitly imported;
- Importing another package's `private` / `protected` top-level symbols;
- Default-package symbols imported across packages;
- `as` aliases in non-conflict situations;
- Import alias conflicts or undisambiguated simple names;
- Import cycles;
- User packages using the `xdk` prefix.

## 4. Top-Level Declarations and Statics

### 4.1 Top-Level Functions

```x
static Int add(final Int left, Int right) {
    return left + right;
}

static void notify(final String message) {
    handle(message);
}
```

- Top-level functions are static by default: `static` may be written or omitted, both equivalent; writing `static` is an explicit style, omitting it changes nothing.
- The return type precedes the function name; write `void` when there is no return value.
- Parameter order is fixed: type first, name second.
- Parameters may be `final`; `final` parameters cannot be reassigned inside the function.
- Top-level functions may be overloaded, resolved by parameter count and types; the return type does not participate in overloading.
- Only ordinary and `final` parameters are supported; no default parameters, variadic parameters, named arguments, or spread arguments.
- Top-level functions must have bodies; this document provides no body-less declarations.
- Top-level functions may be recursive or mutually recursive.
- Top-level functions are public by default; `private` / `protected` only restrict cross-package imports.

### 4.2 Top-Level Fields

```x
static Int nextId = 0;

Int version = 1;
final Int build = 42;
const Int limit = 10;
```

- Top-level fields may be written `static` or declared directly; both spellings are semantically identical.
- Fields are mutable by default; `final` initializes once; `const` requires a compile-time constant.
- Top-level fields must declare explicit types; `var` is for local variables only.
- Mutable top-level fields may omit initializers, in which case they take zero values: 0 for numerics, `false` for `Bool`, `'\0'` for `Char`, `null` for references.
- A `final` top-level field must be initialized once at its declaration; the language provides no top-level assignment statements, so post-hoc assignment is unsupported.
- A `const` field must have a compile-time-constant initializer and is implicitly `static`.
- Top-level fields belong to the current package; cross-package access via import or fully qualified names.
- Top-level reference fields are global roots; ARC objects are retained, GC objects are traced.

### 4.3 Initialization Order

At program startup, initialization proceeds in this order:

1. All top-level and static fields are first set to zero values.
2. Packages are initialized in topological dependency order; within a package, file order is given by the project manifest, defaulting to path lexicographic order; within a file, declaration order.
3. Initializers of top-level fields, static fields, and singletons execute.
4. `main` is called after all initialization completes.

Rules:

- An initializer reading a not-yet-initialized field reads the zero value, without error.
- `const` does not participate in runtime initialization.
- The package import graph must be acyclic; a cycle is a compile error.
- Initializers may call functions; the callee sees the currently completed initialization state.
- Singleton initialization order is in Part 2.
- A panicking initializer terminates the process; `main` is never called.

### 4.4 Overload Resolution

- Candidates are filtered by parameter count, then checked for applicability by parameter types.
- The return type does not participate in overloading; differing only in return type is not a valid overload.
- A `null` argument has no concrete type; if multiple reference-type candidates apply, resolution is ambiguous and an explicit cast is required.
- Integer/float literals adapt to the parameter type; if multiple candidates can represent the literal, resolution is ambiguous and an explicit type must be written.
- No candidates or multiple best candidates is a compile error.

### 4.5 Visibility

- Top-level declarations are public by default.
- `public` is explicit publicity; `private` allows same-package access only; `protected` at top level equals `private`, providing no additional semantics.
- Visibility is a compile-time check only; it does not change layout, memory, or runtime behavior.
- Other packages' `private` / `protected` top-level symbols cannot be imported or accessed via fully qualified names.

## 5. Local Variables

### 5.1 Declaration Forms

```x
Int total = 0;
final Int answer = 42;
const Int limit = 10;
var count = 1;
```

- Typed local variables: `Type name [= expression];`; may be initialized at declaration or definitely assigned once later.
- `final`: bound once; may be initialized at declaration or definitely assigned once later.
- `const`: a compile-time constant; must have an initializer; the type must be a constant type.
- `var`: type inferred from the initializer; must have an initializer; local variables only.
- One statement declares one variable.
- Local variables must have either an explicit type or `var`; omitting both is not allowed.
- Uninitialized local variables must be definitely assigned before being read; otherwise a compile error.

### 5.2 Scope

- A local variable's scope runs from its declaration to the end of its enclosing function body, control body, `case`, or `defer` body.
- Brace bodies may nest: function bodies, control bodies, `defer` bodies, and closure bodies; standalone `{}` cannot create scope.
- Redeclaring a same-named variable in the same scope is a compile error.
- Parameters live in the function body's top-level scope; the body's top level cannot declare locals named like parameters.
- The `for` loop variable's scope is the loop body; each iteration creates a new binding.
- Each `case` / `default` clause of a `switch` is an independent scope.

### 5.3 Definite Assignment

- A local variable must be definitely assigned before being read; otherwise a compile error.
- A `final` local must be assigned exactly once on every normal path.
- A `const` local is initialized at declaration.
- A `var` is initialized at declaration.
- Definite assignment across branches, loops, and `goto` is analyzed on the control-flow graph; `while true` loops without reachable `break` impose no later assignment requirement.
- The error return path of `try` imposes no later assignment requirement; the success path continues per normal control-flow analysis.
- `goto` jump edges are folded into the same control-flow-graph analysis: whether variables are considered assigned at the jump target follows 6.10's rules; `goto` must not be used to make unassigned variables "pass" the definite-assignment check.
- Unread, uninitialized variables may remain unassigned after declaration.

### 5.4 Constant Expressions

Constant expressions consist of:

- Literals;
- Other `const` constants;
- Unary, binary, ternary operators with all operands constant expressions;
- `String + String`;
- Simple enum items (Part 2).

Constant expressions must not contain function calls, object creation, container literals, tuple literals, interpolated strings, assignments, increment/decrement, or `as` / `as?` runtime checks.

Types allowed for `const`: `Bool`, integer types, `Float`, `Double`, `Char`, `String`, simple enums, and `null` with a reference type. `const` does not allow class instances, containers, arrays, closures, or `Any` boxing.

## 6. Statements and Control Flow

### 6.1 Statement Classification

| Statement | Form | Rules |
| --- | --- | --- |
| Local declaration | `Int x = 1;` | see Section 5 |
| Expression statement | `f();` | result discarded |
| Assignment | `x = 1;`, `x += 1;` | left side must be assignable |
| Increment/decrement | `i++;`, `--i;` | integer types only; statement-only |
| `if` / `else` | `if cond { } else { }` | condition must be `Bool` |
| `while` | `while cond { }` | condition must be `Bool` |
| `do` / `while` | `do { } while cond` | condition must be `Bool` |
| `for-in` | `for x in src { }` | iterates arrays, List, Set |
| Range loop | `for i in 0..<n` / `0...n` | loop variable is `Int` |
| `switch` | `switch value { case v: ... default: ... }` | no implicit fallthrough |
| `defer` / `errdefer` | `defer body` / `errdefer body` | scope cleanup; see Section 10 |
| `break` / `continue` | `break [label]` / `continue [label]` | nearest loop/`switch`, or the named label |
| `label` / `goto` | `name: stmt` / `goto name` | same-function jumps |
| `return` | `return value` / `return` | all normal paths of non-`void` functions must return |
| `throw` | `throw value` | fatal/panic; not a recoverable error |
| Empty statement | `;` | no operation |

Assignment, increment, and decrement are statements, not expressions.

### 6.2 Brace Bodies

```x
if ready {
    Int x = 1;
    while x < 3 {
        x++;
    }
}
```

- `{ ... }` is the syntactic form of function bodies, control bodies, type bodies, lambda bodies, and `defer` / `errdefer` bodies — not a standalone statement.
- Writing `{ ... }` directly as a statement is a compile error; for independent scope use `if` / `while` / functions or other structured control bodies.
- A brace body creates a new scope; declarations inside it are invisible after the body ends.
- Brace bodies may nest inside control bodies, function bodies, or closure bodies; nested bodies may shadow outer same-named variables.
- A brace body cannot be an expression; there are no block expressions.

### 6.3 Expression Statements

```x
compute();
value.method();
```

- Expression statements evaluate and discard the result.
- Assignment, increment, and decrement cannot appear in expression positions; `a = (b = 1)` is a compile error.
- An expression statement's result type may be anything; `void` calls are also valid expression statements.

### 6.4 Assignment and Increment/Decrement

```x
total = total + 1;
total += 1;
values[0] = 1;
list[0] = 2;
i++;
--i;
```

- Assignable positions: non-`final` locals, non-`final` parameters, writable fields, array elements, `List` elements, elements of assignable tuples.
- `Map` does not use subscript assignment; use `put`.
- `String` does not use subscript assignment.
- Compound assignment reads the left side once, evaluates the right, applies the operator, and writes back.
- The compound-assignment intermediate result must be assignable to the left type; `Int += Long` is a compile error.
- `++` / `--` apply to integer types only; the operand must be assignable; as a statement the result is discarded.
- `final` variables, `final` fields, `@ReadOnly` fields from outside, and private fields outside their class are all non-assignable.
- An assignment statement has no value; assignments must not be chained.

### 6.5 if / else

```x
if condition {
    handle("yes");
} else if other {
    handle("maybe");
} else {
    handle("no");
}
```

- Conditions must be `Bool` and take no outer parentheses.
- The bodies of `if` / `else` must be brace bodies; single-statement bodies are unsupported.
- `else` pairs with the nearest unclosed `if`; because bodies are forced to braces, there is no dangling else.
- `else if` is syntactic sugar for a nested `if`.

### 6.6 while / do-while

```x
while condition {
    ...
}

do {
    ...
} while condition;
```

- Conditions must be `Bool` and take no outer parentheses.
- The bodies of `while` / `do-while` must be brace bodies; single-statement bodies are unsupported.
- `do` executes the body first, then tests the condition.
- `continue` in `do-while` jumps to the condition test.

### 6.7 for-in and Ranges

```x
for item in items {
    handle(item);
}

for i in 0..<n {
    total += i;
}

for i in 0...n {
    total += i;
}
```

- `for item in source` iterates `T[]`, `List<T>`, `Set<T>`; a `Map` cannot be iterated directly — take `keys()` or `values()` first.
- The loop variable is a new local binding; each iteration creates a new binding, and closures capture per-iteration values independently.
- Iterating `struct` elements copies by value; reference types copy the object handle. Structs have no "non-copyable" branch.
- The loop variable may be reassigned, but writes never flow back into the container.
- Range `a..<b` is half-open, `a...b` closed; both operands must be `Int`, evaluated once at loop start.
- If the lower bound exceeds the upper, the range loop executes zero times.
- Range expressions are allowed only in the `for-in` source position; use elsewhere is a compile error.
- The `for` header takes no parentheses; the `for` body must be a brace body.
- `break` exits the loop; `continue` enters the next round.

### 6.8 switch

```x
switch value {
    case 1:
        handle("one");
    case 2:
        handle("two");
    default:
        handle("other");
}
```

- The `switch` value takes no outer parentheses.
- The `switch` value is evaluated exactly once.
- `case` expressions are evaluated in source order until the first equality match; later `case`s are not evaluated.
- After a `case` matches, its clause executes and the `switch` automatically exits — no implicit fallthrough.
- `case` expressions need not be compile-time constants; `switch` does not check exhaustiveness by default. When the `switch` value is an enum, exhaustiveness is checked per Part 2 8.5: without `default`, all enum items must be covered.
- At most one `default`, which must come last.
- Each `case` / `default` clause is an independent scope; variables declared within do not leak into other clauses.
- `break` exits the `switch`; `continue` applies to the nearest enclosing loop, erroring when none exists.
- The `switch` value type must be `Bool`, integer, `Char`, `String`, a simple enum, or a reference type; `Float` / `Double`, `Result`, and tuples are not allowed as `switch` values.
- `case` expressions must be assignable to the `switch` value type; comparison uses `==` semantics.

### 6.9 break / continue / return / throw

- `break` exits the nearest loop or `switch`; outside both is a compile error.
- `continue` enters the nearest loop's next round; outside a loop is a compile error; inside a `switch` it applies to the enclosing loop.
- `break label` exits the loop or `switch` carrying that label; `continue label` enters the named loop's next round.
- Labels must be in the same function, and `continue label`'s target must be a loop; `break label` may point at a loop or a `switch`.
- Labeled `break` / `continue` are structured control flow and execute `defer` / `errdefer` on scope exit; `goto` does not.
- `return value` may appear only in non-`void` functions; `value` must be assignable to the return type.
- `return;` may appear only in `void` functions, constructors, or `deinit`.
- All normal paths of a non-`void` function must return values; paths terminated by `throw` need not.
- `throw value` is fatal/panic: it prints the diagnostic and call stack, then terminates the process. `throw` is not a recoverable error; use `Result<T,E>` for recoverable errors.
- `throw` does not unwind the stack and does not guarantee execution of `deinit` or cleanup logic.
- `throw`'s operand must be a `String` or a type implementing `Error`; strings print verbatim.

### 6.10 label / goto

```x
Int i = 0
start:
i++
if i < 3 {
    goto start;
}
```

- A label is written `name:`, followed by one statement; the empty statement is written `name: ;`.
- Labels may sit on loops or `switch`es for `break label` / `continue label`, or on other statements for `goto`.
- Label names are unique within a function; labels and variables use separate namespaces.
- `goto name` jumps to a label within the same function; not across functions or lambdas.
- The target label must be in the current function body/control body or an enclosing one; jumping from an outer body into an inner body is forbidden.
- When `goto` jumps out of a function body/control body, no cleanup, `deinit`, or `defer` executes; external resources must be managed with structured control flow.
- After a `goto` jump, uninitialized local variables remain uninitialized; reading them is a compile error.
- Duplicate and undefined labels are compile errors; `break label` / `continue label` targeting the wrong kind is also a compile error.

### 6.11 Empty Statement

```x
;
label: ;
```

The empty statement does nothing. It may serve labels or empty loop bodies. It must not be used as an expression requiring a value.

### 6.12 Control-Flow Diagnostics

The compiler must reject:

- Non-`Bool` conditions;
- `break` outside loops/`switch`;
- `continue` outside loops;
- Standalone `{ ... }` used as a statement;
- `break label` / `continue label` pointing at nonexistent labels or wrong target kinds;
- Non-`void` functions with unreturned normal paths;
- `void` functions returning values;
- Duplicate, undefined, or cross-scope `goto`;
- Incompatible `case` expression types;
- `switch` values using `Float` / `Double` / `Result`;
- `defer` / `errdefer` bodies containing control transfers, `try`, or `throw`;
- `errdefer` or `try` in functions not returning `Result`;
- `if` / `else` / `while` / `do` / `for` / `switch` bodies that are not brace bodies.

## 7. Expressions and Operators

### 7.1 Primary Expressions

- Literals, identifiers.
- Member access: `value.member`, `value.method()`.
- Optional member/call: `value?.member`, `value?.method()`.
- Subscripts: `array[index]`, `list[index]`.
- Calls: `f(args)`, `value.method(args)`.
- Object construction: `new Type(args)`; rules in Part 2, the syntax is legal in this document.
- Explicit generic arguments: `identity<Int>(1)`.
- Array/collection literals: `[1, 2, 3]`; `Set` also uses `[...]`, decided by the target type.
- Fixed-array creation: `new T[count]`, e.g., `new Byte[4096]`; `count` must be `Int`, elements zero-initialized, the result is `T[]`.
- Map literals: `["a": 1, "b": 2]`; the empty Map is written `[:]`.
- Tuple literals: `(1, "a")`; at least two elements; type and access rules in 2.11.
- Closures: `() -> { ... }`, `(Int x) -> { ... }`.
- String interpolation: `$"value={total}"`.
- `Result` propagation: `try expression`; `Result`-only, see 10.2.

### 7.2 Operators and Precedence

Precedence, highest to lowest:

```text
postfix / call / subscript / member
prefix operators (including try)
* / %
+ -
<< >>
..< ...
< <= > >= is as as?
== != === !==
&
^
|
&&
||
??
cond ? a : b
```

- Postfix, call, subscript, and member are left-associative.
- Arithmetic, shift, bitwise, and logical operations are left-associative.
- `??` is right-associative.
- The ternary is right-associative; the condition must be `Bool`, and the two branches must share a common type, or one side `null` and the other a reference type.
- Comparisons cannot be chained; `a < b < c` is a compile error — parenthesize and state the intent explicitly.
- Range operations cannot be chained and are allowed only in the `for-in` source position.
- Assignment is handled separately as a statement and does not participate in expression precedence.

Rules:

- `String + String` concatenates; strings and numerics cannot be directly `+`-ed — use `$"..."` interpolation.
- Arithmetic requires identical numeric types on both sides; literals may adapt.
- `&&` / `||` require `Bool` on both sides; short-circuit: `&&` skips the right when the left is `false`, `||` skips when the left is `true`.
- `??`'s left must be a reference type or `T?`; the right is evaluated only when the left is `null`.
- `a != null && a.f()` relies on short-circuiting: if `a` is `null`, the right side never executes.
- `==` / `!=` default to value comparison; `String` compares by content; reference types' default comparison is object identity; content comparison uses the type's `equals`.
- `===` / `!==` are strict identity comparison.
- `is` / `as` / `as?` target types.
- Generic calls may omit inferable type arguments.
- Unary `!` accepts only `Bool`; unary `-` / `+` only numerics; `~` only integers.
- `try expr` is `Result`-only; on failure it returns the error per 10.2.
- `new` is a primary expression; `new Type(args)` constructs an object, `new T[count]` creates an array.
- `?` serves only the optional-type suffix and the ternary; it is no longer a `Result`-propagation suffix.

### 7.3 Evaluation Order

Except for the ternary and `?.`, expressions evaluate left to right; side-effecting subexpressions must not be reordered:

- Binary operations: left, then right.
- Calls: the callee first, then arguments left to right.
- Assignment: the left-side address first (including subscript expressions), then the right, then the write-back.
- Compound assignment: read the left once, evaluate the right, apply the operator, write back.
- `try` propagation: evaluate the operand first; on `Ok` unwrap and continue, on `Err` execute the current scope's `defer` / `errdefer` and return the error.
- `&&` / `||`: left, then right; the right is skipped on short-circuit.
- `??`: left, then right; the right is skipped when the left is non-`null`.
- Ternary `cond ? a : b`: evaluate `cond` first, then only the chosen branch.
- `?.`: evaluate the left first; when `null`, skip member access and argument evaluation, yielding `null`; otherwise continue.
- `new Type(args)`: evaluate constructor arguments left to right, then allocate and call the constructor.
- `new T[count]`: evaluate `count` first, then allocate and zero-initialize.
- Array literals: elements evaluated left to right.
- Map literals: each key then value, pairs left to right.
- Tuple literals: elements left to right.
- Interpolated strings: parts evaluated in source order.

### 7.4 Numeric and Comparison Operations

- Binary arithmetic and bitwise operations require identical types on both sides; integer literals may adapt to the other side's type.
- `+ - * /` apply to integers and floats; `%` to integer types only; float remainder via XDK.
- `& | ^ ~ << >>` apply to integer types only.
- The right operand of `<<` / `>>` must be `Int`; the result has the left operand's type.
- Comparisons require identical types on both sides; `null` compares only with reference types/`T?`.
- `String` supports only `==` / `!=` / `===` / `!==`; ordering uses `Text.compareTo` or XDK.
- Reference types support only `==` / `!=` / `===` / `!==`; no `<`-style ordering is provided.
- `Bool` supports only `==` / `!=` / `===` / `!==`; it does not participate in ordering.

### 7.5 Optional Chains and Null Coalescing

```x
String? name = user?.name;
Int length = name?.length() ?? 0;
```

- `a?.b` returns `null` when `a` is `null` and never accesses `b`.
- `a?.m(args)` does not evaluate `args` when `a` is `null`; the return type is the original return type optionalized.
- Chained `a?.b.c`: `?.` protects only the immediately adjacent member access; if `a` is non-null but `b` is `null`, `.c` still panics. Protect the whole chain with `?.` at each level.
- `??` removes one level of optionality; `T??` equals `T?`.
- `??` evaluates the right side only when the left is `null`.

### 7.6 Type Operations

- `x is T`: returns `Bool`; `false` when `x` is `null`.
- `x as T`: upcast, downcast, unbox, or optional unwrap; failure panics.
- `x as? T`: returns `null` on failure, result type `T?`.
- The right operand of `as` / `as?` must be a type, not an expression.
- For value types, `is` checks the exact type; for reference types, `is` checks dynamic type or protocol conformance.
- `as` to a superclass or an implemented protocol is an upcast with no runtime check.
- `as` to a subclass, a non-implemented protocol, or a concrete `Any` type requires a runtime check.
- `Result`'s `is` / `as` check by concrete type; no implicit conversion.

### 7.7 Closure Expressions

```x
Int() counter = () -> {
    Int value = 0;
    return () -> {
        value = value + 1;
        return value;
    };
};

Int(Int) add = (Int x) -> {
    return x + 1;
};

Int(Int) inc = (Int x) -> x + 1;   // single-expression body, equivalent to add above

Int(Int, Int) sum = (Int a, Int b) -> {
    return a + b;
};

static Int apply(Int(Int) f, Int value) {
    return f(value);
}

Int result = apply(add, 1);
```

- Closure syntax: `(parameter list) -> { statements }`; zero parameters written `()`; parameter types are mandatory.
- Closure parameters have only type and name and may be `final`; no annotations, defaults, or variadic parameters.
- With a target function type, each `return` is checked against the target return type; without one, the first `return`'s type is the candidate and all other `return`s must be assignable to it; with no value returned, `void` is inferred.
- Closure bodies have two forms: the brace body `(params) -> { statements }`, or the single-expression body `(params) -> expression`.
- The single-expression body abbreviates `{ return expression; }`: the expression is checked against the target return type, or per 7.7's `return` inference rules without one; its evaluation, error, and definite-assignment semantics are exactly `return`'s.
- The expression in a single-expression body cannot be an assignment, increment/decrement, or bare block; write a brace body when side effects are needed.
- Closures capture outer locals, parameters, and `self` by reference.
- Captured variables are promoted to heap cells; all later reads and writes go through the cell.
- Multiple closures capturing the same variable share one cell; mutations are mutually visible.
- Nested closures share outer cells.
- No by-value capture syntax; the language has no weak references, hence no weak capture.
- Captured variables need not be `final`.
- Closure values are GC objects; closures, environments, and cells are all GC-managed. Memory details in Part 2.
- Closures may nest, be passed as arguments, returned, stored in containers and fields.
- Closures may return `Result`; when doing so they may use `try`, `defer`, `errdefer` — errors return from the closure only, never piercing the outer function.
- `try` inside a closure requires the closure's target return type to be `Result<_, E>`; without a target type and uninferable as `Result`, it is a compile error.
- Closure literals may be invoked immediately: `((Int x) -> { return x + 1; })(1)`.
- Calling a `null` closure is a panic.

### 7.8 String Interpolation

- Interpolated strings are `$"..."`; `{expression}` is evaluated and formatted per 1.4.4's rules.
- `{{` produces a literal `{`; a `}` outside interpolation is literal.
- Interpolation expressions cannot be `void` and cannot contain unpaired `}`.
- Interpolation expressions may contain nested parentheses, closures, and generic calls.
- `Result` is not interpolated directly; check, unwrap, or call an explicit formatting API first.
- Format specifiers like `{value:X}` are unsupported; use XDK formatting APIs explicitly.
- The result is a new `String`, not a constant expression.

### 7.9 Constant Expressions

See 5.4. Constant folding in expressions must not change overflow, panic, or evaluation-order semantics; expressions containing runtime checks cannot be folded.

### 7.10 Unified Function and Lambda Rules

Top-level functions (4.1), class and struct methods, constructors (Part 2 6.2, 6.3), and lambdas (7.7) follow one set of function rules:

- Uniform parameter forms: parameters have only type and name and may be `final`; no annotated parameters, defaults, variadic parameters, named arguments, or spread arguments.
- Uniform body forms: functions, methods, and constructors must have brace bodies — no expression bodies; lambdas are the exception, allowing single-expression bodies (7.7). Bodies are mandatory; no body-less declarations.
- Uniform type annotations: function, method, and constructor parameter and return types must be explicit; lambda parameter types must be explicit, with return types inferred per 7.7 or checked against the target — no `var`-style parameter omission.
- Uniform calling: arguments always pass positionally; overloads resolve per 4.4 and Part 2 6.8; `Result` and `@mustUse` rules apply uniformly to all function forms.
- Dispatch is the only difference: methods have receivers, dispatched statically or via vtable per Part 2 5.6; lambdas are first-class function values.

## 8. Generic Functions

### 8.1 Declaration

```x
static T identity<T>(T value) {
    return value;
}

static T first<T>(T[] values) {
    return values[0];
}
```

- Type parameters are written in `<...>` after the function name; only parameter names — no constraints, default types, variadic type parameters, or variance annotations.
- Type parameters are visible only within the current function's signature and body.
- Type parameters must not duplicate other type parameters of the same function.
- Type parameters may be used in parameters, returns, locals, generic arguments of field access, and nested types; they may bind `Result`, function types, and container types.
- Generic functions may overload ordinary functions; resolution in 8.2.
- Generic functions cannot be used as values directly; they must be instantiated first.

### 8.2 Calls and Inference

- Explicit type arguments: `identity<Int>(1)`; the count must match the type-parameter count.
- When type arguments are omitted, the compiler unifies argument types against parameter types:
  - A type parameter directly matching an argument type binds;
  - Nested types match level by level, e.g., `List<T>` against `List<Int>` yields `T = Int`;
  - Conflicting bindings for the same type parameter are errors;
  - Unbound type parameters remaining at the end are errors.
- Unsuffixed integer/float arguments bind `Int` / `Double` absent other constraints; if the same type parameter is already bound by another argument, the literal adapts to that type.
- Return-type context does not participate in inference; write explicit type arguments when needed.
- Overload resolution filters by parameter count first, then checks each candidate's applicability; generic candidates infer type arguments during the check.
- With one applicable candidate, it is chosen; multiple applicable candidates is an ambiguity error; zero candidates is a compile error.
- A `null` argument cannot uniquely determine a type parameter; write explicit type arguments or convert.

### 8.3 Monomorphization

- Each distinct type-argument list generates an independent function instance; instance names are encoded internally by the compiler and never exposed to source.
- After monomorphization, generic functions contain no type parameters; each instance is type-checked and memory-analyzed by concrete type.
- A type parameter cannot be `void`; explicit or inferred `void` is a compile error.
- `is T` / `as T` may be used inside generic functions; after monomorphization they check by concrete type.
- `new T()` cannot be written inside generic functions; type parameters are not constructible runtime types.
- Recursive monomorphization must terminate; the compiler must detect infinite expansion and report. Implementations may use a depth cap, but exceeding it must produce a diagnostic — never silent truncation.
- Generic function bodies must be visible at instantiation points; cross-package generic functions must carry templates or intermediate representations sufficient for instantiation.

### 8.4 Restrictions

- No type constraints, `where` clauses, default type arguments, or variadic type parameters.
- No generic closures; use generic functions when generic behavior is needed.
- No static local variables declared inside generic functions.
- No taking references to generic functions for deferred instantiation.

## 9. Built-in Types and Common Members

### 9.1 Summary Table

| Type | Source | Category | Key Members |
| --- | --- | --- | --- |
| `String` | language | reference, immutable UTF-8 | `length` `substring` `indexOf` `trim` `split` `replace` `toUpper` `toLower` |
| `T[]` | language | reference, fixed length, GC | subscript, `length`, `join` |
| `List<T>` | `xdk.collections` | reference, growable, GC | `push` `insert` `set` `get` `remove` `clear` `length` |
| `Map<K,V>` | `xdk.collections` | reference, hash table, GC | `put` `get` `getOr` `has` `remove` `clear` `length` `keys` `values` |
| `Set<T>` | `xdk.collections` | reference, hash set, GC | `add` `has` `at` `remove` `clear` `length` |
| `StringBuilder` | `xdk.text` | reference, mutable, GC | `append` `toString` `length` |
| `Text` | `xdk.text` | reference, immutable UTF-8 | `fromString` `length` `codePointCount` `toString` |
| `Bytes` | `xdk.text` | reference, mutable byte buffer | `fromString` `get` `set` `push` `append` `slice` `length` |
| `(T1, T2, ...)` | language | value type | `.0` `.1`…; see 2.11 |
| `Result<T,E>` | language | value type, `@mustUse` | `isOk` `isErr` `value` `error` `unwrapOr`; see 10.1 |

### 9.2 String

```x
String text = "a,b";
Int length = text.length();
String part = text.substring(0, 1);
Int index = text.indexOf(",");
String trimmed = text.trim();
Bool starts = text.startsWith("a");
Bool ends = text.endsWith("b");
String[] parts = text.split(",");
String replaced = text.replace("a", "x");
String upper = text.toUpper();
String lower = text.toLower();
String joined = parts.join("-");
```

- `length()` returns the UTF-8 byte count.
- `substring(start, length)` slices by bytes; `start` below 0 clamps to 0, beyond the length clamps to the length; `length` below 0 clamps to 0; overflow at the tail truncates to the end. The result is always a new `String`.
- `indexOf(needle)` returns the first matching byte offset; `-1` when not found.
- `trim()` removes leading/trailing ASCII whitespace: `0x09`, `0x0A`, `0x0B`, `0x0C`, `0x0D`, `0x20`.
- `startsWith` / `endsWith` compare by byte prefix/suffix.
- `split(separator)` splits by a non-empty separator; empty segments are kept; with an empty separator it returns a one-element array containing the original string.
- `replace(from, to)` replaces all non-overlapping matches; with an empty `from` it returns the original string.
- `toUpper()` / `toLower()` convert ASCII letters only; Unicode case conversion uses `xdk.text`.
- `String` supports no subscripts, `length` property, or in-place mutation; use `Text` / `Rune` for code-point operations.
- `String + String` produces a new string; `String` and numerics cannot be directly `+`-ed.

### 9.3 T[]

```x
Int[] values = [1, 2, 3];
Int first = values[0];
values[1] = 9;
Int length = values.length();
String text = values.join(",");
```

- `T[]` is a fixed-length one-dimensional array; literals `[...]` create it, length set by element count.
- `new T[count]` creates an array of the given length, zero-initialized; `count` must be `Int`; negative or failed allocation panics; `T` cannot be an array type.
- Subscripts start at 0; out-of-bounds panics.
- Both subscript reads and writes are supported.
- `length()` returns the element count.
- `join(separator)` formats elements into strings joined by the separator; elements must be formattable.
- Multi-dimensional arrays are nested arrays; no rectangular matrix or `Tensor`.
- No `push` or length changes; use `List<T>` for growable containers.
- `T[]` is a reference type; variable assignment copies the object handle, not the array. `struct` elements copy by value on write/read; reference elements copy the object handle.
- Array element types are invariant; `String[]` cannot be assigned to `Object[]`.

### 9.4 List

```x
List<Int> list = [1, 2];
list.push(3);
list.insert(1, 9);
list.set(0, 7);
Int first = list.get(0);
Int removed = list.remove(0);
list.clear();
Int length = list.length();
```

- `List<T>` is a growable array; insertion order preserved.
- `push(value)` appends to the tail, amortized O(1).
- `insert(index, value)` inserts at position `0..length`; out-of-bounds panics.
- `set(index, value)` replaces; out-of-bounds panics.
- `get(index)` reads; out-of-bounds panics.
- `remove(index)` deletes and returns the element; out-of-bounds panics; later elements shift forward.
- `clear()` empties; `length()` returns the element count.
- `list[index]` reads equivalent to `get(index)`; `list[index] = value` equivalent to `set(index, value)`.
- `List<T>` is a reference type, GC-managed; type parameters invariant.

### 9.5 Map

```x
Map<String, Int> table = ["a": 1];
table.put("b", 2);
Bool has = table.has("a");
Int? value = table.get("a");
Int fallback = table.getOr("missing", 0);
table.remove("a");
table.clear();
Int length = table.length();
String[] keys = table.keys();
Int[] values = table.values();
```

- `Map<K,V>` is a hash table; keys unique.
- Since v3.0.0, key types support only `String`, integer types, and simple enums; other key types are compile errors. Integers and simple enums encode as `Int`.
- The empty Map is written `[:]`; non-empty literals `[key: value, ...]`; duplicate keys — later overrides earlier.
- `put(key, value)` inserts or overwrites; returns no old value.
- `get(key)` returns `V?`; `null` when the key is absent — no panic.
- `getOr(key, fallback)` returns `V`; the fallback when the key is absent.
- `has(key)` reports key existence.
- `remove(key)` deletes the key; a no-op when absent.
- `clear()` empties; `length()` returns the pair count.
- `keys()` / `values()` return the current key/value arrays; the order is stable while the container is structurally unmodified, but the language does not specify it. Callers sort when order matters.
- `Map` cannot be `for-in`-ed directly; take `keys()` or `values()` first.
- `Map` is a reference type, GC-managed; type parameters invariant.

### 9.6 Set

```x
Set<String> tags = ["x", "y"];
tags.add("z");
Bool has = tags.has("y");
String first = tags.at(0);
tags.remove("x");
tags.clear();
Int length = tags.length();
```

- `Set<T>` is a hash set; elements unique; insertion-order preservation is not a language guarantee.
- Element-type restrictions match `Map` keys: `String`, integer types, simple enums.
- Literals `[...]` create Sets; duplicates deduplicate.
- `add(value)` inserts; a no-op when present.
- `has(value)` tests existence.
- `at(index)` returns the `index`-th element in the current iteration order; out-of-bounds panics; order not guaranteed stable.
- `remove(value)` deletes; a no-op when absent.
- `clear()` empties; `length()` returns the element count.
- `Set` may be `for-in`-ed; order not guaranteed stable.
- `Set` is a reference type, GC-managed; type parameters invariant.

### 9.7 StringBuilder / Text / Bytes

```x
import xdk.text;

StringBuilder builder = StringBuilder();
builder.append("count=");
builder.append(1);
String text = builder.toString();

Text immutable = Text.fromString("hello");
Int byteLength = immutable.length();
Int codePoints = immutable.codePointCount();
String plain = immutable.toString();

Bytes bytes = Bytes.fromString("abc");
bytes.set(1, 90);
Int first = bytes.get(0);
Int byteCount = bytes.length();
```

- `StringBuilder()` creates an empty builder; `append` accepts `String`, `Bool`, integers, `Float`, `Double`, `Char`, returning the builder itself; `toString()` returns a new `String`; `length()` returns the current byte length.
- `StringBuilder` is a mutable reference type; suited to loop concatenation, amortized O(1) appends.
- `Text` is immutable UTF-8 text; `fromString` copies the `String`'s content; `length()` returns bytes; `codePointCount()` returns code points; `toString()` returns an equal `String`. Full API in Part 6 §4.6.
- `Bytes` is a mutable byte buffer; `fromString` copies bytes; `get` / `set` index by byte, out-of-bounds panics; `push` appends one byte; `append` appends `Bytes` or `Byte[]`; `slice(start, end)` returns a new `Bytes`; `length()` returns the byte count.
- `Text` / `Bytes` / `StringBuilder` are all GC-managed; conversions between `Text` and `String` copy content.

### 9.8 Complexity

| Operation | Complexity |
| --- | --- |
| `String.length` | O(1) |
| `String.substring` | O(n) |
| `String.indexOf` | worst O(n·m) |
| `String.split` / `replace` | O(n) |
| `StringBuilder.append` | amortized O(1) |
| `StringBuilder.toString` | O(n) |
| `new T[count]` creation | O(n) (zero-initialization) |
| `T[]` subscript / `length` | O(1) |
| `T[].join` | O(n) |
| `Result.isOk` / `isErr` / `value` / `error` / `unwrapOr` | O(1) |
| `List.push` | amortized O(1) |
| `List.insert` / `remove` | O(n) |
| `List.get` / `set` | O(1) |
| `Map` / `Set` lookup, insert, delete | average O(1), worst O(n) |
| `Map.keys` / `values` | O(n) |
| `Set.at` | O(n) |

### 9.9 Member-Resolution Rules

- Built-in type members are language-predefined and cannot be overridden by user extension methods.
- Built-in members resolve by static receiver type; calling a non-`?.` member on a `null` receiver panics.
- `length()` means different things on different types: bytes for `String`, elements/pairs for `T[]` / `List` / `Set` / `Map`, bytes for `Text`.
- `Result`'s `isOk` / `isErr` / `value` / `error` / `unwrapOr` are built-in members, see 10.1.
- Container methods return no optional values unless the signature writes `?` explicitly; out-of-bounds is reported by panic; `Map.get` is the exception returning `null` for missing keys.

## 10. Error Handling

### 10.1 Result

```x
Result<Int, String> ok = Ok(1);
Result<Int, String> fail = Err("missing");
```

- `Result<T,E>` is a value type; `T` is the success-value type, `E` the error-value type.
- `T` may be `void`, meaning no success value; `E` cannot be `void`.
- `Ok(value)` constructs success; `Ok()` serves `Result<void,E>`; `Err(error)` constructs failure.
- Constructors infer from the target type; without one, `Ok(1)` or `Err("x")` cannot determine the other side — write the type explicitly or let context supply it.
- `Result` is `@mustUse`: a `Result` value must be returned, assigned to a variable/field/container, propagated with `try`, or have a member called; discarding it as a bare expression statement is a compile error.
- `Result` provides no `==` / `===`; use member checks.
- `Result` may appear in variables, parameters, returns, fields, containers, and closures.

Members:

```x
Bool isOk()
Bool isErr()
T value()          // only when T is non-void; panics on Err
E error()          // only when E is non-void; panics on Ok
T unwrapOr(T fallback) // only when T is non-void
```

- `isOk()` / `isErr()` are always safe.
- `value()` / `error()` must be called only in the confirmed branch; reading the success value in an error branch (or vice versa) is a program error and panics at runtime.
- For safe unwrapping use `try`, or check `isOk` / `isErr` first.

### 10.2 try Propagation

```x
Result<Config, AppError> load(String path) {
    String text = try File.read(path);
    Config config = try parse(text);
    return Ok(config);
}
```

- `try expr` is `Result`-only.
- On success it unwraps to `T` and continues; on failure it executes the current scope's `defer` / `errdefer`, then returns `Err` from the current function or closure.
- The enclosing function or closure must return `Result<_, E2>`; `E` must be assignable to `E2`; otherwise a compile error. Implicit stringification is forbidden.
- The `try` of `Result<void,E>` is used as an expression statement; it produces no value.
- `try` is a prefix operation applying to the immediately adjacent prefix expression; precedence in 7.2.
- `try` cannot be used in constructors, `deinit`, `main`, or `defer` / `errdefer` bodies.
- With `try` inside a closure, the error returns from the closure, never piercing to the outer function; the closure's target return type must be `Result`.
- `try` does not unwind the stack, print logs, or call global observers.
- `try` may nest: `try try parse(text)` unwraps the outer `Result`, then the inner.

### 10.3 defer / errdefer

```x
Result<void, IoError> copy(String from, String to) {
    File input = try File.open(from);
    defer input.close();

    File output = try File.create(to);
    defer output.close();
    errdefer File.remove(to);

    Byte[] buffer = new Byte[4096];
    while true {
        Int n = try input.read(buffer);
        if n == 0 {
            break;
        }
        try output.write(buffer, n);
    }
    return Ok();
}
```

- `defer Statement` executes when the current scope exits; `errdefer Statement` only when the current function or closure returns with `Err`.
- Trigger times: normal scope end, `return`, `try`, `break` / `continue` (including labeled forms). `goto`, `throw`, and process exit do not trigger.
- `errdefer` triggers when the function or closure returns an `Err` value — including `try` propagation, explicit `return Err(...)`, and returning a `Result` variable that is `Err` at runtime; normal `return Ok(...)`, plain `return`, and `break` / `continue` do not trigger it.
- Within one scope, execution is reverse registration order (LIFO). On error returns both `defer` and `errdefer` run; on normal exit only `defer` runs.
- A `defer` / `errdefer` body may be a brace body or a single non-declaration statement; a brace body is a cleanup body, not a standalone statement.
- A `defer` body's scope is fixed at registration; at execution it reads the variables' current values; closures must not be allocated. The example's `close` / `remove` return `void`; when a cleanup call returns `Result` it must be handled explicitly — unhandled `Result`s still produce diagnostics per `@mustUse`.
- `defer` / `errdefer` bodies (including nested brace bodies) must not contain `return`, `break`, `continue`, `goto`, `try`, `throw`, `defer`, or `errdefer`; cleanup must be non-throwing.
- `errdefer` may appear only in functions or closures returning `Result`; otherwise a compile error.
- `defer` / `errdefer` may appear only in function bodies, control bodies, or closure bodies; never as the single-statement body of `if` / `while` / `for`. Top level and type bodies are not allowed.
- A `defer` / `errdefer` single-statement body must not be a local declaration; use a brace body when a local is needed.
- Cleanups registered inside a loop body execute at each iteration's end; `break` / `continue` exiting the current iteration executes the cleanups registered in the current iteration.
- `defer` is not a substitute for object lifetime management; ARC/GC handle objects, `defer` handles external resources — files, locks, transactions, sockets, etc.

### 10.4 throw and Fatal

- `throw` is fatal/panic: it prints the diagnostic and call stack, then terminates the process; it is not a recoverable error.
- `throw` does not unwind the stack and does not guarantee `defer`, `errdefer`, or `deinit`.
- Implicit fatal paths — array out-of-bounds, null dereference, failed `as`, division by zero, out-of-range shift — likewise terminate the process.
- Recoverable errors must use `Result` + `try`; expressing expected errors with `throw` is forbidden.

### 10.5 Error Observation Boundary

- This document defines `Result`'s construction, propagation, and handling, plus `defer` / `errdefer`.
- Logging, diagnostics, cancellation, timeouts, `ErrorKind`, and boundary translation are defined by the Error Handling specification.
- Error observation is boundary behavior, not control flow; global notification centers and implicit recovery must not be introduced.
- The error type `E` may be an enum, struct, class, or `Error` protocol implementation; `E` cannot be `void`.
- Unhandled `Result`s must produce compile diagnostics; boundaries must translate explicitly (CLI exit codes, HTTP status codes, task failures, etc.).

## 11. XDK and Entry

### 11.1 XDK Imports

```x
import xdk.text;
import xdk.collections;
import xdk.net.http;
```

- `xdk.` is a reserved namespace; user packages must not use the prefix.
- XDK package paths may have multiple levels; the package name is the path's last segment — e.g., `xdk.net.http`'s package name is `http`. The name serves package identity and diagnostics only; no namespace alias is bound.
- Using XDK types or static entries without importing must fail compilation.
- `T[]` is built into the language and requires no `xdk.collections` import.
- `List` / `Set` / `Map` require importing `xdk.collections`; `Text` / `Bytes` / `StringBuilder` require `xdk.text`.
- XDK package versions and `min_runtime_abi` must be compatible with the runtime; incompatibility fails compilation — no silent degradation.
- XDK package layout, capability boundaries, and full APIs are in Part 6.

### 11.2 Entry

```x
static void main(final String[] args) {
    ...
}
```

Or:

```x
static Int main(final String[] args) {
    return 0;
}
```

- The entry must be a top-level `static` function named `main`.
- The entry must take one `String[]` parameter; the parameter name is arbitrary; `final` optional.
- A `void` entry exits with code 0; an `Int` entry's return value is the process exit code. The portable exit-code range is 0..255; other values are truncated by the platform.
- The entry must be public (default-public or explicit `public`).
- The entry cannot be generic, take extra parameters, or have default/variadic parameters.
- A program has exactly one entry matching the signature; other `main` overloads are ordinary functions.
- The entry may live in the default package or the package named by the project manifest; other packages' `main`s cannot serve as entries.
- `args` is a new array created at runtime with the argument strings; mutating its elements does not affect the process's original arguments.

### 11.3 Startup Sequence

1. Runtime and GC initialization.
2. Top-level fields, static fields, and singletons initialized per 4.3.
3. The entry is called.
4. After the entry returns, the process terminates with the exit code; global `deinit` execution is not guaranteed.

A panic during initialization terminates the process; the entry is never called. A panic inside the entry terminates the process without stack unwinding.

### 11.4 Project Entry Resolution

- The project manifest may specify the entry file and entry package.
- Without a manifest, the entry file is `main.x` in the current directory.
- The entry file must contain a signature-matching `main`; missing or duplicated is a compile error.
- The project manifest is outside this document; its format and fields are defined by the Project Configuration specification.

## 12. Implementation Boundary

The following capabilities are not guaranteed or enforced by the current implementation and must not be depended on as supported. This section lists core-syntax boundaries only; the object model's release gates are in Part 2 Section 16 — failing them blocks release.

- `Int128` / `UInt128` do not yet have true 128-bit backend layouts; do not depend on their width or overflow behavior.
- `switch` does not require compile-time-constant `case`s; non-enum `switch` does not check exhaustiveness; enum `switch` checks per Part 2 8.5.
- `&&` / `||` short-circuit; `??` evaluates the right side only when the left is `null`.
- `Result` is still represented as a GC object, allocating per `Ok` / `Err`; the language semantics are value-type, and the full rules of error observation are in the Error Handling specification.
- `Result`'s `@mustUse`, `try`'s error-type-assignability check, and `defer` / `errdefer`'s LIFO execution are **enforced semantics**; gate: conformance may not be claimed before Section 10's acceptance passes (non-committed until acceptance; rationale: implementation progress; consequence: code depending on these checks is unprotected until then).
- `try`, `new T[count]`, and labeled `break` / `continue` have been retained since v2.0.0 and remain in effect in v3.0.0; the current compiler may not have implemented them all — acceptance per Section 13.
- `new` expression syntax is merged into this document; object semantics remain governed by Part 2.
- Generics support no constraints, default type arguments, or variadic type parameters; `Result` as a type argument requires monomorphization support.
- `Text` / `Bytes`' XDK APIs are still experimental; signatures may change.
- `String.toUpper` / `String.toLower` handle ASCII only.
- `String.length` counts bytes; use `Text.codePointCount` for code points.
- `Char` is a 32-bit scalar value and does not participate in arithmetic; integer conversion is provided by XDK.
- `goto`'s scope restrictions and cleanup semantics are **enforced semantics** (same gate; conformance not claimed before acceptance); relying on `goto` for resource cleanup is forbidden (the usage is rejected).
- `as` / `as?` support no numeric conversion.
- No implicit flow-sensitive narrowing; optional values must be explicitly unwrapped with `as` / `??`.
- `Map` / `Set` key types are limited to `String`, integers, and simple enums.
- The current runtime's `Map.get` returns a zero value for missing keys; this document requires `null` and adds `getOr`; during migration do not depend on zero values for missing keys.
- Cross-package generic instantiation needs templates or intermediate representations; the current toolchain may require generic bodies within the same compilation.
- String interpolation requires `toString()` on object types; the current implementation may support only scalars, `String`, and `null`.
- Tuples are new in v3.1.0: out-of-range element access checks, per-element equality, optional-tuple `?.`, and tuple interpolation must be fully implemented; incomplete implementations must not silently accept partial forms.
- `main`'s exit code may behave differently on platforms outside the 0..255 range.
- Cross-package member visibility and `protected` method-call checks are in Part 2's implementation boundary.
- `defer` / `errdefer` cleanup bodies forbid control transfers, `try`, and `throw`; this restriction is **enforced semantics** (same gate; conformance not claimed before acceptance).
- `Result`'s `value()` / `error()` are safe only in confirmed branches; the current implementation may report misuse via assertions rather than panics.

## 13. Acceptance

| ID | Verification Point | Pass Condition |
| --- | --- | --- |
| LEX-01 | Literal matrix | All integer radices, suffixes, underscores, floats, chars, and the five string forms parse; illegal escapes, unterminated strings, illegal scalars rejected |
| STMT-01 | Statement termination | Go-style automatic semicolon insertion correct at newline, `;`, `}`, EOF, `else`, `do`'s `while` boundaries; line-start operators do not continue lines; missing semicolons on one line rejected |
| TYPE-01 | Assignability | Same type, `null`, optional promotion, literals, container literals, closures, `Any` boxing, `Object` root all checked per 2.6; implicit numeric conversion rejected |
| TYPE-02 | Nullability | `T?` normalized for reference types; `?.` / `??` / `as` / `as?` semantics correct; non-optional value types reject `null` |
| EXPR-01 | Evaluation order | `&&` / `||` short-circuit; `??` evaluates right only when left is `null`; `try` propagation order correct |
| CTRL-01 | Control flow | `if` / `while` / `do` / `for` / `switch` conditions unpunctuated, bodies braced; `goto` syntax correct; `break` / `continue` and label scoping correct; non-`void` return paths complete |
| ERR-01 | Error handling | `Result` construction/members/`@mustUse`; `try` propagation and error-type checks; `defer` / `errdefer` LIFO, trigger conditions, and cleanup-body restrictions; correct use of `isOk` / `isErr` / `value` / `error` |
| GEN-01 | Generic functions | Explicit arguments, inference, conflicts, unbound, overloads, monomorphization, infinite-expansion diagnostics all per Section 8; `Result` type arguments instantiable |
| BLD-01 | Built-in types | `String` / `T[]` / `List` / `Map` / `Set` member signatures, boundaries, `Map.get` / `getOr` missing-key behavior, `new T[count]` allocation, complexity per Section 9 |
| TUPLE-01 | Tuples | Type identity, literals, element access, inference, assignability, equality, and interpolation per 2.11; out-of-range selectors, one-/zero-element tuples, destructuring, tuple `switch`, tuple `const` all rejected |
| PKG-01 | Packages and imports | Package imports, symbol imports, disambiguating aliases, non-conflict aliases rejected, simple-name ambiguity, XDK not imported, import cycles all correctly diagnosed |
| ENTRY-01 | Entry and startup | Both `main` signatures runnable; exit codes correct; initialization order correct; missing/duplicate entry rejected |
| DET-01 | Determinism | Same source, implementation version, and options produce identical diagnostics and run results; initialization order independent of file-system enumeration order |
| NEG-01 | Negatives | Every forbidden construction has a corresponding diagnostic; unsupported items rejected per 0.6; the compiler never crashes or silently accepts |

## Appendix A: Core-Syntax Grammar

This appendix uses EBNF; `{ X }` means zero or more, `[ X ]` optional. Newline and semicolon rules are in 1.6; `[ ";" ]` in the grammar means an optional explicit semicolon.

```ebnf
CompilationUnit   = [ PackageDecl ] { ImportDecl } { TopLevelDecl } EOF ;
PackageDecl       = "package" QualifiedName [ ";" ] ;
ImportDecl        = "import" QualifiedName [ "as" Identifier ] [ ";" ] ;
QualifiedName     = Identifier { "." Identifier } ;

TopLevelDecl      = { Annotation } { TopLevelModifier }
                    ( TopLevelFunction | TopLevelField | TypeDecl ) ;
TopLevelModifier  = "public" | "protected" | "private" | "static" ;
TopLevelFunction  = "static" Type Identifier [ GenericParams ]
                    "(" [ ParamList ] ")" Block ;
TopLevelField     = [ "static" ] [ "final" | "const" ] Type Identifier
                    [ "=" Expression ] [ ";" ] ;
TypeDecl          = { Annotation } { TypeModifier } TypeDeclBody ;
TypeModifier      = "public" | "protected" | "private" | "abstract" | "final" ;
TypeDeclBody      = ClassDecl | StructDecl | ProtocolDecl | EnumDecl
                  | SingletonDecl | ExtensionDecl | AnnotationDecl ;

ParamList         = Param { "," Param } ;
Param             = { Annotation } [ "final" ] Type Identifier ;
GenericParams     = "<" GenericParam { "," GenericParam } ">" ;
GenericParam      = Identifier ;
TypeArgList       = TypeRef { "," TypeRef } ;

Type              = TypeRef ;
TypeRef           = PrimaryType { "[]" | "?" } ;
PrimaryType       = FunctionType | NamedType | TupleType ;
FunctionType      = ReturnType "(" [ TypeRef { "," TypeRef } ] ")" ;
ReturnType        = "void" | NamedType | TupleType ;
TupleType         = "(" TypeRef "," TypeRef { "," TypeRef } ")" ;
NamedType         = QualifiedName [ "<" TypeArgList ">" ] ;

Block             = "{" { Statement } "}" ;
Body              = Block | Statement ;
Statement         = LocalDecl
                  | ExprStatement
                  | Assignment
                  | IncDecStatement
                  | IfStatement
                  | WhileStatement
                  | DoWhileStatement
                  | ForStatement
                  | SwitchStatement
                  | DeferStatement
                  | BreakStatement
                  | ContinueStatement
                  | ReturnStatement
                  | ThrowStatement
                  | LabeledStatement
                  | GotoStatement
                  | EmptyStatement ;

LocalDecl         = ( "final" | "const" ) Type Identifier [ "=" Expression ] [ ";" ]
                  | "var" Identifier "=" Expression [ ";" ]
                  | Type Identifier [ "=" Expression ] [ ";" ] ;
ExprStatement     = Expression [ ";" ] ;
Assignment        = Assignable ( "=" | "+=" | "-=" | "*=" | "/=" | "%="
                  | "&=" | "|=" | "^=" | "<<=" | ">>=" ) Expression [ ";" ] ;
IncDecStatement   = ( "++" | "--" ) Assignable [ ";" ]
                  | Assignable ( "++" | "--" ) [ ";" ] ;
Assignable        = Identifier | MemberExpr | IndexExpr ;

IfStatement       = "if" Expression Block [ "else" ( IfStatement | Block ) ] ;
WhileStatement    = "while" Expression Block ;
DoWhileStatement  = "do" Block "while" Expression [ ";" ] ;
ForStatement      = "for" ForHeader Block ;
ForHeader         = Identifier "in" Expression ;
SwitchStatement   = "switch" Expression "{" { CaseClause } [ DefaultClause ] "}" ;
CaseClause        = "case" Expression ":" { Statement } ;
DefaultClause     = "default" ":" { Statement } ;
DeferStatement    = ( "defer" | "errdefer" ) Body ;
BreakStatement    = "break" [ Identifier ] [ ";" ] ;
ContinueStatement = "continue" [ Identifier ] [ ";" ] ;
ReturnStatement   = "return" [ Expression ] [ ";" ] ;
ThrowStatement    = "throw" Expression [ ";" ] ;
LabeledStatement  = Identifier ":" Statement ;
GotoStatement     = "goto" Identifier [ ";" ] ;
EmptyStatement    = ";" ;

Expression        = TernaryExpr ;
TernaryExpr       = CoalesceExpr [ "?" Expression ":" Expression ] ;
CoalesceExpr      = LogicalOrExpr [ "??" CoalesceExpr ] ;
LogicalOrExpr     = LogicalAndExpr { "||" LogicalAndExpr } ;
LogicalAndExpr    = BitOrExpr { "&&" BitOrExpr } ;
BitOrExpr         = BitXorExpr { "|" BitXorExpr } ;
BitXorExpr        = BitAndExpr { "^" BitAndExpr } ;
BitAndExpr        = EqualityExpr { "&" EqualityExpr } ;
EqualityExpr      = ComparisonExpr { ( "==" | "!=" | "===" | "!==" ) ComparisonExpr } ;
ComparisonExpr    = RangeExpr [ ( "<" | "<=" | ">" | ">=" ) RangeExpr
                  | ( "is" | "as" | "as?" ) TypeRef ] ;
RangeExpr         = ShiftExpr [ ( "..<" | "..." ) ShiftExpr ] ;
ShiftExpr         = AdditiveExpr { ( "<<" | ">>" ) AdditiveExpr } ;
AdditiveExpr      = MultiplicativeExpr { ( "+" | "-" ) MultiplicativeExpr } ;
MultiplicativeExpr= UnaryExpr { ( "*" | "/" | "%" ) UnaryExpr } ;
UnaryExpr         = ( "!" | "-" | "+" | "~" | "try" ) UnaryExpr
                  | PostfixExpr ;
PostfixExpr       = PrimaryExpr { PostfixSuffix } ;
PostfixSuffix     = "." MemberSelector
                  | "." IntegerLiteral
                  | "?." MemberSelector
                  | "?." IntegerLiteral
                  | [ "<" TypeArgList ">" ] "(" [ ArgList ] ")"
                  | "[" Expression "]" ;
MemberSelector    = Identifier ;
PrimaryExpr       = Literal | Identifier | "self" | "super"
                  | "(" Expression ")" | TupleLiteral | ArrayLiteral | MapLiteral
                  | NewExpr | LambdaExpr | InterpolatedString ;
ArgList           = Expression { "," Expression } ;
ArrayLiteral      = "[" [ Expression { "," Expression } ] "]" ;
TupleLiteral      = "(" Expression "," Expression { "," Expression } ")" ;
NewExpr           = "new" TypeRef "(" [ ArgList ] ")"
                  | "new" TypeRef "[" Expression "]" ;
MapLiteral        = "[" Expression ":" Expression
                    { "," Expression ":" Expression } "]"
                  | "[:" "]" ;
LambdaExpr        = "(" [ LambdaParam { "," LambdaParam } ] ")" "->" ( Block | Expression ) ;
LambdaParam       = [ "final" ] Type Identifier ;
MemberExpr        = PrimaryExpr "." MemberSelector
                  | "self" "." MemberSelector
                  | "super" "." MemberSelector ;
IndexExpr         = PrimaryExpr "[" Expression "]" ;
Literal           = IntegerLiteral | FloatLiteral | CharLiteral
                  | StringLiteral | "true" | "false" | "null" ;
InterpolatedString = "$\"" { InterpPart } "\"" ;
InterpPart        = StringCharNoBrace
                  | "{" Expression "}"
                  | "{{" | "}}" ;
Annotation        = "@" Identifier [ "(" [ ArgList ] ")" ] ;
```

Grammar notes:

- `<` parses as type arguments only after a called expression, and only when the token sequence up to the matching `>` parses as type arguments followed immediately by `(`; otherwise `<` is the comparison operator.
- Distinguishing function types from named types: a return type immediately followed by `(` parses as a function type.
- `TypeRef`'s `[]` / `?` may appear consecutively; `T?[]` is "array of optional `T`", `T[]?` is "optional array"; `T??` normalizes to `T?`.
- `new T[count]` is an array-creation expression; `value[index]` is a subscript expression. Parsing distinguishes by whether `new` is followed by `(` or `[`.
- `Block` appears only as a `Body`, function body, lambda body, constructor/method body, or cleanup body — never as a standalone `Statement`; standalone `{}` is a syntax error.
- `?.` serves only optional member access; calls are still `?.` then member then call. `?` serves only the optional-type suffix and the ternary.
- `InterpolatedString`'s lexical constraints are in 1.4.4: `{Expression}` evaluates and formats, `{{` / `}}` produce literal `{` / `}`; `StringCharNoBrace` is any source character except `"`, unpaired `}`, and newline, details per the lexer.
- `++` / `--` appear in the grammar only as `IncDecStatement`; the expression grammar contains no increment/decrement — `Int a = i++;` is rejected by this appendix's grammar, consistent with 6.1, 6.4.
- A lambda's single-expression body `-> Expression` abbreviates `-> { return Expression; }`; both forms coexist in the grammar and are treated as equivalent per 7.7.
- Tuple types and tuple literals have at least two elements; `(T)` and `(e)` are the parenthesized forms of a type and an expression respectively, not tuples.
- In a function type versus a declaration's parameter list, the outermost parentheses are the parameter list; a type with nested parentheses containing at least two top-level elements is a tuple type: `Int((Int, String))` is a function type taking a tuple, `Int(Int, String)` a two-parameter function type.
- `.` followed by an integer literal is for tuple element access only; out-of-range positions are compile errors. `?.` followed by an integer literal is for optional tuples only.
- `try` is a prefix operation; `try expr` is `Result`-only.
- `TypeDeclBody`'s grammar is in Part 2 Appendix A; this appendix defines core syntax only.
- Constructions the grammar accepts but that violate semantic rules must be rejected at type checking; grammar acceptance must never be treated as legality.
