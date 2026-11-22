# Cross-package annotation registry BLOCKED

Package attribution now survives `loadUnit`; declarations are tracked with `declPackageOf`, annotation types use `<pkg>.<Name>`, and same-package `app.*` registry output still passes.

Remaining failure with a two-package fixture:

```text
import pkg.a
import pkg.b
registry.types() => pkg.a.A, pkg.b.B
r.ofType("pkg.a.A").first("pkg.a.Marker") != null => true
r.ofType("pkg.b.B").first("pkg.b.Marker") != null => false
```

With only `import pkg.b`, `pkg.b.B`/`pkg.b.Marker` is true. The collision appears when both same-simple-name Marker declarations are merged: the second class/registry type is emitted, but its annotation use is not resolved to `pkg.b.Marker`. Ambiguous simple-name behavior is not yet tested because this unambiguous two-import case fails first.
