# CEO3-RD1 首轮盘点：工具链（xdk / cli / devtool）

> **角色**：CEO3-RD1-工具链（依据《董事会判决-三司编制与团队扩招-v1.6.0》§2.3、§5）
> **日期**：2026-11-07　**基线**：`main` @ `dfcf033`；本域 worktree `wt/c3-rd1` 同基线、无改动
> **范围**：`impl/lib/xdk/**`、`impl/internal/cli/**`；为说明链路，连带只读查看 `cmd/xnull`、`cmd/xnpt`、`internal/devtool`、`internal/sema`、`internal/codegen`、`bindings/xdk`
> **性质**：只读盘点，不构成派工、门禁结论或验收签署。
> **只读声明**：本轮未改生产代码、未 commit、未派工；新增文件仅本件。

---

## 0. 结论

1. **主链可用，但只在“单文件 + 仓库维护”这一层**：`xnull run/build/policy` 单文件跑通；`xnull dev check/ledger/res` 三项可用且测试绿。
2. **XDK 公开面尚未成立**：`impl/lib/xdk/` 只有 1 个 30 行种子单元（设计要求 8 个）；`import xdk.text` 后调用种子函数实测 `RES-101 未定义`；`sema` 的 XDK 注册表与实际源码导出**两套事实源**，且注册表里的 29 个符号没有对应实现。
3. **CLI 用户面存在“假承诺 + 静默降级”**：`test/fmt/lock` 在帮助里可查、执行即“尚未实现”；`--profile/--skip/--check/--emit/--offline/--update-lock` 全局放行但无行为；`manifestExists` 只查当前目录，与提示“向上查找”相反。
4. **`dev` 只守规范文档，不守代码/XDK/证据**：`check` 五项全部是规范母本检查；`ledger` 不校验 `status.tsv` 路径是否存在、PASS 是否有证据；设计要求的 `check_xdk.py` 七条合同核验没有落地，也没有 Go 替代。
5. **建议前 3 张卡**：CLI 用户面收敛 → `xnull dev xdk` 合同门禁 → XDK 最小可导入闭环；详见 §4。

---

## 1. 盘点方法与实测基线

在 `main` 工作树执行（未改文件）：

| 命令 | 结果 |
|---|---|
| `go version` | `go1.27.3 darwin/amd64` |
| `go vet ./internal/cli ./internal/devtool` | 退出 0，无输出 |
| `go test ./internal/cli ./internal/devtool -count=1` | 两包均 `ok`；`cli 110.019s`、`devtool 70.813s` |
| `go test ./internal/codegen -run TestXdkSeedUnitCompiles -count=1` | `ok 22.406s`（种子单元可解析/语义/生成 C） |
| `sh impl/runtime/build_rt.sh` | 退出 0，约 75.7s；策略/GC/hard/abi/std/资源表全过 |
| `git status --porcelain impl` | 0 行 |

未在本轮复跑全量 `go test ./...`。既有证据 `evidence/S0-21e/summary.md` 记录 `internal/codegen` 187.9s 触发 180s 超时（已知 P0-1，非本域引入）；本报告不据此宣称全量绿。

### 1.1 行为探针（关键结论的原始依据）

| 探针 | 实测 |
|---|---|
| 在孙目录执行 `xnull test`，`xnull.project` 位于祖父目录 | `CLI-003 找不到 xnull.project`，退出 2（未向上查找） |
| 当前目录有 `xnull.project`，执行 `xnull test/fmt/lock/build` | 均输出“命令 ... 尚未实现”，退出 2 |
| `xnull run --profile examples/hello.x` | 正常输出 `hello, XNull`，退出 0（`--profile` 被静默忽略） |
| `xnull run --json examples/hello.x` | `CLI-002 unknown flag "--json"`，退出 2 |
| `xnull dev` | 用法提示，退出 2；无 `dev --help` |
| `import xdk.text` + `print(repeatText("ab", 2))`，`xnull run --interp` | `RES-101 未定义的名称 repeatText`，退出 1 |

---

## 2. 工具链现状

### 2.1 代码构成

