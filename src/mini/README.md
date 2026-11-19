# XNull Mini Compiler

新的最小 XNull 编译器。当前 XDK-first 产品计划见 [`../xdk/PLAN.md`](../xdk/PLAN.md)，
编译器支持队列见 [`PLAN.md`](PLAN.md)，已完成的小里程碑记录见 [`MILESTONES.md`](MILESTONES.md)。

```sh
./build.sh
./mini --version
```

当前版本 **Mini 0.3.0 / M10-T0**：T0 XDK 包已有可运行场景、base/full 矩阵和
200M 性能门禁。`mini 0.2.0 / M9-CUT` 的自举固定点、默认切换和 47 个 M9-PAR
场景已完成并归档。

- 自身源码已能被 mini 编译，`mini1` 与 `mini2` 生成的 C 完全一致。
- 泛型函数/泛型类、插值字符串、nullable、throw、Double、位运算和静态类方法已进入最小面。
- `build.sh` 优先用已有 `bin/mini` 自编译；没有种子二进制时回退 legacy bootstrap。
- 资源表、项目 `.xfb` 无参标量、`check --json`、简单工程模式已接通。
- M9-PAR 正向场景差分已完成（47 个文件/工程场景，stdout/stderr/退出码全绿）；M9-CUT 已切换默认命令到 mini，legacy 保留为 `--engine=legacy` oracle；完整 T0 XDK 仍需 package/Resource/Context 面。

## 里程碑

- **2026-11-19 · `mini 0.3.0` / M10-T0**：XDK-first 的 T0 包进入可运行状态；
  并发、资源/Context、集合泛型、log/config/cli 均有场景；base/full 矩阵与
  200M 性能门禁进入回归。见 [`MILESTONES.md`](MILESTONES.md)。
- **2026-11-18 · `mini 0.2.0` / M9-CUT**：第一个完整跑通
  「语言源码 → mini 编译器 → C → 可执行程序」的 mini；自举固定点通过，
  默认引擎切换到 mini，legacy 保留为 oracle。验收记录和性能曲线见
  [`MILESTONES.md`](MILESTONES.md)。
- 旧计划归档：[`archive/2026-11-18-m9cut/`](archive/2026-11-18-m9cut/)。

## 回归

```sh
for t in src/mini/tests/*.sh; do "$t"; done
```

当前 26 个回归覆盖 lex、parser、sema、codegen、class、flow、array、containers、
result、defer、m6_4、xdk、check、project、ffi、resources、object_list、selfhost、
generics、c4、m7_sys、m8、parity、m9_parity、m9_cut 和 xfb_error；另有
`m10_parity`（T0 base/full 矩阵）和 `m10_perf`（200M 性能门禁）。

## 构建

`build.sh` 的 bootstrap 路径仍保留 legacy 回退；自举路径使用 `.cache/xnull/` 的运行时库缓存，
但编译器 C 由当前 mini 直接生成。源码不变时自举构建约数秒。
