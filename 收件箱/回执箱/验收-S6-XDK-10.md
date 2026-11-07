# 验收：S6-XDK-10（资源读取）

> **验收人**：QA1（独立质量线）
> **结论：BLOCKED/P2**（运行时 5 API/7 约束通过；E4 绑定与 XNull 端到端未接）
> **复验点**：main `64e7052`（含 S6-04 `080d6e8`）
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-10/`
> **依据**：S6 §4.8、XDK-10；S6-04 E5 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 5 API：exists/size/read/readText/list | **PASS（runtime）**：资源 API 测试通过 |
| 7 约束：非法路径/缺失/list 字典序/无 close/取消/不回退 FS/文件 API 隔离 | **PASS（runtime）**：`test_res_api` 逐条 |
| 资源 API 发射面 | **PASS**：`TestS6_04ResourceSurface` |
| XNull 端到端资源程序 | **BLOCKED/P2**：E4 FFI `Bytes` 返回编组未实现；`tests/s6/xdk10_resources.x` 未落盘 |

**判定：BLOCKED/P2。** 运行时与发射面成立；绑定/语言面端到端缺失，按计划口径记 BLOCKED，不签完整 PASS。

---

## 二、证据

- `evidence/S6-QA/XDK-10/matrix.tsv`
- `runtime-build.log`（`资源 API 测试通过（5 API / 7 约束）`）
- `codegen-s604.log`（TestS6_04ResourceSurface PASS）
- `收件箱/回执箱/回执-S6-04-E5.md`（待 E4 绑定）
- `impl/runtime/test_res_api.c`
