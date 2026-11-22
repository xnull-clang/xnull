# XNull Solution Part 10: Project Configuration

| Item | Value |
| --- | --- |
| Document ID | Part 10 (S10) |
| Document version | 5.3.0 |
| Specification status | Final |
| Release date | 2026-11-15 |
| Applies to | XNull language implementations |
| Related parts | Part 1 v3.4.0; Part 3 v1.0.0; Part 5 v1.2.0; Part 7 v3.0.0; Part 8 v2.2.0; Part 9 v2.0.0 |

> **Version note**: 5.2.0 patches four gaps where "an example can be written but the grammar cannot read it": ① `language-version` uses `[3.3, 4.0)`, while the original grammar only had bracketed lists → add a **range literal** production; ② **bodyless entries** such as `module platform` and `exclusion org.old:archive` were forced by the original grammar to have `{ }` → the block body becomes optional (C.2, C.3 item 6); ③ **dotted keys** such as `db.pool.max-size` are not identifiers → add a "key name" notation and restrict it to the `configuration` section only (C.3 item 4); ④ the `*` and `?` in the resource glob `**/*.psd` are not in the bare-word character set → added. It also clarifies that **a newline is a statement terminator** (a leaf entry ends at end of line); lists/ranges must not span lines, and an entry that is not terminated by a newline is an error. New diagnostic codes `XPD-105/106/107`.
>
> **Version note**: 5.1.0 adds the **resource directory design**—`src/main/resources` / `src/test/resources`, inclusion and exclusion, the `resources/` prefix inside artifacts, merging of dependency-library resources with failure on conflict, rejection of build-time filtering, and runtime access through the library resource reading API (Part 7 §4); the service configuration file is accordingly located under the resource root. The rest of 5.0.0 is unchanged.
>
> **Finalization note**: This part specifies the complete configuration of an XNull project: the manifest section tree and inheritance, coordinates, properties and variables, dependency management, dependencies and plugins, repositories and credentials, lifecycle and artifacts, resource directories and packaging, service runtime configuration, linking and FFI declarations, reproducibility, diagnostic code ranges, and gives three complete examples—single-module project, multi-service project, and aggregator project—in Appendix A. Drafts v1.0.0 (JSON), v2.0.0 (XML), v3.0.0 (TOML), and v4.0.0 (flat XPD) are archived, and their semantic conclusions have all been absorbed into this version.

## 0. Core Stance

- **Same skeleton, self-evident coordinates**: every project and module has exactly the same manifest section structure; `groupId`/`artifactId`/`version`/`packaging` must be written by each module itself and are not filled in from the parent—coordinates are visible at a glance, and a version change in the parent project will not make a child module "change its name and identity".
- **Inheritance inherits configuration only**: the parent passes down `properties`/`dependencyManagement`/`dependencies`/`repositories`/`build` (including `plugins`)/`configuration`; **coordinates are not inherited**.
- **Exact versions**: dependency and plugin versions must be exact semantic versions; ranges, `SNAPSHOT`, and latest versions are rejected in every case.
- **Configuration per service, overridable, always validated**: configuration lives only under the service's own name; the override order has a fixed five layers; both unknown keys and missing required keys fail startup.
- **Fail rather than degrade**: a misspelled manifest, an unresolved variable, a conflict that cannot be uniquely arbitrated—all fail the build; nothing is silently corrected.

## 1. Positioning and Scope

### 1.1 Scope

Project structure and skeleton consistency; the `xnull.project` manifest (coordinates/inheritance/properties/dependency management/dependencies/repositories/build/plugins/conditional overrides/configuration baseline/linking); dependency and plugin resolution and arbitration; scopes; local and remote repositories; the credentials file; profile activation; packaging types; lifecycle and artifacts; **resource directories and packaging (§5.6)**; the lock file and metadata format; the service runtime configuration file; linking and FFI declarations; reproducibility; diagnostic code ranges; the XPD grammar (Appendix C).

### 1.2 Not specified

- The spelling of command-line tool arguments (semantic equivalence suffices; the behavior in this part is the criterion);
- The operation of remote repositories, mirror governance, and the signing system (signature verification is a non-promise, §4.7);
- IDE integration and CI platform adaptation (editor highlighting/formatting belong to the toolchain and are non-promises, §9);
- Configuration hot reload and configuration centers: rejected; configuration is governed by the five-layer snapshot taken at startup.

### 1.3 Boundaries with other parts

| Dimension | Specified by | Role of this part |
| --- | --- | --- |
| Entry signature and semantics | Part 1 §11.2 | Only specifies "how the entry is found" (§5.4) |
| Exit code mapping | Part 5 §6.2 | Reference (runtime exit codes of compiled artifacts); for the build tool's own exit codes see §5.1 |
| XDK version declaration mechanism | Part 7 §6 | Specifies the manifest fields and validation semantics (§3.9) |
| FFI native libraries and the `@unsafe` gate | Part 8 Appendix A | Specifies the manifest sections and the linking contract (§7) |

## 2. Project Model

### 2.1 Packaging types (`packaging`)

| packaging | Responsibility | Artifact | Can be depended on |
| --- | --- | --- | --- |
| `pom` | Parent or aggregator project: contains only the manifest and metadata; may carry `modules`, `configuration` | Manifest + `.xmeta` | Only as parent / aggregation entry |
| `library` | Library: a code unit that can be depended on | `.xlib` | Yes |
| `starter` | Capability aggregation package: contains only dependency declarations; importing it transitively brings in its `dependencies` | Manifest + `.xmeta` | Yes (transitive dependencies) |
| `app` | Service: has an entry and its own runtime configuration | Executable + `.xmeta` | No |

**Semantic constraints**:

- All four types use the **same section skeleton** (§3.2); differences are expressed only as constraints, with no branching such as "a different packaging means a different set of sections";
- `modules` may be non-empty only for `pom`; `configuration` may be declared only by `pom`; `entryFile`/`entryPackage` may be used only by `app`; `link` may be non-empty only for `app`/`library`;
- `app` must not be used as a dependency, must not be used as a parent, and must not be a transitive dependency of a starter;
- A `starter`'s `dependencies` are all declared with `compile` and passed on to consumers; a `starter` having a source directory (`src/`) → failure;
- The parent project must have `packaging = pom`.

### 2.2 GAV coordinates

```text
groupId    reverse domain name, lowercase dotted (com.example)
artifactId lowercase letters/digits/hyphens (order-service)
version    semantic version, exact (1.4.0)
```

