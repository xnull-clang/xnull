# CEO3-PM-产品 首轮：工具链体验与发布口径条款清单 v1.0.0

> **角色：CEO3-PM-产品**（三司编制，依据 `收件箱/董事会判决-三司编制与团队扩招-v1.6.0-2026-11-07.md` §2.3 PM 行、§5 首轮任务）
> **域：xdk / cli / CI / 测试基建的「对外体验」与「发布口径」**　**性质：只读盘点**
> **写入域自限：仅 `收件箱/CEO3/**`。本轮未改生产代码、未 commit、未派工、未碰他人文件。**
> **基线：main `dfcf033`；Go 1.27.3 darwin/amd64；cc 可用。**　**日期：2026-11-07**

---

## 0. 判定口径（先定尺子再量）

| 记号 | 含义 | 使用条件 |
|---|---|---|
| ✅ 可承诺 | 现状支持，main 内可复现 | 对外表述无需附加条件 |
| ◐ 条件承诺 | 只有限定条件下成立 | 必须同时写出条件，否则等同 ⛔ |
| ⛔ 不可承诺 | 现状不支持 / 条款未实现 / 口径自相矛盾 | 任何对外表述均为超范围 |

**引用规则**：本清单一律写「第 N 部分 §x」，Sn 别名放括号内。原因见 §1——Sn 在本仓库有三套互不兼容的映射。

---

## 1. 前置事实：条款编号已经撞车（此项本身判 ⛔）

| 出处 | 映射 | 证据 |
|---|---|---|
| 规范索引 | S1–S9 = 第1–8 部分（S8=FFI，S9=工程配置） | `XNull规范索引-v1.0.0.md:42-43` |
| 一致性台账 | S1–S8 = 第1–8 部分（S6=XDK，S8=工程配置） | `XNull一致性用例台账-v1.0.0.md:13` |
| 代码注释 | 索引口径（S9=工程配置） | `impl/internal/exitcode/exitcode.go:1`、`impl/internal/diag/diag.go:1` |

**后果**：写「S8」无法判断指 FFI 还是工程配置；写「S6」无法判断指第5部分还是 XDK。发布稿、缺陷表、派工单一旦只写 Sn，读者必然误引。
**处置建议**：任何对外/派工文本禁用裸 Sn，统一「第N部分 §x」；编号统一走 v1.6.1（见 §6 D1）。**此条不解决，本清单其余条目都无法被第三方复核。**

---

## 2. 条款与体验清单（21 条）

