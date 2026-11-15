# XNull Detailed Design for a High-Performance AST and Extremely Compact Tokens

> Status: design draft v1 · 2026-11-15
> Scope: `src/compiler/lexer/`, `src/compiler/parser/`, `src/compiler/codegen/`, `src/mini/main.x`
> Related: Design 01 (backend), Design 03 (Map/array), Design 06 (parallel compilation)
> Algorithm selection: every implementation node lists candidate algorithms, complexity, pros and cons, and the rationale for the choice; see the "Algorithm Selection and Comparison" section.

## 1. Conclusions

The problem with the current front end is not that "the algorithms are slow" but that **the representation is too expensive**:

- Every token is an object carrying `String text`, `String value`, `List<String> segs`, `List<String> interps`, `String suffix`;
- Every AST node is a generic `N/TN` carrying `String raw`, `String nm`, `List<String> fn`, `List<N> fv`, `List<N> el`;
- Field access relies on `fld(n, "Name")` linearly scanning strings;
- Line/column numbers are 4 `Int`s per node, with no byte offset;
- The symbol table in `src/mini/main.x` is parallel `List<String>`s, with lookup done by string comparison;
- `Codegen.x`'s `dec(String)` parses integers character by character via `substring`, and `joinLinear` recursively concatenates pairwise.

Goal: **16-byte tokens, 32-byte AST nodes, zero strings on hot paths, zero per-node malloc**. Estimating at 1 million tokens/nodes, memory drops from hundreds of MB to tens of MB, and front-end throughput improves by 3–10x.

## 2. Current-State Quantification

### 2.1 Token

`src/compiler/lexer/lexer/Tok.x`:

```x
class Tok {
    Int kind = 0
    String text = ""
    Int line = 1
    Int col = 1
    Int str = 0
    String value = ""
    List<String> segs = []
    List<String> interps = []
    Int ch = 0
    Int base = 0
    String suffix = ""
    Bool hasSuffixF = false
}
```

Problems:

- Object header + 12 fields;
- `text` is allocated for every token;
- String tokens additionally carry `value`, `segs`, `interps`;
- `line/col` cost 8 bytes each per token (if `Int` is 64-bit);
- Every `List<String>` costs at least one heap allocation.

Rough estimate: an ordinary token is 200+ bytes, a string token 500+ bytes. 1 million tokens means 200–500 MB.

### 2.2 AST

`src/compiler/parser/parser/TN.x` and `src/compiler/codegen/N.x`:

```x
class TN {
    Bool sc = false
    String raw = ""
    String nm = ""
    List<String> fn = []
    List<TN> fv = []
    List<TN> el = []
}
```

Problems:

- All nodes share a single shape; type information is carried by strings;
- `fld` linearly searches for the field name:

```x
static N fld(N n, String name) {
    Int i = 0
    while i < n.fn.length() {
        if n.fn.get(i) == name { return n.fv.get(i) }
        i = i + 1
    }
    return new N()
}
```

- Every node has at least 2 strings + 3 `List`s;
- A missing field yields `new N()`, silently producing an empty node, so errors are discovered late;
- Source positions use `line/col`, not byte offsets, so the original text cannot be fetched in O(1).

### 2.3 Parser / Codegen

- `Parser` holds a `List<Tok>`; it lexes everything before parsing, and token objects stay resident;
- `Codegen`'s `dec(String)` does a per-character `substring(i,1)`;
- `joinLinear` recursively concatenates pairwise, worst case O(n²);
- `unqBig` repeatedly splits strings with `substring`.

## 3. Design Principles

1. **SoA > AoS**: token/node bodies go into contiguous arrays; cold fields go into side tables.
2. **ID > pointer > string**: hot paths pass only `u32` IDs.
3. **Intern every repeated string**: identifiers, keywords, and literal text are stored only once.
4. **Arena allocation**: freed wholesale at the end of a compilation unit; no per-node GC/ARC.
5. **Decode on demand**: token text, literal values, and line/column numbers are computed only when needed.
6. **Positions use Span**: byte offsets are authoritative; line/column numbers are looked up through `SourceMap`.
7. **Typed nodes**: `NodeKind` enum + fixed layout, no string field names.
8. **Diffable**: old and new ASTs can be dumped simultaneously, keeping the semantic migration verifiable.

