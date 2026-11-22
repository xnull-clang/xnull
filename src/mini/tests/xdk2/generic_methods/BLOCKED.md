# Generic methods BLOCKED

Parser now accepts method-level `<T, ...>` and explicit `receiver.method<T>(...)`, but checker/Mono/codegen are not wired for method type parameters.

Minimal failing input (`minimal.x.txt`):

```x
class Box<T> {
    final T value
    Box(T v) { self.value = v }
    Box<R> map<R>(R(T) transform) { return new Box<R>(transform(self.value)) }
}
class Tools {
    static R apply<T, R>(T value, R(T) transform) { return transform(value) }
}
```

Current failure:

```text
src/mini/tests/xdk2/generic_methods/generic_methods.x:12:14: [SEM-005] unknown type: T
```

Root cause: `Mono.instantiateClass` clones generic methods without removing method-level `TypeParams`; `Checker.findMethod` stores the unsubstituted `R`/`T` return and cannot infer method type args. Codegen has no per-`(class instance, method type args)` specialization. Parser-only change is insufficient.