- **The three coordinate fields and `packaging` must be written explicitly in every module**, including child modules;
- Duplicate `groupId:artifactId:version` within a single build → failure;
- A child module's `groupId` differing from its parent's is allowed (organizational nesting, adaptation layers), but it must be written in the manifest—this is precisely the payoff of "self-evident coordinates".

### 2.3 Directory layout

```text
order-system/
├── xnull.project           # packaging = pom
├── xnull.lock              # lock file (generated by the build, kept under version control)
├── platform/
│   └── xnull.project       # packaging = pom (parent: properties/dependencyManagement/build/plugins)
├── common/
│   ├── xnull.project
│   ├── src/main/x/         # source root
│   └── src/main/resources/ # resource root
├── order-service/
│   ├── xnull.project
│   ├── src/main/x/                 # source root
│   └── src/main/resources/         # resource root
│       ├── application.properties       # service configuration (§6)
│       ├── application-dev.properties   # profile override
│       └── templates/                   # arbitrary resource subtree
└── target/                 # artifact root (do not commit)
```

- The source root defaults to `src/main/x` and the test root to `src/test/x`; both can be overridden via `build.sourceRoot` / `build.testRoot`;
- The resource root defaults to `src/main/resources` and the test resource root to `src/test/resources`; they can be overridden or extended via `build.resources` (§5.6);
- The artifact root is fixed at `target/`; it must not be used as a source root or a resource root;
- The lock file is located at the **aggregation root** (the project root when there is no aggregation), one for the whole project (§4.4).

## 3. The `xnull.project` Manifest

### 3.1 Complete skeleton of each module

Every project and module uses the same skeleton. The order in which sections are written does not affect semantics; the formatter emits them in the order below.

```xpd
project {
  groupId    = com.example
  artifactId = order-service
  version    = 1.4.0
  packaging  = app

  parent {
    groupId      = com.example
    artifactId   = platform
    version      = 2.0.0
    relativePath = ../platform
  }

  modules {
  }

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencyManagement {
    dependencies {
      dependency com.example:common {
        version = 1.4.0
      }
    }
  }

  dependencies {
    dependency com.example:common {
    }

    dependency com.example:xdk-web-starter {
      version  = 3.2.1
      scope    = compile
      optional = false
      exclusions {
        exclusion org.old:archive
      }
    }
  }

  repositories {
    repository central {
      url = https://repo.xnull.dev/repository
    }
  }

  build {
    mode         = release
    warnings     = strict
    entryFile    = src/main/x/main.x
    entryPackage = com.example.order

    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
        configuration {
          output = target/gen
        }
      }
    }
  }

  link {
    unsafe = false
    libraries {
      library sqlite3 {
        kind   = dynamic
        system = true
      }
    }
  }

  profiles {
    profile dev {
      activation {
        platform = macos
      }
      properties {
        build-mode = debug
      }
    }
  }

  configuration {
    db.pool.max-size = 8
    envOverrides     = [db.url, db.password]
  }
}
```

### 3.2 Section overview (common to all packaging)

| Section | Required | Applies to | Repeatable | Content |
| --- | --- | --- | --- | --- |
| `project` | Yes | All | No | Root block, unique within the file |
| `groupId` / `artifactId` / `version` / `packaging` | Yes | All | No | Root block fields (§2.2, §2.1) |
| `parent` | No | All | No | Single parent (§3.3) |
| `modules` | No | All (non-empty only for `pom`) | `module` repeatable | Aggregated subdirectories |
| `properties` | No | All | Keys repeatable (keys unique) | Variables (§3.4) |
| `dependencyManagement` | No | All | Internal structure fixed | Version arbitration (§3.5) |
| `dependencies` | No | All | `dependency` repeatable | Dependencies (§3.6) |
| `repositories` | No | All | `repository` repeatable | Remote repositories (§4.7) |
| `build` | No | All | No | Compilation options, entry, resource roots (§5.2, §5.6) |
| `plugins` | No | All (inside `build`) | `plugin` repeatable | Build plugins (§5.5) |
| `link` | No | `app` / `library` (non-empty) | No | Native libraries and `@unsafe` (§7) |
| `profiles` | No | All | `profile` repeatable | Conditional overrides (§3.8) |
| `configuration` | No | `pom` only | Keys repeatable (keys unique) | Service configuration baseline (§3.10) |

**General rules**:

- Unknown sections, unknown fields, unknown block names → failure;
- A single section appearing more than once → failure; a field repeated within the same section → failure;
- Container sections may contain only their specified entry sections: `dependencies`→`dependency`, `exclusions`→`exclusion`, `repositories`→`repository`, `plugins`→`plugin`, `modules`→`module`, `libraries`→`library`, `profiles`→`profile`;
- An empty section is equivalent to omission, but if present it must be legal.

### 3.3 Inheritance rules

- **Single parent**: at most one `parent`; if absent, the project is a root project;
- Parent resolution: `relativePath` (default `../xnull.project`) → local repository → remote repositories (§4.7);
- **Inherited**: `properties` (child overrides parent), `dependencyManagement` (merged, child wins), `dependencies` (merged, same coordinate: child overrides parent), `repositories` (merged by id, child overrides parent), `build` (field-level override, `plugins` merged by coordinate), `configuration` (merged by key, child overrides parent);
- **Not inherited**: `groupId`/`artifactId`/`version`/`packaging`, `parent`, `modules`, `profiles`;
- Maximum inheritance depth 8; cycles, self-parent, missing parent, parent not `pom` → failure.

### 3.4 properties and variable substitution

- Inside the `properties` section the entries are `key = value`; key names are kebab-case and values are always strings;
- The variable form is `${name}`; it may appear inside a bare word or a string;
- Substitution is performed at **parse time** (after the manifest is loaded and before dependency resolution), exactly once; substitution results are not recursively expanded;
- Built-in variables (read-only): `project.groupId`, `project.artifactId`, `project.version`, `project.basedir`, `xnull.version` (toolchain version);
- Child overrides parent; **unresolved variable → failure** (the original text is not kept and it is not replaced with the empty string);
- Variables may be used in any field value (including `parent.relativePath`, dependency `version`, plugin version);
- **They must not be used in enum fields** (`packaging`, `scope`, `phase`, `kind`): enum values must be literally visible, and making them variable is a failure—otherwise answering "what type is this project" would require looking in two places.

### 3.5 dependencyManagement

```xpd
dependencyManagement {
  dependencies {
    dependency com.example:common {
      version = 1.4.0
      exclusions {
        exclusion org.old:archive
      }
    }
  }
}
```

