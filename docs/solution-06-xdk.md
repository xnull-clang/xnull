# XNull Solution Part 6: Standard Library XDK

| Item | Value |
| --- | --- |
| Document Number | Part 6 (S6) |
| Document Version | 3.0.0 |
| Specification Status | Draft (package catalog and layered contracts; symbol-level API added with implementation) |
| Release Date | 2026-11-15 |
| Audience | XNull language implementers and standard library authors |
| Related Parts | Part 1 v3.4.0; Part 2 v3.4.0; Part 3 v3.2.0; Part 4 v1.2.0; Part 5 v1.3.0; Part 7 v2.2.0 |

Versioning rules: revision numbers are used for clarifications that do not change semantics, minor versions for backward-compatible additions, and major versions for breaking changes. Historical versions are recorded in git.

## 0. Positioning

XDK is the **only public interface** between application code and the runtime. This part specifies XDK's layering, package catalog, inter-package dependencies, contract principles, application-boundary mapping, and versioning rules.

- **Types and algorithms live in the library**: packages, types, functions, container algorithms, text processing, file and network capabilities are all provided by the library;
- **The compiler does not do the library's work**: it only performs syntax, type checking, literal desugaring, `for-in` desugaring, and code generation;
- **The runtime does not implement library algorithms**: it only provides memory, handles, scheduling, diagnostics, and FFI primitives;
- **Package names are the library's public structure**: they are not compiler built-in types; the compiler only resolves `import xdk.a.b` to source code.

## 1. Layered Model

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ L0 Application Code                                                     │
└───────────────────────┬─────────────────────────────────────────────────┘
                        │ only via L1
┌───────────────────────▼─────────────────────────────────────────────────┐
│ L1 Public API Layer (package catalog in §4 of this part)                │
└───────────────────────┬─────────────────────────────────────────────────┘
                        │ only calls L2
┌───────────────────────▼─────────────────────────────────────────────────┐
│ L2 Primitive Layer: memory/handles/scheduling/diagnostics/FFI contracts │
└───────────────────────┬─────────────────────────────────────────────────┘
                        │ sole contact with native world
