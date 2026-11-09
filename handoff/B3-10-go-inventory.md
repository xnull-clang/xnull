# B3-10-05 Go 删除清单（B4a/B4b/B4c 执行版）

- **基线**：`main` `1d353aa`（B3-09 门 PASS 后）；`pod/e4-codegen` 已快进到同一提交。
- **依据**：`handoff/B3-10-plan-v1.0.1.md`、`handoff/B3-10-plan.md`、`handoff/B3-xnullc-plan.md`、ADR-001、ADR-009、`收件箱/门/B3-09门.md`。
- **性质**：只读盘点。未改生产代码、未删任何文件。
- **明细**：`handoff/B3-10-go-inventory.tsv`，共 **368 行** = 362 个受跟踪 `.go` + 6 个构建/CI 相关非 Go 目标。
- **结论**：B4a 前 **codegen / codegen/ffi / sema / xfront / frontbridge / interp / diag / cmd/xnast 一律不能删**；B4b 只替换 CLI/工程工具链；B4c 才删 Go。

## 1. 数量总表

| 类别 | TSV 行 | 其中 .go | 其中非 .go | Go 行数 | 含义 |
|---|---:|---:|---:|---:|---|
| `keep` | 82 | 82 | 0 | 38,397 | B4a 固定点验证仍需的 Go oracle / 自举种子 |
| `replace` | 40 | 37 | 3 | 10,464 | B4b 由 XNull CLI/devtool/工程工具链接管 |
| `delete` | 217 | 214 | 3 | 28,335 | B4c 固定点冻结后删除（含 210 个 `_test.go`） |
| `evidence` | 29 | 29 | 0 | 4,623 | 历史证据/归档，只读保留 |
| **合计** | **368** | **362** | **6** | **81,819** | 362 个 `.go` 中 133 个生产文件、229 个测试文件 |

补充：

- `impl/go.sum` **不存在**；`impl/go.mod` 仅 `module xnull.dev/xnull` + `go 1.27`，零外部依赖。删除 `go.mod` 不需要清理依赖，但删除后无法再从源码重建 Go oracle。
- 仓库**没有 Makefile**，也没有 `go.work`；活跃 Go 构建入口是 `ci/run.sh`、`impl/runtime/build_rt.sh`、`scripts/build_release.sh`、`difftest/golden/build-tools.sh`，测试入口是 `tests/b3/*.sh` 等脚本。
- `delete` 的 214 个 `.go` 中，210 个是 `_test.go`（209 个在 `impl/`，1 个在 `difftest/`），4 个是生产工具：`impl/cmd/xnpt/main.go`、`impl/cmd/xnselfhost/main.go`、`impl/internal/xdkcheck/xdkcheck.go`、`difftest/golden/astdump/main.go`。
- `replace` 的 3 个非 Go 目标：`impl/runtime/build_rt.sh`、`scripts/build_release.sh`、`tests/b3/xnullc-all.sh`。

## 2. 分组矩阵

| 分组 | 总数 | keep | replace | delete | evidence | 处置 |
|---|---:|---:|---:|---:|---:|---|
| `codegen` | 84 | 32 | 0 | 52 | 0 | keep 32 个生产文件；52 个测试 B4c 删 |
| `codegen/ffi` | 16 | 6 | 0 | 10 | 0 | keep 6 个生产文件；10 个测试 B4c 删 |
| `sema` | 76 | 13 | 0 | 63 | 0 | keep 13 个生产文件；63 个测试 B4c 删 |
| `xfront` | 16 | 8 | 0 | 8 | 0 | keep 8 个生产文件；8 个测试 B4c 删 |
| `frontbridge` | 9 | 3 | 0 | 6 | 0 | keep 3 个生产文件；6 个测试 B4c 删 |
| `interp` | 45 | 18 | 0 | 27 | 0 | keep 18 个生产文件（xn-s1 种子）；27 个测试 B4c 删 |
| `diag` | 2 | 1 | 0 | 1 | 0 | 共享诊断类型随 oracle 保留 |
| `cmd/xnast` | 1 | 1 | 0 | 0 | 0 | B4a 的 AST oracle |
| `cli` | 28 | 0 | 9 | 19 | 0 | B4b 整体替换；19 个测试 B4c 删 |
| `devtool` | 10 | 0 | 5 | 5 | 0 | B4b 整体替换；5 个测试 B4c 删 |
| `manifest` | 8 | 0 | 4 | 4 | 0 | B4b 整体替换 |
| `resman` / `reactor` / `config` / `plugin` / `repro` / `artifact` / `xmeta` | 各 2 | 0 | 各 1 | 各 1 | 0 | B4b 替换生产文件；测试 B4c 删 |
| `xpd` | 10 | 0 | 6 | 4 | 0 | B4b 替换 XPD 解析/规范化 |
| `xnfmt` + `cmd/xnfmt` | 5 | 0 | 3 | 2 | 0 | 由 `impl/xnfmt/xnfmt.x` 接管 |
| `version` / `exitcode` / `cmd/xnull` | 各 1 | 0 | 各 1 | 0 | 0 | XNull CLI 元数据/退出码/主入口 |
| `xdkcheck` | 2 | 0 | 0 | 2 | 0 | `go test` 驱动的合同检查，B4c 删除 |
| `cmd/xnpt` / `cmd/xnselfhost` | 各 1 | 0 | 0 | 各 1 | 0 | 无对等物，B4c 删除 |
| `build/CI` | 6 | 0 | 3 | 3 | 0 | `go.mod`/CI/golden 构建删除；运行时/发布/测试脚本替换 |
| `difftest` | 2 | 0 | 0 | 2 | 0 | QA golden 工具与独立用例，B4c 迁移后删 |
| `evidence` | 13 | 0 | 0 | 0 | 13 | 只读 |
| `归档参考草稿` | 16 | 0 | 0 | 0 | 16 | 只读归档 |

