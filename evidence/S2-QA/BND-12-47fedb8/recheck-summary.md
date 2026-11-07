# BND-12 复验摘要（main 47fedb8）

- main：`47fedb8ad1659925af04a677a9e82b861c2dffcd`
- binary：`/tmp/xnull-s2-47fedb8`
- binary sha256：`46a22fee8a5523ef1a6061be2a4c73d3adb8c474762a930efa69850c56d14150`
- 结果：**PASS**（R01–R03 + A01）

## 通过项

| 用例 | 实测 |
|---|---|
| R01 `new T()` | `GEN-104` @2:23 |
| R01 `static T value` | `TY-214` @2:14 |
| R02 泛型协议 | `SYN-101` @1:11 |
| R02 关联类型 | `SYN-101` @2:21 |
| R03 泛型 struct 非值实参 | `TY-204` @5:17 |
| R03 T 不出现在字段 | `TY-204` @5:17 |
| A01 `Box<Int>` 单态化 | interp `7` / compiled `7` |

## 边界（不在本轮黄金矩阵，但属 §13.1/§13.4）

- 泛型 struct 值实参正例：sema rc=0；codegen `类型 T 未支持`（`probes/generic_struct_int/`）。
- 类泛型方法 `U convert<U>(U)`：sema `RES-101 未定义的类型 U`（`probes/class_generic_method/`）。
- 顶层泛型函数 `id<T>`：双路径 `3`（`probes/topfn_generic/`），说明泛型函数单态化可用。

建议 GATE-01 前补 E4 泛型 struct / 类泛型方法卡；本轮不改变 BND-12 判定。
