# BND-08 复验摘要（main 0177c80）

- main ref：`0177c8077670eaa618b3052544ec475a775abf72`
- binary：`/tmp/xnull-s2-0177c80`
- 结果：**PASS（全表 7/7）**

## 全表

- A01 同包 factory 私有构造器：check/interp/compiled 全 rc=0，`cam`
- A02 cross-private：三路径均 rc=1，`TY-219` 跨包非公开构造器
- A02 cross-public：三路径均 rc=0，`x`（编译路径已修复）
- R02 invisible：三路径 rc=1，`TY-217`
- R03 field/generic-args/non-type：三路径 rc=1，`SYN-101` / `TY-217`
- 补充探针：返回约束 `TY-220`、self `TY-221`、factory 非类型 `TY-217`、new factory `TY-217/216`、Target enum/singleton/array/Object/Any/protocol/可空 全部拒绝

## 边界（未纳入全表）

- `protected static` 工厂方法：check/run rc=0（§10.2 应拒绝）
- 重复签名：sema rc=0，编译期 C 重定义错误（§10.5 应提前拒绝）
- 返回 Object / 协议 / 非 String 错误类型 Result：sema 通过，codegen 未支持
