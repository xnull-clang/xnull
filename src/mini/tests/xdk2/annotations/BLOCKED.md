# B1 annotation target status

The target-name table contains all 11 names:
`Package`, `Type`, `Annotation`, `TypeParameter`, `Field`, `Method`,
`Constructor`, `Deinit`, `Parameter`, `TypeUse`, `EnumItem`.

Two names have no legal mount site in the current language surface:

| Target | Status | Dependency |
| --- | --- | --- |
| `Deinit` | BLOCKED | S2 must define a `deinit` declaration syntax; mini does not parse one yet. |
| `TypeUse` | BLOCKED | S2 must define explicit type-use annotation positions; mini has no such syntax yet. |

`@Target(Deinit)` and `@Target(TypeUse)` are still accepted as valid target
names (`AN0009` does not fire). Applying an annotation restricted to either
target to any existing declaration is rejected with `AN0002`; no syntax is
invented in the compiler to make them mountable.

This is why B1 does not claim that all 11 targets are mountable.
