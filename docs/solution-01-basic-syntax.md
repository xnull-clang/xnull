# XNull Solution Part 1: Basic Syntax

| Item | Value |
| --- | --- |
| Document number | Part 1 (S1) |
| Document version | 3.4.0 |
| Specification status | Formal |
| Publication date | 2026-11-15 |
| Intended audience | XNull language implementations |
| Related parts | Parts 2–10 |

Versioning rules: the revision number is used for clarifications that do not change semantics, the minor version for backward-compatible additions, and the major version for breaking changes. Historical versions are available in the git history.

Revision note: 3.4.0 (2026-11-15) retains only standard clauses; implementation status is not part of this document. Part numbers were renumbered on 2026-11-23 to insert Part 3 (Annotations); content is unchanged.

## Decision Summary

- This solution is the normative text for basic syntax and uses RFC 2119 terminology; conformance is determined only by the clauses of this document.
- Statement termination uses automatic semicolon insertion; multi-line expressions MUST use parentheses.
- For reference types, `T?` and `T` are the same type; no flow-sensitive narrowing is provided, and unwrapping uses `as` / `??`.
- `&&` / `||` short-circuit; `??` evaluates the right-hand side only when the left-hand side is `null`.
- Numeric types have no implicit conversions; integer overflow wraps, and division by zero / out-of-range shifts panic.
- The tuple `(T1, T2, ...)` is a built-in value type with at least two elements, accessed positionally as `t.0`; destructuring, labels, and tuple methods are not provided.
- Uniform function rules: top-level functions, methods, constructors, and lambdas follow the same set of explicit function rules (7.10)—explicit types, no default parameters, no named arguments, no variadic parameters; brace bodies (lambdas are the exception and may have a single-expression body); overloading per 4.4 and Part 2, 6.8.
- Top-level functions are static by default; `static` may be written or omitted (4.1).
- `Map` / `Set` keys are limited to `String`, integers, and simple enums; `Map.get` returns `null` for a missing key, and `getOr` provides a default value.
- Generic functions are instantiated per type argument; constraints, default type arguments, or generic closures are not supported.
- Supports `switch`, `Result` / `try`, `defer` / `errdefer`, `new` object construction, and labeled control; unsupported items are listed in 0.6.
- General `switch` does not check exhaustiveness; exhaustiveness of enum `switch` is specified in Part 2, 8.5.

## 0. Specification Foundations

### 0.1 Scope

This solution specifies the basic syntax and semantics of XNull: lexical structure, type system, packages and imports, top-level declarations, local variables, statements and control flow, expressions and operators, closures, generic functions, built-in types, error handling core, object construction expressions, and the program entry point.

This solution does not specify:

- Type declarations, inheritance, protocols, enums, singletons, and extensions; see Part 2.
- Object memory layout and reclamation; see Part 4.
- Annotation declaration/use and the complete annotation execution model; Part 2 §12 is the object-model summary, Part 3 is the complete solution.
- Error observation, cancellation, timeouts, and `ErrorKind` policy; core syntax is in Section 10, the complete model is in Part 5 (Error Handling).
- FFI, C ABI, `unsafe` boundaries, and cross-language ownership; see Part 8 and Part 7.
- Runtime semantics of concurrency, asynchrony, and tasks; the language does not provide `async` / `await` syntax; use the task API provided by the library (Part 7).
- Complete APIs of library types (`List` / `Map` / `Set` / `Text` / `Bytes` / `StringBuilder`) and the standard library packages; see Part 7.
- Project manifest, build system, and package management; this solution only specifies the entry function signature and startup order.

### 0.2 Normative Terminology

**MUST**, **MUST NOT**, **SHOULD**, and **MAY** are used with RFC 2119 semantics. **MUST NOT** is equivalent to "must not". **SHOULD** indicates that well-founded exceptions exist, and exceptions must be well justified.

Syntax not listed in this document MUST NOT be considered supported.

### 0.3 Conformance

An implementation MUST accept all source programs that satisfy the "MUST" clauses of this solution and produce the observable behavior specified by this solution. Source programs that violate "MUST NOT" clauses MUST be rejected with a diagnostic that includes the source location.

An implementation MAY provide extensions not listed in this solution, but extensions MUST be explicitly enabled; default builds MUST NOT depend on extensions, and extensions MUST NOT be used to change behavior already specified by this solution. The same source program, the same implementation version, and the same compilation options MUST produce identical diagnostics and runtime results.

### 0.4 Program Model

A program consists of one or more packages. A package consists of one or more source files, and a file belongs to exactly one package. Top-level declarations within a package are visible in package scope; cross-package access MUST go through `import` or a fully qualified name.

The program entry point is a top-level `static` function `main`. At startup, packages, top-level fields, static fields, and singletons are initialized first, and then the entry point is called.

The grammar of a compilation unit is given in Appendix A. Diagnostics MUST correspond to clauses of this document.

### 0.5 Versions and Compatibility

This solution uses semantic versioning:

| Version component | Permitted changes | Non-permitted changes |
| --- | --- | --- |
| Major version | Remove syntax, change semantics, change default behavior | None |
| Minor version | Add syntax, add built-in members, add diagnostics | Change the meaning of existing programs |
| Revision number | Clarify wording, add examples, fix typos | Change normative constraints |

Within the same major version, source programs that conform to an older version MUST continue to be accepted, and their observable behavior MUST remain unchanged. Implementations MUST NOT silently downgrade or ignore incompatible specification versions.

### 0.6 Explicitly Unsupported Syntax

The following features are not part of the XNull basic syntax. Implementations MUST reject them and MUST NOT simulate them with implicit behavior; when these capabilities are needed, use the alternative on the right.

| Unsupported | Reason | Alternative |
| --- | --- | --- |
| Named arguments, default parameters, variadic parameters, spread arguments | Call resolution stays explicit and predictable | Construct a DTO / configuration `class`, or use explicit overloads |
| C-style `for (init; cond; step)` | `while`, `do-while`, `for-in`, and range loops already exist | Use `while` + explicit state, or a range loop |
| `catch` / `finally`, cross-frame exceptions | Errors must propagate explicitly, implicit unwind is forbidden; `try` is only for `Result` propagation | `Result` + `try` + `defer` / `errdefer`; use `throw` for fatal errors |
| Operator overloading, user-defined implicit conversions | Type behavior stays predictable | Named methods; explicit `as` / `as?` |
| Address-of operator, pointers, smart pointers, weak reference modifiers, memory policy annotations (`@arc` / `@gc`) | Source code must not express reference strength, addresses, or memory policy | Memory management is covered in Part 4; FFI goes through contracts (Part 8) |
| Custom accessor properties (property get/set syntax) | XNull public fields are read and written directly by default; getters/setters are unnecessary | Access public fields directly; use methods for computation, validation, and private state |
| User-defined indexers | Container interfaces already provide them | `get` / `set` / `at` |
| Events | No event syntax is introduced | Closure callbacks or explicit observer lists |
| `if` / `switch` expressions, block expressions | Statement and expression boundaries stay clear | Ternary expressions, or assignment/return within branches |
| Standalone `{}` statement blocks | Scope is introduced only by function bodies, control bodies, type bodies, and `defer` bodies | Encapsulate with `if` / `while` / function bodies |
| `match` / pattern matching | Keep the original `switch`, do not introduce a separate pattern system | `switch` + `if` + `Result` members |
| Tuple destructuring, tuple labels, tuple methods, single-element / zero-element tuples | Tuples remain anonymous and positionally accessed in their minimal form | Access element by element; use `class` / `struct` when named fields or behavior are needed |
| `??=` | No null-assignment syntax is introduced | `if x == null { x = ... }` |
| `?.()` / `?.[]` | Dot syntax retains only nullable member access | Call/index after an `if` check |
| Function type arrow `(P) -> R` | Retain the `R(P...)` form | `R(P...)` |
| `async` / `await`, generators, `yield` | Concurrency is handled by the library; no function coloring is introduced | Task API provided by the library (Part 7) |
| `unsafe` blocks, raw pointers, inline assembly, macros | XNull source has no address-of, pointer, or smart pointer syntax; the safety boundary lies in libraries and FFI | Library APIs and FFI contracts (Parts 6, 7) |
| Conditional compilation, macro expansion, runtime reflection | Build and metaprogramming are not part of the language core | Build configuration, code generation, or library APIs |
| Package re-exports, explicit export lists | Avoid package surface bloat and implicit dependencies | Public wrapper types / functions, or direct imports |
| Nested types, local types | Keep type declarations at package top level for cross-package resolution | Top-level types + qualified names |
| Static initializer blocks, instance initializer blocks | Initialization order stays predictable | Field initializers + constructors |
| Multiple inheritance, type classes / traits, implicit implementations | Maintain nominal typing and the single-inheritance model | Single inheritance + protocols + composition |
| Class method overriding, dynamic dispatch in class hierarchies | Ordinary classes only provide field/method reuse; polymorphism goes only through protocols | Protocols + implementation classes |
| Abstract methods, dynamic contracts in class inheritance | Abstract classes only represent non-instantiable reuse base classes and do not establish class hierarchy contracts | Protocols + concrete classes |
| Structs, enums, singletons implementing protocols | Protocol implementation is limited to `class` | Wrap or compose with `class` |
| Struct instance reference fields, reference fallback | `struct` carries only value fields and always copies | Declare `class` when reference semantics are needed |
| Protocol fields, protocol method bodies, protocol default implementations | Protocols retain only method signatures, avoiding implicit implementations | Concrete class fields/methods + composition |
| Generic protocols, associated types, protocol generic methods | Protocols are non-generic method signature contracts | Non-generic protocols + concrete types + method overloading |
| Generic constraints, `where` clauses, default type arguments | Keep type parameters simple and avoid constraint solving | Protocols + overloading + runtime checks |
| Type aliases / newtype | XNull type identity is determined directly by the declaration; no alias layer is introduced | Write the target type directly; declare `class` / `struct` when independent identity is needed |
| Package-private / `internal` visibility | The visibility model keeps three modifiers | `private` / `protected` + package splitting |
| Implicit numeric promotion, `Bool` and integer conversion | Avoid silent cross-type behavior | Explicit literal types, explicit conversion functions |