| 文件 | 行数 | 作用 |
|---|---:|---|
| `impl/cmd/xnull/main.go` | 24 | 进程入口；SIGINT/SIGTERM → 130 |
| `impl/internal/cli/cli.go` | 313 | 命令白名单、参数形态校验、单文件 run/build/policy 分派 |
| `impl/internal/cli/dev.go` | 69 | `xnull dev check\|ledger\|res` 分派 |
| `impl/internal/cli/cli_test.go` / `dev_test.go` | 88 / 54 | CLI 与 dev 的退出码/输出测试 |
| `impl/internal/devtool/` | 116+295+237+362 | 规范守门、台账生成、资源表生成 |
| `impl/lib/xdk/text.x` | 30 | XDK 唯一源码单元（3 个纯函数） |
| `bindings/xdk/runtime.xfb` / `sys.xfb` | — | XDK C 层绑定声明 |
| `impl/cmd/xnpt/main.go` | 44 | 独立解析对照工具（不属 `xnull` 子命令） |

### 2.2 CLI 命令现状

`cli.go:111-119` 为命令白名单，`cli.go:132-138` 为帮助文本；帮助里列出的命令与真实能力并不一致。

| 命令 | 状态 | 实际行为 | 证据/缺口 |
|---|---|---|---|
| `run <file.x>` | 可用（单文件） | 默认编译执行，`--interp` 走解释器；退出码透传 | `cli.go:81-87`、`177-251`；编译路径丢弃程序参数（`runCompiled` 不接收 `extraArgs`） |
| `build <file.x> [-o] [--runtime]` | 可用（单文件） | 解析→语义→C→`cc`→可执行 | `cli.go:89-91`、`286-313`；无清单、无五阶段、无 `.xmeta` |
| `policy <file.x>` | 可用（单文件） | 输出内存策略判定 JSON | `cli.go:93-95`、`259-282` |
| `test` | **未实现** | 有清单时仍返回“尚未实现”，退出 2 | `cli.go:98-108`、`169-173` |
| `fmt` | **未实现，且规范明确“非承诺”** | 同上；S8 第 775 行写明 `xnull fmt` 不属规范 | 帮助仍展示，属用户面假承诺 |
| `lock` | **未实现** | 同上 | `--update-lock` 被放行但无行为 |
| `dev` | 可用（3 子命令） | 见 §2.3 | `cli.go:77-79`、`dev.go` |
| `help/version` | 可用（静态） | `Version = "0.1.0-dev"`，无 SHA/构建信息 | `cli.go:22`、`49-55` |

参数与清单：

- **清单探测只查当前目录**：`cli.go:162-167` 仅 `os.Stat("xnull.project")`；提示却写“在进程内向上查找”（`cli.go:103`）。实测孙目录失败。
- **全局 flag 白名单**：`cli.go:155-159` 放行 `--skip/--profile/--check/--emit/--offline/--verbose/--interp/--runtime/-o`，但除 `--interp/-o/--runtime` 外均无消费点；`--profile` 实测静默忽略。
- **dev 也先过全局 flag 校验**：`xnull dev check --json` 在进入 `runDev` 前被 `CLI-002` 拒绝，dev 子命令无法有自己的 flag 面（如 `--json`、`--help`）。
- **版本未接清单**：`cli.go:21-22` 注释自认“与清单 properties.xdk-version 的校验后续接入”；全仓库 Go 代码无 `xdk-version/xdkVersion/languageVersion` 消费点（仅 `xpd` 测试样例出现）。
- **运行时目录解析两套顺序**：`runCompiled` 先探测本地候选、后读 `XNULL_RUNTIME`（`cli.go:189-201`）；`buildFile` 先读环境变量、后探测（`cli.go:297-307`）。同一命令族对同一环境变量行为不一致。
- **未实现命令返回 2（用法错误）**：`notImplemented` 返回 `exitcode.Usage`（`cli.go:169-173`）。规范只定义 0/1/2/130，未实现归 2 是否合适需产品口径确认；当前至少会让脚本把“未实现”误判为“参数错误”。

