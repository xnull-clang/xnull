# STRUCT-01 复验摘要（main fa4fbf9）

- main：`fa4fbf9d756882afe7e1aae52b7d9c72e90ec743`（INTEG-S2-BATCH3）
- 包含：`438c28b` STRUCT-01 codegen、`1b1d12e` BND-07/08 sema
- binary：`/tmp/xnull-s2-fa4fbf9`，sha256 `237b1a56b8ca3f84ec12f64c2d79305cbf5a03d77370c71cb08a1d6b76d35585`
- 结果：**PASS**

## 通过

- A01 双路径 `1\n10\n3\n12`
- A02 双路径 `1\n5`（438c28b 修复）
- R01 array/class/String + 补充 String?/List/Result：全部 `TY-204` + 位置
- R02 deinit/generic/recursive：全部 `TY-204` + 位置
- D01：A01/A02 双路径一致
- 官方 sema/codegen STRUCT 用例全 PASS

## 边界（不影响本轮）

`struct_enum_tuple_ok.x`：`Color c = Color.Red; (Int,Int) t = (1,2); Int? q = null`
- interp `Red\nnull`；compiled rc=1 `字段初始化式访问了成员 Red`
- 同一问题在 class 复现；属字段初值成员表达式的通用 codegen 缺口，建议独立卡。
