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

验收记录：

- `src/mini/MILESTONES.md`
- `docs/assets/mini-200m-runtime-20261118.svg`

旧计划归档：

```text
src/mini/archive/2026-11-18-m9cut/PLAN.md
src/mini/archive/2026-11-18-m9cut/RESUME.md
```

## 下一个动作

**XDK-W0：从底层 XDK 建立第一批 probe。**

先锁定 bytes/IO/FS 的运行时与 XDK 契约，并保留 tasks/sync、空 Map 的失败证据。
随后按 `src/xdk/PLAN.md` 的 XDK-W1 → W7 顺序推进。

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

- 完整 T0 XDK 仍未完成；见 `PLAN.md` 的包矩阵。
- `xdk.collections` 仍受泛型函数类型参数、空 Map 字面量阻塞。
- `xdk.tasks` / `xdk.sync` 仍是空骨架。
- 完整 Sys 的 `Resource.x` / `Context` 尚未接入。
- M7-F1 的 Result/companion 仍未完成。
- 闭包环境回收/生命周期仍未完成。
- legacy 对完整 `src/mini/main.x` 的 xparser 仍有超时边界；不影响默认 mini。

## 纪律

- 不重做 M0–M9。
- 每个工作包必须有代码、场景、回归和提交。
- 没有场景的能力登记为“等待”，不得用空实现宣称完成。
- legacy 保留；删除旧引擎或再次改变默认引擎必须单独批准。
- 归档文件只读，不再修改。