### 0.7 Dot Syntax and the Pointer-Free Model

- Member access, calls, and nullable access uniformly use dot syntax: `value.member`, `value.method()`, `value?.member`, `value?.method()`. `->` is used only for lambdas, not for member access or pointer dereferencing.
- There is no address-of operator `&` (`&` is only bitwise AND), pointer type `T*`, dereference `*p`, explicit reference type syntax `&T` / `ref T`, `ref` / `out` parameter modifiers, pointer arithmetic, or manual `free`.
- `out` / `in` are only used for generic variance, not as pass-by-reference modifiers.
- There are no smart pointer types: `Box<T>`, `Rc<T>`, `Arc<T>`, `Ref<T>`, `Weak<T>`, etc. do not exist. Memory policy is not a source type; source code does not write `retain` / `release`.
- Source code has no concept of weak references; reference strength and memory policy are managed entirely by the compiler and runtime and must not be expressed in source code; see Part 2, Section 15.
- Classes, protocols, arrays, containers, `String`, and closures are semantically object handles/reference semantics; they cannot have their address taken, be converted to integers, undergo pointer arithmetic, or be manually released.
- FFI, raw pointers, and `unsafe` blocks are not part of the XNull language syntax; they are defined by Part 8 (FFI) and Part 7 (Standard Library). XNull source contains no pointer declarations or dereferences.

## 1. Lexical Structure

### 1.1 Source Files

- Source file extension is `.x`, encoding UTF-8.
- A file may begin with a UTF-8 BOM; the BOM does not count toward column numbers.
- Line breaks may be LF or CRLF; CRLF is normalized to LF during the lexical phase.
- Line and column numbers start at 1. Columns are counted by Unicode scalar values.

### 1.2 Comments

```text
// line comment, until the end of the line
/* block comment, does not nest */
/** documentation comment, treated as an ordinary block comment */
```

- Comments are equivalent to whitespace and may appear between any two tokens.
- Block comments do not nest; they end at the first `*/`.
- An unterminated block comment is a lexical error.
- Documentation comments do not participate in semantics; they MUST NOT change types, visibility, or runtime behavior.

### 1.3 Identifiers, Keywords, and Reserved Names

Identifiers:

```text
[A-Za-z_][A-Za-z0-9_]*
```

Only ASCII letters, digits, and underscores are used. Naming conventions serve only readability and editor highlighting and do not participate in semantics:

- `PascalCase`: types;
- `UPPER_SNAKE_CASE`: constants;
- `lowerCamelCase`: variables, functions, fields.

Keywords are grouped by purpose:

| Purpose | Keywords |
| --- | --- |
| Packages and imports | `package` `import` `as` |
| Visibility and modifiers | `public` `protected` `private` `final` `static` `const` `var` `abstract` |
| Types and objects | `class` `struct` `protocol` `enum` `singleton` `factory` `extension` `implements` `new` `self` `super` `out` `in` |
| Control flow | `if` `else` `while` `do` `for` `switch` `case` `default` `break` `continue` `return` `throw` `try` `goto` `defer` `errdefer` |
| Type operations | `is` |

`true`, `false`, `null`, and `unit` are predefined constants, not keywords, but are forbidden as declaration names.

The following names are reserved for the unsupported capabilities listed in 0.6 and for future versions, and are forbidden as identifiers:

```text
async await yield unsafe extern macro
```

Annotations beginning with `@` are recognized separately by the lexer and are not keywords.

The following names are predefined type names and MUST NOT be shadowed by user types or type parameters:

```text
Bool Byte Short Int Long UByte UShort UInt ULong Int128 UInt128
Float Double Char void Unit
String Object Any List Set Map Result Text StringBuilder Bytes
```

`Array` is not a source type name; array types are written only as `T[]`.

### 1.4 Literals

#### 1.4.1 Integers

```text
0  42  1_000_000
0xFF  0b1010  0o755
42L  42U  42UL
```

- Decimal, `0x` hexadecimal, `0b` binary, and `0o` octal are supported.
- Underscores may appear only between two digits; they MUST NOT appear after a base prefix, at the beginning or end of a literal, or consecutively.
- Suffixes are case-insensitive, but the canonical forms are `L`, `U`, and `UL`. Suffixes MUST NOT be repeated or combined into other forms.
- Suffixes fix the literal type: `L` is `Long`, `U` is `UInt`, `UL` is `ULong`.
- An unsuffixed integer is a target-typed literal: if there is an expected numeric type and the value is representable, the expected type is used; without an expected type, `Int` is used; a value outside the target type's range is a compile error.
- The expected type of a suffixed literal MUST be the same as the suffix type, otherwise it is a compile error.
- Integer types include `Byte`, `Short`, `Int`, `Long`, `UByte`, `UShort`, `UInt`, `ULong`, `Int128`, `UInt128`; `Int128` / `UInt128` are 128-bit.
- Integer literals carry no sign; the minus sign is a prefix operator, not part of the literal.

#### 1.4.2 Floating Point

```text
1.0  3.14159  1.0e9  2.5e-3  1.0f
```

- Floating-point literals MUST contain a decimal point or an exponent part; there MUST be digits on both sides of the decimal point. `1.` and `.5` are not valid floating-point literals.
- Decimal exponents `e` / `E` are supported, optionally with a `+` / `-` sign.
- Underscores may appear only between two digits.
- An unsuffixed floating-point literal is a target-typed literal: if there is an expected type, the expected type is used; otherwise `Double`.
- The `f` suffix fixes the type to `Float`; a `Float` expected type and the `f` suffix MUST agree.
- Floating point uses IEEE 754 binary32 (`Float`) or binary64 (`Double`); compile-time rounding is round-to-nearest, ties-to-even.
- Hexadecimal floating point, NaN literals, and infinity literals are not provided; these values are produced by numeric APIs provided by the library.

#### 1.4.3 Characters

```text
'a'  '\n'  '\''  '\\'  '\u{1F600}'
```

Character literals use single quotes, and the content MUST be exactly one Unicode scalar value or one escape sequence. Empty character literals, multi-character literals, and multi-line character literals are all lexical errors.

`Char` is a 32-bit value type that represents Unicode scalar values in the range `0..0x10FFFF`, excluding the surrogate range `0xD800..0xDFFF`. `Char` does not participate in arithmetic; it supports only equality and comparison by code point order; conversion to and from integers is provided by library functions.

Escape sequences:

| Escape | Value |
| --- | --- |
| `\\` | Backslash |
| `\'` | Single quote |
| `\"` | Double quote |
| `\n` | U+000A |
| `\r` | U+000D |
| `\t` | U+0009 |
| `\0` | U+0000 |
| `\xHH` | Exactly two hexadecimal digits, value 0..255 |
| `\uHHHH` | Exactly four hexadecimal digits |
| `\u{H...}` | 1 to 6 hexadecimal digits, the value MUST be a valid scalar |

Unknown escapes, insufficient digits, or values outside the valid scalar range are lexical errors.

#### 1.4.4 Strings and Interpolation

| Form | Delimiter | Escapes | Multi-line | Interpolation |
| --- | --- | --- | --- | --- |
| Ordinary string | `"..."` | Yes | No | No |
| Raw string | `r"..."` | No | No | No |
| Multi-line string | `"""..."""` | Yes | Yes | No |
| Raw multi-line string | `r"""..."""` | No | Yes | No |
| Interpolated string | `$"..."` | Yes | No | Yes |

- Ordinary strings cannot span lines; an unterminated string is a lexical error.
- Raw strings do not process backslash escapes; backslashes are preserved as ordinary characters. A raw string cannot contain its closing delimiter.
- The content of a multi-line string is preserved verbatim; indentation is not removed, and leading and trailing newlines are not removed. Non-raw multi-line strings still process escapes.
- String literals have type `String`. `String` is an immutable UTF-8 byte sequence; `length()` counts bytes.
- In an interpolated string, `{expression}` is an expression; `{{` produces a literal `{`; a `}` that is not part of an interpolation is treated literally. Interpolation expressions MUST be complete, and parentheses may nest; an unterminated interpolation is a lexical error.
- Interpolation expressions MUST NOT be `void`. Formattable values are: `String`, `Bool`, integers, `Float`, `Double`, `Char`, `null`, `Unit` (formatted as `unit`), simple enums, tuples whose elements are all formattable (formatted as `(a, b)`, with elements recursively applying this rule), and types that declare `String toString()`. `Bool` is formatted as `true` / `false`, integers in decimal, floating point in the shortest round-trippable representation, simple enums by item name, and `null` as `null`.
- Interpolation is evaluated from left to right in source order; after all interpolation parts are evaluated, they are concatenated into a new `String`. An interpolated string is not a constant expression.
- Adjacent string literals are not automatically concatenated; `+` or interpolation MUST be used.

#### 1.4.5 Booleans and Null

`true` and `false` are `Bool` literals. `null` is the null value literal; its static type is the internal type `Null`, and it can be assigned only to reference types or `T?`.

### 1.5 Operators and Punctuation

Operators are recognized by longest match:

```text
<<=  >>=  ...  ..<  ===  !==  ==  !=  <=  >=  <<  >>
&&  ||  ??  ?.  as?  ->  +=  -=  *=  /=  %=  &=  |=  ^=  ++  --
+  -  *  /  %  =  <  >  !  ?  :  &  |  ^  ~  .  ,  ;  @
```

Punctuation: `(` `)` `{` `}` `[` `]`.

`..<` is a half-open range, `...` is a closed range. `as?` is a single token, not `as` plus `?`. `?.` is a single token.

### 1.6 Statement Termination and Newlines

Go-style automatic semicolon insertion is used:

- The lexer does not produce newline tokens; each token records its starting line.
- At a newline, if the last token is an identifier, literal, `)`, `]`, `}`, `++`, `--`, `return`, `break`, `continue`, or `throw`, a statement end is inserted automatically.
- No statement end is inserted before `else` or before the `while` of a `do`.
- An operator at the beginning of a line does not continue the previous line; multi-line expressions MUST be wrapped in parentheses. It is forbidden to rely on leading tokens such as `+`, `.`, or `?.` to continue the previous line.
- The `{` that opens a body MUST be on the same line as the preceding header; a newline inserts a semicolon at the end of the header.
- The value of `return` / `throw` MUST be on the same line as the keyword; when a line break is needed, wrap it in parentheses.
- Explicit `;` is still allowed; writing multiple statements on the same line MUST use `;` separators.
- Blank lines and comment lines do not trigger statement termination.
- Semicolons after `package` and `import` are optional.

```x
Int a = 1
Int b = 2
a = a + b

Int c = 1; Int d = 2

Int e = (a + b)

Int f = a
Int g = -b
```

- `e` MUST be written with parentheses as a multi-line expression; `Int f = a` and `Int g = -b` are two statements.
- The conditions and headers of `if` / `else` / `while` / `do` / `for` / `switch` do not use parentheses; bodies MUST be brace bodies.
- Brace bodies appear only in functions, types, control bodies, lambdas, and `defer` / `errdefer` positions; they cannot be standalone statements.

Semicolons after `package` and `import` are optional. A semicolon after a control body is an optional empty statement.

### 1.7 Lexical Diagnostics

The following cases MUST produce lexical errors:

- Unterminated block comments, strings, character literals;
- Invalid escapes, invalid scalar values;
- Invalid numeric formats, misplaced underscores, conflicting suffixes;
- Unrecognizable characters;
- Invalid interpolation expression boundaries.

Lexical errors MUST include the file, line, and column range; invalid tokens MUST NOT be silently treated as valid tokens.

## 2. Type System

### 2.1 Type Categories

| Category | Types | Passing semantics |
| --- | --- | --- |
| Value types | `Bool` `Unit` `Byte` `Short` `Int` `Long` `UByte` `UShort` `UInt` `ULong` `Int128` `UInt128` `Float` `Double` `Char` | Copied by value |
| Reference types | `String` `Object` `Any` `T[]` | Passed by object handle |
| Library types | Capability contracts of Part 7 (implementations map to `List` / `Map` / `Set` / `Text` / `Bytes` / `StringBuilder`, etc.) | All are reference types; passed by object handle |
| Language-level error type | `Result<T,E>` | Value type; see Section 10 |
| Tuples | `(T1, T2, ...)` | Copied by value; see 2.11 |
| User types | `class`, `protocol`, `enum`, `singleton`, `struct` in Part 2 | Specified in Part 2 |
| Function types | `R(P1, P2, ...)` | Reference type; the value is a closure |
| Void type | `void` | Only as a return type or as the return type of a function type |

`void` cannot be used as a variable, parameter, field, container element, or type argument. `void()` is a valid function type. A `Result` with no success value uses `Unit` as the success type (§9.1, §10.1).

`Object` is the root of reference types; all reference types and `Any` can be assigned to `Object`. A value type must be explicitly boxed as `Any` before it can be used as `Object`.

`Any` is the explicit boxing type; both value types and reference types can be boxed via `as Any`. Unboxing a boxed `Any` value must use `is` / `as` / `as?`.

### 2.2 Value Types and Numeric Semantics

| Type | Width | Signedness |
| --- | ---: | --- |
| `Byte` / `UByte` | 8 | Signed / unsigned |
| `Short` / `UShort` | 16 | Signed / unsigned |
| `Int` / `UInt` | 32 | Signed / unsigned |
| `Long` / `ULong` | 64 | Signed / unsigned |
| `Int128` / `UInt128` | 128 | Signed / unsigned |
| `Float` | 32 | IEEE 754 |
| `Double` | 64 | IEEE 754 |
| `Char` | 32 | Unicode scalar value |
| `Bool` | 1 logical bit | `true` / `false` |

Integer rules:

- Signed integers use two's complement; unsigned integers use the same bit patterns, but comparison, division, and right shift are interpreted as unsigned.
- Overflow of `+`, `-`, and `*` wraps modulo 2^width and does not trigger a panic.
- Integer division truncates toward zero; the sign of `%` follows the dividend. A divisor of 0 triggers a panic; `MIN / -1` wraps to `MIN` according to the width.
- The right operand of `<<` and `>>` must be `Int` or an integer literal adaptable to `Int`. A runtime shift count less than 0 or greater than or equal to the width triggers a panic; an out-of-range compile-time constant is a compile error.
- Signed `>>` is arithmetic right shift; unsigned `>>` is logical right shift.
- There are no implicit conversions between different numeric types. Binary arithmetic and bitwise operations require both sides to have the same type; literals can adapt to the target type. `Int + Long` is a compile error.
- Unary `-` on unsigned integers wraps according to the width; `~` bitwise-complements all integer types; unary `+` accepts only numeric types.

Floating-point rules:

- `Float` / `Double` follow IEEE 754; overflow produces infinity, underflow produces 0 or a subnormal number, division by zero produces infinity or NaN, and no panic is triggered.
- `==` between NaN and any value (including itself) is `false`, and `!=` is `true`.
- No language-level conversion from floating point to integer is provided; use explicit conversion functions when needed.
- Floating-point literals and operations round to nearest, ties to even.

`Char` rules:

- `Char` is a separate value type and does not participate in arithmetic operations.
- `Char` supports `==`, `!=`, `<`, `<=`, `>`, `>=`, compared by Unicode code point.
- Conversions between `Char` and integers are provided by library functions.

### 2.3 Reference Types and Containers

`String` is an immutable UTF-8 byte sequence, passed by object handle; `String` literals, `+` concatenation, and interpolation all produce a new `String`. `String.length()` returns the number of bytes.

`T[]` is a fixed-length one-dimensional array, passed by object handle. Multi-dimensional arrays are written by appending `[]` repeatedly, with nested-array semantics: `T[][]` is equivalent to `Array<Array<T>>`. The language does not provide rectangular matrix or `Tensor` types.

`List<T>`, `Set<T>`, `Map<K,V>`, and other library container types belong to the data and text capabilities of Part 7. The language only specifies that they are reference types and that their type parameters are invariant; members, construction, and key type restrictions are specified by the library API (Part 7).

`Result<T,E>` is the language-level error type; `Ok` / `Err` are constructors. `Result` is a value type and can appear in variables, parameters, return values, fields, containers, and closures. Core propagation and handling are described in Section 10; error observation, cancellation, and timeouts are specified by the error handling specification.

### 2.4 Nullable Types

- `T?` denotes a nullable type.
- For reference types, `T?` and `T` are the same type; reference types already allow `null`.
- For value types, `T?` is a separate optional value type; `null` is a valid value.
- `T??` is equivalent to `T?`.
- Non-nullable value types cannot receive `null`.
- `null` can be assigned to any reference type or `T?`.
- `?.` returns `null` when the left side is `null`, otherwise accesses the member; when the member is a value type the result type is `T?`, and when the member is a reference type the result type is still a reference type.
- `??` returns the right side when the left side is `null`, otherwise returns the left side. The left side must be a reference type or `T?`; the right side must be assignable to the type obtained by removing nullability from the left side. The right side is evaluated only when the left side is `null`.
- Optional value unwrapping: when `T` is a value type and `x` is `T?`, `x as T` checks for non-nullness and yields `T`, panicking when it is `null`; for reference types, `T?` is the same as `T`, and `as T` performs no non-null check. `x as? T` returns `null` on failure; `x ?? fallback` provides a default value.
- This solution does not provide implicit flow-sensitive narrowing. `if x != null` does not change the static type of `x`; use `as` or `??` when a non-null value is needed.

```x
Int? maybe = 1;
Int value = maybe as Int;

Int? missing = null;
Int fallback = missing ?? 0;

String? name = null;
String display = name ?? "unknown";
```

### 2.5 Function Types

A function type is written as "return type(parameter types...)", with parameters having only types and no names:

```x
Int()
Int(String)
Int(Int, Int)
void()
```

- Function types are reference types and may be `null` by default.
- Function types are checked for equality by signature; both the parameter types and the return type must be exactly the same; function types are invariant.
- Closure literals can be checked against a target function type: parameter types must match, and each `return` expression must be assignable to the target return type.
- Calling a `null` function value is a panic.

### 2.6 Assignability

`from` is assignable to `to` if and only if one of the following holds:

| Rule | Condition |
| --- | --- |
| Same type | `from` and `to` are exactly the same |
| Error value | Both are `Result<T,E>`, and `T` / `E` are the same |
| Null value | `from` is `null`, and `to` is a reference type or `T?` |
| Optional lifting | `from` is `T`, and `to` is `T?` |
| Subtype | `from` is a subclass of `to`, or `from` is a class implementing the `to` protocol; see Part 2 |
| Generic variance | `from` and `to` are instances of the same generic declaration, and the variance check passes; see Part 2 |
| Literal | An integer literal is representable in the target integer type; a floating-point literal is representable in `Float` / `Double`; a string literal to `String` |
| Container literal | The target type provides the element type, and every element is assignable |
| Closure literal | The target type is a function type, the parameters match, and the return value is assignable |
| Tuple | The same length and element types identical one by one; tuple literal elements adapt to the target element types |
| Boxing | `from` is any type, `to` is `Any`; `as Any` must be written explicitly |
| Reference root | `from` is a reference type or `Any`, `to` is `Object` |
| Unboxing | `from` is `Any`, `to` is a concrete type; `as` / `as?` must be written explicitly |

Prohibited:

- implicit widen / narrow between numeric types;
- conversion between `Bool` and integers;
- implicit conversion between strings and numeric values;
- assigning `null` to a non-nullable value type;
- assigning a value type directly to `Object`;
- structural type matching: types are checked nominally, and having the same members does not mean the types are compatible.

### 2.7 Type Inference

- `var` infers the type from the initializer; the initializer must have a unique, determinate static type.
- `null`, an empty array `[]`, an empty Map `[:]`, and closure literals without a target type cannot be used with `var`.
- The default types of integer/floating-point literals are `Int` / `Double` respectively; with a target type, they adapt to the target type.
- Type arguments of generic functions can be omitted and are inferred according to Section 8.
- The return type context does not participate in generic function inference; write type arguments explicitly when needed.
- `var` is only used for local variables; top-level fields and member fields must have explicit types.
- Tuple literals infer element types from the element expressions; each element must have a unique, determinate static type.