| 编号 | 条款/体验点 | 条款锚点 | 现状与证据（main 实测） | 判定 |
|---|---|---|---|---|
| TC-01 | 工具链版本可作发布锚点 | 第8部分 §5.3（`toolchainVersion`）、验收标准 §5.3 L3 | `Version = "0.1.0-dev"`（`impl/internal/cli/cli.go:22`，注释自述版本校验"后续接入"）；`git tag` = 0 | ⛔ |
| TC-02 | 退出码 0/1/2/130 | 第8部分 §5.1、PROJ-05 | 常量齐备 `impl/internal/exitcode/exitcode.go:5-10`；`main.go:15-21` 捕获中断→130；实测 `--version`=0、未知命令=2、缺清单=2 | ✅（仅单文件/CLI 面） |
| TC-03 | 「未实现」不得占用 2（用法错误） | 第8部分 §5.1 + 质量红线 2（显式报错） | `impl/internal/cli/cli.go:169-173`：未实现命令直接返回 `Usage`(2) 并只打印 `xnull: 命令 "x" 尚未实现`；`CLI-901`（cli.go:28）从未被渲染 | ⛔ |
| TC-04 | 帮助文案与实际能力一致 | 第8部分 §5.1 阶段表 | `xnull --help` 列 build/run/test/fmt/lock 五个工程命令，实际工程模式全部不可用；`dev` 被列入 help（cli.go:134-136），而 `impl/README.md:27` 自述"不属于语言用户的稳定 CLI 面" | ⛔ |
| TC-05 | 工程清单向上查找 | 第8部分 §3/§4（工程定位） | 实测：`proj/xnull.project` 存在、在 `proj/sub` 执行 `xnull build` → `CLI-003 找不到 xnull.project`；实现只 `os.Stat("xnull.project")`（cli.go:161-167），与自身 hint"在进程内向上查找清单"（cli.go:103）直接矛盾 | ⛔ |
| TC-06 | 五阶段生命周期 | 第8部分 §5.1、PROJ-05 | 在含清单目录执行 `xnull build` → exit 2「命令尚未实现」；台账 PROJ-01—11 仅 PROJ-05「部分」，其余「未实现」 | ⛔ |
| TC-07 | 单文件运行默认路径口径 | 第1部分入口 + `impl/README.md` + `推广/README升级草案-双语.md:26,49` | `run` 默认走编译路径 `runCompiled`（cli.go:177-185），需 cc + 运行时源码；`--interp` 才走解释器。实测：仓库根 exit 0；离开仓库 exit 2「找不到运行时源码目录」。README 草案却写 "A tree-walking interpreter ships…"，未说明默认已切换到编译路径 | ◐（限「仓库树内 + cc」，且必须写明默认编译路径） |
| TC-08 | 程序参数透传 | 第1部分入口、第4部分 §7.2 | `runCompiled` 丢弃 extraArgs（cli.go:184 只传 path；cli.go:212 `exec.Command(bin)` 无 args）；codegen 固定生成 `int main(void)`（`impl/internal/codegen/codegen.go:306-312`，即缺陷 P1-1） | ⛔ |
| TC-09 | 构建产物契约（`target/`、`.xmeta`、target 外零写入） | 第8部分 §5.3/§5.5、PROJ-05/09 | 实测 `xnull build <src>`：默认产物名 `prog`、同目录遗留中间文件 `prog.c`（cli.go:287；`impl/internal/codegen/build.go:38-43`）；成功零输出；无 `target/`、无 `.xmeta` | ⛔ |
| TC-10 | 诊断格式与诊断码纪律 | 第8部分 附录 C.4 | 主路径 `file:line:col: error[CODE]: msg`（`impl/internal/diag/diag.go:26`）；旁路为无码裸文本（cli.go:171、198、248）；`CLI-901` 从不输出 | ◐（主路径可承诺，旁路不统一） |
| TC-11 | XDK 8 包可用面 | 第6部分 §2/§4/§8；XDK-01—10 | `git ls-files impl/lib/xdk` = 1（仅 `text.x`，标注 `@preview`，含 3 个纯函数）；台账 XDK-01—05/07/08/10「未实现」，XDK-06/09「部分」 | ⛔ |
| TC-12 | XDK 合同机械核验（七条原则、`@stable` 标注、依赖矩阵） | 第6部分 §3；`impl/docs/xdk-design.md:20`（XDK-02） | `git ls-files \| grep -c check_xdk` = 0；`impl/tools/` 目录不存在 | ⛔ |
| TC-13 | 资源表生成器可用 | 第8部分 §5.6、PROJ-11 | `xnull dev res` 可用；`impl/runtime/test_res.c` 覆盖；S0-25 已入 main（`f826d1f`），QA1 9/9 | ✅（仅「生成资源表 C 源」这一动作） |
| TC-14 | 资源读取 API 与资源体积上限 | 第6部分 §4.8（XDK-10）、第8部分 §10 | 五个 API 未实现（XDK-10「未实现」）；上限口径冲突：第8部分 §10「资源体积上限 = 非承诺…不设规范上限」vs `impl/docs/xdk-design.md:133` 建议「单资源 ≤ 8 MiB、总量 ≤ 64 MiB」 | ⛔（API）/⛔（上限，两文冲突，任选其一对外均为私定） |
| TC-15 | CI 可作为发布/修复证据 | 验收标准 G-01/G-06；ERR-005 | main `git ls-files ci` = 0；pod 侧 4 文件、04—09 为显式 SKIP 桩（`收件箱/CEO3/整改台账-v1.0.0.md:18,50-53`） | ⛔ |
| TC-16 | 干净 clone 可复现 | 验收标准 G-01 | 无 tag；CI 不在 main；`run` 依赖相对探测或 `XNULL_RUNTIME`（cli.go:188-201）；离开仓库即不可运行（实测 exit 2） | ⛔ |
| TC-17 | L3 发布验收单可填 | 验收标准 §5.3、G-07 | 需「已判 tag + 副本=tag + README 能力表一致 + 泄漏零命中」；`git tag` = 0；README 能力表含未实现能力（XDK、工程构建） | ⛔ |
| TC-18 | 平台支持口径 | `impl/README.md`「Go 选型风险点 4」 | 自述「windows/amd64、linux/arm64 每次全量测试一并验证」，但 main 无 CI 产物可证；`impl/docs/xdk-design.md:134` 首版按 POSIX 实现，Windows 后端后置；本地仅 darwin/amd64 实测 | ⛔ |
| TC-19 | 写入域路径可执行（编制口径） | 判决 v1.6.0 §2.3 | 判决写 `lib/xdk/**`、`cli/**`、`ci/**`、`cmd/**`、`difftest/**`、`Tests/**`；实际为 `impl/lib/xdk`、`impl/internal/cli`、`impl/cmd`，且 `ci/`、`difftest/`、`Tests/` 均不存在；台账头还要求用例文件相对 `impl/Tests/`（该目录不存在，26 个测试均在 `impl/internal/**` 内联） | ⛔（照原文派卡会写错位置） |
| TC-20 | 证据件可机器解析 | 验收标准 §4.3 七件套、G-06 | `收件箱/CEO3/证据审计-v1.0.0.md:95-97`：`exit_code.txt` 为 Markdown 表格、`sha.txt` 为散文；门禁要求机械核对 | ◐ |
| TC-21 | 上手命令可直接复制执行 | `推广/README升级草案-双语.md:21,44`（"Run It Today" / "今天就能跑"） | 草案命令 `go run ./cmd/xnull run examples/hello.x` 在仓库根实测 **exit 1**（`cannot find main module`，go.mod 在 `impl/`）；在 `impl/` 执行则示例路径失效。可用形式是 `cd impl && go run ./cmd/xnull run ../examples/hello.x`（实测 exit 0）。中英两版同错 | ⛔ |