- Only `version` (required) and optional `exclusions` may be declared; **the presence of `scope`/`optional` → failure** (decisions at the point of use do not belong here);
- When a child module's dependency omits `version`, the nearest management entry provides it uniquely (proximity: this module > near end of the parent chain > far end);
- Writing `version` explicitly in a dependency to override the managed version: allowed, produces a build warning;
- A dependency is declared but no one provides a version → failure (naming `groupId:artifactId`);
- Duplicate coordinates within the same management table → failure.

### 3.6 dependencies

```xpd
dependencies {
  dependency com.example:common {
  }

  dependency com.example:xdk-web-starter {
    version  = 3.2.1
    scope    = compile
    optional = true
    exclusions {
      exclusion org.old:archive
    }
  }
}
```

| Field | Default | Description |
| --- | --- | --- |
| `version` | Provided by dependencyManagement | Neither present → failure |
| `scope` | `compile` | `compile` / `runtime` / `test` / `provided` (§3.7) |
| `optional` | `false` | `true` means not transitive |
| `exclusions` | Empty | Exact coordinates removed from transitive dependencies |

### 3.7 Scopes

| scope | Visible at compile time | Visible at runtime | Transitive |
| --- | --- | --- | --- |
| `compile` | Yes | Yes | Yes (compile) |
| `runtime` | No | Yes | Yes (runtime) |
| `test` | Visible to tests | Test runtime | No |
| `provided` | Yes | No (provided by host) | No |

- Scope propagation has only two forms, `compile`→`compile` and `runtime`→`runtime`; the rest are not propagated;
- `test` dependencies must not appear in an `app`'s artifact dependency list;
- `provided` is provided by the host (runtime/platform); it is not packaged at build time and is not propagated.

### 3.8 profiles

```xpd
profiles {
  profile dev {
    activation {
      platform = macos
    }
    properties {
      build-mode = debug
    }
    dependencies {
      dependency com.example:dev-tools {
        version = 0.9.0
      }
    }
  }
}
```

- Activation (two finalized forms): explicit `-Pdev`; `activation.platform` matching the current build platform. **Environment-variable activation → rejected** (not reproducible);
- Overridable: `properties`, `dependencies`, `build` (including `plugins`), `configuration`;
- Not overridable (presence → failure): `groupId`/`artifactId`/`version`/`packaging`, `parent`, `modules`, `repositories`;
- Multiple profiles activated at once and modifying the same key → failure (do not silently take the latter);
- The set of simultaneously active profiles must be **explicitly determined**: the union of `-P` and `activation.platform`, written into `.xmeta`.

### 3.9 Version declaration (implementing Part 7 Decision 4-3)

- `properties.xdk-version`: the required XDK version (exact); toolchain XDK mismatch → failure;
- `properties.language-version`: the language version range, **the only place where a range expression is allowed** (`[3.3, 4.0)`); outside the range → failure;
- Both must be defined by the **root `pom`**; redefining them in a child module → failure.

### 3.10 configuration (service configuration baseline)

```xpd
configuration {
  db.pool.max-size = 8
  envOverrides     = [db.url, db.password]
}
```

| Field | Required | Description |
| --- | --- | --- |
| Any runtime key | No | The key name must conform to §6.3; the value is always a string; serves as layer 0 of every child service's configuration (§6.6) |
| `envOverrides` | No | List; declares whitelisted keys (runtime key names) that determine which keys may be overridden by environment variables (§6.4) |

- Only `pom` may declare it; presence in any other packaging → failure;
- **`xnull.` prefixed keys are forbidden** (reserved for the toolchain);
- Keys that look like secrets (`password`/`secret`/`token`/`key`) with a non-placeholder value → build failure (§6.6);
- Values must not contain dynamic content other than variable placeholders; variables in this section are likewise substituted per §3.4.

## 4. Dependency and Plugin Resolution

### 4.1 Resolution order

1. Expand the inheritance chain → merge the six categories of configuration (§3.3);
2. Variable substitution;
3. Determine dependency and plugin coordinate versions module by module (§3.5, §5.5);
4. Build the dependency graph (transitivity + scope propagation + exclusions);
5. Conflict arbitration (§4.2);
6. Write the lock file (§4.4);
7. Repository fetching (§4.7).

### 4.2 Conflict arbitration

- **Nearest wins**: in the dependency tree, the path that is shortest wins;
- Appearing multiple times at the same depth → **failure, listing all paths** (do not take the first, so that declaration order does not become an invisible input);
- A `dependencyManagement` version always takes precedence over nearest-wins;
- The arbitration result must be unique, otherwise failure.

### 4.3 Version rules

| Form | Status |
| --- | --- |
| Exact `1.4.0` | Finalized |
| Pre-release `1.2.3-rc.1` | Finalized (exact means allowed) |
| Range `[1.0,2.0)` | Rejected (in dependencies and plugins); only `language-version` may use it |
| `SNAPSHOT` | Rejected |
| `LATEST` / `RELEASE` / `*` | Rejected |
| Workspace module | Finalized: `modules` aggregation or `relativePath` override; no workarounds through version numbers |

### 4.4 Lock file `xnull.lock`

The format is XPD. **One per whole project**, located at the aggregation root (the project root when there is no aggregation), and kept under version control.

```xpd
lock {
  version = 1

  entry com.example:common 1.4.0 {
    kind       = dependency
    repository = central
    sha256     = 0000000000000000000000000000000000000000000000000000000000000000  # 64-digit lowercase hexadecimal
  }

  entry com.example:codegen 1.2.0 {
    kind       = plugin
    repository = central
    sha256     = 1111111111111111111111111111111111111111111111111111111111111111
  }
}
```

| Rule | Content |
| --- | --- |
| Entries | One entry per resolved dependency and plugin; `kind` is `dependency` / `plugin` |
| Ordering | Ascending lexicographic order by `groupId:artifactId`; only one entry per coordinate (guarantees byte stability) |
| Digest | SHA-256 of the artifact content, 64 lowercase hexadecimal digits; verified after download, mismatch → failure |
| Source | `repository` is the repository id |
| Consistency | Lock inconsistent with the manifest → **failure** (prompting regeneration); no automatic update |
| Generation | A first build without a lock generates it and warns to commit; `--update-lock` regenerates explicitly (the only regeneration entry point) |
| Reading | The build is governed by the lock (lock before network); a coordinate in the lock that does not exist in the manifest → failure |

Workspace dependency entries (`modules` aggregation) use the reserved
`repository = workspace` value and the deterministic `.xlib` digest defined in
[lock-workspace-v1.md](lock-workspace-v1.md).

