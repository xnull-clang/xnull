# Generic methods BLOCKED (desugar route)

Parser and desugar are implemented:

- method-level `<T,...>` parsed;
- generic methods removed from class and cloned to `__gm_<Class>_<method>` top-level Funcs with `__self` receiver;
- call rewrite reaches `__gm_Box_map` and `__gm_Tools_apply`.

Remaining failure: generic-function type-arg inference for the desugared function is empty for instance generic methods:

```text
SEM-001 undefined function: __gm_Box_map
```

`__gm_Box_map` has TypeParams `T,R` and first Param `Box<T> __self`; the call receiver is already specialized (`Box__Int`), and `typeArgsFor` does not infer `T` from that receiver, so `Mono.specialize` is never reached. Static `Tools.apply` infers from scalar/lambda args and progresses further.

Minimal input: `generic_methods.x.txt`.