┌───────────────────────▼─────────────────────────────────────────────────┐
│ L3 Operating System / Native World (C ABI)                              │
└─────────────────────────────────────────────────────────────────────────┘
```

Rules:

- **Unidirectional dependency**: L0 → L1 → L2 → L3; reverse, cross-layer, or bypassing dependencies are forbidden.
- **L1 is the developer-visible surface**: all public types, functions, error surfaces, cancellation surfaces, and resource surfaces are in L1.
- **L2 contains no domain policy**: it does not implement collection, text, file, or network algorithms.
- **L3 is entered only through FFI contracts**: the three-contract surface, leases, and error-code mapping (Part 7, Appendix A).

## 2. Inter-Layer Contracts

### 2.1 L1 Public API Layer

- Fallible operations return `Result<T, E>`; error types follow Part 4.
- The first parameter of a blockable operation is `Context`; suspension points are cancellable and reported as `Cancelled`.
- Types holding OS resources MUST provide an explicit `close()`; `deinit` MUST NOT be the only close path.
- No global mutable singletons; no implicit initialization/cleanup hooks; no thread-local implicit state.
- Every API is labeled with stability: `stable` / `preview` / `internal`.

### 2.2 L2 Primitive Layer

- Provides only primitives; does not define domain API names.
- Primitive contracts MUST declare: blocking classification, lease/ownership, error-code mapping, and cancellability.
- Primitives MUST NOT be exposed to application code; L1 is responsible for translating primitives into domain APIs.

### 2.3 Division of Labor Among Compiler, Runtime, and Library

- **Compiler**: syntax, type checking, literal desugaring (`[...]` → `List.of` / `Set.of`, `[k:v]` → `Map.of`), `for-in` desugaring (`iterator()` / `Iterator<T>`), and code generation. The compiler only recognizes desugaring target names and the shape of iteration methods; it does not maintain a table of library type members.
- **Runtime**: memory, handles, scheduling, diagnostics, and FFI primitives. The runtime does not implement library algorithms such as collections, text, files, or networking.
- **Library**: all types and algorithms; see §4 for the package catalog; source code is the authority for APIs.

### 2.4 L3 Native Boundary

- Entered only through the FFI contracts in Part 7, Appendix A.
- "Arbitrary direct native function calls" are not allowed; every entry point is a declarative contract object.
- After native capabilities enter XNull, they MUST be adapted to this language's error, resource, and cancellation contracts.

## 3. Contract Principles

The following seven principles apply to all packages in L1:

1. **Error contract**: all fallible operations return `Result`; using panic to express recoverable failures is forbidden.
2. **Resource contract**: types holding OS resources MUST have `close()`; a failed close is not the same as not closed.
3. **Cancellation contract**: blockable operations carry `Context`; suspension points are cancellable and reported as `Cancelled`.
4. **Naming contract**: types PascalCase; methods start with a lowerCamelCase verb; boolean read access `isX` / `hasX`; private internal names `_name`.
5. **No-implicit contract**: no global mutable state, no implicit initialization/cleanup, no thread-local implicit state.
6. **Stability row**: every API is labeled `stable` / `preview` / `internal`; preview may change in a minor version, internal is not a commitment.
7. **Architecture-informed**: every package MUST declare capabilities, tier, dependencies, and stability; implementations MUST NOT hide dependencies on L2/L3.

## 4. Package Catalog

The package catalog is the library's public structure. `T0` core, `T1` application, `T2` platform/computation; `ecosystem` is not part of XDK.

### 4.1 T0 Core Packages

Any program may depend on them; stability first.

| Package | Responsibility | Key Types / API | Dependencies |
| --- | --- | --- | --- |
| `xdk.errors` | Error protocol, classification, observability | `Error`, `ErrorKind`, `wrap` / `mapErr` / `report` | L2 diagnostics |
| `xdk.runtime` | Diagnostics, exit, clock | `diagnose`, `exit`, `nowMono`, `nowWall` | L2 |
| `xdk.meta` | Language/XDK version, build info, target platform | `languageVersion`, `xdkVersion`, `targetPlatform` | none |
| `xdk.log` | Structured logging | `Logger`, `Level`, fields, sink | `errors`, `runtime`, `text`, `time` |
| `xdk.config` | Configuration snapshots and overrides | `Config`, profile, environment variable allowlist | `fs`, `text`, `codec` |
| `xdk.text` | Text, encoding, formatting, parsing | `Text`, `StringBuilder`, UTF conversion, `formatInt`, `parseInt` | `errors`, `bytes` |
| `xdk.bytes` | Byte buffers and bit operations | `Bytes`, `ByteBuffer`, endianness, bit operations | `errors` |
| `xdk.collections` | Containers and algorithms | `List`, `Map`, `Set`, `Iterator`, `sort` / `groupBy` / `dedup` | `errors` |
| `xdk.math` | Numeric functions and constants | trigonometric/exponential/logarithmic/rounding, `Int128` arithmetic | `errors` |
| `xdk.time` | Time and date | `Instant`, `Duration`, `DateTime`, `TimeZone` | `runtime`, `errors` |
| `xdk.io` | Streams and buffers | `Reader`, `Writer`, `Stream`, `Buffered*` | `bytes`, `errors` |
| `xdk.fs` | Files, directories, paths | `File`, `Dir`, `Path`, temporary files, atomic writes | `io`, `errors` |
| `xdk.sys` | Processes, environment, platform, signals | `Process`, `Env`, `platform`, `signal` | `runtime`, `errors` |
| `xdk.tasks` | Tasks and structured concurrency | `Task`, `TaskGroup`, `Context` | `errors`, `runtime` |
| `xdk.sync` | Mutual exclusion, channels, atomics | `Mutex`, `Channel`, `AtomicInt` / `AtomicBool` / `AtomicRef` | `errors`, `tasks` |
| `xdk.cli` | Command-line parsing and usage | `Args`, `Command`, `usage`, exit-code mapping | `text`, `sys` |

### 4.2 T1 Application Packages

Used by services, tools, network, and data applications; imported on demand.

| Package | Responsibility | Key Types / API | Dependencies |
| --- | --- | --- | --- |
| `xdk.regex` | Regular expressions | `Regex`, compilation, matching, replacement | `text`, `errors` |
| `xdk.codec` | Data encoding | JSON, CSV, Base64, Hex, URL encoding | `text`, `bytes`, `collections` |
| `xdk.random` | Pseudorandom and seeds | `Random`, `nextInt`, `nextDouble` | `math`, `time` |
| `xdk.stats` | Statistics | mean, median, quantiles, histogram | `collections`, `math` |
| `xdk.crypto` | Cryptography | SHA-1/256/512, HMAC, AES, KDF, constant-time comparison | `bytes`, `errors` |
| `xdk.compress` | Compression | gzip, zlib, zip | `bytes`, `io` |
| `xdk.uuid` | Unique identifiers | UUID v4/v7, ULID | `random`, `time` |
| `xdk.i18n` | Internationalization | message catalogs, plurals, locale | `text`, `codec` |
| `xdk.validate` | Validation | field rules, schema, error aggregation | `text`, `collections` |
| `xdk.resource` | Embedded resources | `resourceExists`, `readResource`, `listResources` | `bytes`, `errors` |
| `xdk.terminal` | Terminal | TTY, ANSI, progress, prompts | `io`, `sys` |
| `xdk.test` | Testing | assertions, test registration, runner hooks | `errors`, `text` |
| `xdk.net` | Networking fundamentals | addresses, Socket, DNS | `io`, `bytes`, `tasks` |
| `xdk.net.uri` | URI/URL | parsing, construction, encoding | `text` |
| `xdk.net.http` | HTTP | client, server, headers, Cookie, multipart | `net`, `text`, `codec`, `tasks` |
| `xdk.net.tls` | TLS | certificates, configuration, handshake | `net`, `crypto` |
| `xdk.net.websocket` | WebSocket | handshake, frames, close | `net.http`, `bytes` |
| `xdk.net.mime` | MIME | media types, extension mapping | `text` |
| `xdk.executor` | Executors | dedicated executors, thread affinity | `tasks`, `sync` |
| `xdk.timer` | Timers | timers, periods, deadlines | `tasks`, `time` |
| `xdk.metrics` | Metrics | Counter, Gauge, Histogram | `sync`, `time` |
| `xdk.trace` | Distributed tracing | Span, context propagation | `tasks`, `time` |
| `xdk.health` | Health checks | readiness, liveness | `time`, `metrics` |
| `xdk.audit` | Auditing | events, fields, redaction | `log`, `time` |
| `xdk.schedule` | Scheduling | cron, periodic tasks | `time`, `tasks` |
| `xdk.sql` | SQL interface | connections, statements, parameters, transactions | `net`, `io`, `codec` |
| `xdk.cache` | In-process cache | LRU, TTL | `collections`, `time` |
| `xdk.queue` | In-process queue | bounded queue, batching, close | `sync`, `tasks` |

### 4.3 T2 Platform and Computation Packages

Platform-specific or compute-heavy; stable per target platform.

| Package | Responsibility | Key Types / API | Dependencies |
| --- | --- | --- | --- |
| `xdk.ui` | Windows and application lifecycle | `Window`, `App`, `onAttach` / `onDetach` / `dispose` | `gfx`, `input`, `tasks` |
| `xdk.gfx` | 2D graphics | canvas, color, geometry, paths | `math`, `image` |
| `xdk.image` | Images | PNG/JPEG decoding and encoding, pixel buffers | `bytes`, `io` |
| `xdk.font` | Fonts and typesetting | font loading, glyphs, text layout | `bytes`, `gfx` |
| `xdk.input` | Input | keyboard, mouse, touch, shortcuts | none (event source) |
| `xdk.clipboard` | Clipboard | text/binary read and write | `ui` |
| `xdk.serial` | Serial ports | open, read/write, timeouts | `io`, `sys` |
| `xdk.device` | Devices and sensors | GPIO, I2C, SPI, camera | `sys`, `tasks` |
| `xdk.geo` | Geography | coordinates, distance, projection, paths | `math`, `collections` |
| `xdk.tensor` | CPU tensors | shapes, strides, element-wise, matrix multiplication | `math`, `bytes` |
| `xdk.linalg` | Linear algebra | factorization, solving, eigenvalues | `tensor`, `math` |

### 4.4 Ecosystem (Not Part of XDK)

The following capabilities are provided by third-party libraries or applications and do not enter XDK:

- Database drivers (concrete drivers such as PostgreSQL/MySQL/SQLite; `xdk.sql` provides only a generic interface);
- Protocol stacks (MQTT, SIP, Modbus, OPC-UA, GB28181, etc.);
- Web frameworks, RPC frameworks, template engines;
- ML training frameworks, GPU operators, model runtimes;
- Package managers, build plugins, IDE plugin ecosystems;
- Domain libraries (quantitative factor libraries, robot SLAM, image recognition models, etc.).

## 5. Application-Boundary Mapping

S0's application directions correspond one-to-one with the package catalog; not every program needs to import all packages.

| Application Direction | Primary Packages |
| --- | --- |
| Enterprise business systems | `errors`, `runtime`, `log`, `config`, `collections`, `text`, `codec`, `time`, `uuid`, `validate`, `i18n`, `metrics`, `trace`, `health`, `audit`, `sql`, `cache`, `queue` |
| Network services and gateways | `net`, `net.uri`, `net.http`, `net.tls`, `net.mime`, `net.websocket`, `tasks`, `sync`, `executor`, `timer`, `metrics`, `trace`, `health` |
| IoT and device connectivity | `net`, `serial`, `device`, `codec`, `time`, `tasks`, `log` |
| Data processing and quantitative analysis | `collections`, `math`, `stats`, `random`, `codec`, `time`, `tensor`, `linalg` |
| Rules, workflows, and domain engines | `collections`, `text`, `validate`, `schedule`, `log`, `metrics` |
| Databases, caches, and messaging | `sql`, `cache`, `queue`, `codec`, `crypto`, `net` |
| CPU algorithms and simulation | `math`, `linalg`, `tensor`, `stats`, `random`, `time` |
| AI applications and agents | `net.http`, `codec`, `tensor`, `linalg`, `tasks`, `log`, `trace`, `crypto` |
| Desktop and graphics programs | `ui`, `gfx`, `image`, `font`, `input`, `clipboard`, `fs`, `config` |
| Robotics and edge applications | `device`, `serial`, `geo`, `tasks`, `time`, `math`, `log` |
| Language and compiler tools | `fs`, `io`, `text`, `codec`, `cli`, `terminal`, `log`, `test` |
| Local tools and operations programs | `cli`, `terminal`, `fs`, `io`, `sys`, `config`, `log`, `codec` |

## 6. Dependency Rules

1. **Layering direction**: T0 may depend only on T0 and L2; T1 may depend only on T0/T1 and L2; T2 may depend only on T0/T1/T2 and L2.
2. **Reverse dependencies forbidden**: T0 MUST NOT depend on T1/T2; T1 MUST NOT depend on T2.
3. **Cycles forbidden**: the package dependency graph MUST be acyclic; a cycle is a specification error.
4. **util packages forbidden**: packages such as `util`, `common`, `misc`, `helpers`, and `base` that lack a single responsibility MUST NOT be added.
5. **Dependency declaration**: every package's documentation header MUST list capabilities, tier, dependencies, and stability; undeclared dependencies are considered contract violations.
6. **Internal packages**: `xdk.internal.*` is not public API, and applications MUST NOT import it; internal packages are not covered by stability commitments.

## 7. Naming and Granularity

- Package names are all lowercase, dot-separated: `xdk.<domain>` or `xdk.<domain>.<sub>`.
- One package, one responsibility; when a package has more than roughly 100 symbols, split it by capability, not by "type/function".
- Package names express capability, not implementation hierarchy: use `net.http`, not `net.impl.http`.
- Stable APIs MUST NOT expose internal types in public signatures; public signatures may use only public types from the same package or a lower layer.

## 8. Versioning and Stability

- New package: library minor version; new capability: library minor version; deleting, renaming, or merging packages: library major version.
- T0 packages are stabilized first; T1 packages may be `preview`; T2 packages are labeled per platform.
- Package renaming does not affect the compiler: the compiler resolves source only by `import` path; a package name change is a library version change.
- Every public symbol MUST have a stability marker; `preview` may change in a minor version, `internal` is not a commitment.