## 4. Extremely Compact Tokens

### 4.1 Token Layout

Target 16 bytes:

```c
typedef struct {
    uint16_t kind;      /* TokenKind, < 256 for common cases, reserved */
    uint16_t flags;     /* line start / preceded by space / interpolation / error */
    uint32_t start;     /* source file byte offset */
    uint32_t len;       /* byte length; 0 for synthetic tokens */
    uint32_t aux;       /* NameId / LiteralId / keyword ID / 0 */
} XnToken;              /* 16 B, 4 tokens / cache line */
```

Design points:

- **Keywords/operators**: distinguished directly by `kind`; no `text` needed;
- **Identifiers**: `aux = NameId`; the text is stored only once in the `Interner`;
- **Numeric/string/char literals**: `aux = LiteralId`; the value lives in a side table and is decoded lazily;
- **String interpolation**: `aux = StringLitId`; segments/interps go into a side table;
- **Newlines/automatic semicolons**: expressed via `flags` or a separate `Semi` token; no text stored;
- **Error tokens**: `kind = TokError`, `aux = DiagId`;
- **EOF**: `kind = TokEof`, `len = 0`.

Comparison:

| Representation | Ordinary token | String token |
|---|---|---|
| Current object + String | ~200 B | ~500 B |
| New Token | 16 B | 16 B + side table |
| Reduction | ~12x | ~30x |

### 4.2 TokenKind

Use a dense `u16` enum, segmented by category so ranges can be tested cheaply:

```text
0x0000  EOF / Error / Semi
0x0010  Identifier / IntLit / FloatLit / StringLit / CharLit
0x0100  Keyword range (package/import/class/...)
0x0200  Operator range (+ - * / % == != < <= ...)
0x0300  Delimiter range (( ) [ ] { } , : ; .)
0x0400  Annotations/specials
```

Keywords store no string; `kind` is the semantics. When display is needed, `token_kind_name(kind)` looks it up in a static table.

### 4.3 TokenStream

```c
typedef struct {
    XnToken *data;
    uint32_t len;
    uint32_t cap;
    uint32_t cursor;      /* used by the parser */
    SourceFileId file;
} XnTokenStream;
```

- Contiguous array; the lexer grows it once to an estimated size (source file bytes / 4 + 64);
- The parser holds only a `cursor` and never copies tokens;
- `peek(n)` indexes directly;
- No per-token trivia; comments/whitespace are skipped;
- When comments must be preserved, they go into a separate `CommentTable` that does not pollute the main stream.

### 4.4 Interner

```c
typedef uint32_t NameId;     /* 0 = empty */

typedef struct {
    uint64_t hash;
    NameId   id;
    uint32_t len;
    uint32_t off;            /* offset into the string arena */
} InternEntry;

typedef struct {
    InternEntry *entries;    /* open addressing, power of two */
    uint32_t     cap;
    uint32_t     len;
    char        *bytes;      /* contiguous string arena */
    uint32_t     bytes_len;
    uint32_t     bytes_cap;
    uint32_t     shard_count;
} Interner;
```

- Sharded (64 shards by default), with an independent lock/atomic per shard, enabling parallel lex (Design 06);
- Hashing: Wyhash/xxHash64; the hash is stored to avoid recomputation;
- `NameId` is stable: within the same compilation unit, the same string appears only once;
- Keywords are pre-registered and populate the table at startup;
- Identifier comparison degrades to `u32` comparison;
- The string arena appends in chunks (64 KB) and never relocates via realloc.

### 4.5 LiteralTable