## 3. `keep`：B4a 不能删的 82 个生产文件

| 包/文件 | 数量 | 行数 | 作用 | 为什么 B4a 必须留 |
|---|---:|---:|---|---|
| `impl/internal/codegen/*.go` | 32 | 16,623 | C 发射器：prelude、表达式/语句、类/容器/泛型/元组/协议、S3–S7 内建面 | B3-09 的 141 入口 0 diff 基准；B4a 差分需要 Go C 文本 |
| `impl/internal/codegen/ffi/*.go` | 6 | 2,584 | `.xfb` 词法/语法/合同/包装生成 | FFI 入口与 `xn_ffi_*` 文本基准 |
| `impl/internal/sema/*.go` | 13 | 8,467 | 类型检查、确定赋值、Result/错误、逃逸/策略、包/XDK 符号 | 负例诊断与策略输入由 sema 决定；xnullc 不重复源码 sema |
| `impl/internal/xfront/*.go` | 8 | 4,707 | lexer/parser/AST/printer/xnast 规范文本 | B2 AST oracle；`xnast --ast` 是 B3-10 自编译输入 |
| `impl/internal/frontbridge/*.go` | 3 | 1,226 | Go↔XNull 前端桥、AST bundle、反序列化 | B2/B3 差分与 bundle 入口 |
| `impl/internal/interp/*.go` | 18 | 4,669 | tree-walking 解释器与 XDK 语义 | **B3-10-01 用 interp 生成 xn-s1**；删了就无法从源码重建种子 |
| `impl/internal/diag/diag.go` | 1 | 52 | 诊断结构/渲染 | sema/xfront/codegen 共享类型 |
| `impl/cmd/xnast/main.go` | 1 | 69 | token/AST/诊断规范文本 CLI | B3-10 的 `xnast --ast` 命令 |

关键文件：

- `impl/internal/codegen/codegen.go`：`gen`/`scope` 两遍发射核心，4934+ 行；C 文本排序/临时编号的基准。
- `impl/internal/codegen/classes.go`、`containers.go`、`protocol.go`、`generics.go`、`tuple.go`、`stack.go`：对象/容器/泛型/内存策略的 oracle 面。
- `impl/internal/sema/typedecl.go`、`ty.go`、`error.go`、`escape.go`、`policy.go`：负例诊断与 `Strategy` 的来源。
- `impl/internal/xfront/parser.go`、`ast.go`、`xnast.go`：B2 AST 与规范文本。
- `impl/internal/interp/interp.go`：xn-s1 的唯一源码级种子路径（`xnull run --interp`）。

> **硬规则**：B4a 判定 PASS 前，上述 82 个文件一个都不能删；B4a 通过后也只进入 B4c 批次，不在 B4b 顺手删除。

## 4. `replace`：B4b 的 37 个 Go 生产文件 + 3 个构建目标

