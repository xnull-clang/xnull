# CEO1-QA2 首轮（只读）：双路径 / 回归 / 变异 验收清单

> **会话**：`CEO1-QA2-回归`　**角色**：一司 QA2，负责双路径、回归、变异
> **依据**：`收件箱/董事会判决-三司编制与团队扩招-v1.6.0-2026-11-07.md` 第 2 条（2.1 编制表）与第 5 条（首轮只读）
> **日期**：2026-11-07　**性质**：验收清单草案，不是门禁结论，不是派工单
> **写入域**：仅 `收件箱/CEO1/**`；本轮未改生产代码、未 commit、未派工
> **基线**：`git rev-parse HEAD` = `dfcf033`（工作区有他人未提交改动，验收时必须用干净 checkout 的 sha）

---

## 0. 结论

1. 清单共 **15 条**（R-01—R-15），其中双路径 5 条（R-01—R-05）、回归 4 条（R-06—R-09）、变异 2 条（R-10—R-11）、防假绿与证据 4 条（R-12—R-15）。
2. 双路径判据统一为：**9 个单文件示例 + `examples/multi` 多文件工程，stdout 逐字节一致、退出码一致、单例超时即失败**；9 示例明细见 §2.2。
3. 变异阈值：董事会 §4.1 为 **interp/sema ≥80%（Stage 1）、codegen/tools ≥60%（Stage 2 起）**；QA2 建议 xfront 对齐 ≥80%（需 CEO1 批准），并加 **双路径/退出码/诊断码/ARC 纪律相关变异 100% 击杀**。
4. 现状有 9 个缺口（§5），其中 **4 个直接阻断门禁**：D-01 无 CI 入库、D-03 无变异工具、D-04 无独立 golden、D-05 覆盖率基线不达标；另有双路径设计缺陷 3 项（F-03/F-04/F-05）。
5. 本轮只登记缺口与验收判据；**在 D-01/D-03/D-04/D-05 关闭前，Stage 1 的 L2 门不具备可签条件**（此判断留待 CEO1 结论，QA2 只提供依据）。

---

## 1. 只读盘点（事实 + 证据位置）

| # | 事实 | 证据 | 对验收的影响 |
|---|---|---|---|
| F-01 | 单文件示例 9 个，黄金对照用 glob 自动纳入 | `impl/internal/codegen/codegen_test.go:75` | 新增示例自动进测试集；验收报告必须列出「本次集合 + sha」，不能只说「9 示例」 |
| F-02 | `examples/multi` 不在 glob 内，由独立用例覆盖 | `impl/internal/codegen/multifile_test.go:123` | 双路径必须显式点验 multi，不能只跑 `examples/*.x` |
| F-03 | 黄金对照把**解释器输出当期望值**再与编译输出比较 | `impl/internal/codegen/codegen_test.go:86-93`；`multifile_test.go:135-157` | 命中董事会验收标准 §4.4 反作弊第 4 条；两路径同错时测试仍绿，只能证明「相等」不能证明「正确」 |
| F-04 | 双路径只比 stdout 与退出码，stderr 不比对 | `evidence/S1-22/dualpath/result.txt`；`ast-seed.compiled.err` 1520 B、`parser-seed.compiled.err` 5916 B，对应 `.interp.err` 均为 0 B | 编译路径的 C 告警（`-Wparentheses-equality`）可长期逃逸；stderr 含随机临时路径，不能直接逐字节比对，但必须设白名单与 error 零容忍 |
| F-05 | S1-22 时 9 示例退出码全为 0，无失败路径双路径 | `evidence/S1-22/dualpath/result.txt` | 退出码映射（`throw`→134、`fatal`、`try` 未捕获）未被双路径覆盖 |
| F-06 | 覆盖率基线（2026-11-07 实测，`dfcf033`） | 本轮命令：`go test ./internal/xfront ./internal/sema ./internal/interp ./internal/cli -count=1 -cover` | xfront 73.6%、sema 75.7%、interp 60.0%、cli 46.7%，**全部低于**董事会 §4.1 Stage 1 阈值（≥80 / ≥80 / ≥75 / ≥60） |
| F-07 | 无双路径框架目录、无 CI 入库、无变异工具 | `impl/difftest/` 不存在；`ci/` 不存在（ERR-005）；`go-mutesting`/`gomutant` 均未安装 | 双路径与变异目前只能人工跑，无法机械复现，不满足 §4.3 证据要求 |
| F-08 | 测试中条件跳过 10 处 | `impl/internal/codegen/ffi/emit_test.go:176,187`；`ffi/xdk_test.go:21`；`codegen/xdk_seed_test.go:23`；`devtool/resources_test.go:161,172,185,200`；`devtool/ledger_test.go:83`；`xpd/parser_test.go:155` | 门禁必须统计实际 `SKIP` 数；条件跳过在缺依赖时会静默变绿 |
| F-09 | 台账口径：101 锚点，PASS 10；S1 14、S2 29 | `XNull一致性用例台账-v1.0.0.md:11-13` | 回归不能拿「PASS 数」当覆盖率；QA2 只验行为，不重算条款 |
| F-10 | 红线第 3 条：改动 codegen/interp 后既有示例双路径必须复测，新能力必须带新示例 | `收件箱/质量红线.md:9` | R-01/R-08 的强制来源；不因「只改了一点」豁免 |
| F-11 | 示例自述预期输出与实际不符：`examples/result-try.x:2-5` 列 5 行，实跑 4 行（缺 `negative: -3`） | 本轮实跑：`xnull run --interp examples/result-try.x` 输出 `got 42/true/true/fallback 0`，28 B | 双路径只证两条路径相等，不证与示例自述一致；R-03 的 golden 锚定可抓出 |

