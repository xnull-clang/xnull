# Mini 1.0 恢复计划

> 重启电脑后从这里继续。不要重新写计划，不要再从 M0 开始。

## 当前基线

```text
分支:          dev
HEAD:          以 `git rev-parse dev` 为准
远端 dev:      与本地 dev 同步
main:          1a0a5041（稳定基线，暂不接收日常改动）
reset/minimal: 1a0a5041
```

当前工作区应当干净。最近提交：

```text
e65f8670 feat(mini): add basic data enum support
4d0ec330 docs(mini): reorder M9-FULL execution plan
1cb85ed2 feat(mini): add static class inheritance
b675f154 feat(mini): enforce enum switch exhaustiveness
1d0d39c4 docs(mini): record label/goto slice
```

P0 自举可复现性已关闭：`m8.sh` 使用测试私有的
`XNULL_MODEL_DIR`/`XNULL_TOOL_DIR`，即使 `/tmp` 里残留旧的
xpd/reactor/tools 也不会掩盖冷启动失败。计时口径：热 C 缓存/冷工具
m8 约 43s，全新 C 缓存约 127s；21 回归约 100s，加入 parity 后 22 项约 159s。

## 工作安排速览

```text
D1  M8-P4 完成
D2  M8-P5 完成
D3  M9-C2 完成
D4  M9-C3 完成
D5  XDK 集成 完成
D6  选定 M9-PAR 完成
D7  Mini 1.0 收口 完成
```

D1–D7 已完成，Mini 1.0 / M9-MIN 收口完成。**这不等于 M1–M9 或 M9-FULL 完成**。
M8-P4/P5 已完成；M9-FULL 从 M9-C4 余量开始，按
**M9-C4 → M9-C2/C3 → M7-F3 → M7-F1 → M7-F2/F4 → M9-PAR → M9-CUT** 顺序执行。

## 重启恢复命令

```sh
cd /Users/vjs/Desktop/XNull-Lang
git switch dev
git fetch origin --prune
git pull --ff-only origin dev
./src/mini/build.sh
```

如果本机没有 `src/mini/bin/mini` 种子二进制，使用：

```sh
XNULL_MINI_BOOTSTRAP=legacy ./src/mini/build.sh
```

冷启动 legacy 回退可能较慢；有种子时 `build.sh` 走自编译。

## 冻结回归

每次提交前至少执行：

```sh
for t in lex parser sema codegen class flow array containers result defer m6_4 xdk check project ffi resources object_list selfhost generics c4 m8 parity; do
  ./src/mini/tests/$t.sh || exit 1
done
```

当前 22 个回归全部 PASS，`selfhost` 固定点 PASS。`m8.sh` 现在会
在测试临时目录内从头构建 xpd/xmanifest/reactor 和构建工具，不依赖
`/tmp` 旧缓存。

## 当前范围

当前目标是 **Mini 1.0**：

- mini 自举固定点
- M8 工程接口
- `text/full`
- `io/base`
- errors/runtime/meta 基础面
- 选定场景的新旧差分

暂不包含：

- 完整 `io/system/Sys.x` raw FFI
- 全部 T0 XDK
- 完整 M9-C4
- 全量 M9-PAR
- 默认引擎切换

## 下一阶段执行顺序

### D1：M8-P4 收口（已完成）

目标：先修交付口径，再实现 workspace lock；外部依赖只做负例，不扩大
Mini 1.0 的包管理范围。状态：完成。验证：默认 CLI 不带 `--bootstrap`
可用；workspace lock/`--check`/`--update` 通过；外部依赖 `LOCK-002` 且不写锁；
install 两次 `.xlib` SHA 一致且与 lock 摘要一致；22 回归 + selfhost 全绿；
m8 热 C 缓存约 43s、全新 C 缓存约 127s。以下保留执行记录，不设独立审批门：

1. **默认 CLI 与工具目录**：没有 `impl/` 或没有 go 时自动 bootstrap；
   `prepare_model`/`prepare_graph`/`xmeta`/`tree`/`why` 统一使用
   `XNULL_MODEL_DIR`/`XNULL_TOOL_DIR`；补不带 `--bootstrap` 的 build/run 回归。
2. **fixture**：workspace 依赖可解析/构建/安装；外部仓库依赖只验证
   `LOCK-002`；补缺版本、缺坐标、锁文件不一致负例。
3. **workspace lock**：先补一页规范，定义 `repository = workspace`、entry
   坐标升序、确定性 `.xlib` SHA-256、`--check` 不写和 `--update` 才重写；
   再实现 lock 输出与一致性检查。外部依赖 `LOCK-002` 且不写锁。
4. **install/repro**：`install` 产出确定性 `.xlib`，两次 SHA 一致；lock 摘要
   与安装产物一致；`repro` 两次构建 SHA 一致。
5. **回归与文档**：扩展 m8，记录热/冷缓存，跑 21 回归 + selfhost，更新
   PLAN/RESUME，一次提交 `dev`。

验收：

```sh
./src/cli/xnull --engine=legacy build src/examples/hello.x   # 不带 --bootstrap
./src/mini/tests/m8.sh
./src/cli/xnull --bootstrap --engine=legacy lock --check <workspace-fixture>
./src/cli/xnull --bootstrap --engine=legacy repro <workspace-fixture>
```

失败负例：

- 依赖版本不存在
- 坐标缺失
- 锁文件与清单不一致
- 外部仓库依赖：`LOCK-002`，且不写锁

边界：

- 不做“从本地仓库成功解析外部依赖”；那是新的包管理工作包。
- 本地仓库只用于 `install` 产物和摘要校验。
- 默认引擎仍是 `legacy`；`main` 不接收未过门的改动。
- D1 保留 `LOCK-002` 作为临时内部码；XPD-4xx 具体映射留后续规范。