```c
typedef struct {
    uint32_t off;       /* source file offset */
    uint32_t len;
    uint8_t  kind;      /* int/float/string/char */
    uint8_t  base;      /* 2/8/10/16 */
    uint16_t flags;     /* has suffix / has underscores / decoded */
    union { int64_t i; double f; uint32_t cp; } value;
} LiteralEntry;
```

- The lexer records only the range and kind; it does not parse immediately;
- The value is decoded the first time it is needed, and the result is cached;
- Integer overflow/illegal literals are reported as diagnostics during sema;
- String interpolation: `StringLit { uint32_t seg_start, seg_len; }`, with segments storing `NameId`/`LiteralId` ranges.

## 5. SourceMap and Span

### 5.1 Span

```c
typedef struct {
    uint32_t start;     /* byte offset */
    uint32_t len;
    uint16_t file;      /* SourceFileId */
    uint16_t flags;     /* synthetic / macro */
} XnSpan;               /* 12 B */
```

- The authoritative position is `start/len`, not line/col;
- Diagnostics, `#line`, and IDE navigation all use Span;
- Synthetic nodes use `flags = SYNTHETIC`, `start = 0`.

### 5.2 SourceMap

```c
typedef struct {
    const char *bytes;
    uint32_t    len;
    uint32_t   *line_starts;   /* start offset of each line */
    uint32_t    line_count;
} SourceFile;

typedef struct {
    SourceFile *files;
    uint16_t    file_count;
} SourceMap;
```

- The lexer records `line_starts` in a single scan;
- `span_line_col(span)` uses binary search, O(log lines);
- It is called only on the error path for diagnostics, never on hot paths;
- Line/column numbers are no longer stored in tokens/AST.

## 6. AST Arena and Node Layout

### 6.1 Node Layout

Target 32 bytes:

```c
typedef uint32_t NodeId;      /* 0 = null */
typedef uint16_t NodeKind;
typedef uint32_t TypeId;
typedef uint32_t SymbolId;

typedef struct {
    NodeKind kind;        /* 2 B */
    uint16_t flags;       /* 2 B: lvalue/const/error/... */
    uint32_t span;        /* 4 B: SpanId */
    TypeId   type;        /* 4 B: filled in after sema */
    NodeId   a;           /* 4 B: left child / first child / callee */
    NodeId   b;           /* 4 B: right child / sibling / argument range */
    NodeId   c;           /* 4 B: third child / else / next */
    uint32_t aux;         /* 4 B: NameId/LiteralId/ChildRange */
} XnNode;                 /* 28 B payload, 32 B aligned */
```

A fixed 32 bytes (8-byte aligned) is recommended; variants exceeding 32 bytes use side tables:

- `kind` determines how `a/b/c/aux` are interpreted;
- Most expressions have only 2 operands, so 32 bytes suffice;
- `Call`'s argument list is stored as `ChildRange { start, len }` rather than hanging a `List` off the node;
- `Block`'s statement list likewise uses `ChildRange`;
- Literals store only `LiteralId`, never a `String`.

### 6.2 Child Node Storage

Do not hang a `List<Node>` off every node. Use a global child array plus ranges:

```c
typedef struct {
    NodeId  *items;
    uint32_t len;
    uint32_t cap;
} NodeVec;

typedef struct {
    uint32_t start;
    uint32_t len;
} ChildRange;
```

- `Block`, `Call`, `Params`, `ClassBody`, etc. use `ChildRange`;
- Single children use `a/b/c` directly;
- The sibling chain `next` is used only for top-level declaration/statement lists, not for all nodes;
- This way no node has its own vector allocation.

### 6.3 Arena

```c
typedef struct NodeChunk {
    struct NodeChunk *next;
    uint32_t used;
    uint32_t cap;
    XnNode  nodes[];
} NodeChunk;

typedef struct {
    NodeChunk *head;
    NodeChunk *cur;
    NodeVec    children;
    /* side tables */
    NodeVec    types;
    NodeVec    symbols;
    /* diagnostics */
    DiagVec    diags;
} AstArena;
```