### 4.5 Transitivity constraints

- Cyclic dependencies → failure; `app` as a dependency → failure;
- A dependency's declared `xdk-version` with a major version inconsistent with this project → failure;
- Plugins must not depend on `app` (a plugin must not import service code);
- A `starter`'s transitive dependencies must not contain `app`.

### 4.6 Repository selection and the default repository

- **`repositories` declared**: only the declared repositories are used, tried in declaration order, and the first hit is used; no repository is implicitly appended;
- **No `repositories` declared anywhere in the chain**: use the built-in default repository `central` = `https://repo.xnull.dev/repository`;
- Offline environment: `XNULL_REPO` pointing to a local repository directory is the sole source, and the build does not access the network in that case (missing artifact → failure).

### 4.7 Repositories, mirrors, and credentials

```xpd
repositories {
  repository central {
    url = https://repo.xnull.dev/repository
  }
  repository mirror {
    url      = https://mirror.internal/repository
    mirrorOf = central
  }
}
```

| Field | Required | Description |
| --- | --- | --- |
| `url` | Yes | HTTP(S); artifacts are stored in a three-level directory `groupId/artifactId/version/`, file name `<artifactId>-<version>.<ext>` |
| `mirrorOf` | No | The id of the repository being replaced; only one mirror per id; a mirror must not itself be replaced by another mirror |

**Credentials file** `~/.xnull/settings.xpd` (not part of the project, not under version control):

```xpd
settings {
  credentials central {
    username   = deployer
    tokenEnv   = XNULL_TOKEN_CENTRAL
  }
}
```

- Credentials are read only from this file and **must not be written into the project manifest**;
- Passwords/tokens **may only appear as environment variable names** (`tokenEnv`); no plaintext is stored in the file—their values must not appear in build logs or in `.xmeta`;
- Missing credentials while the repository requires authentication → failure (no fallback to anonymous retries);
- Signature verification: non-promise (reason: the ecosystem is undecided; consequence: it must not be used as a security boundary).

## 5. Lifecycle, Build, and Plugins

### 5.1 Phases and Toolchain Exit Codes

| Phase | Action |
| --- | --- |
| `validate` | Lexical/grammar/unknown-section validation, inheritance expansion, variable substitution, entry existence, lock consistency |
| `compile` | Compile `src/main/x` |
| `test` | Run the `src/test/x` test entry (can `--skip test`) |
| `package` | Produce `target/<artifactId>-<version>.<ext>` + `.xmeta` |
| `install` | Install to the local repository (can be skipped) |

**Toolchain exit codes (final, independent of the runtime exit codes in Part 5 §6.2)**:

| Code | Meaning |
| --- | --- |
| `0` | All phases succeeded |
| `1` | Build failed (compilation/test/plugin/validation failure) |
| `2` | Manifest or usage error (lexical/grammar/unknown section/argument spelling) |
| `130` | Interrupted (received SIGINT) |

- `deploy` (remote publishing) is rejected;
- Plugins may only bind to the above 5 phases and must not add phases.

### 5.2 build Fields

| Field | Value | Description |
| --- | --- | --- |
| `mode` | `debug` / `release` / `size` | Optimization level; does not change language semantics; defaults to `debug` |
| `warnings` | `default` / `strict` | `strict` promotes warnings to errors |
| `sourceRoot` / `testRoot` | path | Override the default `src/main/x` / `src/test/x` |
| `resources` | container (`resource`) | Resource roots and inclusion rules (§5.6); default `src/main/resources` |
| `entryFile` / `entryPackage` | path / package name | Entry location (§5.4); required for `app`; present on non-`app` → failure |
| `plugins` | container | §5.5 |

- Project-level definition, module-level override; environment variables do not participate in build options (`XNULL_REPO` excepted);
- `sourceRoot` must not equal or contain `target/`.

### 5.3 Artifacts and Metadata `.xmeta`

- `target/<artifactId>-<version>.<ext>`: `app` → executable, `library` → `.xlib`, `pom`/`starter` → manifest and metadata only;
- The build does not write outside the manifest directory (the cache is written to `target/.cache`);
- `.xmeta` required fields (format XPD):

| Field | Content |
| --- | --- |
| `groupId` / `artifactId` / `version` / `packaging` | Full coordinates |
| `platform` | Target platform identifier |
| `xdkVersion` / `languageVersion` | Effective values from `properties` |
| `toolchainVersion` | `xnull.version` |
| `profiles` | List of profile ids in effect for this build (ascending) |
| `plugins` | Effective plugin coordinates + goal + phase list (in execution order) |
| `lockSha256` | Content digest of the lock file used for this build |
| `inputs` | Aggregate digest of the manifest chain, source roots, and lock file digests |

### 5.4 Entry Resolution (implementing Part 1 §11.1)

1. `entryFile` + `entryPackage`: the entry is the `main` in that file, and it must be inside `entryPackage`;
2. Only `entryFile`: the entry is the `main` in that file;
3. No entry fields: default `src/main/x/main.x`;
4. No manifest: `main.x` in the current directory (Part 1 §11.1).

Failure set: file does not exist, no matching `main`, multiple matching `main`s, `entryPackage` mismatch, entry declared in a non-`app`.

### 5.5 Plugins

```xpd
build {
  plugins {
    plugin com.example:codegen 1.2.0 {
      phase = validate
      goal  = check
      configuration {
        output = target/gen
      }
    }
  }
}
```

| Field | Required | Description |
| --- | --- | --- |
| Block-header coordinates `groupId:artifactId` + version argument | Yes | Version must be exact (§4.3); uses the same repositories and lock as dependencies |
| `phase` | Yes | One of `validate` / `compile` / `test` / `package` / `install` |
| `goal` | Yes | Goal name declared by the plugin |
| `configuration` | No | Plugin-defined key-values; keys must be declared by the plugin metadata `configKeys`; undeclared → failure |

**Plugin contract (normative):**

| Constraint | Content |
| --- | --- |
| Phase | May only bind to one of the 5 phases; within the same phase, executed in declaration order; across modules, in `modules` declaration order |
| goal | Must be explicitly declared; goals not declared by the plugin must not be executed |
| Filesystem | Read-only: manifest, `src/`, dependencies; write-only: `target/`. Out-of-bounds write → build failure |
| Network | **Network access prohibited** (reason: the network makes builds irreproducible; dependent consequence: steps requiring network access must be placed outside the build) |
| Environment variables | Read-only access limited to the `XNULL_REPO` and `configuration.envOverrides` allowlist; all others invisible |
| Semantics | Must not change language semantics: must not rewrite `src/`, must not inject runtime behavior; artifact transformation, checking/reporting, and generation into `target/` are allowed |
| Failure | Non-zero exit = build failure (not downgraded to a warning) |
| Isolation | The plugin's own `dependencies` go through the same arbitration but do not enter the compile classpath of the project being built |
| Reproducible | Coordinates, goal, and phase all enter the lock and `.xmeta`; same lock ⇒ same plugin behavior |

