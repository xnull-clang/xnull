# Mini 1.0 恢复计划

> 重启电脑后从这里继续。不要重新写计划，不要再从 M0 开始。

## 当前基线

```text
分支:          dev
HEAD:          04c4d1a3
远端 dev:      04c4d1a3
main:          1a0a5041（稳定基线，暂不接收日常改动）
reset/minimal: 1a0a5041
```

当前工作区应当干净。最近提交：

```text
04c4d1a3 fix(mini): handle zero-argument Ok in semantic check
cac3564d docs(mini): add Mini 1.0 seven-day execution plan
14137442 refactor(mini): remove XDK shims and use base sys surface
51a7666a refactor(mini): remove unused shims and switch text to full XDK
```

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
for t in lex parser sema codegen class flow array containers result defer m6_4 xdk check project ffi resources object_list selfhost generics c4 m8; do
  ./src/mini/tests/$t.sh || exit 1
done
```

当前 21 个回归全部 PASS，`selfhost` 固定点 PASS。

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

### D1：M8-P4 外部依赖/本地仓库/lock/install/repro

目标：

- 增加一个**外部依赖 fixture**，使用本地仓库，不访问网络。
- 验证 `lock` 记录依赖坐标与摘要。
- 验证 `install` 从本地仓库生成可用 `.xlib`。
- 验证 `repro` 连续两次构建 SHA 一致。

重点文件：

```text
src/toolchain/xnull-build.sh
src/toolchain/pack_xlib.py
src/toolchain/json_result.py
src/mini/tests/m8.sh
新增 fixture 目录
```

验收：

```sh
./src/mini/tests/m8.sh
./src/cli/xnull --bootstrap --engine=legacy lock --check <fixture>
./src/cli/xnull --bootstrap --engine=legacy repro <fixture>
```

失败负例：

- 依赖版本不存在
- 坐标缺失
- 锁文件与清单不一致

### D2：M8-P5 诊断与退出码矩阵

目标：

- 统一 `CLI-*`、`SEM-*`、`PROJ-*` 诊断输出。
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

目标：

- 选 10–20 个代表性场景，比较 legacy 与 mini 的：
  - stdout
  - stderr
  - 退出码
- 不追求全量 legacy 差分。

### D7：Mini 1.0 收口

必须全部满足：

```text
21 个 mini 回归全绿
mini selfhost 固定点 PASS
m8.sh PASS
选定 M9-PAR PASS
main 默认仍是 legacy
工作区 clean
```

## 已知阻塞/边界

- `io/system/Sys.x` 的完整 raw FFI 还没有做参数/句柄/返回值完整映射；当前 `xdk.sys` 使用 `io/base`。
- `io/system/Sys.x` 的 sema 已能通过，但 emit C 仍有 raw FFI 原型/句柄错误。
- 完整 M9-C4：switch、data enum、继承、lambda、do/for-range、标签控制未完成。
- 全量 T0 XDK 和全量 M9-PAR 不属于 Mini 1.0 当前范围。

## 工作量口径

```text
Mini 1.0 剩余:     6–10 dev-day
当前到完整 M9:     30–50 dev-day（M9-FULL）
从 0 到完整 M9:    60–90 dev-day
```

当前不按 M9-FULL 的 60–90 天开工；按 D1–D7 的 Mini 1.0 范围推进。

## 执行纪律

- 每个切片必须同时有代码、场景、回归、提交。
- 不在工作包内临时扩大范围。
- 发现新缺口登记到 `PLAN.md` 后续包，不阻塞当前 D1–D7。
- 每个工作包完成后更新本文件和 `PLAN.md` 的状态，再进入下一包。
