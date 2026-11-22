# B1 annotation target status

The target-name table contains all 11 names:
`Package`, `Type`, `Annotation`, `TypeParameter`, `Field`, `Method`,
`Constructor`, `Deinit`, `Parameter`, `TypeUse`, `EnumItem`.

`Deinit` has a legal mount site (`class` `deinit`); see
`src/mini/tests/deinit/deinit_registry.x`.

`TypeUse` has legal mount sites (field/parameter/return/local types) via the
prefix form `@Foo Type`; see `src/mini/tests/typeuse/`.

All 11 target names now have at least one legal mount site. `@Target(TypeUse)`
must still be explicit, and a declaration-only annotation is not reinterpreted
as a type-use annotation.