**Plugin package metadata `.xplugin`** (located at the root of the plugin artifact, format XPD):

```xpd
plugin {
  groupId          = com.example
  artifactId       = codegen
  version          = 1.2.0
  toolchainVersion = 5.0.0

  goals {
    goal check {
      phase      = validate
      configKeys = [output, strict]
    }
  }
}
```

- Metadata missing or inconsistent with the manifest (coordinates, phase, goal, configKeys, toolchain version) → failure;
- `toolchainVersion` is a major-version compatibility constraint: different major version → failure;
- **Unrelated to runtime dynamic modules**: plugins in this section are build-time executables and do not enter the artifact; dynamic loading/unloading of managed modules at program runtime is finalized in Part 4 (not included in the initial baseline).

### 5.6 Resource Directories and Packaging

**Definition**: resources = non-`.x` files published with the artifact and not participating in compilation—templates, static pages, icons, SQL, schema, default data, localized text, etc.

```xpd
build {
  resources {
    resource src/main/resources {
    }
    resource assets {
      includes = [images/**, fonts/**]
      excludes = [**/*.psd]
    }
  }
}
```

| Rule | Content |
| --- | --- |
| Default resource root | `src/main/resources` (the only default root, effective when `resources` is not declared); test resource root `src/test/resources` |
| Additional resource roots | `resource <dir>` can be repeated; when no `resource` is declared only the default root exists; **once `resource` is declared only the declared ones are used** (the default root is not stacked on top, avoiding judging "what was actually included" in two places) |
| Inclusion | All regular files in the directory, included by **path relative to that resource root**; empty directories produce no entries |
| Filtering | `includes` defaults to `**`; `excludes` takes precedence over `includes`; `/`-separated glob (`*` single segment, `**` cross-segment, `?` single character); regular expressions and character classes are not supported |
| Location in artifact | Fixed prefix `resources/`, with the relative path preserved after it: `src/main/resources/templates/a.html` → `resources/templates/a.html` in the artifact |
| Conflict | Two sources mapping to the same artifact path → **failure** (naming both source paths); the latter does not silently overwrite the former |
| Build-time filtering/variable substitution | **Rejected** (reason: resource bytes that change with the manifest cannot be reviewed file-by-file, and this overlaps with runtime configuration responsibilities; dependent consequence: content that must vary by environment must go through runtime configuration, §6) |
| Symbolic links | Read by target content; broken link → failure |
| Permission bits, timestamps | Not preserved (the artifact digest contains content only) |
| `.x` files inside resource roots | Not compiled, packaged as data (final; to participate in compilation they must be placed in a source root) |
| Applicable packaging | `library` / `app` / `starter`; non-empty resource roots or `build.resources` on `pom` → failure |
| Test resources | Visible only in the `test` phase, do not enter the artifact |

**Dependency library resource merging**:

- When packaging `app`, merge its own resources and the resources of all `compile`/`runtime` dependencies (including `starter` transitives) under the same `resources/` prefix;
- Same-path conflict → **failure** (naming both `groupId:artifactId`);
- A `starter`'s resources are published with its metadata and are **not merged** into consumers (a starter has no code artifact);
- A `library`'s `.xlib` contains only its own resources.

**Runtime access**: read-only; paths are rooted at `resources/` (e.g., `templates/a.html`); absolute paths and `..` segments prohibited; nonexistent → `NotFound` error. For the API, see the library resource reading capability in Part 7 §4. Resources are separate from the filesystem: resources do not support writing, deletion, or renaming.

**Relationship to configuration**: `application.properties` / `application-<profile>.properties` are **fixed-filename resources at the top level of the resource root** (§6.1), allowed only at the top level of the resource root and must not be placed in subdirectories; read at build time and counted in the `.xmeta` input digest.

## 6. Service Runtime Configuration

### 6.1 Per-Service Principle

- **Configuration belongs only to the service itself**: only modules with `packaging = app` have `application.properties`; the presence of this file in other packagings → build failure;
- Configuration files are **fixed-filename resources at the top level of the resource root**: `src/main/resources/application.properties` (baseline), optionally `src/main/resources/application-<profile>.properties`; placing them in a resource subdirectory or the module root → build failure (§5.6);
- The profile in the file name must match one of the ids in `profiles.profile`, otherwise failure;
- Services **must not implicitly share configuration**; sharing can only occur via the parent `pom`'s `configuration` section (frozen at build time, §6.6);
- Centralized configuration center: rejected.

### 6.2 Format

```properties
# application.properties — UTF-8, flat properties
net.http.listen-port=8080
db.url=jdbc:sqlite:data/order.db
db.pool.max-size=8
feature.new-checkout=false
```

- One key per line, `#` comments; **values are always read as strings**, and types are explicitly parsed by binding code;
- The manifest uses section-style XPD (it needs structure: section tree, entry containers, inheritance), while configuration uses flat key-value (it only needs key-value)—the two share comment and value rules and do not constitute a second mental model;
- YAML / JSON / nested structures **rejected** (reason: implicit types and indentation ambiguity; dependent consequence: complex structures are constructed in code);
- Multi-line values and escape sequences rejected; there is no escaping for `#` inside a value, and when a `#` is needed it must be written outside the comment position that follows (a `#` appearing in a key-value → treated as the start of a comment).

### 6.3 Key Space

| Prefix | Ownership | Example |
| --- | --- | --- |
| `xnull.` | Reserved by the toolchain | `xnull.profile` |
| `xdk.` | XDK configuration namespace (Part 7) | `xdk.log.level` |
| `app.` | The service itself | `app.name` |
| Custom (lowercase dot-separated, hyphens within segments) | Service-internal | `net.http.listen-port` |

- Key names may only contain lowercase letters, digits, dots, and hyphens; uppercase letters, underscores, consecutive dots, leading or trailing dots → startup failure;
- Key length limit 128 characters.

### 6.4 Override Precedence (low → high, five layers final)

