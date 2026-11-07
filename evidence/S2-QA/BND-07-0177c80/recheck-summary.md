# BND-07 复验摘要（main 0177c80）

- main ref：`0177c8077670eaa618b3052544ec475a775abf72`（读取 `.git/refs/heads/main`，未运行 git 命令）
- binary：`/tmp/xnull-s2-0177c80`，sha256 `44a6b9f31a0bec34115f91b43673a3442ca9c6e0b85e7dc5d58e8429be9fe6d4`
- 结果：**PASS（全表 7/7）**

## 全表

- A01/A02：check/interp/compiled 全 rc=0，双路径 `XNull\n3`、`localhost\n8080`
- R01 implements/inherit/new/write：三路径均 rc=1，`SYN-101` / `TY-202` / `TY-216` / `TY-215`
- R02 fwd：三路径均 rc=1，`TY-222` 前向引用
- 补充探针：abstract `TY-222`、手动 instance `TY-215`、构造器 `TY-201`、泛型 `SYN-101` 全部拒绝

## 边界（ADR-005：BND-07 暂只做 sema）

- 单例静态字段/方法：sema+interp 可用；compiled codegen 暂未支持
- 初始化式引用前面单例：sema+interp 可用；compiled codegen 失败
- `instance` 用全局 `rt_arc_new` 句柄发射；进程常驻可观察，GC 分类归 E5