- Chunks are 64 KB by default and appended on demand;
- `NodeId` is a global index and does not change with chunks;
- All chunks are freed at once when the compilation unit ends;
- No GC/ARC calls, hence no per-node reclamation pressure;
- If the XNull language layer cannot yet manage raw memory directly, use the FFI arena from `xdk.compiler.support` (C implementation) as a bootstrap; replace it with an XNull implementation after self-hosting.

### 6.4 Node Kinds

Layering by syntax is recommended, with `NodeKind` as `u16`:

```text
Declarations: Program, Package, Import, Class, Struct, Enum, Protocol, Method, Field, ...
Types: NamedType, GenericType, ListType, MapType, SetType, OptionalType, FunctionType
Expressions: IntLit, FloatLit, StringLit, CharLit, BoolLit, NullLit,
        Ident, Self, New, Call, MethodCall, FieldAccess, Index,
        Binary, Unary, Assign, Cast, Is, As, IfExpr, Match, ...
Statements: Block, VarDecl, ExprStmt, If, While, ForIn, Return, Break, Continue,
        Defer, ErrDefer, Try, Throw, Report
Patterns: Wildcard, Binding, Tuple, EnumPattern, ...
```

The meaning of each kind's fields is written into `ast_layout.def` (X-macro or generated table) and shared by parser/codegen/sema, preventing "field name typos".

## 7. Parser Design

### 7.1 Streaming Parsing

```c
typedef struct {
    const XnTokenStream *ts;
    uint32_t cursor;
    AstArena *arena;
    Interner *interner;
    DiagVec *diags;
    uint32_t recovery_depth;
} Parser;
```

- Tokens are not copied;
- `peek(n)` indexes directly;
- On failure, `expect(kind)` produces an `ErrorNode` and resynchronizes to `;`/`}`;
- Error recovery throws no exceptions and allocates no strings;
- Creating a node only writes to the arena, with a single `node_new(kind, span)`.

### 7.2 Node Construction API

```c
NodeId node_new(AstArena *a, NodeKind k, XnSpan span);
NodeId node_unary(AstArena *a, NodeKind k, XnSpan s, NodeId x);
NodeId node_binary(AstArena *a, NodeKind k, XnSpan s, NodeId l, NodeId r);
NodeId node_list(AstArena *a, NodeKind k, XnSpan s, const NodeId *xs, uint32_t n);
```

`node_list` appends the children to the global `children` array and returns a `ChildRange` encoded into `aux`.

### 7.3 Diagnostics

```c
typedef struct {
    uint16_t code;      /* diagnostic code, e.g. PAR-001 */
    uint16_t flags;
    uint32_t span;
    uint32_t arg0;
    uint32_t arg1;
} Diag;
```

- Diagnostics store only the ID/span/arguments, never a formatted string;
- Output looks up a static template + `SourceMap`;
- The sort key is `(file, start, code)`, guaranteeing identical output for parallel/serial runs;
- Error recovery uses `ErrorNode` and does not abort the whole file.

## 8. HIR and Name Resolution

The AST is the syntax tree; the HIR is the tree in which "names/types have been resolved". Do not let codegen read AST strings directly.

```c
typedef struct {
    NodeKind kind;
    uint16_t flags;
    uint32_t span;
    TypeId   type;
    SymbolId symbol;      /* resolved */
    NodeId   a, b, c;
    uint32_t aux;
} HirNode;
```

- Scope chains use `ScopeId` + side tables, not string-keyed Maps;
- Symbol table `Symbol { NameId name; TypeId type; SymbolKind kind; uint32_t decl; }`;
- Type table `Type { TypeKind kind; ... }`, with globally unique `TypeId`s;
- Method/protocol slots are assigned stable `u16 slot`s during sema;
- The DET-01 decision result is written to `Type.memory_policy` and read directly by codegen.

## 9. Eliminating Stringified Codegen

### 9.1 Replacing `fld(N, String)`

Old:

```x
N n = fld(node, "Body")
```

