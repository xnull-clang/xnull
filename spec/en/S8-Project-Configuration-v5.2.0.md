# XNull Specification, Part 8: Project Configuration

> **Translation notice**: This is an English translation of the normative Chinese specification
> 《XNull 解决方案 第 8 部分：工程配置》v5.2.0. The Chinese original prevails in case of any
> divergence. Translation version follows the original's version number.

| Item | Content |
| --- | --- |
| Document ID | Part 8 (S9) |
| Document Version | 5.2.0 |
| Specification Status | Normative (approved 2026-11-05) |
| Release Date | 2026-11-05 |
| Upstream Dependencies | Part 1 §11.2/§11.4/§12; Part 4 §7.2; Part 6 §4.8/§5; Part 7 §2.2/§6.1/§8 |

> **Version note**: 5.2.0 reverse-validated Appendix C against the implementation (`impl/internal/xpd`), patching four gaps where "examples could be written but the grammar could not parse them": ① `language-version` uses `[3.3, 4.0)`, but the original grammar had only bracketed lists → added the **range literal** production; ② body-less entries such as `module platform` and `exclusion org.old:legacy` were forced to take `{ }` by the original grammar → block bodies became optional (C.2, C.3 rule 6); ③ dotted keys such as `db.pool.max-size` are not identifiers → added the "key name" notation, restricted to the `configuration` section (C.3 rule 4); ④ the `*` and `?` of resource globs such as `**/*.psd` were not in the bare-word character set → added. Also clarified that **a newline is the statement terminator** (fields and leaf entries end at end of line); lists/ranges MUST NOT span lines, and an entry not terminated by a newline is an error. New diagnostic codes `XPD-105/106/107` added. All specification examples now parse block by block under automated cases.
>
> **Version note**: 5.1.0 added the **resource-directory design** — `src/main/resources` / `src/test/resources`, inclusion and exclusion, the in-artifact `resources/` prefix, dependency-library resource merging and conflict failure, rejection of build-time filtering, and runtime access via the `xdk.sys` resource-reading APIs (Part 6 §4.8); service configuration files were thereby located at the resource root. The rest of 5.0.0 is unchanged.
>
> **Finalization note**: This part defines the complete project configuration for XNull: the manifest paragraph tree and inheritance, coordinates, properties and variables, dependency management, dependencies and plugins, repositories and credentials, lifecycle and artifacts, resource directories and packaging, service runtime configuration, linking and FFI declarations, reproducibility, and diagnostic-code segments, with Appendix A giving three complete examples (single-module project, multi-service project, aggregate project). Drafts v1.0.0 (JSON), v2.0.0 (XML), v3.0.0 (TOML), and v4.0.0 (flat XPD) are archived; their semantic conclusions are absorbed into this version.

## 0. Core Stances

- **One skeleton, coordinates self-evident**: the manifest paragraph structure is identical for every project and module; `groupId`/`artifactId`/`version`/`packaging` MUST be written by every module itself and are not filled in from the parent — coordinates are visible at a glance, and a parent version change cannot silently "rename" child modules.
- **Inheritance carries configuration only**: the parent propagates `properties`/`dependencyManagement`/`dependencies`/`repositories`/`build` (including `plugins`)/`configuration`; **coordinates are not inherited**.
- **Exact versions**: dependency and plugin versions MUST be exact semantic versions; ranges, `SNAPSHOT`, and "latest" are rejected outright.
- **Per-service configuration, overridable, strictly validated**: configuration belongs only to the service itself; the override order is fixed at five layers; unknown keys and missing required keys both fail startup.
- **Failure over degradation**: a misspelled manifest, an unresolved variable, a conflict that cannot be uniquely arbitrated — all fail the build; silent correction is forbidden.

## 1. Positioning and Scope

### 1.1 Scope

Project structure and skeleton consistency; the `xnull.project` manifest (coordinates / inheritance / properties / dependency management / dependencies / repositories / build / plugins / conditional overrides / configuration baseline / linking); dependency and plugin resolution and arbitration; scopes; local and remote repositories; credential files; profile activation; packaging types; lifecycle and artifacts; **resource directories and packaging (§5.6)**; the lock file and metadata format; service runtime configuration files; linking and FFI declarations; reproducibility; diagnostic-code segments; the XPD grammar (Appendix C).

### 1.2 Not Defined Here