---

## 2. 验收清单

### 2.1 总表（15 条）

> 所有命令默认在仓库根执行；`XN=/tmp/xnull-qa2`、`OUT=/tmp/qa2` 先建好。证据统一落 `evidence/<task-id>/` 七件套（§4）。

| 编号 | 类别 | 验什么 | 怎么验（核心命令） | 通过判据 | 不通过示例 |
|---|---|---|---|---|---|
| **R-01** | 双路径 | 9 个单文件示例编译↔解释一致 | `cd impl && go build -o $XN ./cmd/xnull` 后逐个跑 `run --interp` 与 `run`，`cmp` 两份 stdout | 9/9 stdout 逐字节一致；退出码逐一相等；单例 ≤120 s | 只跑一条路径；用 interp 输出当唯一期望；超时不处理 |
| **R-02** | 双路径 | `examples/multi` 多文件工程一致 + 构建确定性 | `go test ./internal/codegen -run 'TestMultiFileExampleCompileMatchesInterp\|TestLoadUnitsOrderDeterministic' -count=1 -v`；连续两次 `EmitC` 取 sha256 | stdout/退出码一致；加载顺序固定；两次 C 源码 hash 相同 | 只测单文件；多文件靠「能编译」判过 |
| **R-03** | 双路径 | 期望值必须独立锚定，不得拿解释器当唯一 oracle | 将 9+multi 的 stdout/退出码 pin 为 golden 文件；golden 同时比对两条路径，并核对示例头注释 | `interp == golden` 且 `compiled == golden`；示例自述输出与实际一致；golden 变更须有条款 ID 与批准记录 | 直接沿用 F-03 的写法；改 golden 让测试变绿 |
| **R-04** | 双路径 | 失败路径一致：非 0 退出码与错误输出 | 至少 4 个负向样例：未捕获 `throw`、`fatal`、`try` 未捕获、缺失 `main`；两路径各跑一次 | 退出码一致（按 §10.4 映射）、stdout 一致、stderr 的**错误行**一致；无 panic/栈回溯 | 只测 happy path；把编译失败当解释失败 |
| **R-05** | 双路径 | 超时与挂起必须判失败 | `go test ./internal/codegen -run TestExamplesCompileMatchesInterp -count=1 -timeout 300s`；CLI 循环用 `perl -e 'alarm 120; exec @ARGV' "$XN" run …` 或无超时工具时由 CI 兜底 | 任一用例超时即整卡不通过；不得用「它只是慢」解释 | 无限等待；用 `-short` 跳过 |
| **R-06** | 回归 | 确定性与 flaky | 全量双路径连跑 10 次，收集 stdout sha 集合；`go test ./internal/codegen -run TestExamplesCompileMatchesInterp -count=10` | 输出 hash 集合大小 = 1；10/10 通过；0 flaky | 输出顺序随机；两次结果不同仍判过 |
| **R-07** | 回归 | 既有测试与运行时构建不退化 | `cd impl && go vet ./... && go test ./... -count=1 -timeout 300s`；`sh impl/runtime/build_rt.sh` | 两条命令 exit 0；实际 SKIP 数逐条登记（F-08） | 删测试/改期望；SKIP 不登记 |
| **R-08** | 回归 | 回归资产完整性 | `git diff --stat <base>..<sha>`；`git diff --diff-filter=D --name-only`；检查 `examples/*.x`、golden、`*_test.go` | 无未经批准的测试/示例删除；新增能力带新示例（红线 3）；期望值变更逐条有理由 | 删示例降耗时；把断言改宽松 |
| **R-09** | 回归 | 覆盖率不低于基线、逐步达到阶段阈值 | `cd impl && go test ./internal/... -count=1 -cover -timeout 600s`（codegen 单跑并记录耗时） | 不低于本轮基线；Stage 1 目标：xfront/sema ≥80%、interp ≥75%、cli ≥60%、codegen ≥70%；Stage 2 起核心 ≥85% | 覆盖率下降无书面说明；用 `-coverpkg` 虚增；用 300 s 超时把 codegen 判成失败 |
| **R-10** | 变异 | 变异分数达阈值 | 逐包跑变异工具，报告 `total/killed/survived/equivalent/timeout` | xfront ≥80%、sema ≥80%、codegen ≥60%、interp ≥80%；双路径/退出码/诊断码/ARC 纪律相关变异 **100% 击杀** | 只报总分不报分包；等价变异不登记 |
| **R-11** | 变异 | 变异执行可复现、不可作弊 | 固定工具与版本；每个变异体独立应用；跑前跑后对测试/示例/golden 做 sha 比对 | 测试资产 sha 前后一致；命令可复制；超时计 killed 并标注；存活变异逐条归类 | 变异体同时改测试；批量应用不隔离 |
| **R-12** | 防假绿 | 断言能区分正确/错误实现 | 抽样 ≥20% 用例人工审查；统计 `t.Skip`/`t.Log` 后无断言；检查长字符串硬编码 | 无恒真断言；无「只断言不 panic」；无硬编码示例输出；期望值可溯源到条款 ID | `assert(true)`；把输出抄进测试 |
| **R-13** | 回归 | 性能不回退 | `time $XN run examples/hello.x`；`time $XN run --interp examples/parser-seed.x`；与基线比 | hello 编译 ≤5 s、运行 ≤200 ms；parser-seed 解释 <10 s；回归 ≤20% | 超 20% 无豁免；用「机器慢」解释 |
| **R-14** | 证据 | 七件套齐全、可复现 | `evidence/<task-id>/{command,stdout,stderr,exit_code,sha}.txt`、`artifact.sha256`、`acceptance.md` | 七项齐全；命令从干净 checkout 可复现；sha = 被测 commit | 截图/口头说明；无 sha；artifact 缺失 |
| **R-15** | 独立性 | 验收人 ≠ 实现者，测试未被篡改 | 核对签名；`git log --format='%an %s' <base>..<sha> -- '*_test.go' 'examples/**'`；复跑关键项 | QA2/必签人不在实现者名单；测试改动有对应任务卡 | 自验；实现者顺手改测试 |