### 2.8 Equality and Ordering

| Operation | Value types | `String` | Reference types | `Any` |
| --- | --- | --- | --- | --- |
| `==` / `!=` | Compare by value | Compare by content | By object identity by default | By boxed object identity |
| `===` / `!==` | Compare by value | By object identity | By object identity | By boxed object identity |

- Both sides of `==` / `!=` must have the same type, or one side must be `null` and the other a reference type/`T?`.
- Content comparison of reference types must explicitly call the `equals` method provided by the type; `==` does not call user code.
- `===` / `!==` are strict identity comparisons: value types compare values, and reference types compare references. `null === null` is `true`.
- `Result` does not provide `==` / `===`; use `isOk` / `isErr` / `value` / `error` to check.
- Tuple `==` / `!=` use the element type's equality semantics element by element; `===` / `!==` compare identity element by element; both sides must be the same tuple type.
- Ordering comparisons `< <= > >=` apply only to the same numeric type, `Char`, and simple enums (by underlying value). `String`, containers, and ordinary reference types do not participate in ordering comparisons.
- For floating-point NaN rules, see 2.2.

### 2.9 Type Checking and Conversion

- `x is T` returns `Bool`. When `x` is `null` it returns `false`. For value types it checks the exact runtime type; for reference types it checks the dynamic type or protocol implementation.
- `x as T` performs an upcast, downcast, `Any` unboxing, or optional unwrapping. Failure is a panic.
- `x as? T` is the same as `as`, but returns `null` on failure; the result type is `T?`.
- `as` / `as?` do not support numeric type conversion and do not support a `void` target.
- Upcasting is an identity conversion; downcasting checks the type descriptor at runtime; protocol conversion checks the implementation relationship.
- Unboxing `Any` to a concrete type checks the boxed type; unboxing `Any` to a protocol checks the implementation relationship.
- `x as Any` creates a boxed value for value types and wraps the reference for reference types.
- The target of `is` / `as` / `as?` must be a type, not an expression.

```x
Any boxed = 1 as Any;
if boxed is Int {
    Int value = boxed as Int;
}
Int? maybe = boxed as? Int;
```

### 2.10 Any Boxing

- A value type entering `Any` must be boxed; boxing preserves the original value and type information.
- Reference types entering `Any` also produce a boxed object; unboxing yields the original reference.
- `==` / `===` on `Any` compare boxed object identity and do not automatically unbox. For value comparison, first `as` to a concrete type.
- A boxed value cannot directly participate in arithmetic, comparison, or member access; it must be unboxed first.

### 2.11 Tuple Types

```x
(Int, String) pair = (1, "a");
(Int, Int, Bool) triple = (1, 2, true);
var inferred = (1, "a");            // (Int, String)

Int first = pair.0;
String second = pair.1;
```

Form and identity:

- A tuple type is written `(T1, T2, ...)`; it has at least two elements, the element types are listed one by one, and order is significant.
- Tuples are built-in anonymous value types with structural identity: tuples with the same length and element types identical one by one are the same type; no declaration is required.
- `(T)` is not a tuple but the parenthesized form of `T`; single-element tuples and zero-element tuples do not exist.
- Tuple elements are numbered by position starting from 0; elements have no names and no labels.
- Tuples can be nested: `((Int, String), Bool)` is a valid type.
- Tuples can be used as variables, parameters, return values, fields, container elements, closure capture values, and generic type arguments.
- Tuples cannot be used as `switch` values, `Map` / `Set` keys, `const` types, or constant expressions.
- Tuples do not participate in meaningful `is` / `as` conversions; `as` between the same type is an identity operation, and between different types it is a compile error.
- For restrictions on tuples as struct fields, see Part 2.

Value semantics:

- Assignment, parameter passing, returning, and storing in a container all copy the entire tuple; the copy is independent of the original.
- Value elements are copied by value; reference elements copy the object handle.
- Tuples do not produce object identity; tuples with all value elements can be struct fields, while tuples containing reference elements cannot be struct fields.

Member access:

- Element access is written `pair.0`, `pair.1`; after `.` there must be an integer literal within range, and out of range is a compile error.
- Tuples have no methods, properties, or other members; `pair.length` is a compile error.
- Use `?.` on a nullable tuple `T?`: `pair?.0` returns `null` when `pair` is `null`, and when the element is a value type the result is `T?`.
- Tuple elements are assignable locations: `pair.0 = 2;` requires the tuple itself to be in an assignable location.

Assignability and equality:

- There is no subtype relationship between tuples; `from` is assignable to `to` if and only if the length is the same and the element types are identical one by one.
- Tuple literals adapt each element to the target tuple's element types: a `(Int, String)` target accepts `(1, "a")`.
- `==` / `!=` use the element type's equality semantics element by element; `===` / `!==` compare identity element by element; both sides must be the same tuple type.

Interpolation:

- Tuples can be interpolated, with the format `(a, b)`; each element is formatted recursively according to the rules in 1.4.4, and if any element cannot be formatted it is a compile error.

## 3. Packages and Imports

### 3.1 package

```x
package com.acme.order
```

- A file has at most one `package`, which must be at the top of the file (except for comments).
- The semicolon is optional.
- A package name is a dot-separated sequence of identifiers and must not contain empty segments.
- When `package` is omitted, the file belongs to the default package. The default package cannot be `import`ed by other packages and is only used for single-file programs or entry points.
- Package names are case-sensitive; naming conventions do not participate in semantics.

### 3.2 import

```x
import com.acme.common.Thing
import com.acme.common.Thing as AcmeThing
import com.other.Thing as OtherThing
```

- `import` must come after `package` and before other declarations; the semicolon is optional.
- Importing package `P`: brings all public top-level symbols of `P` into the file scope; does not bind a package namespace alias.
- Importing symbol `P.S`: brings only `S` into the file scope.
- `import P.S as A`: allowed only when the simple name of `S` conflicts with another imported symbol; `A` is a disambiguation alias and is not used for arbitrary renaming. Using `as` in a non-conflicting scenario is a compile error.
- When importing, if the simple name is already taken by another import, an `as` alias must be used for the new import; otherwise it is a compile error.
- Package imports cannot create aliases for individual symbols within them; when two packages have symbols with the same name, use `import P.S as A` selective import instead.
- Duplicate imports of the same package or the same symbol are allowed and do not produce new bindings; the same simple name from different sources is a conflict.
- Wildcard imports are prohibited; `import P as Q` package aliases are prohibited.
- Imports must not execute user code, register global state, or modify process state. Package initialization must be side-effect-free, or explicitly triggered by the caller.
- Imports must resolve to packages in the current compilation; they must not depend on undeclared binary packages.
- Fully qualified names are always available: `com.acme.common.helper(value)`.

### 3.3 Name Resolution

Names within a file are resolved in the following order:

1. Local variables, parameters, type parameters;
2. Top-level declarations of the current package;
3. Imported symbols;
4. Fully qualified names.

For resolution of type members, see Part 2, 5.7; instance fields can be accessed without qualification, local variables or parameters shadow fields with priority, and `self` / `super` are used for disambiguation.

- Top-level declarations in the current package shadow imports with the same name.
- When two imports provide the same simple name and the current package has no declaration with that name, `as` must be used for the new import to disambiguate, or a fully qualified name must be used; two undisambiguated simple names must not coexist.
- Import aliases must be unique and must not conflict with keywords, predefined type names, or top-level declarations in the current file.
- The last segment of a package name does not bind a namespace; different packages may have the same last segment, and symbol conflicts are resolved with `as` or fully qualified names.
- Top-level `private` / `protected` symbols cannot be imported by other packages; they are visible within the same package.
- Symbols in the default package cannot be imported by other packages.

### 3.4 Multi-Package Compilation

- During multi-package compilation, types and top-level functions are internally prefixed with their package; types with the same name in different packages can coexist.
- Cross-package references must go through `import` or fully qualified names; cross-package symbol resolution must not depend on file order.
- The package import graph must be acyclic; a detected cycle is a compile error.
- Declaration order within a package does not affect visibility; functions, types, and top-level fields can forward-reference each other (for initialization order, see 4.3).

### 3.5 Import Diagnostics

The following situations must be reported as errors:

- Package or symbol does not exist;
- Use of wildcards;
- Importing `private` / `protected` top-level symbols of other packages;
- Symbols of the default package being imported across packages;
- Use of an `as` alias in a non-conflicting scenario;
- Import alias conflicts or undisambiguated simple names;
- Package import cycles;

## 4. Top-Level Declarations and Static

### 4.1 Top-Level Functions

```x
static Int add(final Int left, Int right) {
    return left + right;
}

static void notify(final String message) {
    handle(message);
}
```

- Top-level functions are static by default: `static` may be written or omitted, and the two are equivalent; writing `static` is an explicit style, and omitting it does not change semantics.
- The return type is written before the function name; write `void` when there is no return value.
- The parameter order is fixed as "type first, name second".
- Parameters may be written `final`; a `final` parameter cannot be reassigned within the function.
- Top-level functions can be overloaded and are resolved by parameter count and type; the return type does not participate in overloading.
- Parameters support only ordinary parameters and `final`; default parameters, variadic parameters, named arguments, and spread arguments are not supported.
- Top-level functions must have a function body; this solution does not provide bodyless declarations.
- Top-level functions can be recursive and can also be mutually recursive.
- Top-level functions are public by default; `private` / `protected` only restrict cross-package imports.

### 4.2 Top-Level Fields

```x
static Int nextId = 0;

Int version = 1;
final Int build = 42;
const Int limit = 10;
```

- Top-level fields may be written with `static` or declared directly; the two forms have the same semantics.
- Fields are mutable by default; `final` can only be initialized once; `const` requires a compile-time constant.
- Top-level fields must have explicit types; `var` is only used for local variables.
- A mutable top-level field may omit the initializer, in which case it takes the zero value: numeric 0, `Bool` is `false`, `Char` is `'\0'`, and references are `null`.
- A `final` top-level field must be initialized once at the declaration site; the language does not provide top-level assignment statements, so later assignment is not supported.
- A `const` field must have a compile-time constant initializer and is implicitly `static`.
- Top-level fields belong to the current package; cross-package access goes through imports or fully qualified names.
- Top-level reference fields are initialized at program startup and persist until the process ends.

