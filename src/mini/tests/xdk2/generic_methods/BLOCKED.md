# Generic methods BLOCKED (desugar route)

Parser accepts method-level TypeParams and explicit method type args. Desugar generates:

```text
__gm_Box_map params=2
__gm_Box_get params=2
__gm_Tools_apply params=2
```

But call rewriting reaches `__gm_Box_map` and generic-function inference returns an empty type-arg string:

```text
TA __gm_Box_map=
TA __gm_Tools_apply=Int,Int
SEM-001 undefined function: __gm_Box_map
```

The generated functions exist; failure is inference of the class type parameter from a specialized receiver (`Box__Int` vs pattern `Box<T>`), so `Mono.specialize` is not reached. `Tools.apply` (non-generic class, no receiver) infers `Int,Int` and is the only call that progresses.

Minimal input: `generic_methods.x.txt`.
