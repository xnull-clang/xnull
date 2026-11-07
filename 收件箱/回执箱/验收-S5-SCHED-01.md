# 验收：S5-SCHED-01（调度与阻塞分类）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（基础调度/取消/超时通过；任务感知阻塞不占载体线程、`.unaware` 伴生执行器未达）
> **复验点**：main `6c0609b`（含 S5-01 `2ac7e21`、S5-02 `1dc8314`、S5-03 `63d15e6`）
> **时间**：2026-11-08
> **证据**：`evidence/S5-QA/SCHED-01/`
> **依据**：S5 §2.2、§9、SCHED-01；S5-01/S5-03 回执；`收件箱/门/S5盘点-E5.md` P0-6
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 基础调度（spawn/join/close/取消/超时） | **PASS**：`task tests passed` |
| 阻塞分类清单（声明半段） | **PASS**：`TestBlockingClassificationDocInSync`；`.xfb @blocking(.aware/.unaware)` |
| 任务感知阻塞不占载体线程 | **FAIL**：单载体线程 + FIFO；任务挂起/长阻塞占住唯一 worker |
| `.unaware` 长阻塞伴生执行器 | **FAIL**：无 M:N 载体池 / 无 companion executor |
| 取消/超时 | **PASS**（见 CANCEL/TIMEOUT 验收） |

**判定：FAIL。** 调度器只有 1 个载体线程；`worker_main` 一次只执行一个 task body，任务在 `xrt_channel_receive` 等挂起点上 5ms 轮询期间无法调度其他任务；`.unaware` 长阻塞会占死载体。声明清单已有，运行半段未达 SCHED-01。

---

## 二、精确缺口（给 E5）

| # | 缺口 | 证据 | 影响 |
|---:|---|---|---|
| S-01 | 单载体线程 + 全局 FIFO，无 M:N 载体池 | `impl/runtime/rt_task.c:184-250`：`worker_main` 单线程、逐个执行 body | 阻塞任务占用唯一 worker，后续任务饥饿 |
| S-02 | 任务感知阻塞未让出载体 | `rt_sync.c` Channel send/receive 5ms 轮询 `check_cancel`，轮询在 worker 内进行 | 另一个可运行任务无法推进 |
| S-03 | `.unaware` 长阻塞无伴生执行器 | `BlockingManifest` 仅声明；`S5盘点-E5.md` P0-6；S5-03 回执“单载体线程下任务互阻塞自锁（B3 M:N）” | 长阻塞 FFI 占死载体 |

**建议**：B3/S5-06 落地载体池（M:N）+ `.unaware` companion executor，并补“两个任务、一个长阻塞、另一个应推进”的运行期断言；完成前 SCHED-01 不得判 PASS。

---

## 三、已通过面

```text
task tests passed (spawn/join/close/cancel/token/deadline/cleanup/timeout/root/panic)
```

- spawn/join/close、重复 join/close fatal、任务 panic 进程终止。
- 取消令牌、deadline、joinDeadline 超时、清理排队、env root。
- 阻塞分类清单与 `.xfb` 声明一致。

---

## 四、证据

- `evidence/S5-QA/SCHED-01/matrix.tsv`
- `runtime-build.log`（task/sync 套件）
- `blocking-manifest.log`（声明清单一致性）
- `impl/runtime/rt_task.c:184-250`（单载体 worker）
- `收件箱/门/S5盘点-E5.md` P0-6
- `收件箱/回执箱/回执-S5-01.md`、`回执-S5-03-E5.md`