### 4.3 Initialization Order

At program startup, initialization proceeds in the following order:

1. All top-level fields and static fields are first set to their zero values.
2. Packages are initialized in package dependency topological order; within the same package in path lexicographic order; within a file in declaration order.
3. The initializers of top-level fields, static fields, and singletons are executed.
4. After all initialization is complete, `main` is called.

Rules:

- When an initializer reads a field that has not yet been initialized, it reads the zero value and no error is reported.
- `const` does not participate in runtime initialization.
- The package import graph must be acyclic; a cycle is a compile error.
- Initializers may call functions; the called function sees the current state of completed initialization.
- For singleton initialization order, see Part 2.
- If an initializer panics, the process terminates and `main` is not called.

### 4.4 Overload Resolution

- Candidate functions are filtered by parameter count, then checked for applicability by parameter type.
- The return type does not participate in overloading; differing only in return type is not a valid overload.
- A `null` argument has no concrete type; if multiple reference type candidates are applicable, the resolution is ambiguous and an explicit conversion is required.
- Integer/floating-point literals adapt to the parameter type; if multiple candidates can represent the literal, the resolution is ambiguous and the type must be written explicitly.
- When there are no candidates or multiple best candidates, it is a compile error.

### 4.5 Visibility

- Top-level declarations are public by default.
- `public` explicitly makes them public; `private` allows only same-package access; `protected` is the same as `private` at the top level and provides no additional semantics.
- Visibility is only checked at compile time and does not change field storage or object identity.
- `private` / `protected` top-level symbols of other packages cannot be imported, nor accessed through fully qualified names.

## 5. Local Variables

### 5.1 Declaration Forms

```x
Int total = 0;
final Int answer = 42;
const Int limit = 10;
var count = 1;
```

- Typed local variable: `Type name [= expression];`; it can be initialized at the declaration site or definitely assigned once later.
- `final`: bound once; it can be initialized at the declaration site or definitely assigned once later.
- `const`: compile-time constant; must have an initializer; the type must be a constant type.
- `var`: infers the type from the initializer; must have an initializer; can only be used for local variables.
- A statement declares only one variable.
- Local variables must have an explicit type or `var`; omitting both is not allowed.
- An uninitialized local variable must be definitely assigned before it is read; otherwise it is a compile error.

### 5.2 Scope

- The scope of a local variable starts at the declaration and ends at the end of the enclosing function body, control body, `case`, or `defer` body.
- Brace bodies can be nested: function bodies, control bodies, `defer` bodies, and closure bodies; a standalone `{}` cannot be used to create a scope.
- Declaring a variable with the same name repeatedly in the same scope is a compile error.
- Parameters are in the top-level scope of the function body; the top level of the function body cannot declare a local variable with the same name as a parameter.
- The scope of a `for` loop variable is the loop body; each iteration creates a new binding.
- Each `case` / `default` clause of a `switch` is an independent scope.

### 5.3 Definite Assignment

- A local variable must be definitely assigned before it is read; otherwise it is a compile error.
- A `final` local variable must be assigned exactly once on every normal path.
- A `const` local variable is initialized at the declaration site.
- `var` is initialized at the declaration site.
- Definite assignment for branches, loops, and `goto` is analyzed according to the control flow graph; a `while true` loop with no reachable `break` does not require subsequent assignment.
- The error return path of `try` does not require subsequent assignment; the success path continues to be analyzed according to normal control flow.
- The jump edges of `goto` are included in the above control flow graph analysis: whether a variable is considered assigned at the jump target is determined by the rules in 6.10; `goto` must not be used to make an unassigned variable "pass" the definite assignment check.
- When an uninitialized variable is not read, it is allowed to be declared without being assigned for the time being.

### 5.4 Constant Expressions

A constant expression consists of the following:

- Literals;
- Other `const` constants;
- Unary, binary, and ternary operators, with all operands being constant expressions;
- `String + String`;
- Simple enum items (Part 2).

Constant expressions must not contain function calls, object creation, container literals, tuple literals, interpolated strings, assignment, increment/decrement, or `as` / `as?` runtime checks.

Types allowed for `const`: `Bool`, integer types, `Float`, `Double`, `Char`, `String`, simple enums, and `null` with a reference type. `const` does not allow class instances, containers, arrays, closures, or `Any` boxing.

## 6. Statements and Control Flow

### 6.1 Statement Categories

| Statement | Form | Rule |
| --- | --- | --- |
| Local declaration | `Int x = 1;` | See Section 5 |
| Expression statement | `f();` | Result discarded |
| Assignment | `x = 1;`, `x += 1;` | The left side must be assignable |
| Increment/decrement | `i++;`, `--i;` | Only for integer types; only as a statement |
| `if` / `else` | `if cond { } else { }` | The condition must be `Bool` |
| `while` | `while cond { }` | The condition must be `Bool` |
| `do` / `while` | `do { } while cond` | The condition must be `Bool` |
| `for-in` | `for x in src { }` | Iterates over arrays, List, Set |
| Range loop | `for i in 0..<n` / `0...n` | The loop variable is `Int` |
| `switch` | `switch value { case v: ... default: ... }` | No implicit fallthrough |
| `defer` / `errdefer` | `defer body` / `errdefer body` | Scope cleanup; see Section 10 |
| `break` / `continue` | `break [label]` / `continue [label]` | Applies to the nearest loop/`switch`, or the specified label |
| `label` / `goto` | `name: stmt` / `goto name` | Jump within the same function |
| `return` | `return value` / `return` | All normal paths of a non-`void` function must return |
| `throw` | `throw value` | fatal/panic; not a recoverable error |
| Empty statement | `;` | No operation |

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

- `{ ... }` is the syntactic form of function bodies, control bodies, type bodies, lambda bodies, and `defer` / `errdefer` bodies, not an independent statement.
- Writing `{ ... }` directly as a statement is a compile error; when an independent scope is needed, use `if` / `while` / a function or another structured control body.
- A brace body creates a new scope; declarations in the body are not visible after the body ends.
- Brace bodies can be nested in control bodies, function bodies, or closure bodies; nested bodies can shadow outer variables with the same name.
- Brace bodies cannot be used as expressions; there are no block expressions.

### 6.3 Expression Statements

```x
compute();
value.method();
```

- An expression statement evaluates and discards the result.
- Assignment, increment, and decrement cannot appear in expression position; `a = (b = 1)` is a compile error.
- The result type of an expression statement can be any type; a `void` call is also a valid expression statement.

### 6.4 Assignment and Increment/Decrement

```x
total = total + 1;
total += 1;
values[0] = 1;
list[0] = 2;
i++;
--i;
```

- Assignable locations: non-`final` local variables, non-`final` parameters, writable fields, array elements, `List` elements, and elements of assignable tuples.
- `Map` does not use subscript assignment; use `put`.
- `String` does not use subscript assignment.
- A compound assignment reads the left side once, then evaluates the right side, then applies the operator and writes back.
- The intermediate result of a compound assignment must be assignable to the left side's type; `Int += Long` is a compile error.
- `++` / `--` apply only to integer types; the operand must be assignable; when used as a statement, the result is discarded.
- `final` variables, `final` fields, `@ReadOnly` fields accessed from outside, and private fields outside the class are not assignable.
- An assignment statement itself has no value; assignments must not be chained.

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

- The condition must be `Bool`; no parentheses are written around the condition.
- The bodies of `if` / `else` must be brace bodies; single-statement bodies are not supported.
- `else` pairs with the nearest unclosed `if`; because bodies require braces, there is no dangling else.
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

- The condition must be `Bool`; no parentheses are written around the condition.
- The bodies of `while` / `do-while` must be brace bodies; single-statement bodies are not supported.
- `do` executes the loop body first, then tests the condition.
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

- `for item in source` iterates over `T[]` and any type that provides an `iterator(): Iterator<T>` method.
- `Iterator<T>` is a library type that provides `hasNext(): Bool` and `next(): T`; calling `next()` when there are no elements is a programming error (panic).
- `Map` does not provide `iterator()` by default; to iterate, first get `keys()` or `values()`.
- The loop variable is a new local binding; each iteration creates a new binding, so closures capturing each iteration's value do not affect each other.
- When the iterated element is a `struct`, it is copied by value; reference types copy the object handle. Structs have no "non-copyable" branch.
- The loop variable can be reassigned, but it is not written back to the container.
- The range `a..<b` is half-open and `a...b` is closed; the left and right operands must be `Int` and are evaluated once at the start of the loop.
- If the lower bound is greater than the upper bound, the range loop executes zero times.
- Range expressions are only allowed in the source position of `for-in`; use in other positions is a compile error.
- No parentheses are written in the `for` header; the `for` body must be a brace body.
- `break` exits the loop; `continue` proceeds to the next iteration.

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

- No outer parentheses are written around the `switch` value.
- The `switch` value is evaluated only once.
- `case` expressions are evaluated in source order until the first equality match; subsequent `case`s are not evaluated.
- After a `case` matches, its clause is executed, and the `switch` exits automatically after execution; there is no implicit fallthrough.
- `case` does not require compile-time constants; `switch` does not check exhaustiveness by default. When the `switch` value is an enum, exhaustiveness is checked according to Part 2, 8.5: when there is no `default`, all enum items must be covered.
- There is at most one `default`, and it must be last.
- Each `case` / `default` clause is an independent scope; variables declared within a clause do not leak into other clauses.
- `break` exits the `switch`; `continue` applies to the nearest enclosing loop, and if there is no enclosing loop it is an error.
- The `switch` value type must be `Bool`, an integer, `Char`, `String`, a simple enum, or a reference type; `Float` / `Double`, `Result`, and tuples are not allowed as `switch` values.
- `case` expressions must be assignable to the `switch` value type; comparison uses the semantics of `==`.

### 6.9 break / continue / return / throw