### 2.2 R-01 明细：9 示例双路径（必跑，不可抽样）

| # | 示例 | 守护的语言面 | 专用判据（在 stdout+退出码之外） | 编译路径已知噪声 |
|---|---|---|---|---|
| 1 | `examples/hello.x` | 入口、`print`、Int 算术 | 输出非空；退出码 0 | 无 |
| 2 | `examples/result-try.x` | `Result`/`try`/错误即值 | 覆盖 Err 传播与 `unwrapOr` 回退；示例头注释与实际输出不符（F-11） | 无 |
| 3 | `examples/defer-cleanup.x` | `defer`/`errdefer`、LIFO、块退出 | 清理顺序逐行固定；错误路径与正常路径都出现 | 无 |
| 4 | `examples/containers.x` | `T[]`/`List`/`Map`/`Set`/`for-in` | 容器元素增删查与遍历顺序 | 无 |
| 5 | `examples/classes.x` | 类、字段、方法、容器参数 | 方法返回 String；字段初值 | 无 |
| 6 | `examples/objlist.x` | 类元素容器、字段链、跨函数传 `List<T>` | 元素 retain/release 不崩；字段链取值 | 无 |
| 7 | `examples/lexer-seed.x` | 自举词法器、String 成员、`while` | `substring/indexOf` 边界；while 条件重求值 | 无 |
| 8 | `examples/ast-seed.x` | 递归类、`List<Node>` 字段容器、S 表达式 | 递归求值与 dump 顺序 | **1520 B cc 告警**（冗余括号） |
| 9 | `examples/parser-seed.x` | Pratt 解析、表驱动、前向声明 | 解释路径 <10 s（S1-22 实测 0.02 s） | **5916 B cc 告警**（冗余括号） |
| 10 | `examples/multi`（`main.x` + `lib/shapes.x` + `lib/text.x`） | import 闭包、依赖优先后序、跨文件可见性 | 两次 C 源码 hash 一致；`RES-108` 环检测有独立负向用例 | 归 R-02 |

