# 验收：S6-XDK-02（合同原则）

> **验收人**：QA1（独立质量线）
> **结论：BLOCKED/P2**（仅第 1/3 条有机械用例；2/5/7 与静态核验脚本缺失）
> **复验点**：main 含 S6-03/04/05 合并（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/sema-s6.log`、`codegen-s6.log`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 可失败操作返回 `Result`（第 1 条） | **PASS**：`TestS601XDK02Clause1Result` |
| 默认可阻塞 API 首参 `Context`（第 3 条） | **PASS**：`TestS601XDK02Clause3ContextFirst` |
| 命名/稳定性/依赖矩阵机械核验 | **BLOCKED**：`tests/s6/check_xdk_contracts.sh` 未落地 |
| 无隐藏全局可变状态 | **BLOCKED**：无机械扫描脚本 |
| 绑定阻塞分类一致性 | **PASS**：`TestBlockingClassificationDocInSync`（上一轮 ffi 套件） |
| XDK-02 全七条 | **BLOCKED/P2**：4/6 仅部分，2/5/7 缺脚本 |

**判定：BLOCKED/P2。** 第 1/3 条有机械用例，但不满足“七条原则对全包生效”的完整验收；缺合同脚本与全局/稳定性机械核验，不能签 PASS。

---

## 二、实测

```bash
cd impl
go test ./internal/sema -run 'TestS601XDK02' -count=1 -v
```

- `TestS601XDK02Clause1Result`：PASS（`readResource`/`parseInt` 必须 `Result`；裸值拒绝）。
- `TestS601XDK02Clause3ContextFirst`：PASS（可阻塞 API 首参 `Context`；缺参拒绝）。
- 计划要求的 `tests/s6/check_xdk_contracts.sh` **不存在**；`tests/s6/` 目录未落地。
- `codegen-s6.log`：`TestS6_02RuntimeSurface` 因 runtime 链接缺符号失败，进一步阻断绑定/运行时侧的合同复验。

---

## 三、缺口

| # | 缺口 | 归属 |
|---:|---|---|
| 02-1 | 合同静态核验脚本（命名/稳定性/依赖矩阵/全局可变）缺失 | E2/E6 |
| 02-2 | `TestS6_02` 链接缺 S6-03 runtime 符号 | E4/E5 |
| 02-3 | 七条原则仅 1/3 有机械证据 | E2 |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/sema-s6.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/codegen-s6.log`
- 断言依据：S6 §3/§10 XDK-02；计划 v0.1 状态“部分”