### D2：M8-P5 诊断与退出码矩阵
状态：完成（CLI/SEM/JSON/退出码矩阵；外部 lock `XPD-401`、锁不一致 `XPD-402`，保留 `LOCK-002` 兼容别名）。

目标：

- 统一 `CLI-*`、`SEM-*`、`XPD-*` 诊断输出；外部 lock 保留 `LOCK-002` 别名。
- 覆盖退出码：

```text
0   成功
1   编译/语义/构建失败
2   用法或清单错误
130 中断
134 程序 fatal
```

重点文件：

```text
src/toolchain/json_result.py
src/toolchain/xnull-build.sh
src/cli/xnull
src/mini/tests/m8.sh
src/mini/tests/check.sh
```

验收：

- `build/run/check --json` 的 `diagnostics` 字段稳定。
- JSON 与 stderr 的诊断位置一致。
- 失败时 stdout 不混入非 JSON 文本。

### D3：M9-C2 String 面
状态：完成。

目标：

- 补齐 `trim`、`replace`、`toUpper`、`toLower`。
- 覆盖 UTF-8 边界和空串。
- 增加文本场景，保持 `xdk.text` 走 `text/full`。

重点文件：

```text
src/mini/main.x
src/mini/tests/features.x
src/mini/tests/xdk.sh
```

验收：

- `./src/mini/tests/c4.sh`
- `./src/mini/tests/xdk.sh`
- 新文本场景通过。

### D4：M9-C3 泛型面
状态：完成。

目标：

- 泛型函数推断和多类型参数。
- 嵌套泛型类实例化。
- 函数类型参数的边界。
- 对不支持项给明确负例，不静默通过。

重点文件：

```text
src/mini/main.x
src/mini/tests/generics.x
src/mini/tests/generics.sh
```

验收：

- `generics.sh` 扩展场景通过。
- selfhost 固定点不漂移。

### D5：XDK 集成
状态：完成。`xdk_integration.x` 覆盖 text/sys/errors 组合；`xdk.sh` 同时校验 `src/xdk` 与 `xdk/lib/xdk`；resources/errors 场景通过。

目标：

- `text/full`、`io/base`、resources、errors 组合场景。
- 验证 `src/xdk` 与 `xdk/lib/xdk` 同步。
- 不在本阶段引入新的 mini 专用 XDK shim。

验收：

```sh
./src/mini/tests/xdk.sh
./src/mini/tests/resources.sh
diff -qr src/xdk xdk/lib/xdk
```

### D6：选定 M9-PAR
状态：完成。`parity.sh` 覆盖 16 个代表性场景，legacy/mini 的 stdout、stderr、退出码均为 `diff=0`。

目标：

- 选 10–20 个代表性场景，比较 legacy 与 mini 的：
  - stdout
  - stderr
  - 退出码
- 不追求全量 legacy 差分。

### D7：Mini 1.0 收口
状态：完成。22 个回归、selfhost、m8 冷缓存（约 127s）、选定 parity 全绿；默认引擎仍为 `legacy`。

必须全部满足：

```text
22 个 mini 回归全绿
mini selfhost 固定点 PASS
m8.sh PASS
选定 M9-PAR PASS
main 默认仍是 legacy
工作区 clean
```

## 下一阶段（M9-FULL）

Mini 1.0 / M9-MIN 已完成，M8-P4/P5 已完成。M9-FULL 严格按以下顺序执行：

1. **M9-C4 收口**：data enum → protocol 动态派发 → lambda。
2. **M9-C2/C3 余量**：完整 String API、泛型约束和边界负例。
3. **M7-F3**：完整 `io/system` raw FFI、handle/Bytes/Result C 编译。
4. **M7-F1**：通用 `.xfb` 参数/返回值、租约、错误码。
5. **M7-F2/F4**：`text/full` 余量和 T0 包按 import 场景接入。
6. **M9-PAR**：全量 stdout/stderr/退出码差分。
7. **M9-CUT**：仅 M9-PAR 全绿且用户批准后切换默认引擎。

每步必须全绿后再进入下一步；M9-C4/M7/PAR 未完成前不切默认引擎。

## 已知阻塞/边界

- P0 自举路径已修复并加入冷启动隔离；旧的 `61eb86c9` 基线不能直接作为 D1 起点。
- `io/system/Sys.x` 的完整 raw FFI 还没有做参数/句柄/返回值完整映射；当前 `xdk.sys` 使用 `io/base`。
- `io/system/Sys.x` 的 sema 已能通过，但 emit C 仍有 raw FFI 原型/句柄错误。
- M9-C4：基础 `switch`（Int/String/Bool/枚举穷尽性）、`do-while`、`..<`/`...` range、label/goto、静态类继承、基础 data enum 已接入；protocol 动态派发、lambda 未完成。
- 全量 T0 XDK 和全量 M9-PAR 不属于 Mini 1.0 当前范围。

## 工作量口径

```text
Mini 1.0 剩余:     0 dev-day（D1–D7 已完成）
当前到完整 M9:     30–50 dev-day（M9-FULL）
从 0 到完整 M9:    60–90 dev-day
```

当前不按 M9-FULL 的 60–90 天开工；按 D1–D7 的 Mini 1.0 范围推进。

## 执行纪律

- 每个切片必须同时有代码、场景、回归、提交。
- 多个会话不要同时写同一个 `dev` 工作区；并行时各自使用独立 worktree，
  合并前必须重新跑冷启动 m8 和 22 回归。
- 不在工作包内临时扩大范围。
- 发现新缺口登记到 `PLAN.md` 后续包，不阻塞当前 D1–D7。
- 每个工作包完成后更新本文件和 `PLAN.md` 的状态，再进入下一包。