**执行模板**（单文件 9 个）：

```bash
cd /Users/vjs/Desktop/XNull-Lang
XN=/tmp/xnull-qa2; OUT=/tmp/qa2; mkdir -p "$OUT"
(cd impl && go build -o "$XN" ./cmd/xnull)
fail=0
for f in examples/*.x; do
  n=$(basename "$f" .x)
  perl -e 'alarm 120; exec @ARGV' "$XN" run --interp "$f" > "$OUT/$n.interp.out" 2> "$OUT/$n.interp.err"; i=$?
  perl -e 'alarm 120; exec @ARGV' "$XN" run "$f"          > "$OUT/$n.compiled.out" 2> "$OUT/$n.compiled.err"; c=$?
  cmp -s "$OUT/$n.interp.out" "$OUT/$n.compiled.out" || { echo "STDOUT-DIFF $n"; fail=1; }
  [ "$i" = "$c" ] || { echo "EXIT-DIFF $n: $i vs $c"; fail=1; }
done
exit $fail
```

**要求**：输出目录按 `<示例>.{interp,compiled}.{out,err}` 归档进证据；`result.txt` 逐行写 `示例 interp=<码> compiled=<码> stdout=OK/DIFF`（沿用 S1-22 格式）。

### 2.3 R-10 / R-11 明细：变异阈值与执行规范

**工具现状**：`go-mutesting`、`gomutant` 均未安装；仓库无 `difftest/`。变异分数在工具落地前**无法评分**，不得用「手改两处能红」替代（D-03）。

**分数定义**：

```
MS = killed / (total - equivalent)
killed     测试失败、编译失败或超时（超时单独计数并标注）
survived   测试仍全绿
equivalent 语义等价，需第二人复核并登记理由；不计入分母
```

**分层阈值**（董事会下限 + QA2 关键路径要求；不降低任何董事会阈值）：

| 包/面 | 阈值 | 适用阶段 | 依据 | 备注 |
|---|---|---:|---|---|
| `internal/xfront` | ≥80% | Stage 1 | QA2 建议（对齐 sema；董事会未单列） | 需 CEO1 批准后执行；不批准则记录基线 |
| `internal/sema` | ≥80% | Stage 1 | 董事会验收标准 §4.1 | 诊断码与类型检查 |
| `internal/interp` | ≥80% | Stage 1 | 同上 | interp 是双路径 oracle，分数不足则 R-03 失效 |
| `internal/codegen` | ≥60% | Stage 2 起 | 同上（codegen/tools） | Stage 1 记录基线；发布前不得低于此值 |
| `internal/cli` | ≥60% | Stage 2 起 | 同上（codegen/tools） | 只作为回归入口，不替代包内单测 |
| 双路径关键路径 | **100% 击杀** | 每阶段 | QA2 追加，依据反作弊 §4.4 与红线 3 | 覆盖：`EmitC` 输出分流、`print` 分型、`str` 格式化、退出码映射、诊断码常量、ARC retain/release 配对 |