**统计**：✅ 2 条（TC-02、TC-13）· ◐ 3 条（TC-07、TC-10、TC-20）· ⛔ 16 条。

---

## 3. 可承诺白名单（对外唯一可说的六句）

每句都必须连同条件一起说，单独摘句即失真。

1. 在 **macOS/amd64 + Go 1.27.3 + cc**、且从 `impl/` 目录执行 `go run ./cmd/xnull run ../examples/hello.x` 时可运行（实测 exit 0）；加 `--interp` 走解释路径。**公开草案里的 `go run ./cmd/xnull run examples/hello.x` 不可照抄（TC-21）。**
2. 单文件与参数面的退出码为 **0/1/2/130**（130 由 `impl/cmd/xnull/main.go:15-21` 捕获中断产生；实现把 SIGTERM 也归入 130，条款只写 SIGINT）。
3. 解析/语义失败的诊断格式为 **`file:line:col: error[CODE]: message`**，可被正则解析。
4. 仓库自带 **内部维护工具** `xnull dev check / ledger / res`，`dev check` 在 main 当前全绿；**不属于语言用户面**。
5. 资源表生成（`dev res`）按第8部分 §5.6 递归收录、按名升序、断链/越界失败，有 main 内证据（S0-25）。
6. 9 个示例 + multi 的双路径一致性有 QA 证据（S0-21d）；但 `evidence/S0-21a—e` 的 `artifact.sha256` 未入 main，**干净 clone 复算受限**，只能说「有证据」不能说「可复算」。

