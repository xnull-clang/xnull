# Cross-package annotation registry

Real multi-package fixtures (no fake AST):

- `pkg.a` and `pkg.b` each declare `@Marker`.
- `main_b` imports only `pkg.b`; `pkg.b.B` resolves `pkg.b.Marker`.
- `main_both` imports both; registry keeps `pkg.a.Marker` and `pkg.b.Marker` apart.
- `main_ambig` imports both and uses simple `@Marker`; compilation fails with `AN0001` listing both candidates.

Run `cross_package.sh` (also registered in `xdk2.sh`).

Known language limit: `@pkg.a.Marker(...)` on a declaration is not parsed (`.` after `@` gives
`unexpected top-level token: .`). Resolution is therefore: same package, then the owner's
single imported package, then a unique global simple name; anything else is `AN0001`.
