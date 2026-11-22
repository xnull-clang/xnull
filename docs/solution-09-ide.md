# XNull Solution Part 9: IDE

| Item | Value |
| --- | --- |
| Document ID | Part 9 (S9) |
| Document version | 2.0.0 |
| Specification status | Draft (depends on Part 8 machine interface validation) |
| Release date | 2026-11-15 |
| Intended audience | XNull IDE / editor integration implementations |
| Related parts | Parts 1–8 |

Version rules: revision numbers are used for clarifications that do not change semantics, minor versions for backward-compatible additions, and major versions for breaking changes. Historical versions are available in the git history.

Renumber note: document renumbered from Part 8 to Part 9 on 2026-11-23 to insert Part 3 (Annotations); content is unchanged.

## 0. Positioning and boundaries

### 0.1 What Part 9 is

Part 9 specifies the **stable contract** among the IDE, the toolchain, and the language specification: editing experience, project creation, standard library browsing, build/run entry points, diagnostics presentation, and settings. It adds no new language semantics, nor does it prescribe UI form.

### 0.2 What it is not

- It does not define editors, language service protocols, or UI interaction details; these are implementation choices.
- It does not replace the Part 8 CLI, compiler, or build system; the IDE only invokes them.
- It does not require a specific implementation form (a plugin, a standalone workbench, or a language service are all acceptable).

### 0.3 Conflict rules

- Language semantics are governed by Parts 0–10; the IDE MUST NOT change the observable behavior of source code.
- The IDE's interactions, commands, layout, and caching strategies are implementation choices and MUST NOT be written as language commitments.

## 1. Required capabilities

### 1.1 Editing

- Syntax highlighting, bracket matching, comment toggling, code snippets.
- Diagnostic navigation: jump from a diagnostic to `file:line:column`.
- Completion, refactoring, or a debugger is not required; when provided, it MUST follow the Part 8 machine interface.

### 1.2 Projects

- Create `app` / `library` projects, generating `xnull.project`, `src/main/x/`, `src/main/resources/`.
- Read and write the manifest's visible fields: coordinates, dependencies, profiles, resources, link declarations.
- MUST NOT modify build inputs; MUST obtain user confirmation before writing.

### 1.3 Standard library

- Browse the Part 7 XDK capabilities: errors and observability, concurrency, data and text, system and resource reading.
- Display public signatures and documentation; insert `import` and call snippets.
- MUST NOT display internal implementation details or undecided APIs.

### 1.4 Build and run

- Execute `build` / `run` / `check` through the Part 8 CLI; MUST NOT assemble compiler commands on its own.
- Display diagnostics, exit codes, and artifact paths; pass program output through unchanged.
- On run failure, preserve the original exit code; MUST NOT swallow it.

### 1.5 Diagnostics

- Diagnostic fields: `file` / `line` / `column` / `code` / `message` / `hint` / `snippet` / `width`.
- Stable ordering by file and position; the same input yields the same order.
- MUST NOT write internal governance information or task numbers into user-visible output.

### 1.6 Settings

- Configurable toolchain path, target platform, formatting options.
- Settings MUST NOT change language semantics; MUST NOT implicitly enable extensions not defined by the specification.

### 1.7 Security and reproducibility

- No implicit network access; dependency and repository access follow the Part 10 manifest.
- Do not cache stale diagnostics; MUST recompute after source files or the toolchain version change.
- Build artifacts are consistent with the CLI; the IDE MUST NOT generate substitute artifacts that "look runnable".

## 2. Machine interface

The IDE uses only the stable machine interface defined in Part 8:

- `check --json`: `ok` / `file` / `diagnostics`.
- `build --json`: `ok` / `file` / `output` / `exitCode` / `diagnostics` / `log`.
- For diagnostic fields, see §1.5.
- MUST NOT parse human-readable output; the human-readable output format is not a stable interface.

## 3. Non-promises

- No commitment to a specific UI form, language service protocol, or plugin ecosystem.
- No commitment to completion, refactoring, a debugger, remote development, or multi-language support.
- No commitment to build paths other than the IDE and CLI.