### 2.3 `dev` 子命令现状

| 子命令 | 用法 | 实际能力 | 退出码 | 测试/证据 |
|---|---|---|---|---|
| `dev check [根]` | 根可省，默认 `.` | 规范守门五项：头部三方一致、正式版零待定、§ 引用不悬空、仓库根禁二进制、EN 快照版本+内容哈希 | 0 通过 / 1 有缺陷 / 2 参数错误 | `internal/devtool/specs.go`；`specs_test.go` 6 个测试 |
| `dev ledger [根]` | 根可省，默认 `.` | 从 S1—S8 母本重生成《一致性用例台账》；`status.tsv` 映射用例文件/状态 | 0 成功 / 1 失败 / 2 参数错误 | `internal/devtool/ledger.go`；`ledger_test.go` 2 个测试 |
| `dev res <资源目录> <输出.c>` | 必须恰好 3 个位置参数 | 递归收录资源、按名升序、重名/非法名/符号链接规则校验、生成 C 表 | 0 成功 / 2 错误（输出带 `gen_resources: ` 前缀） | `internal/devtool/resources.go`；13 个测试；`build_rt.sh` 实际消费 |

`dev` 的边界与缺口：

- **只守文档，不守代码**：`dev check` 不检查 `.xn` 残留、不检查 XDK 合同、不检查证据七件套、不校验 `go vet/go test`。
- **台账校验偏软**：`loadStatus` 在 `status.tsv` 缺失时返回空表而不报错（`ledger.go:250-255`）；不校验“用例文件”是否存在，也不校验 `PASS` 行是否有对应测试或证据。`status.tsv` 首行声称路径相对 `impl/Tests/`，但该目录实际不存在（`test -d impl/Tests` = no），路径口径需统一。
- **无机器可读输出**：`--json` 被全局拒绝；CI 只能用退出码和文本 grep。
- **无 `dev --help`/子命令帮助**；`xnull dev` 只打印一行用法。

### 2.4 XDK 现状（源码层 / 绑定层 / C 层 / 语义层）

| 层 | 现状 | 证据 |
|---|---|---|
| XNull 源码层 | **1/8 包**：仅 `lib/xdk/text.x`，30 行、3 个函数（`repeatText/repeatJoined/isPositive`），无 `package`/`import` | `impl/lib/xdk/text.x:1-30` |
| 绑定层 | 2 个：`bindings/xdk/runtime.xfb`、`sys.xfb` | 设计 §6 表 |
| C 原语层 | `rt_std_runtime.c`、`rt_std_text.c`、`rt_std_sys.c`、资源表生成器已完成；`rt_std_sync.c`/`rt_std_net.c` 未开工 | `xdk-design.md:140-158`；`build_rt.sh` 实测绿 |
| 语义层注册表 | 29 个符号：errors 5、tasks 3、sync 5、runtime 6、collections 4、text **仅 Regex**、sys 5、net 0 | `impl/internal/sema/xdk.go:33-58` |
| 编译加载 | `LoadUnits` 明确跳过 `import xdk.*`，不加载任何 XDK 源文件 | `impl/internal/codegen/multifile.go:15-16,76` |
| 实测可用性 | `import xdk.text` + `repeatText(...)` → `RES-101` | 本报告 §1.1 探针 |

**结构性矛盾（本轮最重要的发现）**：

1. `sema/xdk.go` 注册的 29 个名字是**手工白名单**，不是从 `lib/xdk/*.x` 导出面生成；注册表与源码层没有机械对应关系。
2. `text.x` 实际导出的 3 个函数不在注册表里（text 只有 `Regex`），所以“文件存在”和“可 import 调用”是两件事。
3. `Regex` 等 29 个符号没有对应源码实现，`import xdk.text.Regex` 能过语义检查，但调用时无实现——这是**假通过面**：名称解析绿，不代表能力存在。
4. 设计要求的七条合同机械核验（Result 白名单、`close()`、`Context` 首参、命名、无全局可变、稳定性标注、依赖矩阵）在仓库中无实现：`xdk-design.md` 指定的 `tools/check_xdk.py` 不存在，也没有 Go 替代，且 Python 已被 B-full 移除。
5. `XDK-01/03/06` 因此没有可交付路径；台账现有 `XDK-06/09 = 部分` 只覆盖 C 层，标注是诚实的，但不能据此宣称 XDK 包层成立。