**变异算子最小集**：算术替换、比较/边界替换（`<`↔`<=`）、逻辑替换（`&&`↔`||`）、常量替换（0/1/空串）、返回值翻转（true/false）、条件取反、语句删除、字符串字面量替换。每包至少覆盖前 6 类。

**执行规范**：

1. 在干净 checkout 的 sha 上跑；记录工具名+版本+命令。
2. 每个变异体独立应用并还原；跑前跑后对 `*_test.go`、`examples/**`、golden 做 sha256 比对，任何变化即判作弊（R-11/R-12）。
3. 超时计 killed，但必须单列 `timeout` 计数；超时率 >5% 视为变异无效，需修工具或缩范围。
4. 存活变异逐条归类：**真缺陷**（登记缺陷，修复后重跑）／**缺测试**（补测后重跑）／**等价**（二人复核 + 理由）。等价变异不得批量豁免。
5. 报告必须分包、分算子给出数字；只报总分不通过。

### 2.4 R-07 / R-09 回归基线（本轮实测）

| 项 | 命令 | 本轮结果 | Stage 1 阈值 | 判定 |
|---|---|---|---:|---|
| 静态检查 | `go vet ./...` | 本轮未跑全量（工作区有他人未提交改动，避免污染结论） | 0 | 待签 |
| 全量测试 | `go test ./... -count=1 -timeout 300s` | 本轮未跑全量；xfront/sema/interp/cli 四包已通过（见 F-06 命令） | 全绿、SKIP 登记 | 待签 |
| 运行时构建 | `sh impl/runtime/build_rt.sh` | 本轮未跑 | exit 0 | 待签 |
| xfront 覆盖率 | `go test ./internal/xfront -cover` | **73.6%** | ≥80% | **不达标** |
| sema 覆盖率 | `go test ./internal/sema -cover` | **75.7%** | ≥80% | **不达标** |
| interp 覆盖率 | `go test ./internal/interp -cover` | **60.0%** | ≥75% | **不达标** |
| cli 覆盖率 | `go test ./internal/cli -cover` | **46.7%** | ≥60% | **不达标** |
| codegen 覆盖率 | `go test ./internal/codegen -cover -timeout 600s` | **72.4%**（`-cover` 实测 313.7 s） | ≥70% | 达标（余量 2.4 pp） |

> 覆盖率数字是 `-cover` 下的单次测量，只作基线；验收时必须同 sha 复跑，不得引用本文件的数字签字。
>
> **超时口径**：`-cover` 下 `internal/codegen` 实测 313.7 s，已超过 300 s。覆盖跑统一 `-timeout 600s`；普通回归（无 `-cover`）仍用 `-timeout 300s`。两者不得混用，否则会把「慢」误判成「失败」或反之。

---

## 3. 阈值汇总（QA2 门禁口径）

| 指标 | 阈值 | 证据 |
|---|---:|---|
| 双路径一致率 | **100%**（9 单文件 + multi） | `dualpath/result.txt` + 每例 `cmp` 为空 |
| 失败路径双路径 | ≥4 个负向样例，退出码与错误行一致 | `negdual/` |
| 确定性 | 10 次运行 stdout hash 集合 = 1 | `determinism/hashes.txt` |
| Flaky | 0/10 | CI 记录或本地 10 次 |
| 回归 | `vet`+`go test ./...` exit 0，SKIP 全登记 | 七件套 |
| 覆盖率 | 不低于基线；Stage 1 见 §2.4 | 覆盖率报告 |
| 变异分数 | xfront/sema ≥80%、codegen ≥60%、interp ≥80% | 变异报告 |
| 关键路径变异 | 100% 击杀 | 变异报告 + 存活清单 |
| 性能 | hello 编译 ≤5 s/运行 ≤200 ms；parser-seed 解释 <10 s；回归 ≤20% | `time` 输出 |
| 证据完整率 | 100%（七件套） | `evidence/<task-id>/` |

---

## 4. 证据格式（QA2 交付形态）