| 范围 | 文件 | XNull 接管物 | 阻塞点 |
|---|---|---|---|
| CLI 主入口/命令 | `impl/cmd/xnull/main.go`、`impl/internal/cli/*.go`（9 个） | XNull CLI（`new/check/build/run/test/fmt/lock/install/tree/why/dev`），由 xn-s2 构建 | 命令/退出码/诊断/`--json` 逐项对等；`impl/internal/cli/cli.go` 的 13 个依赖包必须先替换 |
| devtool | `impl/internal/devtool/*.go`（5 个） | XNull `xnull dev check/ledger/res/board/test` | 台账/看板/规范守门与 Python/Go golden 逐字节一致；`board` 的 SSOT 生成不能断 |
| 清单/锁/XPD | `impl/internal/manifest/*.go`（4）、`impl/internal/xpd/*.go`（6）、`impl/internal/xmeta/xmeta.go` | XNull 清单/锁/元数据解析与校验 | XPD 文法、继承链、profile、锁字节稳定性；S8 夹具需迁移 |
| 资源/聚合/配置 | `impl/internal/resman/resman.go`、`impl/internal/reactor/reactor.go`、`impl/internal/config/config.go` | XNull 对应子系统 | S8 资源 glob、pom 拓扑、五层配置覆盖 |
| 插件/可复现/产物 | `impl/internal/plugin/plugin.go`、`impl/internal/repro/repro.go`、`impl/internal/artifact/artifact.go` | XNull 对应子系统 | `.xplugin` 执行策略、`.xmeta` 摘要、`.xlib` 布局 |
| 格式化 | `impl/internal/xnfmt/*.go`（2）、`impl/cmd/xnfmt/main.go` | `impl/xnfmt/xnfmt.x`（B1 已存在） | `--check` 退出码、原子批处理、FMT-104 文案 |
| 版本/退出码 | `impl/internal/version/version.go`、`impl/internal/exitcode/exitcode.go` | XNull CLI 常量/构建元数据 | 版本注入方式（Go `-ldflags` 需换成 XNull 构建描述） |
| 运行时资源表 | `impl/runtime/build_rt.sh:75,90` | XNull `dev res` | **P0 隐藏依赖**：C 运行时构建本身在调 `go run ./cmd/xnull dev res` |
| 发布构建 | `scripts/build_release.sh:9-10` | XNull 构建 xn-s2 + xnfmt.x | 发布物必须由自举二进制生成，不能继续 `go build` |
| B3 测试 harness | `tests/b3/xnullc-all.sh:36-37`（同组 20+ 脚本） | xn-s2 + XNull xnast；冻结 golden C | 141 入口/98 负例/9 示例的参考 C 必须先冻结 |

**替换顺序原则**：先侧车并行（XNull CLI 与 Go CLI 同时可跑）→ 切换默认入口 → 保留 `XNULL_ORACLE=1` 回退 → B4c 再删 Go 实现。不要先删 `impl/internal/cli` 再补功能，`cmd/xnull` 的依赖闭包会让整个 Go 构建立刻红。

## 5. `delete`：B4c 的 217 行

### 5.1 测试（210 个 `.go`）

- `impl/internal/codegen/*_test.go` 52、`codegen/ffi/*_test.go` 10、`sema/*_test.go` 63、`xfront/*_test.go` 8、`frontbridge/*_test.go` 6、`interp/*_test.go` 27、`cli/*_test.go` 19、`devtool/*_test.go` 5、`manifest/*_test.go` 4、`xpd/*_test.go` 4，以及 `cmd/xnfmt/main_test.go`、`diag`/`resman`/`reactor`/`config`/`plugin`/`repro`/`artifact`/`xmeta`/`xnfmt`/`xdkcheck` 各 1。
- `difftest/anchors/cases/qa2_pkg_accept_test.go` 1 个。
- **前置**：每个测试的断言必须先转成 XNull 测试或冻结为 evidence；尤其 codegen 的 C 文本断言、sema 的 98 负例、interp 的 9 示例行为。

### 5.2 Go 专用工具（4 个）

| 文件 | 原因 | 删除前动作 |
|---|---|---|
| `impl/cmd/xnpt/main.go` | M5.1-c 解析对照，B2 AST diff 已覆盖 | 确认无脚本引用 |
| `impl/cmd/xnselfhost/main.go` | frontbridge xnull 模式的外部自举解释器 | 先退役 frontbridge xnull 模式，或改由 XNull CLI `run --interp` |
| `impl/internal/xdkcheck/xdkcheck.go` | 以 `go test ./...` 驱动 XDK 合同检查 | 合同条目迁到 XNull 测试；否则记录为 B4c 已知损失 |
| `difftest/golden/astdump/main.go` | QA golden 的 xfront overlay 工具 | 冻结 golden 输出后删 |

### 5.3 构建/CI（3 个非 Go 目标）