### 2.5 测试与 CI 基线

- `internal/cli` 测试 110s、`internal/devtool` 70.8s；CLI 测试直接调用 `cc` 编译临时程序，无 `-short` 跳过、无“cc 不存在则 skip”分支，离开本机 C 工具链不可移植。
- `impl/runtime/build_rt.sh` 75.7s，绿。
- `main` 上 `git ls-files ci` = **0**；`ci/{run.sh,lib.sh,README.md}` 只存在于 `pod/e6-toolchain` 的 `65e7dd4`（S0-04b，待验）。因此当前任何“CI 通过”都不能以 `main` 为证据（ERR-005）。
- 仓库无 `.github/workflows`；CI 为自建 `ci/run.sh` 路线。

---

## 3. 缺口清单（9 条，按严重度）

> 归属说明：G1—G6 在 RD1 域内或可由 RD1 主责；G7—G9 需与 CEO1-RD2/RD3、CEO3-RD2/RD3 协同。跨司只列依赖，不代派工。

### G1【P0】XDK 源码层与注册表“双事实源”，形成假通过面

- 事实：`text.x` 导出 3 个函数，`sema` 的 text 包只登记 `Regex`；注册表 29 个符号均无对应 XNull 源码实现；`LoadUnits` 不加载 `xdk.*`。
- 影响：`import xdk.text` 能过语义，调用即 `RES-101`；后续若把 `import` 成功当验收，会重演“假绿”。
- 方向：注册表从源码导出生成（或生成后做一致性校验）；删除无实现符号或显式标 `@preview` + 未实现诊断；加载器按 `xdk.<pkg>` 映射到 `lib/xdk/<pkg>.x`。

### G2【P0】XDK 8 包只有 1 个种子单元

- 事实：设计 §2.3 要求 errors/runtime/text/collections/sys/tasks/sync/net 八单元；实际仅 text.x。
- 影响：M4.6a 的 errors/runtime/text 核心、M5 自举的 sys 读写均无源码层；XDK-01 无法验收。
- 方向：先出 8 个骨架（含 `@preview/@stable` 标注与依赖头），再按 P0（sys/errors/runtime/text）补实现；骨架函数必须显式报“未实现”，不得返回假值。

### G3【P0】CLI 帮助包含未实现命令，flag 静默接受

- 事实：`commands` 列出 `test/fmt/lock`，执行返回“尚未实现”；`fmt` 还被 S8 第 775 行明确列为非承诺；`--profile` 等 6 个 flag 被全局放行却无消费点。
- 影响：用户/脚本按帮助调用得到退出 2；CI 若传 `--profile` 会以为生效；违反“无静默降级”。
- 方向：命令面与规范对齐（删 `fmt` 或降为 `dev fmt`；`test/lock` 明确未实现状态与退出码）；flag 改为按命令白名单，未实现即拒绝；帮助只列真实可用项。

### G4【P0】清单探测只查当前目录，清单模式缺失

- 事实：`manifestExists` 只 `os.Stat("xnull.project")`；提示与实现相反；`xpd` 解析器已存在但 CLI 未使用；`build/run/test/lock` 的清单分支全部落到“未实现”。
- 影响：从子目录调用即失败；S8 §5.1 五阶段、§5.4 入口解析、`.xmeta`、锁文件均无法开始；PROJ-05 无法验收。
- 方向：先修向上查找（含边界与多清单冲突诊断），再接 `xpd` 的最小清单模式；五阶段分阶段落地，不一次性铺开。

### G5【P1】工具链版本/XDK 版本未接