| Layer | Source | Description |
| --- | --- | --- |
| 0 | Parent `pom`'s `configuration` | Frozen at build time, §6.6 |
| 1 | Built-in defaults | Binding code / XDK package declarations |
| 2 | `resources/application.properties` | Service baseline (top level of the resource root) |
| 3 | `resources/application-<profile>.properties` | Specified by `--profile`; environment variables are not read |
| 4 | Environment variables | **Allowlisted keys only** `XNULL_OVERRIDE_<KEY>` (uppercase, dots→underscores); the allowlist is listed by `configuration.envOverrides` |
| 5 | Command line | `--key=value`, overrides everything; written to the startup audit log |

- Duplicate keys in the same layer → startup failure;
- `XNULL_*` outside the allowlist is ignored (no error); a missing allowlisted key is not an error;
- Overrides can only change values, **cannot add keys** (an addition is an unknown key, §6.5);
- When layer 0 and layer 2 conflict, layer 2 wins (layer 0 is only a baseline); layer 0 keys take effect if no one overrides them.

### 6.5 Strict Validation

- **Unknown key = startup failure** (list all unknown keys; binding code must declare the keys it uses);
- Missing required key = startup failure (named);
- Value parse failure (e.g., `listen-port=abc`) = startup failure;
- Error messages must contain: the key name, the layer where it occurs, and the file path (or "command line");
- Configuration validation occurs before `main` executes; validation failure → exit code handled as an initialization failure per Part 5 §6.2.

### 6.6 Cross-Service Sharing (build time only)

```xpd
configuration {
  db.pool.max-size = 8
  envOverrides     = [db.url, db.password]
}
```

- `configuration` serves as **layer 0** for all child service configurations (lower than `application.properties`, can be overridden);
- No cross-service reading at runtime (rejecting "configuration inherits from another service"); external configuration services rejected;
- Secrets must not be written to `configuration` or `application*.properties`: at build time, suspected secret keys (`password`/`secret`/`token`/`key`) with non-placeholder values → build failure, requiring the use of allowlisted environment variables instead.

## 7. Linking and FFI

```xpd
link {
  unsafe = false
  libraries {
    library sqlite3 {
      kind   = dynamic
      system = true
    }
  }
}
```

| Field | Required | Description |
| --- | --- | --- |
| `unsafe` | No | Defaults to `false`; `true` indicates allowing the controlled `@unsafe` entry (Part 8 Appendix A §A.8); once enabled, the build log must record it |
| `library <name>` | Yes (when non-empty) | Native library name |
| `kind` | Yes | `static` / `dynamic` |
| `system` | No | Defaults to `false`; `true` indicates a system library (provided by the host, not packaged) |

- Native libraries that are not declared must not be linked; FFI bindings referencing an undeclared library → build failure (Part 8 Appendix A §A.2.2 auditable);
- Duplicate declaration of a library with the same name → failure;
- Runtime ABI symbols (`xrt_*`, Part 8 Appendix A §A.6.1) are linked automatically by the toolchain; no declaration is needed, and they must not be rewritten;
- A non-`app`/`library` declaring a non-empty `link` → failure.

## 8. Reproducibility

- Same manifest + same lock file + same toolchain version ⇒ same artifact (PROJ-09 compares by digest);
- Exhaustive inputs: manifest (including the inheritance chain), lock file, source code, toolchain version, target platform, profile set, effective plugin set. There are no other inputs (`XNULL_REPO` only affects the fetch location; plugins are prohibited from network access and environment reads, §5.5);
- `.xmeta` records digests of all the above inputs;
- Lock file bytes are stable (§4.4 ordering rules); the same resolution result produces identical content when generated twice.

## 9. Explicit Rejections and Non-Promises

| Capability | Conclusion | Description |
| --- | --- | --- |
| Plugin mechanism | Adopted (controlled) | See §5.5 for constraints |
| Plugins adding phases | Rejected | The phase set is fixed at 5 |
| Plugins accessing the network | Rejected | Reproducibility takes priority |
| Dependency/plugin version ranges | Rejected | Reproducibility takes priority |
| `SNAPSHOT` / `LATEST` | Rejected | Same as above |
| `deploy` to remote | Rejected | The publishing process awaits ecosystem stabilization; see Index §9 engineering-layer candidates |
| Configuration hot reload | Rejected | Configuration is governed by the five-layer snapshot at startup |
| Configuration center (Nacos-like service) | Rejected | Configuration is governed by the five-layer snapshot at startup; external configuration services are not within the commitments of this part |
| YAML / nested configuration | Rejected | Implicit types and ambiguity |
| Cross-service configuration inheritance | Rejected | Implicit coupling |
| Environment-variable profile activation | Rejected | Irreproducible |
| Remote repository signature verification | Non-promise | Reason: ecosystem undecided; consequence: must not be used as a security boundary |
| Incremental compilation / parallel build strategies | Non-promise | Reason: implementation freedom; consequence: only consistency of semantics and artifact digest is guaranteed |
| Editor highlighting/formatting | Not part of this part | See Part 9 and the toolchain |
| Build artifact encryption/obfuscation | Rejected | Not within the scope of this part |
| Build-time resource filtering/variable substitution | Rejected | Reason: resource bytes that change with the manifest cannot be reviewed file-by-file; dependent consequence: content that varies by environment must go through runtime configuration |
| Resource size limit | Non-promise | Reason: resource volume is determined by the user; consequence: oversized resources lengthen build time and memory usage; no specification limit is set |

**Resource directory capability ownership (final)**: resource packaging rules belong to §5.6 of this part; the resource reading API belongs to the resource reading capability in Part 7 §4; the toolchain is only responsible for assembling artifacts per §5.6 and does not interpret resource content.

## Appendix A: Complete Examples of Three Project Types

### A.1 Single project (one service, no parent, no aggregation)

```text
single-app/
├── xnull.project
├── xnull.lock
├── src/main/x/main.x
└── src/main/resources/
    ├── application.properties
    └── templates/page.html
```

`xnull.project` (`packaging = app`, no `parent`, no `modules`, no `repositories` → the default repository is used):

```xpd
project {
  groupId    = com.example
  artifactId = single-app
  version    = 0.1.0
  packaging  = app

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencies {
    dependency com.example:xdk-web-starter {
      version = 3.2.1
    }
  }

  build {
    mode         = release
    warnings     = strict
    entryFile    = src/main/x/main.x
    entryPackage = com.example.app

    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
      }
    }
  }

  link {
    unsafe = false
    libraries {
      library sqlite3 {
        kind   = dynamic
        system = true
      }
    }
  }

  profiles {
    profile dev {
      activation {
        platform = macos
      }
      properties {
        build-mode = debug
      }
    }
  }
}
```

