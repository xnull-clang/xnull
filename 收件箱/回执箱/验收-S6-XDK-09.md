# 验收：S6-XDK-09（sys / net）

> **验收人**：QA1（独立质量线）
> **结论：BLOCKED/P2**（File/Dir/Async/Process 运行时可验；net 仅骨架，FFI 测试链接缺口）
> **复验点**：main `64e7052`（含 S6-03 E4/E5）
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-09/`
> **依据**：S6 §4.7、XDK-09；S6-03 E4/E5 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| File/Dir 打开/读写/close 幂等 | **PASS（runtime）**：sysasync tests passed |
| Async 首参 `Context` + 取消 | **PASS（runtime/发射）**：`TestS6_03AsyncAndProcessSurface` |
| Process spawn/wait/kill/close | **PASS（runtime/发射）** |
| `procStatus` + file/dir close 幂等跨 FFI | **BLOCKED/P2**：`TestS6_03ProcStatusAndHandleClose` 链接缺 `xrt_resource_*`（测试 harness 未注入空资源表） |
| net 独立包 | **BLOCKED/P2**：`impl/lib/xdk/net.x` 仅骨架，socket API 未冻结 |

**判定：BLOCKED/P2。** sys 主体已实现；net 与部分 FFI 端到端未闭合，按任务口径不判 FAIL，记 BLOCKED/P2。

---

## 二、精确缺口

| 项 | 证据 | 归属 |
|---|---|---|
| FFI 测试链接缺资源表符号 | `codegen-s603.log`：`_xrt_resource_at/count/get` undefined | E4/E6 测试 harness |
| net socket API 未冻结/实现 | `impl/lib/xdk/net.x` 仅注释骨架 | E2/E4 S6-09 |
| XDK 端到端 sys 用例未落 `tests/s6/xdk09_sys.x` | 计划 §3 骨架未落盘 | E2/QA |

---

## 三、证据

- `evidence/S6-QA/XDK-09/matrix.tsv`
- `runtime-build.log`（`sysasync tests passed (file/dir/process async + close + cancel)`）
- `codegen-s603.log`（Async/Process 发射 PASS；ProcStatus 链接失败）
- `impl/lib/xdk/net.x`