- 事实：`Version = "0.1.0-dev"` 硬编码；无 `properties.xdk-version` 校验；无 `toolchainVersion/languageVersion/xdkVersion` 输出。
- 影响：S8 §5.3 `.xmeta` 必填字段无法生成；S8 第 336 行“XDK 版本不匹配 → 失败”无法执行；构建不可复现的输入清单不完整。
- 方向：版本注入（`-ldflags` 或生成常量）+ 清单读取 + `.xmeta` 字段；先做 `--version --json` 与 XDK 版本校验，再做完整 `.xmeta`。

### G6【P1】`dev` 质量门只覆盖规范文档

- 事实：`dev check` 五项均为母本文档检查；无 XDK 合同、无 `.xn` 扫描、无证据七件套、无 `status.tsv` 路径/证据校验；`loadStatus` 缺文件静默空表。
- 影响：CEO3 证据审计仍靠手工脚本；台账可把不存在的测试文件标 PASS；ERR-003 的 CI 第 10 项仍未在 main 生效。
- 方向：新增 `dev xdk`（G1 的机械核验）与 `dev evidence [卡号]`（七件套/哈希/签名）；`dev ledger --check` 校验路径存在与 PASS 证据；统一机器可读输出。

### G7【P1】运行时目录解析两套顺序，易漂移

- 事实：`runCompiled` 候选目录优先、`XNULL_RUNTIME` 兜底（`cli.go:189-201`）；`buildFile` 环境变量优先、候选兜底（`cli.go:297-307`）。
- 影响：同一环境变量在 `run` 与 `build` 下可能选中不同运行时；两处重复代码后续易再分叉。
- 方向：抽单一 `resolveRuntimeDir(flagValue)`，明确优先级并加对照测试。

### G8【P1】CLI 测试慢且非 hermetic

- 事实：`internal/cli` 110s、`internal/devtool` 70.8s；CLI 测试直接调用宿主 `cc`；无 `-short` 跳过、无 cc 缺失 skip；全量 codegen 有 187.9s 超 180s 的 P0-1 记录。
- 影响：Stage 1 门与 CI 时间预算被测试基建吞噬；换机/无 cc 环境直接红。
- 方向：把 CLI 测试拆成“分派/用法单测（快）”与“端到端编译（`-short` 或 build tag）”；cc 探测失败时 skip 并打印原因；此项与 CEO3-RD3 测试基建共担。

### G9【P2】`xnpt` 是孤岛工具

- 事实：`cmd/xnpt` 44 行、无测试、不在 `xnull` 子命令、不在 `dev` 下；仅靠手工 `go run` 与 `examples/parser-seed.x` 对照。
- 影响：解析对照语料无自动化入口，M5.1-c 的回归靠人跑。
- 方向：收进 `xnull dev parse`（或 `dev parser`），加固定语料与 golden；输出格式与退出码固化。

### G10【P0·外部】CI 未入 main（ERR-005），不占 RD1 卡

- 事实：`git ls-files ci` = 0；S0-04b 交付只在 `pod/e6-toolchain`。
- 影响：任何“CI 绿/守门通过”在 main 上不可复现；本报告不据此下结论。
- 归属：CEO3-RD2（构建与 CI）/ E6；RD1 只消费其入口。

---

## 4. 前 3 张建议卡

> 建议编号 `S0-29/30/31` 仅为占位，最终由 CEO3 审核、CEO2 编号派工；本轮不派工、不写生产代码。
> 每张卡按“唯一主责 + 明确写入域 + 可机械验收 + 七件套证据”设计。

### 建议卡 1（S0-29）：CLI 用户面收敛与静默降级清零

