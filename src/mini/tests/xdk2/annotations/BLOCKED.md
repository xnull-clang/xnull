# B1 annotation target status

The target-name table contains all 11 names:
`Package`, `Type`, `Annotation`, `TypeParameter`, `Field`, `Method`,
`Constructor`, `Deinit`, `Parameter`, `TypeUse`, `EnumItem`.

`Deinit` now has a legal mount site (`class`/`singleton` `deinit`); see
`src/mini/tests/deinit/deinit_registry.x`.

One name has no legal mount site in the current language surface:

| Target | Status | Dependency |
| --- | --- | --- |
| `TypeUse` | BLOCKED | S2 must define explicit type-use annotation positions; mini has no such syntax yet. |

`@Target(TypeUse)` is still accepted as a valid target name (`AN0009` does not
fire); applying it to an existing declaration is rejected with `AN0002`.
B1 does not claim that all 11 targets are mountable until TypeUse exists.
