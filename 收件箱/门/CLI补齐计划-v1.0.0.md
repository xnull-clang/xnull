# CLI 补齐计划（v1.0.0）

> 日期：2026-11-08 17:50
> 现状：`new/check/build/run/test/fmt/lock/policy/dev` 九个命令；`fmt` 只格式化清单类文件，不格式化 `.x` 源码。
> 目标：补齐到可用工具链，而不是堆命令。

## 一、P0（开发者每天会用）

| 命令 | 作用 | 依赖 | 归属 |
|---|---|---|---|
| `xnull fmt <path>` | 格式化 `.x` 源码（调用现有 xnfmt），`--check` 只检查 | 无 | E6 |
| `xnull clean` | 清理 `target/`、缓存，`--all` 连本地仓库缓存 | 无 | E6 |
| `xnull version` | 工具链版本、规范版本、ABI 版本、commit | 无 | E6 |
| `xnull doctor` | 环境自检：cc、runtime、仓库、清单、锁 | 无 | E6 |
| `xnull install` | 产物安装到本地仓库（`.xlib`/app） | S8-13 | E6 |
| `xnull tree` | 依赖树（GAV/版本/仲裁结果） | S8-13 | E6 |
| `xnull why <GAV>` | 解释某依赖为何被引入（路径/仲裁） | S8-13 | E6 |

## 二、P1（工程化）

| 命令 | 作用 | 依赖 |
|---|---|---|
| `xnull add/remove` | 编辑清单依赖（保持格式与排序） | S8-13 |
| `xnull update [--lock]` | 受控更新锁/依赖 | S8-13 |
| `xnull vendor` | 依赖落盘到工程内 | S8-13 |
| `xnull lint` | 在 check 之上做风格/死代码/未使用导入 | 无 |
| `xnull doc` | 生成 XDK/工程 API 文档 | 无 |
| `xnull completion bash/zsh` | shell 补全 | 无 |
| `xnull test --filter/--list` | 测试筛选与枚举 | 无 |

## 三、P2（IDE/高级）

| 命令 | 作用 | 说明 |
|---|---|---|
| `xnull lsp` | 语言服务器（替代扩展直接调 CLI） | 第 10 部分，B4 后 |
| `xnull repl` | 交互式解释执行 | 可选 |
| `xnull audit` | 依赖/许可/安全审计 | 需仓库生态 |
| `xnull migrate` | 旧工程/旧清单迁移 | 按需 |

## 四、顺序与边界

1. **P0 的 fmt/clean/version/doctor 不依赖 S8-13，可先做**；
2. `install/tree/why` 依赖 S8-13（`.xlib` + 本地仓库），排在其后；
3. P1 依赖 S8-13；
4. P2 在 B4 后，不阻塞自举；
5. 全部命令保持：退出码 0/1/2/130、`--json` 机器接口、中文错误信息。

## 五、卡拆分

| 卡 | 内容 | owner | 依赖 |
|---|---|---|---|
| S8-16 | P0 无依赖四项：`fmt .x`、`clean`、`version`、`doctor`；含版本体系 | E6 | 无 |
| S8-17 | `install`、`tree`、`why` | E6 | S8-13 |
| S8-18 | `add/remove`、`update`、`vendor` | E6 | S8-13 |
| S8-19 | `lint`、`doc`、`completion`、`test --filter` | E6 | 无（可并行后置） |
| S8-20 | `lsp`、`repl`、`audit`、`migrate` | E6+E2 | B4 后 |

> 以上全部排 E6，因为 CLI 是单写者；E6 当前在 S8-12，S8-16 排在 S8-12 之后。

## 六、版本体系（并入 S8-16）

现状：`impl/internal/cli/cli.go` 硬编码 `Version = "0.1.0-dev"`，无 `version` 命令、无 commit/日期/规范集/ABI 版本。

目标：

1. 新增 `impl/internal/version` 包：`Version`、`Commit`、`BuildDate`、`SpecSet`、`ABIVersion`；
2. 构建时用 `-ldflags -X` 注入 commit/date，未注入时回退 `dev`；
3. `xnull version` 与 `xnull --version` 输出：
   - 工具链版本（semver）
   - commit / 构建日期
   - 规范集：S1 v3.3.0 … S8 v5.2.0
   - 运行时 ABI：v1
4. `.xmeta` 的 `toolchainVersion` 记录完整版本（含 commit 短哈希）；
5. 版本策略：B4 前保持 `0.x`；B4 门通过后升 `1.0.0`；规范版本独立，不跟随工具链。