- `break` exits the nearest loop or `switch`; not being inside a loop or `switch` is a compile error.
- `continue` proceeds to the next iteration of the nearest loop; not being inside a loop is a compile error; when inside a `switch`, it applies to the enclosing loop.
- `break label` exits the loop or `switch` with that label; `continue label` proceeds to the next iteration of the loop with that label.
- The label must be within the same function, and the target of `continue label` must be a loop; `break label` can point to a loop or a `switch`.
- Labeled `break` / `continue` are structured control flow and execute `defer` / `errdefer` when leaving the scope; `goto` does not.
- `return value` can only appear in a non-`void` function; `value` must be assignable to the return type.
- `return;` can only appear in a `void` function, a constructor, or `deinit`.
- All normal paths of a non-`void` function must return a value; paths terminated by `throw` do not need to return.
- `throw value` is fatal/panic: it prints diagnostics and a call stack, then terminates the process. `throw` is not a recoverable error; recoverable errors use `Result<T,E>`.
- `throw` does not unwind the stack and does not guarantee execution of `deinit` or cleanup logic.
- The operand of `throw` must be `String` or a type implementing `Error`; strings are output as-is.

### 6.10 label / goto

```x
Int i = 0
start:
i++
if i < 3 {
    goto start;
}
```

- A label is written `name:`, followed by a statement; an empty statement is written `name: ;`.
- A label can be attached to a loop or `switch` for use by `break label` / `continue label`; it can also be attached to other statements for use by `goto`.
- Label names are unique within a function; labels and variables use different namespaces.
- `goto name` jumps to a label within the same function; it cannot cross functions or lambdas.
- The target label must be in the current function body/control body or an outer function body/control body; jumping from an outer body into an inner body is prohibited.
- When `goto` jumps out of a function body/control body, it does not execute any cleanup, `deinit`, or `defer`; external resources must be managed with structured control flow.
- After a `goto` jump, uninitialized local variables remain uninitialized; reading them is a compile error.
- Duplicate labels and undefined labels are compile errors; a target type mismatch for `break label` / `continue label` is also a compile error.

### 6.11 Empty Statement

```x
;
label: ;
```

An empty statement performs no operation. An empty statement can be used for a label or an empty loop body. An empty statement must not be used as an expression that requires a value.

### 6.12 Control Flow Diagnostics

The compiler must reject:

- Non-`Bool` conditions;
- Use of `break` outside a loop/`switch`;
- Use of `continue` outside a loop;
- Treating a standalone `{ ... }` as a statement;
- `break label` / `continue label` pointing to a nonexistent label or an incorrect target type;
- A non-`void` function with a normal path that does not return;
- A `void` function returning a value;
- Duplicate, undefined, or cross-scope `goto`;
- Incompatible `case` expression types;
- `Float` / `Double` / `Result` used as a `switch` value;
- A `defer` / `errdefer` body containing a control transfer, `try`, or `throw`;
- Use of `errdefer` or `try` in a function that does not return `Result`;
- The body of `if` / `else` / `while` / `do` / `for` / `switch` not being a brace body.

## 7. Expressions and Operators

### 7.1 Basic Expressions

- Literals, identifiers.
- Member access: `value.member`, `value.method()`.
- Nullable member/call: `value?.member`, `value?.method()`.
- Subscript: `array[index]`, `list[index]`.
- Call: `f(args)`, `value.method(args)`.
- Object construction: `new Type(args)`; the rules are in Part 2; the syntax is valid in this Solution.
- Explicit generic arguments: `identity<Int>(1)`.
- Array/collection literal: `[1, 2, 3]`; `Set` also uses `[...]`, determined by the target type.
- Fixed array creation: `new T[count]`, e.g. `new Byte[4096]`; `count` must be `Int`, the elements are zero-initialized, and the result is `T[]`.
- Map literal: `["a": 1, "b": 2]`; the empty Map is written `[:]`.
- Tuple literal: `(1, "a")`; at least two elements; type and access rules are in 2.11.
- Closure: `() -> { ... }`, `(Int x) -> { ... }`.
- String interpolation: `$"value={total}"`.
- `Result` propagation: `try expression`; only for `Result`, see 10.2.

### 7.2 Operators and Precedence

Precedence from high to low:

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
- Arithmetic, shift, bitwise, and logical operators are left-associative.
- `??` is right-associative.
- The ternary operator is right-associative; the condition must be `Bool`, and the two branches must have a common type, or one side is `null` and the other side is a reference type.
- Comparison operators cannot be chained; `a < b < c` is a compile error, and the intent must be written explicitly with parentheses.
- Range operators cannot be chained and are only allowed in the `for-in` source position.
- Assignment statements are handled separately and do not participate in expression precedence.

Rules:

- `String + String` is concatenation; a string and a number cannot be directly `+`-ed; use `$"..."` interpolation.
- Both sides of an arithmetic operation must have the same numeric type; literals may adapt.
- `&&` / `||` require both sides to be `Bool`; short-circuit evaluation: when the left side of `&&` is `false` or the left side of `||` is `true`, the right side is not evaluated.
- The left side of `??` must be a reference type or `T?`; the right side is evaluated only when the left side is `null`.
- `a != null && a.f()` relies on short-circuit semantics; if `a` is `null`, the right side is not executed.
- `==` / `!=` are value comparisons by default; `String` compares by content; the default comparison for reference types is object identity; content comparison uses the `equals` provided by the type.
- `===` / `!==` are strict identity comparisons.
- The target of `is` / `as` / `as?` is a type.
- Generic calls may omit inferable type arguments.
- Unary `!` accepts only `Bool`; unary `-` / `+` accept only numbers; `~` accepts only integers.
- `try expr` is only for `Result`; on failure it returns the error per 10.2.
- `new` is a primary expression; `new Type(args)` constructs an object, and `new T[count]` creates an array.
- `?` is only used as a nullable type suffix and in the ternary operator; it is no longer a `Result` propagation suffix.

### 7.3 Evaluation Order

Except for the ternary operator and `?.`, expressions are evaluated from left to right, and subexpressions with side effects must not be reordered:

- Binary operations: left first, then right.
- Calls: evaluate the called expression first, then evaluate the arguments from left to right.
- Assignment: evaluate the left-side address first (including the subscript expression), then evaluate the right side, then write back.
- Compound assignment: read the left side once, evaluate the right side, apply the operator, and write back.
- `try` propagation: evaluate the operand first; on `Ok`, unwrap and continue; on `Err`, run the current scope's `defer` / `errdefer` and return the error.
- `&&` / `||`: left first, then right; the right side is not evaluated when short-circuiting.
- `??`: left first, then right; the right side is not evaluated when the left side is not `null`.
- Ternary `cond ? a : b`: evaluate `cond` first, and evaluate only the selected branch.
- `?.`: evaluate the left side first; if it is `null`, skip the member access and the evaluation of call arguments, and the result is `null`; otherwise continue.
- `new Type(args)`: evaluate the constructor arguments from left to right first, then allocate the object and call the constructor.
- `new T[count]`: evaluate `count` first, then allocate the array and zero-initialize it.
- Array literal: the elements are evaluated from left to right.
- Map literal: for each key-value pair, the key is evaluated before the value, and the pairs are evaluated from left to right.
- Tuple literal: the elements are evaluated from left to right.
- Interpolated string: the parts are evaluated in source order.

### 7.4 Numbers and Comparison

- Binary arithmetic and bitwise operations require both sides to have the same type; integer literals may adapt to the other side's type.
- `+ - * /` apply to integers and floating-point numbers; `%` applies only to integer types; floating-point remainder is provided by library functions.
- `& | ^ ~ << >>` apply only to integer types.
- The right operand of `<<` / `>>` must be `Int`; the result has the left operand's type.
- Comparison operations require both sides to have the same type; `null` can only be compared with reference types/`T?`.
- `String` supports only `==` / `!=` / `===` / `!==`; no ordering comparison is provided.
- Reference types support only `==` / `!=` / `===` / `!==`; no ordering comparison such as `<` is provided.
- `Bool` supports only `==` / `!=` / `===` / `!==`; it does not participate in magnitude comparison.

### 7.5 Nullable Chaining and Null Coalescing

```x
String? name = user?.name;
Int length = name?.length() ?? 0;
```

- `a?.b` returns `null` when `a` is `null` and does not access `b`.
- `a?.m(args)` does not evaluate `args` when `a` is `null`; the return type is the optionalized version of the original return type.
- Chained `a?.b.c`: `?.` only guards the immediately adjacent member access; if `a` is non-null but `b` is `null`, `.c` still panics. To guard the whole chain, use `?.` at each level.
- `??` removes only one layer of nullability; `T??` is equivalent to `T?`.
- `??` evaluates the right side only when the left side is `null`.

### 7.6 Type Operations

- `x is T`: returns `Bool`; returns `false` when `x` is `null`.
- `x as T`: upcast, downcast, unboxing, or optional unwrapping; panics on failure.
- `x as? T`: returns `null` on failure; the result type is `T?`.
- The right operand of `as` / `as?` must be a type, not an expression.
- For value types, `is` checks the exact type; for reference types, `is` checks the dynamic type or protocol conformance.
- `as` to a superclass or an implemented protocol is an upcast and produces no runtime check.
- `as` to a subclass, an unimplemented protocol, or a concrete `Any` type requires a runtime check.
- `is` / `as` on `Result` check the concrete type; no implicit conversion is performed.

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

