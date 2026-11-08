# S8-16 自检结论（CLI P0 + 版本体系）

## 交付

`impl/internal/version`（新包）：
- `Base=0.1.0-dev`、`ABI=v1`、`SpecSet=S1 v3.3.0 … S8 v5.2.0`；`Commit`/`BuildDate` 可用 `-ldflags -X` 注入（未注入回退 `dev`/`unknown`）；
- `Full()` 返回 `<Base>[+<commit 前 7 位>]`；`Info()` 输出版本/commit/日期/规范集/ABI。

`impl/internal/cli/cli.go`：
- `Version` 从硬编码常量改为 `version.Full()`（`.xmeta.toolchainVersion` 自动记录完整版本，含短哈希；未改 `cli/manifest.go`）。
- `xnull version` 与 `xnull --version`：输出完整版本信息（同一实现）。
- `xnull fmt`：显式 `.x` 路径走 `internal/xnfmt`；`--check` 只检查（有差异 exit 1，不写文件）；清单/锁/元数据仍走原 `runFmt`。
- `xnull clean [dir]`：删除 `target/`；`--all` 追加清理本地仓库缓存（`XNULL_REPO` 或 `~/.xnull/repository`）。
- `xnull doctor [dir]`：cc / runtime / 本地仓库 / 清单 / 锁五项自检，`[ok]/[warn]/[fail]` 分级，fail 才 exit 1。
- `knownFlags` 注册 `--all`。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前四项用例全部失败（命令未知 / `--all` 未知标志 / fmt 走清单解析报错，`red.txt`） |
| 绿 | `TestFmtSource`（--check 不写、写回正确、已格式化 0）、`TestClean`（target 清理、--all 清仓库缓存）、`TestVersionOutput`（version/--version 五字段）、`TestDoctor`（五项齐全且 exit 0） |
| ldflags | `-X ...Commit=abc1234def5678 -X ...BuildDate=2026-11-08` → `xnull 0.1.0-dev+abc1234` |
| `.xmeta` | 同二进制构建：`toolchainVersion = 0.1.0-dev+abc1234` |
| 全量 `go test ./...` | **红**：`codegen`、`codegen-ffi`（与上卡 S8-14 基线完全同集，新增 0） |

## 缺口

1. `clean` 只清本工程 `target/` 与本地仓库，不遍历聚合子模块（聚合根一次 clean 后再逐个模块 clean，S8-17+ 可补）。
2. `doctor` 的 repo 检查只验证目录存在，不验证可写/权限。
3. `fmt` 默认路径扫描不含 `.x`（只处理显式 `.x` 路径）；批量格式化 `.x` 需显式列文件。
4. 版本策略：B4 前保持 `0.x`；`SpecSet` 为常量，规范升版需同步改 `version.go`。