---

## 4. 不可承诺红名单（禁用话术 → 可替代表述）

| 禁用话术 | 依据 | 现在能说 |
|---|---|---|
| 「XDK 标准库可用 / 8 包齐备」 | TC-11、TC-12 | 「XDK 仅有 `text` 包种子（3 个纯函数），完整 API 面与合同核验未实现」 |
| 「支持工程构建 / `xnull build` 五阶段」 | TC-05、TC-06、TC-09 | 「工程模式未实现；当前仅单文件 `run`/`build`，且产物落在当前目录」 |
| 「CI 全绿 / 修复已过 CI / 有 CI」 | TC-15 | 「CI 脚本在 pod 分支未入 main，04—09 为显式 SKIP 桩」 |
| 「已发布 / 稳定版 / 可下载安装」 | TC-01、TC-17 | 「仓库内源码构建；无 tag、无安装包、版本号为 0.1.0-dev」 |
| 「Windows / Linux 已验证」 | TC-18 | 「仅 darwin/amd64 实测；Windows 后端未实现」 |
| 「开箱即用 / 装到哪都能跑」 | TC-07、TC-16 | 「需 Go 1.27 + C 编译器；须在仓库树内运行（或设 `XNULL_RUNTIME`），离开仓库树即 exit 2」 |
| 「README 的 Run It Today 照抄可跑」 | TC-21 | 「需 `cd impl` 并改用 `../examples/hello.x`；草案命令在仓库根 exit 1」 |
| 「资源上限 8 MiB / 64 MiB」 | TC-14 | 「规范层面不设上限；实现层建议值未定案」 |
| 「`xnull fmt` 格式化 / 支持插件 / 增量编译」 | TC-04、TC-06、第8部分 §10 | 「命令与机制未实现；增量编译为非承诺项」 |
| 「条款 ID 覆盖 100%」 | §1、验收标准 G-03 | 「S 编号存在三套映射，条款对账口径未统一」 |

---

## 5. 体验缺陷排序（PM 视角的影响面，不是派工单）

| 序 | 缺陷 | 用户感受 | 影响面 |
|---|---|---|---|
| 1 | README 上手命令不可照抄（TC-21） | 复制即报 `cannot find main module`，判定为项目不能跑 | 发布物首屏；演示与外部试用全部踩中 |
| 2 | 清单向上查找失效，且 hint 明说会找（TC-05） | 照提示操作必失败，怀疑自己目录错 | 每一个工程模式用户；也影响后续 9 个 worktree 的联调 |
| 3 | `xnull build` 成功零输出、产物名 `prog`、残留 `prog.c`（TC-09） | 不知道产物在哪；仓库被污染 | 首次构建体验；`target/` 外写入直接违反 PROJ-09 |
| 4 | 「尚未实现」返 2，与「用法错误」同码（TC-03） | 脚本把未实现当参数错，CI 误判类型 | 所有自动化与门禁脚本 |
| 5 | help 列 5 个不可用命令、`dev` 混入用户面（TC-04） | 第一次 `--help` 就被误导 | 新用户首触点 |
| 6 | 离开仓库树无法运行（TC-07、TC-16） | 装好的工具链跑不了任何程序 | 发布与演示场景的硬阻断 |
| 7 | 诊断旁路无码、`CLI-901` 空转（TC-10） | 同一工具两套错误风格；无法按码归类 | 错误处理与文档 |

---

## 6. 待决项（一次列全，均非 PM 可自定）