- `impl/go.mod`：删除前确认 xn-s2 可独立构建；`go.sum` 不存在，无需清理。
- `ci/run.sh`：01 `gofmt+vet`、02 `go test`、04 `frontbridge` 差分三个 Go 步骤必须替换；05–09 仍是 SKIP 桩，不能把“删 Go”当成“CI 已迁移”。
- `difftest/golden/build-tools.sh`：`go build xnull + astdump`，与 astdump 同批删除。

### 5.4 B4c 删除顺序

1. 冻结 evidence：141 入口 C 文本、98 负例诊断、9 示例 stdout/exit、xparser/xnullc 的 SHA-256。
2. 迁移测试：`tests/b3/*.sh`、`tests/b2/*.sh`、`tests/s3/run.sh`、`tests/b0-07c-numeric/run.sh` 中所有 `go build`/`go test` 改为 xn-s2/XNull 测试入口。
3. 删测试：210 个 `_test.go`。
4. 删 Go 专用工具：`xnpt`、`xnselfhost`、`xdkcheck`、`astdump`。
5. 删构建：`go.mod`、`ci/run.sh` 的 Go 步骤、`difftest/golden/build-tools.sh`。
6. 终检：活跃脚本中 `go build|go test|go run|go vet|gofmt` 为 0；`git ls-files '*.go'` 只剩 `evidence/` 与 `收件箱/_归档/`。

## 6. `evidence`：29 个只读文件

- `evidence/INTEG-e2-sema/probe/*.go` 3、`evidence/INTEG-final-e2/probe/*.go` 4、`evidence/M1-PKG-01-qa/*.go` 1、`evidence/M1-TUPLE-01-qa/qa-tests/*.go` 4、`evidence/NEG-3/neg_test.go` 1：历史 QA 探针/独立验收快照。
- `收件箱/_归档/2026-11-07/旧回执/E6/参考草稿-B-full-2026-11-07/**/*.go` 16：B-full 迁移前 E6 参考草稿（含 2 套 devtool 副本）。
- 规则：只读；不参与构建；不作为 B4 验收输入；归档材料不得因“去 Go”被恢复或重新编译。

## 7. 三阶段前置与门禁

### B4a（不动点，24h）

**前置**

- B3-10-01..04 全部 PASS：xn-s1/s2/s3 可执行，xn-s2.c == xn-s3.c，xn-s3.c == xn-s4.c；9 示例、B3-09 全量入口、98 负例行为一致。
- oracle commit 冻结（记录 `git rev-parse HEAD`）；Go `xnull`、`xnast` 二进制与 SHA-256 入 evidence。
- 本清单经董事会确认。

**执行**

- 只用 keep + replace 两类的现有 Go 包构建 oracle；不删任何文件。
- 重跑 141 入口 C diff、98 负例、9 示例；记录 xn-s1 种子来源（interp 或归档二进制）。
- 产出 `hashes.tsv`、`fixed-point.log`、`negative.log`、`examples.log`。

**门禁**：B4a PASS 前，`keep` 82 个文件禁止删除/改写语义；`replace` 包允许并行改造，但必须保持 Go CLI 可构建。

### B4b（CLI + devtool，24h）

**前置**

- B4a PASS；XNull CLI 功能矩阵冻结（命令、flag、退出码、诊断码、`--json` 字段）。
- `impl/runtime/build_rt.sh` 的资源表生成已有 XNull 对等物（P0）。
- 发布线确认 `scripts/build_release.sh` 可切换到自举二进制。

**执行**

- 先替换 `build_rt.sh` 的 `go run dev res`（否则 C 运行时构建永远拖 Go）。
- 再替换 CLI 依赖闭包：`xpd → manifest/xmeta → resman/reactor/config/plugin/repro/artifact → devtool → cli → cmd/xnull`。
- `xnfmt`/`cmd/xnfmt` 切到 `impl/xnfmt/xnfmt.x`。
- Go CLI 保留为 `XNULL_ORACLE=1` 旁路，默认入口切到 XNull CLI。

**门禁**：用户路径（`new/check/build/run/test/fmt/lock/install/tree/why/dev`）不再触发 `go` 进程；XNull CLI E2E 全绿；Go oracle 仍可按需启动。

### B4c（去 Go 构建，24h）

**前置**

- B4b PASS；所有测试已迁移或冻结；`tests/**` 活跃脚本不再依赖 `go build/test`。
- `xdkcheck` 合同条目已迁到 XNull 测试（或董事会批准记录损失）。
- `frontbridge` xnull 模式已退役，`xnselfhost` 无活引用。

**执行**：按 §5.4 顺序删除；每一步先 `git grep` 确认无活引用，再删下一批。

**门禁**：`git ls-files '*.go'` 只剩 evidence/归档；全量 XNull 测试绿；9 示例双路径绿；98 负例诊断一致；发布物由 xn-s2 构建。