```
evidence/<task-id>/
├── command.txt                 # 可复制执行；含 XN/OUT 与 sha
├── stdout.txt                  # 汇总输出（含 9 行 result）
├── stderr.txt
├── exit_code.txt               # 汇总脚本退出码 + 每个示例的 i/c 码
├── sha.txt                     # git rev-parse HEAD + git status --short
├── artifact.sha256             # 二进制、每例 stdout、golden 的 sha256
├── acceptance.md               # 验收人签名/时间/结论（通过|不通过）
├── dualpath/                   # 36 个文件：9 例 × <例>.{interp,compiled}.{out,err}
├── negdual/                    # 失败路径 4 例
└── determinism/hashes.txt      # 10 次运行 hash
```

缺任一项 = 任务未完成。不接受截图、聊天记录、口头说明（董事会验收标准 §4.3）。

**存放位置**：董事会 §4.3 规定 `evidence/<task-id>/`；CEO1 交接要求新证据落 `收件箱/CEO1/evidence-<门号>/`。两者结构相同，按 CEO1 当次门禁指定位置执行，本清单不自行改口径。

---

## 5. 缺口与阻塞（只登记，不派工）

| 编号 | 缺口 | 影响 | 建议接收方（仅供 CEO1 决策） |
|---|---|---|---|
| **D-01** | `ci/` 未入库，`git ls-files ci` = 0（ERR-005） | 回归与双路径无法一键复现，§4.3 的「干净 clone 可复现」无法满足 | CEO3-RD2 构建与 CI |
| **D-02** | 无 `impl/difftest/`，双路径无统一框架 | 每次靠手写 shell，集合与超时易漂移 | CEO3-RD3 测试基建 |
| **D-03** | 无变异工具与报告格式 | R-10/R-11 无法评分，「变异 ≥80%」只能写在纸上 | CEO3-RD3 + 二司 QA2 协同 |
| **D-04** | 无 golden 期望值，现用解释器输出作期望（F-03） | 命中反作弊 §4.4-4；两路径同错仍绿 | CEO3-RD3 建 golden；一司 QA1 审条款溯源 |
| **D-05** | 四个包覆盖率低于 Stage 1 阈值：xfront 73.6%、sema 75.7%、interp 60.0%、cli 46.7%（§2.4） | Stage 1 L2 门不可签 | 一司 RD1/RD2 与二司 RD1 补测（不降低阈值） |
| **D-06** | 编译路径 stderr 有 cc 告警且不纳管（F-04） | 告警长期逃逸；stderr 含随机路径不可直接比对 | 一司 RD3（codegen 修冗余括号）+ 三司 RD3（归一化） |
| **D-07** | 9 示例退出码全 0，失败路径双路径零覆盖（F-05） | 退出码映射、`throw`/`fatal`/`try` 未验证 | 一司 QA1 出负向清单，QA2 执行 |
| **D-08** | 测试存在 10 处条件跳过（F-08） | 缺依赖时静默变绿 | CI 统计 SKIP=0；确需跳过须登记批准 |
| **D-09** | 示例自述输出与实际不符（F-11） | 读者与验收人会被注释误导；双路径测不出 | 一司 PM/QA1 修注释或补输出，改动后重跑双路径 |

---

## 6. 明确边界（本轮不验）

- 不验 S3/S5/S7 运行时功能、内存/并发/FFI 语义（二司域）；
- 不验条款追溯、诊断码触发清单、负向否决项（一司 QA1 域，QA2 只消费其结果）；
- 不验文档同步、发布副本一致性、泄漏扫描（三司/COO 域）；
- 不重算台账 PASS 数与里程碑口径（台账单一事实源）；
- 本文件不是门禁结论，不构成「通过/不通过」签署。

---

## 7. 只读声明

本轮只读：未修改任何生产代码，未 commit，未派工，未改动 `收件箱/` 下他人文件。本文件是 `收件箱/CEO1/` 新增的唯一产物。所有实测命令均为只读/临时目录操作（`go test`、`go build -o /tmp`、`cmp`）。

**下一步（等 CEO1 派卡）**：R-01/R-02 按 §2.2 模板出首份双路径证据；R-03 与 D-04 合并推进；R-10 在 D-03 关闭后首次评分。