| 项 | 内容 |
|---|---|
| 优先级 | P0 |
| 主责 | CEO3-RD1 |
| 写入域 | `impl/internal/cli/**`（必要时 `impl/README.md` 的命令说明） |
| 目标 | 帮助里只出现真实可用命令；参数按命令白名单校验；清单向上查找；run/build 运行时解析统一；版本信息可追溯 |
| 动作 | ①`manifestExists` 改为向上查找，补“多清单/到根未找到”诊断；②`test/fmt/lock` 二选一：实现最小面或从用户帮助移除（`fmt` 按 S8 第 775 行降为 `dev` 或删除）；③flag 白名单按命令拆分，未消费 flag 一律 `CLI-002`；④抽 `resolveRuntimeDir`，固定“显式 flag > `XNULL_RUNTIME` > 相对探测”并加测试；⑤`--version` 输出版本+commit（构建注入），为 `xdk-version` 校验留接口；⑥未实现命令的退出码与产品口径对齐并写入帮助 |
| 验收 | ①孙目录 `xnull test` 能找到祖父 `xnull.project`（测试夹具）；②`xnull run --profile` 返回 `CLI-002`；③`xnull --help` 不含未实现命令；④`run`/`build` 对同一 `XNULL_RUNTIME` 选中同一目录；⑤`go vet ./internal/cli`=0、`go test ./internal/cli -count=1` 绿；⑥七件套证据 |
| 依赖/风险 | 无跨司依赖；命令面删减需 CEO3-PM 与 CEO1 确认（`fmt` 规范地位敏感） |

### 建议卡 2（S0-30）：`xnull dev xdk` 合同门禁（先红后绿）

| 项 | 内容 |
|---|---|
| 优先级 | P0 |
| 主责 | CEO3-RD1 |
| 写入域 | `impl/internal/cli/**`（新增 `dev xdk` 分派；若 CEO3 批准复用 E6 域，则落 `impl/internal/devtool/**`） |
| 目标 | 把 `xdk-design.md` §1 的七条合同与“注册表 ↔ 源码导出”一致性做成可重复执行的只读门禁；当前树必须**红**，且错误清单可复算 |
| 动作 | ①扫描 `impl/lib/xdk/*.x` 与 `bindings/xdk/*.xfb`；②实现七检：可失败 API 返回 `Result`（含白名单）、持资源类型有 `close()`、可阻塞 API 首参 `Context`、命名规范、无全局可变、`@stable/@preview/@internal` 标注、依赖矩阵声明；③对比 `sema/xdk.go` 注册表与源码导出，列出“注册无实现/实现未注册”；④输出稳定排序的文本报告（预留 `--json`），退出 0/1/2；⑤加 golden 测试，固定当前红基线（预期：7 包缺失、29 个注册符号无实现、text 3 个导出未注册） |
| 验收 | ①在 `dfcf033` 上运行 `xnull dev xdk` 退出 1，报告条目与手工盘点一致；②构造最小合规 fixture 时退出 0；③重复运行输出逐字节一致；④`go test ./internal/cli -run DevXdk -count=1` 绿；⑤不改任何 `lib/xdk` 生产代码即可交付；⑥七件套证据 |
| 依赖/风险 | 无语言特性依赖；若坚持“RD1 写入域仅 cli”，检查逻辑放 `internal/cli`，否则需 CEO3 书面扩展至 `internal/devtool` |

### 建议卡 3（S0-31）：XDK 最小可导入闭环（text 纯函数先行）

| 项 | 内容 |
|---|---|
| 优先级 | P0（价值最大，周期最长） |
| 主责 | CEO3-RD1 |
| 写入域 | `impl/lib/xdk/**`、`impl/internal/cli/**`；子卡：`impl/internal/sema/xdk.go` 归 CEO1-RD2，`impl/internal/codegen/multifile.go` 归 CEO1-RD3 |
| 目标 | `import xdk.text` 后 `repeatText/repeatJoined/isPositive` 在编译路径与 `--interp` 路径均可调用且输出一致；注册表与源码导出单一事实源；8 包骨架带稳定性标注 |
| 动作 | ①补齐 8 个 `lib/xdk/<pkg>.x` 骨架（先声明、显式未实现）；②text.x 加 `package xdk.text`/依赖头；③codegen 加载器把 `xdk.<pkg>` 映射到 `lib/xdk/<pkg>.x`（子卡）；④sema 注册表改为从源码导出生成或加生成后校验（子卡）；⑤CLI 增加 `xnull run --interp` 对照用例；⑥对 errors/runtime/sys 的实现依赖 P-09/P-10，标阻塞不抢跑 |
| 验收 | ①`import xdk.text` + 三函数调用，编译路径与 `--interp` 输出逐字节一致；②`xnull dev xdk` 对 text 包零“注册/导出”差异；③`sema` 无“注册但无实现”符号，或每个都有显式未实现诊断；④8 包骨架均带稳定性标注并通过七检；⑤`go test ./internal/cli ./internal/codegen -run 'Xdk|XdkSeed' -count=1` 绿；⑥七件套证据 |
| 依赖/风险 | 依赖卡 2 的门禁作为验收锚点；跨司子卡需 CEO2 协调；errors/runtime/sys 的完整实现受 P-09/P-10（extern 钩子、构建清单）阻塞，text 纯函数可先行 |