New:

```x
NodeId body = node_field(node, FieldBody)   // compile-time constant, direct offset
```

- `FieldBody` is an enum/constant, not a string;
- `node_field` is a `switch(kind)` or table-driven, O(1);
- A missing field is reported at parse time and never produces an empty `N`.

### 9.2 Replacing `dec(String)`

Old:

```x
static Int dec(String s) {
    Int v = 0
    Int i = 0
    while i < s.length() {
        String c = s.substring(i, 1)
        if c == "0" { v = v * 10 + 0 }
        ...
    }
}
```

New:

- The lexer stores `int64_t value` in the `LiteralTable`;
- The parser fetches it directly with `literal_int(id)`;
- No per-character substring;
- Overflow/base handling happens once in the lexer/sema.

### 9.3 Replacing `joinLinear`

Old: pairwise recursive concatenation, O(n²) and full of temporary strings.

New: `StringBuilder`:

```c
typedef struct {
    char   *buf;
    size_t  len;
    size_t  cap;
} StringBuilder;

void sb_reserve(StringBuilder *b, size_t n);
void sb_append(StringBuilder *b, const char *s, size_t n);
```

- Estimate the total length and grow once;
- Code generation appends block by block, producing no intermediate String;
- Finally a single `rt_string_new`, or write straight to the file.

### 9.4 Switching Codegen Input to MIR

- No longer walks the generic `N` tree;
- Reads instructions, blocks, and types from MIR's `MnFunction`;
- C output uses `CBuf` (see Design 01);
- Source positions are mapped through `MnSpanId`, not the line/col in nodes.

## 10. Memory and Performance Targets

| Metric | Current estimate | Target |
|---|---|---|
| Token size | 200–500 B | 16 B |
| Token allocations | 1/ token + strings | 0 (preallocated array) |
| AST node size | 100–300 B | 32 B |
| AST node allocations | 1 object + 2–3 Lists | 0 (arena chunk) |
| Identifier storage | one String per occurrence | one global interned copy |
| Line/column numbers | 4 Ints per token/node | 0 (Span + SourceMap) |
| 1M token memory | 200–500 MB | ~16 MB + interner |
| 1M AST node memory | 300 MB+ | ~32 MB + side tables |
| Front-end throughput | baseline 1x | 3–10x |
| 100k-line front end | several seconds | < 1.5s (single-threaded) |

## Algorithm Selection and Comparison (by Front-End Node)

> Notation: N = source bytes, T = tokens, A = AST nodes, K = number of keywords, S = number of distinct identifiers.
> The primary constraint on front-end algorithms is constants and memory, not big-O: for the same O(N), a cache-friendly implementation can be 3–10x faster.

### A1. Lexical Analysis

| Algorithm | Complexity | Throughput | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Hand-written DFA (switch/goto) | O(N) | High | Fastest, good error messages, easy to extend | Large amount of code | **Adopted** |
| Table-driven DFA | O(N) | Medium-high | Compact code, easy to generate | Many table-lookup cache misses | Alternative |
| Regex/NFA engine | O(N·M) | Low | Flexible | Backtracking/state explosion | Not adopted |
| SIMD whitespace/identifier scanning | O(N/16) | Highest | Fast on large text volumes | Platform-dependent, complex | Optional acceleration |

Choice: hand-written DFA with a `switch` main loop; whitespace/identifier scanning can optionally be accelerated with SSE2/NEON. Rationale: XNull's grammar is simple and its diagnostic requirements are high, so the hand-written DFA has the smallest constants.

### A2. Keyword Recognition

| Algorithm | Complexity | Pros | Cons | Verdict |
|---|---|---|---|---|
| Per-character comparison/linear table | O(K·L) | Simplest | Slow when K is large | Not adopted |
| Binary search | O(log K·L) | Simple, ordered | Still involves string comparison | Alternative |
| Trie | O(L) | Prefix sharing | Pointer chasing, poor cache | Alternative |
| Perfect hashing (gperf style) | O(L) | One hash + one comparison | Requires generated tables | **Adopted** |
| Hash table | O(L) average | Flexible | Collisions/memory | Alternative |