- Closure syntax: `(parameter list) -> { statement block }`; write `()` for zero parameters; parameter types must be written.
- Closure parameters have only a type and a name and may be marked `final`; annotations, default values, and variadic parameters are not supported.
- With a target function type, each `return` is checked against the target return type; without a target, the type of the first `return` is the candidate, and the remaining `return`s must be assignable to that type; with no value returned, it is inferred as `void`.
- A closure body has two forms: a brace body `(parameters) -> { statement block }`, or a single-expression body `(parameters) -> expression`.
- A single-expression body is shorthand for `{ return expression; }`: the expression's type is checked against the target return type, and with no target it is handled by the `return` inference rules of 7.7; the expression's evaluation, exception, and definite-assignment semantics are exactly the same as `return`.
- The expression in a single-expression body cannot be an assignment, an increment/decrement, or a bare block; when side effects are needed, write a brace body.
- Closures capture outer local variables, parameters, and `self` by reference.
- Captured variables are promoted to heap cells; subsequent reads and writes go through the cell.
- When multiple closures capture the same variable, they share the same cell, and modifications are visible to each other.
- Nested closures share the outer cell.
- Capture-by-value syntax is not supported; the language provides no weak references, so weak capture does not exist.
- Captured variables need not be `final`.
- Closures are first-class function values; the storage of captured variables is held by the closure, and lifetimes are covered in Part 2.
- Closures can be nested, passed as parameters, returned, and stored in containers and fields.
- Closures can return `Result`; when returning `Result`, they may use `try`, `defer`, and `errdefer`, and errors return only from the closure, not through the enclosing function.
- `try` inside a closure requires the closure's target return type to be `Result<_, E>`; with no target type and no inferred `Result`, it is a compile error.
- A closure literal can be called immediately: `((Int x) -> { return x + 1; })(1)`.
- Calling a `null` closure is a panic.

### 7.8 String Interpolation

- An interpolated string is `$"..."`; `{expression}` is evaluated and formatted per the rules of 1.4.4.
- `{{` produces a literal `{`; a `}` that is not inside an interpolation is a literal.
- An interpolation expression cannot be `void`; it cannot contain an unpaired `}`.
- An interpolation expression may contain nested parentheses, closures, and generic calls.
- `Result` is not interpolated directly; check it, unwrap it, or call an explicit formatting API first.
- Format specifiers such as `{value:X}` are not supported.
- The interpolation result is a new `String`, not a constant expression.

### 7.9 Constant Expressions

See 5.4. Constant folding in expressions must not change overflow, panic, or evaluation-order semantics; expressions containing runtime checks cannot be folded.

### 7.10 Unified Rules for Functions and Lambdas

Top-level functions (4.1), methods and constructors of classes and structs (Part 2, 6.2 and 6.3), and Lambdas (7.7) follow the same set of function rules:

- Uniform parameter form: parameters have only a type and a name and may be marked `final`; annotated parameters, default values, variadic parameters, named arguments, and spread arguments are not supported.
- Uniform body form: functions, methods, and constructors must have brace bodies, and expression bodies are not provided; Lambdas are the exception and allow a single-expression body (7.7). A function body is mandatory, and bodyless declarations are not provided.
- Uniform type annotations: the parameter and return types of functions, methods, and constructors must be explicit; Lambda parameter types must be explicit, and the return type is inferred per 7.7 or checked against the target type; `var`-style parameter omission is not provided.
- Uniform calls: arguments are always passed positionally; overloads resolve per 4.4 and Part 2, 6.8; `Result` and `@mustUse` rules apply uniformly to all function forms.
- Dispatch is the only difference: methods have a receiver and dispatch statically or dynamically per Part 2, 5.6; Lambdas are first-class function values.

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

- Type parameters are written in `<...>` after the function name; only type parameter names are written, and constraints, default types, variadic type parameters, and variance annotations are not supported.
- Type parameters are visible only in the current function's signature and body.
- A type parameter must not have the same name as another type parameter of the same function.
- Type parameters may be used in parameters, return values, local variables, generic arguments of field access, and nested types; they may bind `Result`, function types, and container types.
- Generic functions can overload ordinary functions; resolution rules are in 8.2.
- A generic function cannot be used directly as a value; it must be instantiated first.

### 8.2 Calls and Inference

- Explicit type arguments: `identity<Int>(1)`; the count must match the number of type parameters.
- When type arguments are omitted, unify the parameter types against the argument types:
  - a type parameter matches the argument type directly;
  - nested types match layer by layer, e.g. `Box<T>` matching `Box<Int>` yields `T = Int`;
  - conflicting bindings for the same type parameter are an error;
  - if any type parameter remains unbound at the end, it is an error.
- Unsuffixed integer/floating-point arguments bind `Int` / `Double` respectively when there are no other constraints; if the same type parameter is already bound by another argument, the literal adapts to that type.
- The return type context does not participate in inference; write explicit type arguments when needed.
- Overload resolution first filters by argument count, then performs an applicability check on each candidate; type arguments for generic candidates are inferred during the check.
- When exactly one candidate is applicable, that candidate is chosen; when multiple candidates are applicable, it is an ambiguity error; zero candidates is a compile error.
- A `null` argument cannot uniquely determine a type parameter; type arguments must be written explicitly or a conversion performed.

### 8.3 Generic Instantiation

- Each distinct type-argument list produces an independent function instance; instances do not share static state.
- A type parameter cannot be `void`; an explicit or inferred `void` is a compile error.
- `is T` / `as T` can be used inside a generic function; they check against the instantiated concrete type.
- `new T()` cannot be written inside a generic function; a type parameter is not a constructible runtime type.
- Recursive instantiation must terminate; infinite expansion is a compile error and must not be silently truncated.
- A generic function body must be visible at the instantiation point.

### 8.4 Restrictions

- Type constraints, `where` clauses, default type arguments, and variadic type parameters are not supported.
- Generic closures are not supported; when generic behavior is needed, use a generic function.
- Static local variables cannot be declared inside a generic function.
- Taking a reference to a generic function and instantiating it later is not supported.

## 9. Built-in Types and Common Members

### 9.1 Overview

| Type | Source | Category | Key Members |
| --- | --- | --- | --- |
| `String` | Language | reference, immutable UTF-8 | `length` `substring` `indexOf` `trim` `split` `replace` `toUpper` `toLower` |
| `T[]` | Language | reference, fixed length | subscript, `length`, `join` |
| `(T1, T2, ...)` | Language | value type | `.0` `.1`…; see 2.11 |
| `Unit` | Language | value type, zero size | sole value `unit` |
| `Result<T,E>` | Language | value type, `@mustUse` | `isOk` `isErr` `value` `error` `unwrapOr`; see 10.1 |

`Unit` is the built-in empty-value type: its sole value is `unit`; it is zero-sized, has no identity, and is copied by value; it is used as `Result<Unit,E>` to represent operations with no success value. `unit == unit` is `true`, and `str(unit)` is `"unit"`.

`List<T>`, `Map<K,V>`, `Set<T>`, `StringBuilder`, `Text`, and `Bytes` are library types and belong to the XDK capabilities of Part 7; the language only specifies that they are all reference types with invariant type parameters.

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

- `length()` returns the number of UTF-8 bytes.
- `substring(start, length)` slices by bytes; a `start` below 0 is treated as 0, and one beyond the length is treated as the length; a `length` below 0 is treated as 0; a length past the end truncates to the end. The result is always a new `String`.
- `indexOf(needle)` returns the byte offset of the first match; returns `-1` if not found.
- `trim()` removes leading and trailing ASCII whitespace: `0x09`, `0x0A`, `0x0B`, `0x0C`, `0x0D`, `0x20`.
- `startsWith` / `endsWith` compare by byte prefix/suffix.
- `split(separator)` splits on a non-empty separator; empty segments are preserved; an empty separator returns a one-element array containing the original string.
- `replace(from, to)` replaces all non-overlapping matches; an empty `from` returns the original string.
- `toUpper()` / `toLower()` convert only ASCII letters.
- `String` does not support subscripts, a `length` property, or in-place modification.
- `String + String` produces a new string; a `String` and a number cannot be directly `+`-ed.

### 9.3 T[]

```x
Int[] values = [1, 2, 3];
Int first = values[0];
values[1] = 9;
Int length = values.length();
String text = values.join(",");
```

- `T[]` is a fixed-length one-dimensional array; the literal `[...]` creates one, and its length is determined by the number of elements.
- `new T[count]` creates an array of the specified length and zero-initializes it; `count` must be `Int`; a negative count or an allocation failure is a panic; `T` cannot be an array type.
- Subscripts start at 0; out of bounds is a panic.
- Both subscript reads and assignments are supported.
- `length()` returns the number of elements.
- `join(separator)` formats the elements as strings and joins them with the separator; the elements must be formattable.
- Multidimensional arrays are nested arrays; rectangular matrices and `Tensor` are not provided.
- An array cannot be `push`-ed or have its length changed; when a growable container is needed, use a library container (Part 7).
- `T[]` is a reference type; assigning it to a variable copies the object handle, not the array. When elements are `struct`s, writes and reads copy by value; when elements are reference types, the object handle is copied.
- Array element types are invariant; `String[]` cannot be assigned to `Object[]`.

### 9.4 Container Literals

```x
Int[] values = [1, 2, 3];
Map<String, Int> counts = ["a": 1, "b": 2];
Map<String, Int> empty = [:];
```

The `Map` / `List` / `Set` in the examples are library types, not language built-in types.

- `[...]` is a sequence literal:
  - with no target type, or a target type of `T[]`, it constructs an array; when non-empty the element type is inferred as `T`; an empty `[]` must have a target type;
  - when the target type is `List` / `Set`, it desugars to `List.of(...)` / `Set.of(...)` respectively.
- `[key: value, ...]` constructs a `Map`: it desugars to `Map.of(...)`; `[:]` is the empty Map.
- When the target type is not `T[]`, `List`, `Set`, or `Map`, it is a type error.
- Each element or key-value pair is evaluated from left to right; for a key-value pair, the key is evaluated before the value.
- For duplicate keys, the value that appears later wins.
- The empty literals `[]` / `[:]` must be determined by the target type and cannot be used with `var` (see 2.7).
- `List.of` / `Set.of` / `Map.of` are library constructors whose signatures and documentation are provided by the source; the compiler only desugars and does not maintain a member table for library types.
- Key-type restrictions are specified by the library API.

### 9.5 Complexity

| Operation | Complexity |
| --- | --- |
| `String.length` | O(1) |
| `String.substring` | O(n) |
| `String.indexOf` | worst case O(n·m) |
| `String.split` / `replace` | O(n) |
| `new T[count]` creation | O(n) (zero initialization) |
| `T[]` subscript / `length` | O(1) |
| `T[].join` | O(n) |
| `Result.isOk` / `isErr` / `value` / `error` / `unwrapOr` | O(1) |

