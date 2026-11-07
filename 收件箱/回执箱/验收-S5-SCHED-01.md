# 验收：S5-SCHED-01（调度与阻塞分类）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（载体池 + 伴生执行器修复后复签）
> **复验点**：main `11bf22f`（含 E5 `47fd089` SCHED-01：载体池 + 伴生执行器）
> **时间**：2026-11-08
> **证据**：`evidence/S5-QA/SCHED-01b/`
> **依据**：S5 §2.2、§9、SCHED-01；S5-01/02/03 回执
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 载体池（默认 4，`XNULL_CARRIERS` 可配） | **PASS**：`worker_init` 创建 N 个载体线程 |
| 任务感知阻塞不占 worker | **PASS**：3 个阻塞任务 + flag 任务，flag 在 150ms 内完成 |
| `.unaware` 长阻塞伴生执行器 | **PASS**：2×150ms companion 期间普通任务 <80ms 完成 |
| 取消/超时可打断等待 | **PASS**：`companion_wait(deadline 10ms)` → `Cancelled`；随后可完成 |
| 基础调度/取消/超时 | **PASS**：`task tests passed (... pool/companion)` |
| 阻塞分类清单 | **PASS**：`TestBlockingClassificationDocInSync` |

**判定：PASS。** 上一轮“单载体线程 + 无 unaware executor”的两个缺口已由 `47fd089` 关闭：载体池让阻塞任务不独占 worker，companion executor 承载 `.unaware` 长阻塞，且等待可被 deadline/取消打断。

---

## 二、实测

```text
$ sh impl/runtime/build_rt.sh
...
task tests passed (spawn/join/close/cancel/token/deadline/cleanup/timeout/root/panic/dump/pool/companion)
sync tests passed (channel/mutex/atomic/cancel)
exit 0
```

### 2.1 载体池

`test_carrier_pool`：spawn 3 个长阻塞任务 + 1 个 flag 任务；`join_deadline(flag, +150ms)` 返回 0，`g_flag=1`。若仍是单载体，flag 需等 3×长阻塞结束。

### 2.2 伴生执行器

`test_companion_executor`：
- 提交 2 个 150ms companion；
- 普通 flag 任务在 80ms deadline 内完成；
- `companion_wait(fa/fb)` 均得原参数；
- 10ms deadline 等待 → `XRT_ERR_CANCELLED`；任务继续，随后 `wait(NULL)` 完成。

### 2.3 载体配置

`impl/runtime/rt_task.c:245-262`：`XNULL_CARRIERS` 默认 4（1..64），创建 N 个 `worker_main`。

---

## 三、证据

- `evidence/S5-QA/SCHED-01b/matrix.tsv`
- `runtime-build.log`（pool/companion 用例）
- `source-contract.txt`（test_carrier_pool / test_companion_executor）
- `runtime-source.txt`（worker_init / companion 实现）
- `evidence/S5-QA/SCHED-01/blocking-manifest.log`
- `收件箱/回执箱/回执-S5-01.md`、`回执-S5-02.md`、`回执-S5-03-E5.md`