Choice: the keyword set is fixed, so use perfect hashing; identifiers go through the interner and never consult the keyword table.

### A3. Token Representation

| Representation | Memory/token | Locality | Decoding cost | Verdict |
|---|---|---|---|---|
| Object + String (current) | 200–500 B | Poor | Low | Rejected |
| AoS packed 16 B | 16 B | Good (4/cache line) | Low | **Adopted** |
| Bit-packed 8 B | 8 B | Best | Medium (bit operations) | Alternative |
| SoA (kind/span/aux separate) | 12–16 B | Scan-friendly | Medium | Alternative |
| Pure text re-scan | 0 | Poor | High | Not adopted |

The 8 B scheme would need to squeeze offset/len into 24/16 bits, limiting single-file size; the 16 B scheme supports 4 GB files and is more robust in engineering terms.

### A4. String Interning

| Algorithm | Lookup | Insert | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Chained hashing | O(1+α) | O(1) | Simple, easy deletion | Pointer chasing, poor cache | Not adopted |
| Open addressing with linear probing | O(1/(1-α)) | O(1) | Contiguous, good cache | Deletion needs tombstones | **Adopted** |
| Robin Hood | O(1+α) | O(1) | Low variance, good tail latency | Complex deletion/rehashing | Alternative |
| Trie | O(L) | O(L) | Prefix sharing | Many pointers/much memory | Not adopted |
| Sorted array + binary search | O(log S·L) | O(S) | Deterministic | Slow insertion | Not adopted |

Hash function comparison:

| Function | Speed | Quality | DoS resistance | Verdict |
|---|---|---|---|---|
| FNV-1a | Fast | Medium | Weak | Not adopted |
| MurmurHash3 | Fast | Good | Medium | Alternative |
| xxHash64 | Very fast | Good | Medium | **Adopted** |
| Wyhash | Fastest | Good | Medium | **Adopted** |
| SipHash | Slow | Very good | Strong | Alternative for untrusted input |

Choice: sharded open addressing + Wyhash/xxHash; compiler source is trusted input, so SipHash's DoS resistance is unnecessary. Sharding uses the top 6 bits of `NameId`, supporting Design 06's parallel lex.

### A5. Parser

| Algorithm | Complexity | Grammar power | Error messages | Memory | Verdict |
|---|---|---|---|---|---|
| Recursive descent | O(T) | Hand-written LL(k) | Best | Low | **Adopted** |
| Pratt / precedence climbing | O(T) | Expression-friendly | Good | Low | **Adopted for expressions** |
| LR(1)/LALR | O(T) | Strong | Fair (needs recovery strategy) | Large tables | Not adopted |
| PEG / packrat | O(T) with memo | Strong | Fair | O(T) memo, large memory | Not adopted |
| GLR | O(T) average | Strongest | Poor | High | Not adopted |

Choice: recursive descent for declarations/statements, Pratt for expressions. Rationale: XNull's grammar is predominantly LL, and a hand-written parser gives the best diagnostics and error recovery; Pratt solves precedence/associativity with one small table, avoiding a separate function layer for every binary operator.

### A6. Error Recovery

| Algorithm | Complexity | Recovery quality | Implementation cost | Verdict |
|---|---|---|---|---|
| Panic mode (synchronization sets) | O(T) | Medium | Low | **Adopted** |
| Error productions | O(T) | High | High (requires grammar changes) | Later |
| LLVM-style recovery | O(T) | High | High | Not in the first version |
| Backtracking/retry | Exponential worst case | High | Medium | Not adopted |

Choice: a failed `expect` produces an `ErrorNode` and skips to `;`/`}`/top-level keywords; diagnostics are deduplicated to avoid a flood of cascading errors.

### A7. AST Representation

