1. 完成：B3 只读架构盘点，输出 `handoff/B3-xnullc-plan.md`——当前 Go 版 codegen 生产代码约 1.48 万行（不含测试）+ FFI 子包 2100 行；列出 2.2 模块表、2.3 对外接口、2.4 `gen`/`scope` 状态、C 输出五层、XDK 可复用库现状。
2. 关键判断：B3 是“有状态两遍发射器 + 8 类语言面 + FFI/内存策略/构建边界”的整体重写；XNull 版必须先定显式 `Emitter/Scope` 状态与逐语言面文件边界，不能把 45+17 字段的 Go 结构平移到巨型类。
3. 前置：`xdk.sys` 源码面（File/Dir/readFileText/writeFileText）是 xnullc 读 AST/写 C 的硬依赖；`text/errors/collections` 可复用，`runtime/tasks/sync/net` 后置；B2 AST 接口需冻结。
4. Oracle 口径：同一 AST/源+import+`.xfb`+策略输入，C 文本逐字节一致；成功/失败码与诊断位置一致；同一 C 双路径 stdout/退出码一致；两次生成 sha256 一致；不以“能运行”替代文本差分。
5. 卡拆分：B3-00 差分基座、B3-01 骨架、B3-02 基础表达式/语句、B3-03 Result/try/defer、B3-04 容器、B3-05 对象面、B3-06 泛型/元组/可选/Any、B3-07 内存策略、B3-08 FFI/XDK、B3-09 全量收口、B3-10 B4 前置；每卡带验收锚点与风险（R1–R10）。
6. 是否越界：否（只新增 `handoff/B3-xnullc-plan.md` 与本回执；未改生产代码/oracle/构建系统，未 push）。