`src/main/resources/application.properties`:

```properties
app.name=single-app
net.http.listen-port=8080
db.url=jdbc:sqlite:data/app.db
db.pool.max-size=8
```

`src/main/resources/templates/page.html` (an ordinary resource, read at runtime as `templates/page.html`):

```html
<!doctype html>
<title>single-app</title>
```

Key points: a single file is the project; `modules`/`configuration`/`parent` are all omitted (the skeleton allows empty sections to be omitted); the default resource root `src/main/resources` takes effect without being declared in the manifest; the lock file sits alongside the manifest.

### A.2 Multi-service project (aggregation root + parent project + shared library + two services)

```text
order-system/
├── xnull.project              # pom: aggregation (modules) + arbitration root
├── xnull.lock
├── platform/
│   └── xnull.project          # pom: parent (properties / dependencyManagement / build.plugins / configuration)
├── common/
│   ├── xnull.project          # library
│   └── src/main/
│       ├── x/
│       └── resources/         # library resources (merged into the consumer's artifact)
│           └── templates/mail/order-created.html
├── order-service/
│   ├── xnull.project          # app
│   └── src/main/
│       ├── x/
│       └── resources/
│           ├── application.properties
│           ├── application-dev.properties
│           └── static/index.html
├── payment-service/
│   ├── xnull.project          # app
│   └── src/main/
│       ├── x/
│       └── resources/
│           └── application.properties
└── target/
```

**Aggregation root `xnull.project`**:

```xpd
project {
  groupId    = com.example
  artifactId = order-system
  version    = 2.0.0
  packaging  = pom

  modules {
    module platform
    module common
    module order-service
    module payment-service
  }

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }
}
```

**Parent project `platform/xnull.project`** (unifies versions and artifact conventions, for each service to inherit):

```xpd
project {
  groupId    = com.example
  artifactId = platform
  version    = 2.0.0
  packaging  = pom

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencyManagement {
    dependencies {
      dependency com.example:common {
        version = 2.0.0
      }
      dependency com.example:xdk-web-starter {
        version = 3.2.1
      }
      dependency com.example:xdk-metrics {
        version = 1.6.0
      }
    }
  }

  build {
    warnings = strict
    mode     = release

    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
      }
    }
  }

  configuration {
    db.pool.max-size = 16
    xdk.log.level    = info
    envOverrides     = [db.url, db.password]
  }
}
```

**Shared library `common/xnull.project`**:

```xpd
project {
  groupId    = com.example
  artifactId = common
  version    = 2.0.0
  packaging  = library

  parent {
    groupId      = com.example
    artifactId   = platform
    version      = 2.0.0
    relativePath = ../platform
  }

  dependencies {
    dependency com.example:xdk-metrics {
    }
  }
}
```