| Representation | Memory/node | Number of allocations | Traversal locality | Pros | Cons | Verdict |
|---|---|---|---|---|---|---|
| Object graph (current) | 100–300 B | 1 + lists | Poor | Intuitive | High allocation/GC pressure | Rejected |
| Arena AoS 32 B | 32 B | 0 (chunk) | Good | Compact, stable | Variants need side tables | **Adopted** |
| Arena SoA | 16–24 B | 0 | Best (scan by field) | Dataflow-friendly | Multiple arrays accessed, complex code | Later |
| Flat bytecode | 8–16 B | 0 | Good | Serializable | Hard to debug/rewrite | Not adopted |

Choice: AoS 32 B. Most passes traverse by node, and AoS gets kind/span/children in one cache line; SoA suits specific passes and can be added later as side tables.

### A8. Child Node Storage

| Algorithm | Per-node overhead | Insert | Traversal | Pros | Cons | Verdict |
|---|---|---|---|---|---|---|
| Per-node `List<Node>` | 24+ B + heap | O(1) | Pointer chasing | Flexible | Many allocations | Rejected |
| Singly linked sibling | 4–8 B | O(1) | Sequential | Saves memory | Poor random access | Alternative for lists |
| Global children + ChildRange | 8 B | O(1) append | Contiguous | Compact, good cache | Ranges are immutable | **Adopted** |
| first-child/next-sibling | 8 B | O(1) | Sequential | Classic | Poor reverse/random access | Alternative |

Choice: fixed arity uses the direct `a/b/c` fields; lists use a global `children` + `ChildRange`. The parser only appends and never inserts in the middle, which fits the arena naturally.

### A9. Name Resolution

| Algorithm | Lookup | Insert | Scope | Pros | Cons | Verdict |
|---|---|---|---|---|---|---|
| Scope stack + hash table | O(1) average | O(1) | Explicit push/pop | Simple, fast | Must handle shadowing | **Adopted** |
| Persistent Map | O(log S) | O(log S) | Functional | Rollback-able | Large constants | Not adopted |
| Trie | O(L) | O(L) | Prefix | Sharing | Large memory | Not adopted |
| Linear List (current) | O(S) | O(1) | Simple | No dependencies | Slow | Rejected |

Choice: one `HashMap<NameId, SymbolId>` per scope, with stack-style push/pop; `NameId` is an integer, so comparison is O(1).

### A10. Source Positions

| Representation | Per node | Line/column lookup | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Four line/col fields (current) | 16–32 B | O(1) | Direct | Large memory, cannot fetch original text | Rejected |
| Byte offset + global line table | 8–12 B | O(log L) | Compact, sliceable | Slightly slower lookup | **Adopted** |
| Delta encoding | 2–4 B | O(k) | Most space-efficient | Poor random access | Not adopted |
| Token index only | 4 B | O(1) token hop | Saves space | Depends on tokens staying resident | Alternative |

Choice: `Span { start, len, file, flags }`, with line numbers obtained by binary search in `SourceMap`; diagnostics are a cold path, so O(log L) is enough.

### A11. Diagnostic Sorting

| Algorithm | Complexity | Stability | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Insertion sort | O(D²) | Stable | Simple | Slow when D is large | Not adopted |
| Stable merge/`qsort` | O(D log D) | Controllable | General-purpose | Needs a comparison function | **Adopted** |
| Radix sort | O(D·k) | Stable | Fast for large volumes | Complex key design | Alternative |
| Generation order | O(1) | Poor | No sorting | Nondeterministic under parallelism | Not adopted |

Choice: stable sort by `(file, start, code, message)`; under parallelism, collect thread-locally and merge at the end.

### A12. Algorithm Selection Summary

