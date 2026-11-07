# 验收：S6-XDK-06（runtime）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（核心 runtime API 编译路径可用；`dumpTasks` 未支持、interp 桥缺失）
> **复验点**：main `64e7052`（含 S6-02 / S6-03/04/05 批量）
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-06/`
> **依据**：S6 §4.1–§4.4、XDK-06；`收件箱/门/S6验收计划-E2.md`
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `diagnose` 单行、`nowMono` 单调、`nowWall` UTC、`env` 快照 | **PASS（compiled）**：`s6 runtime` 单行，`true/true/true` |
| `exit` 不执行 defer、退出码原样 | **PASS（compiled）**：rc=7，stdout 无 defer |
| `dumpTasks` 单行 `tasks: live=N` | **FAIL**：sema `TY-229` 未支持，`check` rc=1 |
| 解释路径 | **FAIL**：`run --interp` rc=1（XDK 桥缺失） |
| `TestS6_02*` | **FAIL**：RuntimeSurface/DumpTasks 被 TY-229 拒绝；Exit 测试链接缺资源符号 |

**判定：FAIL。** 编译路径的 5 个 runtime API 可用；`dumpTasks` 仍被 sema 列为未支持，解释路径未接，XDK-06 不能签 PASS。

---

## 二、实测

```text
$ xnull run core.x
true
true
true
stderr: s6 runtime        # diagnose 单行

$ xnull check dumpTasks
error[TY-229]: XDK API `dumpTasks` 尚未支持（S6-01）

$ xnull run exit.x         # compiled
exit=7，stdout 无 defer

$ xnull run --interp core.x
rc=1（解释器 XDK 桥缺失）
```

---

## 三、失败项

| # | 失败项 | 归属 |
|---:|---|---|
| P-01 | `dumpTasks` 在 sema 白名单中显式未支持（`sema/s6_01_test.go:130`），与 S6-02 codegen 发射面冲突 | E2 sema |
| P-02 | 解释器 XDK runtime 桥缺失（diagnose/env/now* 均 rc=1） | E3 |
| P-03 | codegen 测试链接 `rt_std_res.c` 缺资源表符号（测试 harness 未注入空表） | E4/E6 |

---

## 四、证据

- `evidence/S6-QA/XDK-06/matrix.tsv`
- `core.x` / `core.compiled.{out,err}` / `core.interp.err`
- `codegen-s602.log`、`runtime-build.log`