**排序理由**：卡 1 独立、当天可验，先清用户面假象；卡 2 是只读门禁，成本低、直接给出红基线，防止卡 3“做了但不可验收”；卡 3 是 XDK 真正成立的必要条件，但跨 sema/codegen，必须拆子卡，不能由 RD1 单方面改同域外文件。

---

## 5. 待决策与阻塞（一次列全）

1. **`fmt` 的命令面**：S8 第 775 行明确“非承诺”，但 CLI 帮助仍列出。删除、降为 `dev fmt`、还是保留为实验命令，需 CEO3-PM 与 CEO1 给口径。
2. **未实现命令的退出码**：当前 `notImplemented` 返回 2（用法错误）；若脚本需要区分“未实现”与“参数错”，需新增约定或统一为 1。属产品口径，不自行改。
3. **XDK 八包骨架的“空实现”策略**：骨架函数应显式报未实现，还是先不导出？前者可被 import 但运行失败，后者 import 即失败。建议前者 + `@preview` + 诊断码，需 PM/QA 确认。
4. **`dev xdk` 的落点**：严格按 v1.6.0 写入域，只能放 `internal/cli`；若允许复用 E6 的 `internal/devtool`，需 CEO3 书面扩展，避免越界。
5. **跨司子卡**：卡 3 的 sema/codegen 改动必须由 CEO1-RD2/RD3 主责，RD1 只提接口与用例；本轮不派工。
6. **CI 前置**：ERR-005（`ci` 未入 main）未关闭前，任何门禁结论只能写“本机命令 + 证据路径”，不得写“CI 通过”。
7. **测试时间预算**：`cli` 110s、`devtool` 70.8s、`build_rt` 75.7s、codegen 已知 187.9s；Stage 1 门若设 180s 硬界，需先拆快慢测试或调整预算，归 CEO3-RD3 主导。

---

## 6. 复现命令（供 CEO3/QA 复核）

```bash
cd /Users/vjs/Desktop/XNull-Lang

# 1. 基线
git log --oneline -1
git status --porcelain impl

# 2. 本域测试
cd impl
go vet ./internal/cli ./internal/devtool
go test ./internal/cli ./internal/devtool -count=1

# 3. XDK 种子
go test ./internal/codegen -run TestXdkSeedUnitCompiles -count=1

# 4. 运行时 C 层
cd ..
sh impl/runtime/build_rt.sh

# 5. 行为探针
cd impl && go build -o /tmp/xnull-probe ./cmd/xnull
cd ..
d=$(mktemp -d); mkdir -p "$d/a/b"; touch "$d/xnull.project"
(cd "$d/a/b" && /tmp/xnull-probe test; echo "nested_exit=$?")
(cd "$d" && /tmp/xnull-probe test; echo "cwd_exit=$?")
/tmp/xnull-probe run --profile examples/hello.x; echo "profile_exit=$?"
cat > "$d/use_xdk.x" <<'EOF'
import xdk.text
static Int main() {
    print(repeatText("ab", 2))
    return 0
}
EOF
/tmp/xnull-probe run --interp "$d/use_xdk.x"; echo "xdk_exit=$?"
```

---

## 7. 声明

- 本件为**只读盘点**，未改生产代码、未 commit、未派工、未碰他人文件。
- 本件不构成门禁结论；缺口状态以 CEO3 整改台账与董事会判决为准。
- 本件新增文件仅 `收件箱/CEO3/CEO3RD1-首轮.md`。