## 8. 风险（按严重度）

1. **codegen/sema 在 B4a 前删 = 自举链断**：xn-s1 的 C 文本基准、98 负例、9 示例都依赖 Go oracle；B4a 的“C 产物逐字节一致”没有第二方就无法判定。`keep` 82 个文件是硬约束。
2. **sema 没有 XNull 对等物（最大缺口）**：B3 合同是 AST→C；`impl/lib/b3/xnullc.x` 不做源码 sema（B3-09 门也明确“负例矩阵由共享前端/sema 判定”）。B4b/B4c 若直接删 `impl/internal/sema`，`xnull check` 的类型错误、确定赋值、Result/try 诊断会失去实现；98 负例会退化成“xnullc 不检查”。B4b 必须给出 sema 迁移方案，或由董事会明确接受诊断面收窄。
3. **测试迁移滞后**：`delete` 含 210 个 `_test.go`；`tests/b3/*.sh` 20+ 脚本仍用 `go build ./cmd/xnull ./cmd/xnast` 生成 oracle。先删测试/脚本再迁移，会让 B4a 失去回归网。必须“先冻结 golden，再迁测试，最后删 Go”。
4. **运行时构建的隐藏 Go 依赖**：`impl/runtime/build_rt.sh:75,90` 用 `go run ./cmd/xnull dev res` 生成资源表；即使 CLI 已替换，C 运行时构建仍会拉 Go。B4b 首卡处理，否则 B4c 无法真正去 Go。
5. **发布链仍 `go build`**：`scripts/build_release.sh:9-10` 构建 xnull/xnfmt；B4b 不切换，发布物仍带 Go 构建链，自举口径不成立。
6. **CI 是半成品**：`ci/run.sh` 01/02/04 依赖 Go，05–09 还是 SKIP 桩；删 Go 步骤前必须先有 XNull CI（测试、规范守门、台账、资源、产物 SHA）。
7. **frontbridge/xnselfhost 耦合**：`frontbridge` 默认 go 模式，xnull 模式会自动构建 `xnselfhost`；B4a 若还跑 xnull 前端差分，提前删 `cmd/xnselfhost` 会断桥。删除顺序应是“先退役桥接层，再删 helper”。
8. **xdkcheck 的合同覆盖**：`impl/internal/xdkcheck/xdkcheck.go` 以 `go test` 驱动 XDK 合同；删掉后没有自动核验，必须把合同条目迁到 XNull 测试，不能静默丢。
9. **xnfmt/xnpt 的 oracle 价值**：B1/B2 已过门，但格式化/解析的回归仍可用 Go oracle；B4b 切到 `impl/xnfmt/xnfmt.x` 前，先跑 B1-03 差异用例；`xnpt` 确认无脚本引用再删。
10. **二进制可复现性**：B3-10 允许 `sha256(xn-s2) != sha256(xn-s3)` 时以 C 文本 + 行为为准；B4a 若要求二进制一致，需先消除时间戳/路径/构建顺序差异，否则会阻塞 B4a。该项必须写进 B4a 证据，不能静默降级。
11. **Go 工具链版本**：`impl/go.mod` 要求 `go 1.27`；删除 `go.mod` 后旧工具链无法再构建 oracle。B4a 前应把 Go 源码、二进制、构建命令、SHA 一起冻结到 evidence，避免“以后想复现但环境已漂移”。

## 9. 执行检查命令

```bash
# 清单计数（应输出 keep=82 replace=40 delete=217 evidence=29）
awk -F'\t' 'NR>1{c[$4]++} END{for(k in c) print k,c[k]}' handoff/B3-10-go-inventory.tsv

# 全仓 Go 文件（B4c 后应只剩 evidence/归档）
git ls-files '*.go' | wc -l
git ls-files '*.go' | grep -v '^evidence/' | grep -v '^收件箱/_归档/'

# 活跃脚本中的 Go 调用（B4c 后应为 0；evidence/归档除外）
grep -rnE '\bgo (build|test|run|vet|fmt)\b' ci impl scripts tests difftest --include='*.sh' | grep -v evidence

# B4a 固定点（示例）
sha256sum /tmp/xn-s2.c /tmp/xn-s3.c
cmp /tmp/xn-s2.c /tmp/xn-s3.c
```

## 10. 声明

本文件只做盘点与排序，不执行删除；所有 `delete` 项的实际删除属于 B4c，且必须先满足对应前置。`keep`/`replace` 的边界以 TSV 的 `class` 字段为准；任何调整需新版本 + 董事会确认，不得在 B4a/B4b 中临时改口径。
