# Mini 恢复入口

> 小里程碑 0.2.0 / M9-CUT 已结束并归档。
> 当前产品计划：`src/xdk/PLAN.md`（XDK-first / Mini 0.3.0 / M10-T0）。
> 编译器支持队列：`src/mini/PLAN.md`。

## 当前基线

```text
分支:          main / dev（以 git rev-parse 为准）
Mini 版本:     0.2.0（M9-CUT）
默认引擎:      mini
可选引擎:      legacy（oracle）
活动里程碑:    Mini 0.3.0 / M10-T0
目标版本:      0.3.0
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

验收记录：

- `src/mini/MILESTONES.md`
- `docs/assets/mini-200m-runtime-20261118.svg`

旧计划归档：

```text
src/mini/archive/2026-11-18-m9cut/PLAN.md
src/mini/archive/2026-11-18-m9cut/RESUME.md
```

## 下一个动作

**XDK-W4：`xdk.collections` 算法与泛型边界。**

W2/W3 已关闭：`tests/resources.sh` 覆盖 base、full（mini + legacy 差分）和
取消上下文三种资源工程；`src/xdk/PLAN.md` 记录 legacy 无
`Context.background` 的取消路径边界。下一步从 `tests/xdk_collections.x`
和 `xdk.collections` 源码出发，补 Map/Set/List 算法与泛型函数值。

不要先做编译器功能；只有当 XDK 场景明确指出需要时，才进入
`src/mini/PLAN.md` 的编译器支持队列。

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
         c4 m7_sys m8 parity m9_parity m9_cut; do
  ./src/mini/tests/$t.sh || exit 1
done
```

其中：

- `m9_parity.sh`：当前 47 个正向场景，不能回退。
- `m9_cut.sh`：默认 mini，legacy 仍可显式选择。
- `m8.sh`：工程/工具链冷路径。
- `selfhost.sh`：mini1/mini2 固定点。

## 当前边界

- W1 已关闭：bytes、in-memory io、fs 文本面有 mini/legacy 差分证据。
- W2 已关闭：`Mutex<T>`/`withLock` 有 mini + legacy 差分；tasks、取消/超时、
  Channel close 有 mini 场景。`xdk.tasks`、`xdk.sync` 不再是空骨架。
- W3 已关闭：full Sys 装载完整 `Resource.x`；base/full 资源工程与取消路径
  在 `tests/resources.sh` 通过。legacy 无 `Context.background`，取消路径仅 mini。
- `xdk.sync` 的 Channel<Int> 仅 mini；legacy 有 `Result<void, ...>` codegen 缺口
  （`xn_Result_void_CancelledError` 未定义）。
- tasks 的 legacy 缺口：生成的 `xn_task_body_*` 缺少适配器原型声明。
- `xdk.collections` 仍受泛型函数类型参数阻塞；空 Map 字面量已通。
- M7-F1 的 Result/companion 仍未完成。
- 闭包环境回收/生命周期仍未完成。
- legacy 对完整 `src/mini/main.x` 的 xparser 仍有超时边界；不影响默认 mini。

## 基线（2026-11-19 复核）

```text
src/mini/tests/xdk.sh        PASS
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