- Command-line argument spellings (semantic equivalence suffices; this part's behavior is the judging basis);
- Remote-repository operations, mirror governance, signing systems (signature verification is non-committed, §4.7);
- IDE integration and CI platform adaptation (editor highlighting/formatting belongs to the toolchain, non-committed, §10);
- Configuration hot-reload and configuration centers: rejected in 1.x; evolution directions in §10.

### 1.3 Boundaries with Other Parts

| Dimension | Definer | This Part's Role |
| --- | --- | --- |
| Entry signature and semantics | Part 1 §11.2 | Only "how the entry is found" (§5.4) |
| Exit-code mapping | Part 4 §7.2 | Referenced (runtime exit codes of build outputs); the build tool's own exit codes in §5.1 |
| XDK version declaration mechanism | Part 6 decision 4-3 | Manifest fields and validation semantics (§3.9) |
| FFI native libraries and the `@unsafe` gate | Part 7 §2.2/§6.1/§8 | Manifest sections and the linking contract (§7) |

## 2. The Project Model

### 2.1 Packaging Types (`packaging`)

| packaging | Responsibility | Artifact | Dependable? |
| --- | --- | --- | --- |
| `pom` | Parent or aggregate project: manifest and metadata only; may carry `modules`, `configuration` | Manifest + `.xmeta` | Only as parent / aggregate entry |
| `library` | Library: a dependable code unit | `.xlib` | Yes |
| `starter` | Capability-aggregation package: dependency declarations only; importing it transitively brings its `dependencies` | Manifest + `.xmeta` | Yes (transitively) |
| `app` | Service: has an entry and its own runtime configuration | Executable + `.xmeta` | No |

**Semantic constraints**:

- The four types share **one paragraph skeleton** (§3.2); differences are expressed only as constraints — no forking into "a different paragraph set per packaging";
- `modules` may be non-empty only for `pom`; `configuration` may be declared only by `pom`; `entryFile`/`entryPackage` only for `app`; `link` may be non-empty only for `app`/`library`;
- An `app` must not be a dependency, a parent, or a transitive dependency of a starter;
- A `starter`'s `dependencies` are declared as `compile` and passed to consumers; a `starter` with a source directory (`src/`) → fail;
- A parent project MUST have `packaging = pom`.

### 2.2 GAV Coordinates

```text
groupId    reverse domain, lowercase dotted (com.example)
artifactId lowercase letters/digits/hyphens (order-service)
version    semantic version, exact (1.4.0)
```

- **The three coordinate fields and `packaging` MUST be written explicitly by every module**, including submodules;
- A duplicate `groupId:artifactId:version` within one build → fail;
- A submodule's `groupId` may differ from the parent's (organizational nesting, adaptation layers), but MUST be written in the manifest — this is precisely the payoff of "coordinates self-evident."

### 2.3 Directory Layout

```text
order-system/
├── xnull.project           # packaging = pom
├── xnull.lock              # lock file (build-generated; version-controlled)
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

- Source root defaults to `src/main/x`, test root to `src/test/x`; overridable via `build.sourceRoot` / `build.testRoot`;
- Resource root defaults to `src/main/resources`, test resource root to `src/test/resources`; overridable or extended via `build.resources` (§5.6);
- The artifact root is fixed at `target/`; it must not be a source or resource origin;
- The lock file lives at the **aggregate root** (or the project root when unaggregated), one per project (§4.4).

## 3. The Manifest `xnull.project`

### 3.1 The Complete Skeleton of Every Module

All projects and modules use the same skeleton. Paragraph order does not affect semantics; formatters emit in the order below.

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
        exclusion org.old:legacy
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

### 3.2 The Paragraph Table (common to all packaging types)

| Paragraph | Required | Applies To | Repeatable | Content |
| --- | --- | --- | --- | --- |
| `project` | Yes | All | No | Root block, unique per file |
| `groupId` / `artifactId` / `version` / `packaging` | Yes | All | No | Root-block fields (§2.2, §2.1) |
| `parent` | No | All | No | Single parent (§3.3) |
| `modules` | No | All (non-empty only `pom`) | `module` repeatable | Aggregate subdirectories |
| `properties` | No | All | Keys repeatable (keys unique) | Variables (§3.4) |
| `dependencyManagement` | No | All | Fixed inner structure | Version arbitration (§3.5) |
| `dependencies` | No | All | `dependency` repeatable | Dependencies (§3.6) |
| `repositories` | No | All | `repository` repeatable | Remote repositories (§4.7) |
| `build` | No | All | No | Compile options, entry, resource roots (§5.2, §5.6) |
| `plugins` | No | All (inside `build`) | `plugin` repeatable | Build plugins (§5.5) |
| `link` | No | `app` / `library` (non-empty) | No | Native libraries and `@unsafe` (§7) |
| `profiles` | No | All | `profile` repeatable | Conditional overrides (§3.8) |
| `configuration` | No | `pom` only | Keys repeatable (keys unique) | Service configuration baseline (§3.10) |

**General rules**:

- Unknown paragraphs, unknown fields, unknown block names → fail;
- A single-occurrence paragraph appearing twice → fail; duplicate fields within one paragraph → fail;
- Container paragraphs may contain only their prescribed entry paragraphs: `dependencies`→`dependency`, `exclusions`→`exclusion`, `repositories`→`repository`, `plugins`→`plugin`, `modules`→`module`, `libraries`→`library`, `profiles`→`profile`;
- An empty paragraph is equivalent to omission, but once present it MUST be legal.

### 3.3 Inheritance Rules

- **Single parent**: at most one `parent`; absent means root project;
- Parent location: `relativePath` (default `../xnull.project`) → local repository → remote repository (§4.7);
- **Inherited**: `properties` (child overrides parent), `dependencyManagement` (merged, child first), `dependencies` (merged, same coordinates child overrides parent), `repositories` (merged by id, child overrides parent), `build` (field-level override, `plugins` merged by coordinates), `configuration` (merged by key, child overrides parent);
- **Not inherited**: `groupId`/`artifactId`/`version`/`packaging`, `parent`, `modules`, `profiles`;
- Inheritance depth capped at 8; cycles, self-parent, missing parent, non-`pom` parent → fail.

### 3.4 Properties and Variable Substitution

- Within the `properties` section: `key = value`; keys are kebab-case; values are always strings;
- Variable form `${name}`, may appear inside bare words or strings;
- Substitution runs at **parse time** (after manifest load, before dependency resolution), single pass, no recursive expansion of substitution results;
- Built-in variables (read-only): `project.groupId`, `project.artifactId`, `project.version`, `project.basedir`, `xnull.version` (toolchain version);
- Child overrides parent; **an unresolved variable → fail** (the original text is not kept, and it is not replaced with an empty string);
- Variables may be used in any field value (including `parent.relativePath`, dependency `version`, plugin versions);
- **MUST NOT be used on enumeration fields** (`packaging`, `scope`, `phase`, `kind`): enumeration values must be literal-visible; variable substitution there fails — otherwise "what kind of project is this" would require reading two places to answer.

### 3.5 dependencyManagement

```xpd
dependencyManagement {
  dependencies {
    dependency com.example:common {
      version = 1.4.0
      exclusions {
        exclusion org.old:legacy
      }
    }
  }
}
```

- Declares only `version` (required) and optional `exclusions`; **the presence of `scope`/`optional` → fail** (usage-site decisions do not belong here);
- When a submodule's dependency omits `version`, the nearest managed entry uniquely provides it (proximity: this module > nearer parent > farther parent);
- An explicit `version` inside the dependency overrides the managed version: allowed, with a build warning;
- A declared dependency with no version provider → fail (naming the `groupId:artifactId`);
- Duplicate coordinates within one management table → fail.

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
      exclusion org.old:legacy
    }
  }
}
```

| Field | Default | Notes |
| --- | --- | --- |
| `version` | Provided by dependencyManagement | Neither present → fail |
| `scope` | `compile` | `compile` / `runtime` / `test` / `provided` (§3.7) |
| `optional` | `false` | `true` means not transitive |
| `exclusions` | empty | Removes transitive dependencies by exact coordinates |

### 3.7 Scopes

| scope | Visible at Compile | Visible at Runtime | Transitive |
| --- | --- | --- | --- |
| `compile` | Yes | Yes | Yes (compile) |
| `runtime` | No | Yes | Yes (runtime) |
| `test` | Test-visible | Test runs | No |
| `provided` | Yes | No (host provides) | No |

- Scope propagation has only two forms: `compile`→`compile` and `runtime`→`runtime`; the rest are non-transitive;
- `test` dependencies must not appear in the artifact dependency list of an `app`;
- `provided` is supplied by the host (runtime/platform); not packaged and not transitive at build time.

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

- Activation (two settled forms): explicit `-Pdev`; `activation.platform` matching the current build platform. **Environment-variable activation → rejected** (not reproducible);
- May override: `properties`, `dependencies`, `build` (including `plugins`), `configuration`;
- Must not override (presence → fail): `groupId`/`artifactId`/`version`/`packaging`, `parent`, `modules`, `repositories`;
- Multiple simultaneously active profiles changing the same key → fail (never silently take the latter);
- The set of simultaneously active profiles MUST be **explicitly determined**: the union of `-P` and `activation.platform`, recorded in `.xmeta`.

### 3.9 Version Declarations (implementing Part 6 decision 4-3)

- `properties.xdk-version`: the required XDK version (exact); a toolchain XDK mismatch → fail;
- `properties.language-version`: a language-version range, **the only place a range expression is allowed** (`[3.3, 4.0)`); outside the range → fail;
- Both MUST be defined by the **root `pom`**; redefinition in a submodule → fail.

### 3.10 configuration (Service Configuration Baseline)

```xpd
configuration {
  db.pool.max-size = 8
  envOverrides     = [db.url, db.password]
}
```

| Field | Required | Notes |
| --- | --- | --- |
| Arbitrary runtime keys | No | Key names MUST conform to §6.3; values always strings; serve as layer 0 of all child-service configuration (§6.6) |
| `envOverrides` | No | List; declares whitelisted keys (runtime key names), determining which keys may be overridden by environment variables (§6.4) |

- Declared by `pom` only; its presence under other packaging → fail;
- **Keys with the `xnull.` prefix are forbidden** (toolchain-reserved);
- Suspected-secret keys (`password`/`secret`/`token`/`key`) with non-placeholder values → build failure (§6.6);
- Values must contain no dynamic content other than variable placeholders; variables in this section substitute per §3.4.

## 4. Dependency and Plugin Resolution

### 4.1 Resolution Order

1. Expand the inheritance chain → merge the six configuration classes (§3.3);
2. Substitute variables;
3. Determine dependency and plugin coordinate versions per module (§3.5, §5.5);
4. Build the dependency graph (transitivity + scope propagation + exclusions);
5. Arbitrate conflicts (§4.2);
6. Write the lock file (§4.4);
7. Fetch from repositories (§4.7).

### 4.2 Conflict Arbitration

- **Nearest wins**: the shortest path in the dependency tree prevails;
- Same depth, multiple occurrences → **fail with all paths listed** (never take the first, which would make declaration order an invisible input);
- A `dependencyManagement` version always prevails over nearest-wins;
- The arbitration result MUST be unique; otherwise fail.

### 4.3 Version Rules

| Form | Status |
| --- | --- |
| Exact `1.4.0` | Settled |
| Pre-release `1.2.3-rc.1` | Settled (exact means allowed) |
| Range `[1.0,2.0)` | Rejected (in dependencies and plugins); only `language-version` may use it |
| `SNAPSHOT` | Rejected |
| `LATEST` / `RELEASE` / `*` | Rejected |
| Workspace modules | Settled: `modules` aggregation or `relativePath` override; no version-number workarounds |

### 4.4 The Lock File `xnull.lock`

The format is XPD. **One per project**, at the aggregate root (or project root when unaggregated), under version control.

```xpd
lock {
  version = 1

  entry com.example:common 1.4.0 {
    kind       = dependency
    repository = central
    sha256     = 0000000000000000000000000000000000000000000000000000000000000000  # 64 lowercase hex chars
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
| Entries | One per resolved dependency and plugin; `kind` is `dependency` / `plugin` |
| Ordering | Ascending lexicographic by `groupId:artifactId`; one entry per coordinate (guarantees byte stability) |
| Digest | SHA-256 of artifact content, 64 lowercase hex chars; verified after download; mismatch → fail |
| Source | `repository` is the repository id |
| Consistency | Lock–manifest mismatch → **fail** (prompting regeneration); no automatic update |
| Generation | First build without a lock generates one and warns to commit it; `--update-lock` explicitly regenerates (the only regeneration entry) |
| Reading | The build follows the lock (lock first, network second); a locked coordinate absent from the manifest → fail |

### 4.5 Transitivity Constraints

- Dependency cycles → fail; an `app` as a dependency → fail;
- A dependency declaring an `xdk-version` with a different major version than this project → fail;
- Plugins must not depend on `app`s (plugins must not pull in service code);
- A `starter`'s transitive dependencies must not contain `app`s.

### 4.6 Repository Selection and the Default Repository

- **`repositories` declared**: only the declared repositories are used, tried in declaration order, first hit wins; no repository is implicitly appended;
- **`repositories` undeclared anywhere in the chain**: the built-in default repository `central` = `https://repo.xnull.dev/repository` is used;
- Offline environments: `XNULL_REPO` pointing at a local repository directory becomes the sole source; the build then performs no network access (missing artifact → fail).

### 4.7 Repositories, Mirrors, and Credentials

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

| Field | Required | Notes |
| --- | --- | --- |
| `url` | Yes | HTTP(S); artifacts stored under the three-level directory `groupId/artifactId/version/`, file name `<artifactId>-<version>.<ext>` |
| `mirrorOf` | No | The id of the repository being replaced; one mirror per id; a mirror itself must not be mirrored |

**Credentials file** `~/.xnull/settings.xpd` (not part of the project, not version-controlled):

```xpd
settings {
  credentials central {
    username   = deployer
    tokenEnv   = XNULL_TOKEN_CENTRAL
  }
}
```

- Credentials are read only from that file; **MUST NOT be written into project manifests**;
- Passwords/tokens **may appear only as environment-variable names** (`tokenEnv`); no plaintext in the file — build logs and `.xmeta` must never contain their values;
- Missing credentials where the repository requires authentication → fail (no anonymous-retry degradation);
- Signature verification: non-committed (rationale: ecosystem undetermined; consequence: must not be treated as a security boundary; not done in 1.x).

## 5. Lifecycle, Build, and Plugins

### 5.1 Phases and Toolchain Exit Codes

| Phase | Action |
| --- | --- |
| `validate` | Lexical/grammar/unknown-paragraph validation, inheritance expansion, variable substitution, entry existence, lock consistency |
| `compile` | Compile `src/main/x` |
| `test` | Run the `src/test/x` test entries (`--skip test` allowed) |
| `package` | Produce `target/<artifactId>-<version>.<ext>` + `.xmeta` |
| `install` | Install into the local repository (skippable) |

**Toolchain exit codes (settled; independent of the Part 4 §7.2 runtime exit codes)**:

| Code | Meaning |
| --- | --- |
| `0` | All phases succeeded |
| `1` | Build failure (compile/test/plugin/validation) |
| `2` | Manifest or usage error (lexical/grammar/unknown paragraph/argument spelling) |
| `130` | Interrupted (SIGINT received) |

- `deploy` (remote publishing) rejected in 1.x (see index §9, project-layer candidates);
- Plugins may bind only to the 5 phases above; new phases must not be added.

### 5.2 build Fields

| Field | Values | Notes |
| --- | --- | --- |
| `mode` | `debug` / `release` / `size` | Optimization tier; does not change language semantics; default `debug` |
| `warnings` | `default` / `strict` | `strict` promotes warnings to errors |
| `sourceRoot` / `testRoot` | paths | Override the defaults `src/main/x` / `src/test/x` |
| `resources` | container (`resource`) | Resource roots and inclusion rules (§5.6); default `src/main/resources` |
| `entryFile` / `entryPackage` | path / package name | Entry location (§5.4); required for `app`; presence under non-`app` → fail |
| `plugins` | container | §5.5 |

- Defined at project level, overridden at module level; environment variables do not participate in build options (`XNULL_REPO` excepted);
- `sourceRoot` must not equal or contain `target/`.

### 5.3 Artifacts and Metadata `.xmeta`

- `target/<artifactId>-<version>.<ext>`: `app` → executable, `library` → `.xlib`, `pom`/`starter` → manifest and metadata only;
- The build writes nowhere outside the manifest directory (caches go to `target/.cache`);
- Required `.xmeta` fields (XPD format):

| Field | Content |
| --- | --- |
| `groupId` / `artifactId` / `version` / `packaging` | Full coordinates |
| `platform` | Target platform identifier |
| `xdkVersion` / `languageVersion` | Effective values from `properties` |
| `toolchainVersion` | `xnull.version` |
| `profiles` | The effective profile ids of this build (ascending) |
| `plugins` | Effective plugin coordinates + goal + phase list (in execution order) |
| `lockSha256` | Content digest of the lock file used by this build |
| `inputs` | Aggregate digest of the manifest chain, source roots, and lock file |

### 5.4 Entry Resolution (implementing Part 1 §11.4)

1. `entryFile` + `entryPackage`: the entry is that file's `main`, and it MUST reside in `entryPackage`;
2. `entryFile` only: the entry is that file's `main`;
3. No entry fields: default `src/main/x/main.x`;
4. No manifest: `main.x` in the current directory (Part 1 §11.4).

Failure set: file missing, no matching `main`, multiple matching `main`s, `entryPackage` mismatch, entry declared by non-`app`.

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

| Field | Required | Notes |
| --- | --- | --- |
| Block-header coordinates `groupId:artifactId` + version argument | Yes | Version must be exact (§4.3); same repository and lock machinery as dependencies |
| `phase` | Yes | One of `validate` / `compile` / `test` / `package` / `install` |
| `goal` | Yes | The goal name declared by the plugin |
| `configuration` | No | Plugin-specific key-values; keys MUST be declared in the plugin metadata's `configKeys`; undeclared → fail |

**Plugin contract (normative):**

| Constraint | Content |
| --- | --- |
| Phases | Bind to one of the 5 phases only; within a phase, executed in declaration order; across modules, in `modules` declaration order |
| Goals | Must be explicitly declared; undeclared goals must not execute |
| File system | Read-only: manifest, `src/`, dependencies; write-only: `target/`. Out-of-bounds writes → build failure |
| Network | **Network access forbidden** (rationale: network makes builds unreproducible; consequence: network-requiring steps belong outside the build) |
| Environment variables | Read-only access limited to `XNULL_REPO` and the `configuration.envOverrides` whitelist; all else invisible |
| Semantics | Must not change language semantics: must not rewrite `src/`, must not inject runtime behavior; artifact transformation, checks/reports, and generation into `target/` are allowed |
| Failure | Non-zero exit = build failure (never degraded to a warning) |
| Isolation | The plugin's own `dependencies` go through the same arbitration, but do not enter the compiled project's classpath |
| Reproducibility | Coordinates, goal, phase all enter the lock and `.xmeta`; same lock ⇒ same plugin behavior |

**Plugin package metadata `.xplugin`** (at the plugin artifact root, XPD format):

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

- Missing metadata or mismatch with the manifest (coordinates, phase, goal, configKeys, toolchain version) → fail;
- `toolchainVersion` is a major-version compatibility constraint: a different major → fail;
- **Unrelated to runtime dynamic modules**: plugins in this section are build-time executors and never enter the artifact; runtime dynamic loading/unloading of managed modules follows the Part 3 decision (outside the initial baseline).

### 5.6 Resource Directories and Packaging

**Definition**: resources = non-`.x` files published with the artifact and not compiled — templates, static pages, icons, SQL, schemas, default data, localization text, etc.

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
| Default resource root | `src/main/resources` (the sole default root, effective when `resources` is undeclared); test resource root `src/test/resources` |
| Additional resource roots | `resource <dir>` repeatable; with no `resource` declared, only the default root exists; **once any `resource` is declared, only the declared ones are used** (the default root does not stack — avoiding "what exactly got included" requiring two places to judge) |
| Inclusion | All regular files in the directory, keyed by **path relative to that resource root**; empty directories produce no entries |
| Filtering | `includes` defaults to `**`; `excludes` take precedence over `includes`; `/`-separated globs (`*` one segment, `**` across segments, `?` one character); regex and character classes unsupported |
| In-artifact location | Fixed prefix `resources/`, then the relative path preserved: `src/main/resources/templates/a.html` → in-artifact `resources/templates/a.html` |
| Conflicts | Two sources mapping to the same artifact path → **fail** (both source paths named); never silently last-wins |
| Build-time filtering/variable substitution | **Rejected** (rationale: once resource bytes vary with the manifest, per-file review becomes impossible, and it overlaps with runtime-configuration responsibility; consequence: environment-varying content must go through runtime configuration, §6) |
| Symbolic links | Read per target content; broken links → fail |
| Permission bits, timestamps | Not preserved (artifact digests cover content only) |
| `.x` files inside a resource root | Not compiled; packaged as data (settled; to be compiled they must live in a source root) |
| Applicable packaging | `library` / `app` / `starter`; a non-empty resource root or `build.resources` under `pom` → fail |
| Test resources | Visible only in the `test` phase; never enter the artifact |

**Dependency-library resource merging**:

- When packaging an `app`, its own resources and those of all `compile`/`runtime` dependencies (including `starter` transitives) merge under the same `resources/` prefix;
- Same-path conflicts → **fail** (both `groupId:artifactId` named);
- A `starter`'s resources publish with its metadata and are **not merged** into consumers (starters have no code artifacts);
- A `library`'s `.xlib` contains only its own resources.

**Runtime access**: read-only; paths rooted at `resources/` (e.g., `templates/a.html`); absolute paths and `..` segments forbidden; missing → `NotFound` error. APIs in Part 6 §4.8 (`xdk.sys`). Resources and the file system are separate: resources support no write, delete, or rename.

**Relationship to configuration**: `application.properties` / `application-<profile>.properties` are **fixed-filename resources at the resource-root top level** (§6.1), allowed only there and never in subdirectories; read at build time and counted into the `.xmeta` input digest.

## 6. Service Runtime Configuration

### 6.1 The Per-Service Principle

- **Configuration belongs to the service alone**: only modules with `packaging = app` own an `application.properties`; its presence under other packaging → build failure;
- The configuration file is a **fixed-filename resource at the resource-root top level**: `src/main/resources/application.properties` (baseline), optionally `src/main/resources/application-<profile>.properties`; placement in a resource subdirectory or the module root → build failure (§5.6);
- The profile in the filename MUST match one of the `profiles.profile` ids, otherwise fail;
- Services **must not implicitly share configuration**; sharing goes only through the parent `pom`'s `configuration` section (frozen at build time, §6.6);
- A centralized configuration center: not in 1.x; see §10 evolution directions.

### 6.2 Format

```properties
# application.properties —— UTF-8, flat properties
net.http.listen-port=8080
db.url=jdbc:sqlite:data/order.db
db.pool.max-size=8
feature.new-checkout=false
```

- One key per line; `#` comments; **values are always read as strings**; types are parsed explicitly by binding code;
- The manifest uses paragraph-style XPD (it needs structure: paragraph trees, entry containers, inheritance); configuration uses flat key-values (it needs only key-values) — both share comment and value rules, forming no second mental model;
- YAML / JSON / nested structures **rejected** (rationale: implicit types and indentation ambiguity; consequence: complex structures are constructed in code);
- Multi-line values and escape sequences rejected in 1.x; `#` inside a value has no escaping — a `#` starts a comment (a `#` within the key-value is treated as the comment start).

### 6.3 The Key Space

| Prefix | Owner | Example |
| --- | --- | --- |
| `xnull.` | Toolchain-reserved | `xnull.profile` |
| `xdk.` | XDK packages (Part 6) | `xdk.log.level` |
| `app.` | The service itself | `app.name` |
| Custom (lowercase dotted, hyphens within segments) | Service-internal | `net.http.listen-port` |

- Key names allow only lowercase letters, digits, dots, and hyphens; uppercase, underscores, consecutive dots, leading/trailing dots → startup failure;
- Key length capped at 128 characters.

### 6.4 Override Precedence (low → high, five layers, settled)

| Layer | Source | Notes |
| --- | --- | --- |
| 0 | Parent `pom`'s `configuration` | Frozen at build time, §6.6 |
| 1 | Built-in defaults | Declared by binding code / XDK packages |
| 2 | `resources/application.properties` | Service baseline (resource-root top level) |
| 3 | `resources/application-<profile>.properties` | Selected by `--profile`; environment variables not read |
| 4 | Environment variables | **Whitelisted keys only**, `XNULL_OVERRIDE_<KEY>` (uppercase, dots→underscores); the whitelist is listed by `configuration.envOverrides` |
| 5 | Command line | `--key=value`, overrides everything; written to the startup audit log |

- Duplicate keys within a layer → startup failure;
- `XNULL_*` variables outside the whitelist are ignored (no error); missing whitelisted keys are not an error;
- Overrides may change values only, **never add keys** (a new key is an unknown key, §6.5);
- When layer 0 and layer 2 conflict, layer 2 wins (layer 0 is only a baseline); a layer-0 key nobody overrides takes effect.

### 6.5 Strict Validation

- **Unknown keys = startup failure** (all unknown keys listed; binding code must declare the keys it uses);
- Missing required keys = startup failure (named);
- Value-parse failure (e.g., `listen-port=abc`) = startup failure;
- Error messages MUST include: the key name, the layer, and the file path (or "command line");
- Configuration validation runs before `main`; validation failure → exit code per Part 4 §7.2's initialization-failure handling.

### 6.6 Cross-Service Sharing (Build Time Only)

```xpd
configuration {
  db.pool.max-size = 8
  envOverrides     = [db.url, db.password]
}
```

- `configuration` serves as **layer 0** of all child-service configuration (below `application.properties`, overridable);
- No cross-service reads at runtime ("configuration inherited from another service" rejected); external configuration services rejected in 1.x (§10);
- Secrets must not be written into `configuration` or `application*.properties`: the build checks suspected-secret keys (`password`/`secret`/`token`/`key`) with non-placeholder values → build failure, directing the value into the whitelisted environment-variable channel.

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

| Field | Required | Notes |
| --- | --- | --- |
| `unsafe` | No | Default `false`; `true` allows `@unsafe` controlled entries (Part 7 §8); when enabled, the build log MUST record it |
| `library <name>` | Yes (when non-empty) | Native library name |
| `kind` | Yes | `static` / `dynamic` |
| `system` | No | Default `false`; `true` means a system library (host-provided, not packaged) |

- Undeclared native libraries must not be linked; an FFI binding referencing an undeclared library → build failure (auditable per Part 7 §2.2);
- Duplicate declaration of a same-named library → fail;
- Runtime ABI symbols (`xrt_*`, Part 7 §6.1) are linked automatically by the toolchain; they need no declaration and must not be overridden;
- A non-empty `link` declared by non-`app`/`library` → fail.

## 8. Reproducibility

- Same manifest + same lock file + same toolchain version ⇒ same artifact (PROJ-09 compares digests);
- Input enumeration: manifest (including the inheritance chain), lock file, source, toolchain version, target platform, profile set, effective plugin set. No other inputs (`XNULL_REPO` affects only fetch location; plugins are network-banned and environment-read-banned, §5.5);
- `.xmeta` records digests of all the above inputs;
- The lock file is byte-stable (§4.4 ordering rules): the same resolution result generates identical content twice.

## 9. Acceptance Matrix

| ID | Domain | Acceptance Content |
| --- | --- | --- |
| PROJ-01 | Skeleton and coordinates | Paragraph order irrelevant; unknown paragraphs/fields fail; single-occurrence paragraph duplication fails; container paragraphs contain only prescribed entries; missing any of the four fields fails; duplicate coordinates fail; submodule `groupId` may differ from the parent |
| PROJ-02 | Inheritance | Single-parent expansion correct; depth > 8 fails; cycles/missing/non-pom parent fail; **coordinates not inherited from parent**; merge rules of `properties`/`dependencyManagement`/`repositories`/`configuration` correct |
| PROJ-03 | Dependency arbitration | The managed table provides versions by proximity; missing version fails; same-depth conflicts fail with paths listed; explicit-version overrides warn; `scope`/`optional` in the managed table fails |
| PROJ-04 | Versions and locking | Ranges/`SNAPSHOT`/`LATEST` rejected (dependencies and plugins); lock ordering and digests correct; lock–manifest mismatch fails; extra locked coordinates fail; `--update-lock` the only regeneration entry |
| PROJ-05 | Lifecycle and artifacts | 5 phases in order; `--skip test` effective; `deploy` absent; toolchain exit codes 0/1/2/130 correct; `.xmeta` fields complete |
| PROJ-06 | Plugins | Exact versions; phase legality; undeclared goals rejected; undeclared `configuration` keys fail; writes outside `target/` fail; network rejected; non-zero exit fails; plugin dependencies excluded from the compile classpath; missing/malformed `.xplugin` fails |
| PROJ-07 | Configuration overrides | Layers 0–5 verified layer by layer; duplicate keys within a layer fail; whitelisted-out environment variables ignored; command-line overrides with audit trail; profile filename mismatching manifest ids fails |
| PROJ-08 | Configuration strictness | Unknown keys fail with a listing; missing required keys fail; parse failures include key and layer; `application.properties` on non-`app` fails; suspected secrets fail the build; illegal key names fail |
| PROJ-09 | Reproducibility | Two builds with identical digests; lock bytes stable; no writes outside `target/` |
| PROJ-10 | Grammar | Every error rule of Appendix C has corresponding cases; diagnostics include line/column/paragraph path; diagnostic codes fall in the prescribed segments |
| PROJ-11 | Resources | Default resource root inclusion correct; `includes`/`excludes` priority and glob matching correct; the in-artifact `resources/` prefix and relative paths preserved; multi-source same-path conflicts fail with sources named; dependency-library resources merge into `app`, conflicts fail; `starter` resources not merged into consumers; resource roots under `pom` fail; `.x` files packaged as data; symlinks followed, broken links fail; no filtering (manifest variables never alter resource bytes); resource configuration in subdirectories or module roots fails |

## 10. Implementation Boundaries and Evolution Directions

| Capability | 1.x Status | Notes |
| --- | --- | --- |
| Plugin mechanism | Settled (controlled) | Constraints in §5.5 |
| Plugin-added phases | Rejected | The phase set is fixed at 5 |
| Plugin network access | Rejected | Reproducibility first |
| Dependency/plugin version ranges | Rejected | Reproducibility first |
| `SNAPSHOT` / `LATEST` | Rejected | Same |
| `deploy` to remote | Rejected | Publishing process awaits ecosystem maturity; see index §9 project-layer candidates |
| Configuration hot-reload | Rejected | Configuration is the five-layer startup snapshot |
| Configuration center (Nacos-like service) | Rejected (1.x) · Evolution direction | Two paths: ① Nacos-protocol compatibility (replacing only layers ≥ 2; the five-layer order unchanged); ② a self-built external configuration service. Hard admission criteria: the startup snapshot is auditable; disconnection without a snapshot → startup failure |
| YAML / nested configuration | Rejected | Implicit types and ambiguity |
| Cross-service configuration inheritance | Rejected | Implicit coupling |
| Environment-variable profile activation | Rejected | Not reproducible |
| Remote-repository signature verification | Non-committed | Rationale: ecosystem undetermined; consequence: not a security boundary |
| Incremental compilation / parallel build strategy | Non-committed | Rationale: implementation freedom; consequence: only semantic and artifact-digest consistency is guaranteed |
| Editor highlighting/formatting | Non-committed (toolchain delivery) | `xnull fmt` and highlighting plugins are outside the specification |
| Artifact encryption/obfuscation | Rejected | Outside 1.x language-project scope |
| Resource build-time filtering/variable substitution | Rejected | Rationale: resource bytes varying with the manifest defeat per-file review; consequence: environment-varying content must go through runtime configuration |
| Resource size limits | Non-committed | Rationale: resource volume is the user's decision; consequence: very large resources lengthen build time and memory usage; no specification ceiling |

**Resource-capability ownership (settled)**: resource packaging rules belong to this part §5.6; resource-reading APIs belong to Part 6 §4.8 (`xdk.sys`); the toolchain only assembles artifacts per §5.6 and never interprets resource content.

## Appendix A: Three Complete Project Examples

### A.1 Single-Module Project (one service; no parent, no aggregation)

```text
single-app/
├── xnull.project
├── xnull.lock
├── src/main/x/main.x
└── src/main/resources/
    ├── application.properties
    └── templates/page.html
```

`xnull.project` (`packaging = app`; no `parent`, no `modules`, no `repositories` → the default repository applies):

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

Key points: one file is the whole project; `modules`/`configuration`/`parent` are all omitted (the skeleton allows omitting empty paragraphs); the default resource root `src/main/resources` takes effect without manifest declaration; the lock file sits beside the manifest.

### A.2 Multi-Service Project (aggregate root + parent project + common library + two services)

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
│       └── resources/         # library resources (merged into consumer artifacts)
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

**Aggregate root `xnull.project`**:

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

**Parent project `platform/xnull.project`** (unified versions and build conventions for the services to inherit):

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

**Common library `common/xnull.project`**:

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

**Service `order-service/xnull.project`** (coordinates written by itself, not inherited from the parent; dependency versions provided by the parent's management table):

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

`order-service/src/main/resources/application.properties` (service-specific):

```properties
app.name=order-service
net.http.listen-port=8081
db.url=jdbc:sqlite:data/order.db
```

`order-service/src/main/resources/application-dev.properties` (dev-profile override; overrides values only, adds no keys):

```properties
xdk.log.level=debug
db.url=jdbc:sqlite:/tmp/order-dev.db
```

**Service `payment-service/xnull.project`** is isomorphic to the former (different `artifactId`, `entryPackage`, and port); its `application.properties` contains only payment-side keys (`app.name`, `net.http.listen-port=8082`, `payment.gateway.url`).

Key points: the aggregate root handles only `modules` and the arbitration root; the parent handles versions and build conventions; **each service owns its configuration and reads no other's**; `db.pool.max-size` comes from the parent `configuration` (layer 0), `db.url` is overridden by each service's own `application.properties` (layer 2), and `db.password` can only be injected via the whitelisted environment variable (layer 4).

Resource points: when packaging `order-service`, `common`'s `templates/mail/order-created.html` merges into `resources/templates/mail/order-created.html`, read at runtime as `templates/mail/order-created.html`; `payment-service` does not reference that template and its artifact contains no such file (merging follows dependency relations, not the workspace). If `common` and `order-service` each had a same-named template → packaging fails with both sources named (§5.6).

### A.3 Aggregate Project (multiple libraries published together; no services)

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

**Aggregate root `xnull.project`**:

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

**`http/xnull.project`** (library dependencies carry no versions — all decided by the aggregate root's arbitration table; after `install`, the four artifacts enter the local repository):

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

Key points: the aggregate project has no `parent` (each module writes its own coordinates; versions are uniformly constrained by the root arbitration table); the `modules` declaration order is both the build order and the cross-module plugin execution order; upgrading the whole group's version = changing the four modules' `version` fields and the root arbitration table (what to change is visible at a glance; no implicitly inherited versions).

## Appendix B: Decision Record

1. **One paragraph skeleton for all packaging types**: only one structure to remember; differences expressed as semantic constraints (`modules` only for pom, `entryFile` only for app), with no per-packaging paragraph forks.
2. **Coordinates not inherited from the parent**: if inherited, changing a parent version would silently re-version a batch of modules, making them uncountable in the repository; requiring every module to write them costs a few redundant lines and buys auditability.
3. **Container paragraphs + entry paragraphs** (`dependency` nested in `dependencies`, etc.): avoids same-name same-level ambiguity and makes "what is repeatable" structurally visible.
4. **Plugins moved from rejection to controlled settlement**: the capability is retained while nine contract clauses pin down the uncertainty — exact versions, explicit goals, a fixed 5-phase set, writing only `target/`, no network, no environment reads, no semantic changes, fail on failure, everything in the lock and metadata.
5. **Exact versions; ranges/SNAPSHOT all rejected**: reproducibility is a hard constraint (§8).
6. **Same-depth conflicts fail rather than take the first**: taking the first would make declaration order an invisible input, with build results varying by file line counts.
7. **Two grammars: manifest and configuration**: the manifest needs structure; configuration needs only flat key-values; forcing them together would grow meaningless syntax in one of them.
8. **Values are always strings**: no type inference at the format layer; type errors are reported uniformly at schema validation, locatable to paragraph/field.
9. **Cross-service sharing only via build-time `configuration`**: cross-service configuration reads at runtime are implicit coupling, breaking the per-service principle.
10. **Configuration center listed as an evolution direction**: no centralized configuration now; in the future either a compatible external configuration-center protocol or a self-built service; §10 gives the two paths and hard admission criteria to avoid re-debating direction later.
11. **One lock file, fixed ordering**: multiple locks would turn "which lock applies" into an implicit question; fixed ordering guarantees byte stability and direct code-reviewability.
12. **Diagnostic codes divided by segment** (Appendix C.5): upgrades errors from "text descriptions" to stable identifiers indexable by tools and documentation.
13. **Resources in their own root, with the `resources/` prefix in artifacts**: not mixed with source, not competing with manifest/metadata paths; the prefix makes "what is user resources" visible at a glance in the artifact (§5.6).
14. **No build-time resource filtering**: filtering would make one file's bytes vary with the manifest, and "where did this HTML line come from" could not be answered per file; only runtime configuration may vary by environment.
15. **Dependency-library resource merging with conflict failure**: without merging, a library's templates would be unfindable in services; with silent overriding, "whose template wins" would depend on dependency order — both unacceptable, hence merge + explicit failure.
16. **Configuration files located at the resource-root top level**: the configuration file is itself a resource published with the artifact; allowing it in the module root or a resource subdirectory would create a second path-rule set for "which copy the runtime reads after packaging."

## Appendix C: The XPD Grammar (Normative)

### C.1 Lexical Rules

| Token | Definition |
| --- | --- |
| Whitespace | Spaces, tabs; **newline is its own notation** (see below) |
| Newline | The statement terminator: fields and leaf entries end at end of line; `{`/`}` may be adjacent to newlines |
| Comment | `#` to end of line; may occupy a line alone or follow a statement |
| Punctuation | `{` `}` `=` `[` `]` `(` `)` `,` |
| Identifier | `[A-Za-z][A-Za-z0-9-]*` |
| Key name | Lowercase letters/digits/dots/hyphens, not starting or ending with a dot (configuration keys, §6.3; allowed only in the `configuration` section) |
| Bare word | A contiguous string of `[A-Za-z0-9._:/\\*?\-]` and `${…}`, not starting with `"`, containing no whitespace or the punctuation above (`*` `?` serve resource globs, §5.6) |
| String | `"` … `"`, only `\"` and `\\` escapes allowed; other `\x` is a lexical error |
| Variable | `${` identifier `}`; may appear inside bare words or strings |

- UTF-8, BOM forbidden; tabs and spaces are equivalent, **indentation carries no semantics**.

### C.2 Grammar (EBNF)

```text
File        = { Newline | Entry } ;
Entry       = Field | Block ;
Field       = Name "=" Value ;
Block       = Name { Argument } [ "{" { Newline | Entry } "}" ] ;
Argument    = Value ;
Name        = Identifier | KeyName ;
Value       = String | BareWord | List | Range ;
List        = "[" [ Value { "," Value } ] "]" ;
Range       = ( "[" | "(" ) Value "," Value ( "]" | ")" ) ;
```

**Block bodies may be omitted**: the trailing `{ … }` of a `Block` is optional, so `module platform`, `exclusion org.old:legacy`, and `repository central { … }` are all legal. To judge "where does this entry end," look only at the line end — which is why the newline must be in the grammar.

### C.3 Semantic Constraints

1. The root level allows one `project` block (manifest), one `lock` block (lock file), one `plugin` block (plugin metadata), or one `settings` block (credentials file), which must be present; other root-level paragraphs → error;
2. Paragraph nesting and legal field combinations are defined by §3.2, §4.4, §4.7, §5.3, §5.5; unlisted combinations → error;
3. Each identifier's repeatability is defined by the corresponding table; a non-repeatable one appearing twice → error;
4. **Name forms**: paragraphs and entries use identifiers; **key names are allowed only in the `configuration` section** (configuration keys); a key name elsewhere → error;
5. Block-header arguments: `dependency`/`repository`/`library`/`module`/`profile`/`entry`/`goal`/`exclusion`/`resource`/`credentials` take one argument; `plugin` takes two (coordinates + version); `project`/`parent`/`build`/`properties`/`modules`/`dependencies`/`dependencyManagement`/`repositories`/`plugins`/`profiles`/`activation`/`exclusions`/`configuration`/`link`/`libraries`/`goals`/`lock`/`settings`/`plugin` (metadata root) take zero;
6. **Block bodies may be omitted**: `dependency`/`repository`/`library`/`module`/`profile`/`entry`/`goal`/`exclusion`/`resource`/`credentials`/`plugin` may be body-less (`module platform`); `project`/`parent`/`build`/`properties`/`modules`/`dependencies`/`dependencyManagement`/`repositories`/`plugins`/`profiles`/`activation`/`exclusions`/`configuration`/`link`/`libraries`/`goals`/`lock`/`settings` MUST have bodies;
7. Values are always treated as strings; list fields (`envOverrides`, `configKeys`, `profiles`) MUST receive lists, and other fields MUST NOT;
8. **A range is an independent value form**: `language-version` MUST receive a range (starting `[`/`(`, ending `]`/`)`, endpoints version-number bare words); a range appearing on any other field, or on a list field, → error; a closed `[a, b]` is treated as a two-element list, semantics decided by the field;
9. Lists and ranges MUST NOT span lines; a field or entry not terminated by a newline or `}` → error;
10. Unclosed blocks, fields missing `=`, empty values → error;
11. Errors MUST report: line number, column number, paragraph path (e.g., `project/dependencies/dependency[2]/optional`).

### C.4 Error Message Format (Specification Requirement)

```text
xnull.project:12:3: error[XPD-204]: unknown field "optonal" in dependency
  12 |   optonal = true
     |   ^^^^^^^ unknown field; available fields: version, scope, optional, exclusions
```

### C.5 Diagnostic-Code Segments

| Segment | Category |
| --- | --- |
| `XPD-0xx` | Lexical (illegal characters, unterminated strings, illegal escapes, BOM) |
| `XPD-1xx` | Grammar and structure (missing `}`, missing `=`, block-header argument counts, empty values, root-level duplication, lists spanning lines `106`, entries not newline-terminated `107`, range endpoints not 2 `105`) |
| `XPD-2xx` | Paragraph and field semantics (unknown paragraphs/fields, repeated non-repeatable paragraphs, illegal entries in containers) |
| `XPD-3xx` | Coordinates and inheritance (missing coordinate fields, duplicate coordinates, depth overrun, cycles, non-pom parent) |
| `XPD-4xx` | Dependencies and locking (missing versions, same-depth conflicts, lock inconsistency, digest mismatch, extra locked coordinates) |
| `XPD-5xx` | Plugins (illegal phase, undeclared goal, missing/mismatched `.xplugin`, out-of-bounds writes, network access) |
| `XPD-6xx` | Configuration (unknown keys, missing required keys, illegal key names, suspected secrets, profile filename mismatch) |
| `XPD-7xx` | Metadata (missing/mismatched `.xmeta` fields, toolchain-version mismatch) |
| `XPD-8xx` | Resources and packaging (illegal resource roots, glob syntax errors, same-path source conflicts, resources under `pom`, illegal configuration-file locations, broken symlinks) |

- Each diagnostic code has a fixed category and a fixed message template; new codes must fall within existing segments; cross-segment additions are specification revisions.