### 9.6 Member Resolution Rules

- Built-in type members are predefined by the language and cannot be overridden by user extension methods.
- Built-in members resolve by the static receiver type; calling a non-`?.` member on a `null` receiver panics.
- `length()` counts bytes on `String` and elements on `T[]`.
- `Result`'s `isOk` / `isErr` / `value` / `error` / `unwrapOr` are built-in members, see 10.1.
- Array out-of-bounds is reported via panic; the behavior of library type members is covered in Part 7.

## 10. Error Handling

### 10.1 Result

```x
Result<Int, String> ok = Ok(1);
Result<Int, String> fail = Err("missing");
```

- `Result<T,E>` is a value type; `T` is the success value type, and `E` is the error value type.
- `T` may be `Unit`, meaning there is no success value; `E` cannot be `void`.
- `Ok(value)` constructs a success value; `Ok(unit)` is used for `Result<Unit,E>`; `Err(error)` constructs a failure value.
- Constructors are inferred from the target type; with no target type, `Ok(1)` or `Err("x")` cannot determine the other side's type, so the type must be written explicitly or supplied by context.
- `Result` is `@mustUse`: a `Result` value must be returned, assigned to a variable/field/container, propagated with `try`, or have one of its members called; discarding it as a bare expression statement is a compile error.
- `Result` does not provide `==` / `===`; use the members to check.
- `Result` may appear in variables, parameters, return values, fields, containers, and closures.

Members:

```x
Bool isOk()
Bool isErr()
T value()          // panics when Err
E error()          // only when E is non-void; panics when Ok
T unwrapOr(T fallback)
```

- `isOk()` / `isErr()` are always safe.
- `value()` / `error()` are only called in the branch already confirmed; reading the success value in the error branch, or the error value in the success branch, is a program error and panics at runtime.
- For safe unwrapping, use `try` or check `isOk` / `isErr` first.

### 10.2 try Propagation

```x
Result<Config, AppError> load(String path) {
    String text = try readText(path);
    Config config = try parse(text);
    return Ok(config);
}
```

- `try expr` is only for `Result`.
- On success, unwrap to `T` and continue; on failure, run the current scope's `defer` / `errdefer`, then return `Err` from the current function or closure.
- The enclosing function or closure must return `Result<_, E2>`; `E` must be assignable to `E2`; otherwise it is a compile error. Implicit stringification is forbidden.
- `try` on `Result<Unit,E>` produces `Unit`; when used as an expression statement, the value is discarded.
- `try` is a prefix operation that applies to the immediately adjacent prefix expression; precedence is in 7.2.
- `try` cannot be used in constructors, `deinit`, `main`, or `defer` / `errdefer` bodies.
- When `try` is used inside a closure, the error returns from the closure and does not pass through to the enclosing function; the closure's target return type must be `Result`.
- `try` does not unwind the stack, print logs, or invoke global observers.
- `try` can be nested: `try try parse(text)` unwraps the outer `Result` first, then the inner `Result`.

### 10.3 defer / errdefer

```x
Result<Unit, IoError> copy(String from, String to) {
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
    return Ok(unit);
}
```

- `defer Statement` runs when the current scope exits; `errdefer Statement` runs only when the current function or closure returns with `Err`.
- Execution points: normal scope exit, `return`, `try`, `break` / `continue` (including labeled forms). They do not run on `goto`, `throw`, or process exit.
- `errdefer` execution condition: the function or closure returns with an `Err` value, including `try` propagation, an explicit `return Err(...)`, and returning a `Result` variable that is `Err` at runtime; it does not run for a normal `return Ok(...)`, a plain `return`, or `break` / `continue`.
- Within the same scope, bodies run in reverse registration order (LIFO). On an error return, both `defer` and `errdefer` run; on a normal exit, only `defer` runs.
- A `defer` / `errdefer` body may be a brace body or a single non-declaration statement; a brace body is a cleanup body, not an independent statement.
- The body of `defer` fixes its scope at registration time and reads the variables' current values at execution time; it must not allocate closures. In the example, `close` / `remove` return `void`; when a cleanup call returns `Result`, it must be handled explicitly, and an unhandled `Result` still produces a diagnostic per `@mustUse`.
- A `defer` / `errdefer` body (including nested brace bodies) must not contain `return`, `break`, `continue`, `goto`, `try`, `throw`, `defer`, or `errdefer`; cleanup must be non-throwing.
- `errdefer` may appear only in a function or closure that returns `Result`; otherwise it is a compile error.
- `defer` / `errdefer` may appear only in a function body, a control body, or a closure body; they must not serve as the single-statement body of `if` / `while` / `for`. They are not allowed at top level or in type bodies.
- The single-statement body of `defer` / `errdefer` must not be a local declaration; when a local variable is needed, use a brace body.
- Cleanups registered inside a loop body run at the end of each iteration; when `break` / `continue` exits the current iteration, the cleanups registered in that iteration run.
- `defer` manages only external resources such as files, locks, transactions, and sockets; object lifetimes are covered in Part 4.

### 10.4 throw and fatal

- `throw` is fatal/panic: it prints a diagnostic and call stack, then terminates the process; it is not a recoverable error.
- `throw` does not unwind the stack and does not guarantee that `defer`, `errdefer`, or `deinit` runs.
- Implicit fatal paths such as array out-of-bounds, null-reference dereference, a failed `as`, division by zero, and shift out of range also terminate the process.
- Recoverable errors must use `Result` + `try`; using `throw` to express expected errors is forbidden.

### 10.5 Error Observation Boundary

- This Solution specifies the construction, propagation, and handling of `Result`, as well as `defer` / `errdefer`.
- Logging, diagnostics, cancellation, timeouts, `ErrorKind`, and boundary conversions are specified by the error handling specification.
- Error observation is boundary behavior, not control flow; a global notification hub or implicit recovery must not be introduced.
- The error type `E` may be an enum, struct, class, or `Error` protocol implementation; `E` cannot be `void`.
- An unhandled `Result` must produce a compile diagnostic.

## 11. Program Entry Point

### 11.1 Entry

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
- The entry must receive one `String[]` parameter; the parameter name is arbitrary; `final` is optional.
- When the entry returns `void`, the exit code is 0; when it returns `Int`, the return value is used as the process exit code. The portable exit-code range is 0..255; other values are truncated by the platform.
- The entry must be public (public by default or explicitly `public`).
- The entry cannot be a generic function, cannot have extra parameters, and cannot have default or variadic parameters.
- A program may have only one entry with a matching signature; other `main` overloads are ordinary functions.
- The entry may live in the default package or in a package specified by the build configuration; a `main` in any other package cannot serve as the entry.
- The entry file is specified by the build configuration; this Solution only specifies the entry function signature and the startup order.
- `args` is a new array created at runtime whose elements are the argument strings; modifying the array elements does not affect the process's original arguments.

### 11.2 Startup Order

1. Initialize top-level fields, static fields, and singletons per 4.3.
2. Call the entry.
3. After the entry returns, the process terminates with the exit code; global `deinit` is not guaranteed to run.

If a panic occurs during initialization, the process terminates and the entry is not called. If a panic occurs inside the entry, the process terminates without unwinding the stack.

## Appendix A: Basic Syntax Grammar

This appendix uses EBNF; `{ X }` means zero or more times, and `[ X ]` means optional. Line-break and semicolon rules are in 1.6; in the grammar, `[ ";" ]` denotes an optional explicit semicolon.

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
TopLevelField     = [ "static" ] ( "const" Type Identifier "=" Expression
                                  | [ "final" ] Type Identifier [ "=" Expression ] ) [ ";" ] ;
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

LocalDecl         = "final" Type Identifier [ "=" Expression ] [ ";" ]
                  | "const" Type Identifier "=" Expression [ ";" ]
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

- Type-argument parsing for `<` takes effect only after a called expression and only when the token sequence up to the matching `>` parses as type arguments and is immediately followed by `(`; otherwise `<` is the comparison operator.
- Distinguishing function types from named types: when the return type is immediately followed by `(`, it is parsed as a function type.
- The `[]` / `?` of a `TypeRef` may appear consecutively; `T?[]` is "an array of nullable `T`", `T[]?` is "a nullable array"; `T??` normalizes to `T?`.
- `new T[count]` is an array-creation expression; `value[index]` is a subscript expression. Parsing distinguishes them by whether `(` or `[` follows `new`.
- `Block` appears only as a `Body`, function body, lambda body, constructor/method body, or cleanup body, not as an independent `Statement`; a standalone `{}` is a syntax error.
- `?.` is only for nullable member access; a call is still `?.` followed by a member and then a call. `?` is only used as a nullable type suffix and in the ternary operator.
- The lexical constraints of `InterpolatedString` are in 1.4.4: `{Expression}` is evaluated and formatted, `{{` / `}}` produce literal `{` / `}`; `StringCharNoBrace` is any source character other than `"`, an unpaired `}`, and a newline; details are specified by the lexical rules.
- `++` / `--` appear in the grammar only in the statement form `IncDecStatement`; the expression grammar contains no increment/decrement, so `Int a = i++;` is rejected by this appendix's grammar, consistent with 6.1 and 6.4.
- The Lambda single-expression body `-> Expression` is shorthand for `-> { return Expression; }`; both forms coexist in the grammar and are treated as equivalent semantically per 7.7.
- Tuple types and tuple literals have at least two elements; `(T)` and `(e)` are the parenthesized forms of a type and an expression respectively, not tuples.
- The outermost parentheses of a function type and of a declaration's parameter list form the parameter list; a type in nested parentheses inside a parameter list that contains at least two top-level elements is a tuple type: `Int((Int, String))` is a function type taking a tuple, and `Int(Int, String)` is a two-parameter function type.
- An integer literal after `.` is only for tuple element access; an out-of-range position is a compile error. An integer literal after `?.` is only for nullable tuples.
- `try` is a prefix operation, and `try expr` is only for `Result`.
- The grammar of `TypeDeclBody` is in Part 2, Appendix A; this appendix defines only the basic syntax.
- A construct accepted by the grammar that violates semantic rules must be rejected during type checking; acceptance by the grammar must not be treated as validity.
