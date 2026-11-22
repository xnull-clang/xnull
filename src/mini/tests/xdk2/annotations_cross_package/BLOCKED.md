# Cross-package annotation use BLOCKED

Package ownership now travels on `AstNode.packageName`; `declPackageOf` prefers that field and annotation type names are `<pkg>.<Name>`.

Fixture: `fixture/run.sh` (real `xnull` compile/run, no fake AST).

Observed:

```text
$ sh fixture/run.sh
true        # import pkg.b only -> pkg.b.B / pkg.b.Marker
false       # import pkg.a + pkg.b -> pkg.a.A / pkg.a.Marker
```

With both imports, both uses still resolve to `pkg.a.Marker`; the second package's class node is a clone and its `packageName` is lost after Mono cloning/walking. `cloneAst`/`cloneSubst` carry the field, but a later path that creates class/member nodes still drops it.

Remaining:
- identify the clone path that drops `packageName` for `pkg.b.B`;
- then implement simple-name ambiguity error when both imports are used unqualified.