| Node | Candidates | Choice | Main rationale |
|---|---|---|---|
| Lexing | hand-written DFA / table-driven / NFA | hand-written DFA | Small constants, good diagnostics |
| Keywords | linear / Trie / perfect hashing | perfect hashing | O(L) with no collisions |
| Token | object / 16B / 8B / SoA | 16B packed | Balance of memory/decoding |
| Interner | chained / open addressing / Trie | sharded open addressing | cache + parallelism |
| Parsing | recursive descent / LR / PEG | recursive descent + Pratt | Balance of diagnostics/implementation |
| Recovery | panic / error productions / backtracking | panic + synchronization sets | Simple and effective |
| AST | object graph / AoS / SoA / bytecode | Arena AoS 32B | Balance of locality/implementation |
| Children | List / linked list / ChildRange | ChildRange | Allocation-free, contiguous |
| Names | stack + hash / persistent Map / Trie | stack + hash | O(1) lookup |
| Positions | line/col / Span + line table | Span + line table | Saves memory, sliceable |
| Diagnostics | insertion / stable sort / radix | stable sort | Determinism |

### Implementation Mapping

| Algorithm/Node | Implementation Location | Phase |
|---|---|---|
| Hand-written DFA + perfect-hash keywords | `src/compiler/lexer/Lexer.x`, new `keyword_hash.x` | A1 |
| 16B Token + TokenStream | `src/compiler/lexer/Tok.x`, new `TokenStream.x` | A1 |
| Sharded open-addressing Interner | new `src/compiler/support/interner.x` (FFI transition) | A1 |
| Recursive descent + Pratt | `src/compiler/parser/Parser.x` | A2 |
| Arena AoS AST + ChildRange | `src/compiler/parser/TN.x` replaced by `ast_arena.x` | A2 |
| Span + SourceMap | new `src/compiler/support/source_map.x` | A1–A2 |
| HIR + NameId symbol table | new `src/compiler/sema/` | A3 |
| CBuf/StringBuilder codegen | `src/compiler/codegen/emit_c.x` | A4 |

**Fallback conditions**: when a single file exceeds 4 GB, the 16B token's offset overflows, so switch to the 24B/64-bit variant; when Interner shard collisions become severe, increase the shard count or switch to Robin Hood.

## 11. Phased Rollout

| Phase | Deliverable | Acceptance |
|---|---|---|
| A0 | Benchmarks and counters: token count, node count, allocation count, peak RSS | The current baseline can be measured repeatably |
| A1 | `XnToken` + `TokenStream` + `Interner` + `SourceMap`; old AST adapter | lex output matches the old path token for token; memory drops > 5x |
| A2 | Arena AST + typed nodes; parser rewrite; `NodeId`/`Span` | AST dump semantically identical to the old path; node allocations ≈ 0 |
| A3 | HIR + symbol table + type table; DET-01 results enter the tables | sema tests all green; codegen no longer looks up fields by string |
| A4 | Codegen switched to `CBuf`/`StringBuilder`/MIR input | C output diff passes; `joinLinear`/`dec` removed |
| A5 | Remove the old `Tok/TN/N` representations; update `xparser` | The self-hosting parser uses the new AST; the fixed point is reproducible |

## 12. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| The XNull language layer lacks `u32`/raw memory/arena | First provide `u32` arrays and arenas via the FFI `xdk.compiler.support`; replace after self-hosting |
| Interner contention under parallelism | Sharding + atomic IDs; single-threaded first, parallelize in Design 06 |
| Semantic drift from the AST migration | Dual dumps of old and new ASTs + differential testing; keep an adapter at every phase |
| 32 B nodes are not enough | side tables; `aux` encodes a range; 40/48 B variants when necessary |
| SourceMap binary search is slow | Use only for diagnostics/`#line`; hot paths never query line/column |
| The self-hosting compiler still uses the old AST | `xparser` switches to TokenStream first, then to the AST; two steps |

## 13. Open Questions

1. Does `NameId` need to be stable across compilation units (incremental compilation/parallelism)?
2. Should the AST retain comment/formatting information for `xnfmt`?
3. Should `NodeId` be 32-bit or 64-bit (very large files)?
4. Should the Arena be reset per phase (free the AST after sema)?
5. Should `SourceMap` be mmap-based to avoid copying file contents when reading?
