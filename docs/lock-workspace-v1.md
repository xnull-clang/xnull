# Workspace lock entries (v1)

Status: normative addendum to `solution-09-project-configuration.md` §4.4.
Scope: Mini 1.0, workspace dependencies resolved from a `modules` aggregation.

## Format

```xpd
lock {
  version = 1

  entry demo:common 1.0.0 {
    kind       = dependency
    repository = workspace
    sha256     = 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  }
}
```

## Rules

1. An entry is emitted for each workspace module that is the target of a
   dependency edge from another module. The aggregation root and modules that
   are not dependency targets do not produce entries.
2. `repository = workspace` is reserved. It is not a repository declaration,
   is never used for network access, and must not be redeclared under
   `repositories`.
3. `version` is the exact module version from the manifest. Only finalized
   versions are allowed.
4. `kind` is `dependency` for workspace dependencies. Plugin entries are
   unchanged and use their declared repository.
5. `sha256` is the SHA-256 of the deterministic `.xlib` produced by
   `src/toolchain/pack_xlib.py` for that module, written as 64 lowercase
   hexadecimal digits. The archive uses sorted stored entries, fixed timestamps,
   includes `xnull.project`, and excludes build/cache outputs.
6. Entries are sorted by ascending `groupId:artifactId`; duplicate coordinates
   and unresolved versions are errors.
7. A coordinate that is not a workspace module is unresolved in Mini 1.0:
   the lock command reports `LOCK-002` (temporary code) and must not create or
   modify the lock file.
8. `--check` only verifies: a missing or different lock returns non-zero and
   leaves the file untouched. `--update` is the only explicit rewrite path.
   A first successful generation without a lock writes the file once.
9. The lock is located at the aggregation root and its bytes are stable for the
   same manifest/source tree.

## Consequences

- Changing a workspace dependency's source or `xnull.project` changes its
  `.xlib` digest; `lock --check` fails until the lock is explicitly updated.
- `install` must produce the same `.xlib` bytes as the lock digest; a mismatch
  is a reproducibility failure.
- `relativePath` workspace entries and external repository resolution are not
  part of v1. They require separate specification and implementation.
