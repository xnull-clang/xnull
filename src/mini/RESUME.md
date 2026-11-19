# Mini 恢复入口

> 小里程碑 0.3.0 / M10-T0 已发布。
> 当前产品计划：`src/xdk/PLAN.md`（XDK-first）。
> 编译器支持队列：`src/mini/PLAN.md`。

## 当前基线

```text
分支:          main / dev（以 git rev-parse 为准）
Mini 版本:     0.3.0（M10-T0）
默认引擎:      mini
可选引擎:      legacy（oracle）
活动里程碑:    M10-T0 已发布
目标版本:      0.3.0（已达成）
```

已完成的小里程碑：

- Mini 1.0 / M9-MIN
- M9-PAR：47 个正向文件/工程场景，stdout/stderr/退出码 `diff=0`
- M9-CUT：默认引擎切换为 mini
- 26 个回归、selfhost 固定点、m8 冷启动路径
- XDK-W0：T0 包矩阵每行都有 owner 和场景名
- XDK-W1：bytes / in-memory io / fs 文本面通过 `tests/xdk.sh`（mini + legacy）
- XDK-W2：Mutex/tasks/Channel close/取消与超时，四个场景进入 `tests/xdk.sh`
- XDK-W3：完整 Resource.x 装载；base/full 资源工程与取消路径通过 `tests/resources.sh`
- XDK-W4：泛型函数特化；`sortBy`/`dedup`/`find` 在 Int/String 列表上通过 `tests/xdk_collections_algo.x`
- XDK-W5：`xdk.log`/`xdk.config`/`xdk.cli` 三个可运行场景进入 `tests/xdk.sh`
- XDK-W6：`tests/m10_parity.sh` 覆盖 T0 base/full；`tests/m10_perf.sh` 守住 200M 门禁
- XDK-W7：`mini 0.3.0` 发布，记录与标签为 `mini-v0.3.0`

验收记录：

- `src/mini/MILESTONES.md`
- `docs/assets/mini-200m-runtime-20261118.svg`

旧计划归档：

```text
src/mini/archive/2026-11-18-m9cut/PLAN.md
src/mini/archive/2026-11-18-m9cut/RESUME.md
```

## 下一个动作

**发布后维护：T1 包扩展。**

W0–W7 已全部关闭，`mini 0.3.0` 已发布。后续从 T1 包矩阵中选择下一批场景；
沿用同一纪律：场景先行、base/full 回归、legacy 缺口显式记录。legacy 保留；
删除旧引擎或再次改变默认引擎必须单独批准。

## 重启命令

```sh
cd /Users/vjs/Desktop/XNull-Lang
git switch main
git pull --ff-only origin main
./src/mini/build.sh
```

如果本机没有 mini 种子：

```sh
XNULL_MINI_BOOTSTRAP=legacy ./src/mini/build.sh
```

## 回归命令

每次提交前至少执行：

```sh
for t in lex parser sema codegen class flow array containers result defer m6_4 \
         xdk check project ffi xfb_error resources object_list selfhost generics \
         c4 m7_sys m8 parity m9_parity m9_cut m10_parity m10_perf; do
  ./src/mini/tests/$t.sh || exit 1
done
```

其中：

- `m9_parity.sh`：当前 47 个正向场景，不能回退。
- `m10_parity.sh`：T0 包 base/full 矩阵。
- `m10_perf.sh`：200M 性能门禁（>20% 回退失败）。
- `m9_cut.sh`：默认 mini，legacy 仍可显式选择。
- `m8.sh`：工程/工具链冷路径。
- `selfhost.sh`：mini1/mini2 固定点。

## 当前边界

- W1 已关闭：bytes、in-memory io、fs 文本面有 mini/legacy 差分证据。
- W2 已关闭：`Mutex<T>`/`withLock` 有 mini + legacy 差分；tasks、取消/超时、
  Channel close 有 mini 场景。`xdk.tasks`、`xdk.sync` 不再是空骨架。
- W3 已关闭：full Sys 装载完整 `Resource.x`；base/full 资源工程与取消路径
  在 `tests/resources.sh` 通过。legacy 无 `Context.background`，取消路径仅 mini。
- W4 已关闭（mini 算法面）：泛型函数按 `List<T>` 实参推断并单态化；
  `sortBy`/`dedup`/`find` 覆盖 Int/String。`groupByInt` 仍缺 `Map<Int,...>`
  运行时；legacy 泛型算法缺 `xn_fn_*` typedef。
- W5 已关闭：log/config 差分通过；CLI 在 mini 通过，legacy 读
  `List<String>.get` 的 String 元素仍有错，差分保持开放。
- W6 已关闭：`tests/m10_parity.sh` 覆盖 T0 base/full；`tests/m10_perf.sh`
  200M 实测 0.727s（0.2.0 基线 0.733s，0.992x）。
- `xdk.sync` 的 Channel<Int> 仅 mini；legacy 有 `Result<void, ...>` codegen 缺口
  （`xn_Result_void_CancelledError` 未定义）。
- tasks 的 legacy 缺口：生成的 `xn_task_body_*` 缺少适配器原型声明。
- `xdk.collections` 的空 Map 字面量与泛型算法已通；`groupByInt` 仍待 Map 键类型扩展。
- M7-F1 的 Result/companion 仍未完成。
- 闭包环境回收/生命周期仍未完成。
- legacy 对完整 `src/mini/main.x` 的 xparser 仍有超时边界；不影响默认 mini。

## 基线（2026-11-19 复核）

```text
src/mini/tests/xdk.sh        PASS
src/mini/tests/resources.sh  PASS
src/mini/tests/m10_parity.sh PASS
src/mini/tests/m10_perf.sh   PASS（200M 0.727s / 基线 0.733s）
26 个回归                    全部 PASS
m9_parity（47 个场景）       PASS
selfhost                    PASS
```

## 纪律

- 不重做 M0–M9。
- 每个工作包必须有代码、场景、回归和提交。
- 没有场景的能力登记为“等待”，不得用空实现宣称完成。
- legacy 保留；删除旧引擎或再次改变默认引擎必须单独批准。
- 归档文件只读，不再修改。