| 编号 | 事项 | 为什么 PM 不能定 | 建议决策方 |
|---|---|---|---|
| D1 | Sn 编号三套映射统一（索引 / 台账 / 代码注释） | 涉及规范引用体系，属董事会口径 | 董事会（v1.6.1） |
| D2 | v1.6.0 §2.3 写入域与仓库实况对齐（`impl/` 前缀；`ci/`、`difftest/`、`Tests/` 不存在） | 判决已冻结，修订须另发版本 | 董事会（v1.6.1） |
| D3 | 资源体积上限：第8部分 §10「不设上限」vs 设计文档 8/64 MiB | 前者是正式规范条款，改它须走版本修订 | 董事会 + CTO 技术结论 |
| D4 | 对外「解释器 / 编译器」默认路径与上手命令口径（README 写解释器、CLI 默认编译；草案命令不可照抄，TC-21） | 涉及公开发布物措辞与冻结流程 | CEO（终审）+ CTO 技术关 |
| D5 | `dev` 是否出现在用户 help（隐藏 / 分区 / 保持） | 影响公开 CLI 面的稳定性承诺 | CEO3 提方案，CEO 决定 |
| D6 | 平台口径：继续声称 windows/linux 已验，或改为「仅 darwin/amd64 实测」 | 与 G-01 证据要求直接冲突 | 董事会（验收标准解释） |
| D7 | 首个可 tag 版本的准入线（0.1.0-dev → ?），L3 需要「已判 tag」 | 发布节奏属司长/董事会 | CEO1 + 董事会 |
| D8 | 「未实现」的退出码语义（继续用 2，或新增专用码） | 2 的语义写在第8部分 §5.1，新增码属规范变更 | 提案 → 董事会 |

---

## 7. 复现命令（全部只读；产物只落临时目录）

```bash
# 0) 从仓库根执行；探针二进制不写入仓库
REPO=$(pwd); cd impl && go build -o "$TMPDIR/xnull-pm" ./cmd/xnull; cd "$REPO"

# 1) 清单向上查找（预期：子目录应找到，实测 exit 2）
P=$(mktemp -d); mkdir -p "$P/proj/sub"
printf 'project {\n  groupId = "a"\n  artifactId = "b"\n  version = "1.0.0"\n  packaging = "app"\n}\n' > "$P/proj/xnull.project"
(cd "$P/proj/sub" && "$TMPDIR/xnull-pm" build; echo "exit=$?")

# 2) 含清单时 build 的实际行为（预期：五阶段，实测：尚未实现 exit 2）
(cd "$P/proj" && "$TMPDIR/xnull-pm" build; echo "exit=$?")

# 3) 离开仓库根运行（预期：可运行，实测：找不到 rt.h exit 2）
(cd "$P" && "$TMPDIR/xnull-pm" run "$REPO/examples/hello.x"; echo "exit=$?")

# 4) 产物契约（预期：target/ + .xmeta，实测：./prog + ./prog.c，零输出）
(cd "$P" && XNULL_RUNTIME="$REPO/impl/runtime" \
  "$TMPDIR/xnull-pm" build "$REPO/examples/hello.x"; ls -1)

# 5) 上手命令：草案原文 vs 可用形式
(cd "$REPO" && go run ./cmd/xnull run examples/hello.x; echo "draft_exit=$?")
(cd "$REPO/impl" && go run ./cmd/xnull run ../examples/hello.x; echo "working_exit=$?")

# 6) 发布锚点核对
git tag | wc -l              # 0
git ls-files ci | wc -l      # 0
git ls-files impl/lib/xdk    # 仅 text.x
git ls-files | grep -c check_xdk  # 0
```

---

## 8. 边界声明

- 本轮**未**改任何生产代码、测试、规范、门文件；**未** commit；**未**向任何会话派工。
- `git status --porcelain impl` = 0（探针产物在 `$TMPDIR`）；仓库既有未跟踪项（如 `evidence/S0-18/`）非本轮产生。
- 未读取公开仓（无授权），故 P1-7 相关口径不在本清单内。
- 未替任何 QA 签 L1、未替 CEO1 签 L2；本清单只回答「能说什么、不能说什么」。
- 条款引用以 main `dfcf033` 为准；修订后本清单需重出 v1.0.1。