**Service `order-service/xnull.project`** (coordinates are written explicitly, not inherited from the parent; dependency versions are provided by the parent's management table):

```xpd
project {
  groupId    = com.example
  artifactId = order-service
  version    = 2.0.0
  packaging  = app

  parent {
    groupId      = com.example
    artifactId   = platform
    version      = 2.0.0
    relativePath = ../platform
  }

  dependencies {
    dependency com.example:common {
    }
    dependency com.example:xdk-web-starter {
    }
  }

  build {
    entryFile    = src/main/x/main.x
    entryPackage = com.example.order
  }

  repositories {
    repository central {
      url = https://repo.xnull.dev/repository
    }
  }
}
```

`order-service/src/main/resources/application.properties` (specific to this service):

```properties
app.name=order-service
net.http.listen-port=8081
db.url=jdbc:sqlite:data/order.db
```

`order-service/src/main/resources/application-dev.properties` (dev profile overrides; only overrides values, does not add keys):

```properties
xdk.log.level=debug
db.url=jdbc:sqlite:/tmp/order-dev.db
```

**Service `payment-service/xnull.project`** has the same structure as the former (with different `artifactId`, `entryPackage`, and port); its `application.properties` contains only payment-side keys (`app.name`, `net.http.listen-port=8082`, `payment.gateway.url`).

Key points: the aggregation root is responsible only for `modules` and the arbitration root; the parent project is responsible for versions and build conventions; **each service has its own configuration, and they do not read one another's**; `db.pool.max-size` comes from the parent `configuration` (layer 0), `db.url` is overridden by each service's own `application.properties` (layer 2), and `db.password` can only be injected through an allowlisted environment variable (layer 4).

Resource points: `common`'s `templates/mail/order-created.html` is merged into `resources/templates/mail/order-created.html` when packaging `order-service`, and is read at runtime as `templates/mail/order-created.html`; `payment-service` does not reference this template, so its artifact does not contain the file (merging follows dependency relationships only, not the workspace). If `common` and `order-service` each have a template with the same name → packaging fails and names both sources (§5.6).

### A.3 Aggregation project (multiple libraries released together, no services)

```text
sdk-suite/
├── xnull.project          # pom: aggregation + arbitration
├── xnull.lock
├── core/
│   ├── xnull.project      # library
│   └── src/main/x/
├── codec/
│   ├── xnull.project      # library (depends on core)
│   └── src/main/x/
├── http/
│   ├── xnull.project      # library (depends on core, codec)
│   └── src/main/x/
└── cli/
    ├── xnull.project      # app (depends on http)
    └── src/main/x/
```

**Aggregation root `xnull.project`**:

```xpd
project {
  groupId    = io.xnull
  artifactId = sdk-suite
  version    = 3.1.0
  packaging  = pom

  modules {
    module core
    module codec
    module http
    module cli
  }

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencyManagement {
    dependencies {
      dependency io.xnull:core {
        version = 3.1.0
      }
      dependency io.xnull:codec {
        version = 3.1.0
      }
      dependency io.xnull:http {
        version = 3.1.0
      }
    }
  }

  repositories {
    repository central {
      url = https://repo.xnull.dev/repository
    }
  }
}
```

**`http/xnull.project`** (library dependencies carry no version; they are all determined by the aggregation root's arbitration table; after `install`, all four artifacts go into the local repository):

```xpd
project {
  groupId    = io.xnull
  artifactId = http
  version    = 3.1.0
  packaging  = library

  dependencies {
    dependency io.xnull:core {
    }
    dependency io.xnull:codec {
    }
  }

  build {
    warnings = strict
  }
}
```

**`cli/xnull.project`** (the only `app`, producing an executable):

```xpd
project {
  groupId    = io.xnull
  artifactId = cli
  version    = 3.1.0
  packaging  = app

  dependencies {
    dependency io.xnull:http {
    }
  }

  build {
    entryFile    = src/main/x/main.x
    entryPackage = io.xnull.cli
  }
}
```

Key points: an aggregation project has no `parent` (each module writes its own coordinates, and versions are constrained uniformly by the root arbitration table); the declaration order of `modules` is at once the build order and the cross-module execution order of plugins; upgrading the whole group's version = changing the `version` of the four modules and the root arbitration table (it is obvious where to change, and there are no implicitly inherited versions).

## Appendix C: XPD Grammar (Normative)

### C.1 Lexical Elements

| Token | Definition |
| --- | --- |
| Whitespace | Spaces and tabs; **a newline is a separate token** (see below) |
| Newline | Statement terminator: fields and leaf entries end at the end of the line; `{`/`}` may be adjacent to newlines before or after |
| Comment | `#` to the end of the line, either on a line of its own or after a statement |
| Punctuation | `{` `}` `=` `[` `]` `(` `)` `,` |
| Identifier | `[A-Za-z][A-Za-z0-9-]*` |
| Key name | Lowercase letters/digits/dots/hyphens, not beginning or ending with a dot (configuration key, §6.3; only allowed in the `configuration` section) |
| Bare word | A contiguous string composed of `[A-Za-z0-9._:/\\*?\-]` and `${…}`, not starting with `"`, containing no whitespace and none of the above punctuation (`*` `?` are used by resource globs, §5.6) |
| String | `"` … `"`, only the two escapes `\"` and `\\` are allowed; any other `\x` is a lexical error |
| Variable | `${` identifier `}`, may appear inside a bare word or string |

- UTF-8, BOM forbidden; tabs and spaces are equivalent, and **indentation is not semantic**.

### C.2 Grammar (EBNF)

```text
File       = { Newline | Entry } ;
Entry      = Field | EntryBlock ;
Field      = Name "=" Value ;
EntryBlock = Name { Argument } [ "{" { Newline | Entry } "}" ] ;
Argument   = Value ;
Name       = Identifier | KeyName ;
Value      = String | BareWord | List | Range ;
List       = "[" [ Value { "," Value } ] "]" ;
Range      = ( "[" | "(" ) Value "," Value ( "]" | ")" ) ;
```

**The block body may be omitted**: the trailing `{ … }` of an `EntryBlock` is optional, so `module platform`, `exclusion org.old:archive`, and `repository central { … }` are all legal. To determine "where this entry ends", look only at the end of the line—this is also why newlines must be part of the grammar.

### C.3 Semantic Constraints

1. At the root level, only one `project` block (manifest), one `lock` block (lock file) or one `plugin` block (plugin metadata), and one `settings` block (credentials file) are allowed, and one must exist; other sections at the root level → error;
2. Legal combinations of section nesting and fields are specified by §3.2, §4.4, §4.7, §5.3, and §5.5; combinations not listed → error;
3. The repeatability of each identifier is specified by the corresponding table; a non-repeatable one appearing twice → error;
4. **Name form**: section names and entry names use identifiers; **key names are only allowed in the `configuration` section** (configuration keys); a key name appearing anywhere else → error;
5. Block header arguments: `dependency`/`repository`/`library`/`module`/`profile`/`entry`/`goal`/`exclusion`/`resource`/`credentials` take one argument; `plugin` takes two arguments (coordinates + version); `project`/`parent`/`build`/`properties`/`modules`/`dependencies`/`dependencyManagement`/`repositories`/`plugins`/`profiles`/`activation`/`exclusions`/`configuration`/`link`/`libraries`/`goals`/`lock`/`settings`/`plugin` (metadata root) take zero arguments;
6. **The block body may be omitted**: `dependency`/`repository`/`library`/`module`/`profile`/`entry`/`goal`/`exclusion`/`resource`/`credentials`/`plugin` allow no body (`module platform`); `project`/`parent`/`build`/`properties`/`modules`/`dependencies`/`dependencyManagement`/`repositories`/`plugins`/`profiles`/`activation`/`exclusions`/`configuration`/`link`/`libraries`/`goals`/`lock`/`settings` must have a body;
7. Values are always treated as strings; list fields (`envOverrides`, `configKeys`, `profiles`) must be given a list, and all other fields must not be given a list;
8. **A range is a distinct value form**: `language-version` must be given a range (starting with `[`/`(`, ending with `]`/`)`, with version-number bare words at both ends); a range appearing in other fields, or in a list field → error; when both ends of `[a, b]` are closed, it is treated as a two-element list, and the semantics are determined by the field;
9. Lists and ranges must not span lines; a field or entry not terminated by a newline or `}` → error;
10. Unclosed blocks, fields missing `=`, and empty values → error;
11. An error must report: line number, column number, and section path (e.g., `project/dependencies/dependency[2]/optional`).

### C.4 Error Message Format (Normative Requirement)

```text
xnull.project:12:3: error[XPD-204]: unknown field "optonal" in dependency
  12 |   optonal = true
     |   ^^^^^^^ unknown field; available fields: version, scope, optional, exclusions
```

### C.5 Diagnostic Code Ranges

| Range | Category |
| --- | --- |
| `XPD-0xx` | Lexical (illegal character, unterminated string, illegal escape, BOM) |
| `XPD-1xx` | Grammar and structure (missing `}`, missing `=`, block header argument count, empty value, duplicate root-level block, list spanning lines `106`, entry not terminated by a newline `107`, range endpoint count not 2 `105`) |
| `XPD-2xx` | Section and field semantics (unknown section/field, duplicate non-repeatable section, container containing an illegal entry) |
| `XPD-3xx` | Coordinates and inheritance (missing coordinate field, duplicate coordinates, depth limit exceeded, cycle, parent not pom) |
| `XPD-4xx` | Dependencies and lock (missing version, conflict at the same depth, lock inconsistency, digest mismatch, extra locked coordinates) |
| `XPD-5xx` | Plugins (illegal phase, goal not declared, `.xplugin` missing/mismatched, out-of-bounds write, network access) |
| `XPD-6xx` | Configuration (unknown key, missing required key, illegal key name, suspected secret, profile file name mismatch) |
| `XPD-7xx` | Metadata (`.xmeta` field missing/mismatched, toolchain version mismatch) |
| `XPD-8xx` | Resources and packaging (illegal resource root, glob syntax error, conflicting sources at the same path, `pom` declaring resources, illegal configuration file location, broken symbolic link) |

- Each diagnostic code corresponds to a fixed category and a fixed message template; new codes must fall within an existing range, and adding a code in a new range is a specification revision.
