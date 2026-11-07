# CEO3-QA2 首轮（只读）：差分 / 变异 / 防假绿 验收清单

> **会话**：`CEO3-QA2-差分与变异`　**角色**：三司 QA2（差分/变异/防假绿）
> **依据**：`收件箱/董事会判决-三司编制与团队扩招-v1.6.0-2026-11-07.md` 第 2 条（2.3 编制表，第 70 行）与第 5 条（首轮只读，第 109 行）
> **域**：三司交付域 `xdk / cli / CI / 测试基建`；本清单覆盖全仓差分与变异判据，工具侧重点在 `cli`、`internal/devtool`、`ci/`
> **日期**：2026-11-07　**性质**：验收清单草案，不是门禁结论，不是派工单
> **基线**：主仓 `dfcf033`（工作区有他人改动）；公开仓 `xnull` `b8ebfa3`，`git status` 干净
> **本轮动作**：只读盘点 + 临时目录（`$TMPDIR/ceo3qa2-mut`）变异探针；**未改生产代码、未 commit、未派工、未碰他人文件**

---

## 0. 结论

1. 清单共 **15 条**（DM-01—DM-15）：差分 5 条、变异 4 条、防假绿 4 条、门禁/覆盖率 2 条。
2. **差分现状不合格**：主仓无 `difftest/`（只在 `wt/qa-1` 未合并）；双路径的期望值就是解释器自输出（`codegen_test.go:86`），不构成正确性 oracle；只比 stdout + 退出码，不比 stderr；9 个示例全部退出码 0，无失败路径差分。
3. **变异现状为零**：无工具、无报告格式、无历史分数；「mutation ≥80%」目前只存在于文档。
4. **防假绿有 4 个已实证漏洞**：① 仓库级台账 golden 在真实布局下**静默 SKIP**；② 台账 `PASS` 是手填字符串，实测把 `LEX-01` 指向不存在的文件仍生成 `PASS` 且退出码 0；③ 未知锚点与畸形行被静默丢弃；④ CI 有 6 项 SKIP 仍返回退出码 0。
5. 5 个变异探针实测 **4 killed / 1 survived（80%，样本太小不评分）**；存活体落在 `status.tsv` 畸形行解析路径，证明「旁表解析」这一测试基建自身缺负例。
6. **本轮不开门禁结论**：在 G-01—G-05 关闭前，任何「测试全绿」都不能作为 L1/L2 依据。

---

## 1. 只读盘点（事实 + 证据）

| # | 事实 | 证据位置 | 对验收的影响 |
|---|---|---|---|
| F-01 | 主仓无 `difftest/` 目录；`wt/qa-1/difftest` 存在但未合并 | `find . -type d -name difftest` → 仅 `./wt/qa-1/difftest`；`收件箱/QA1/验证-S1-02.md:11,51` | 差分为「每次手写脚本」，集合/超时/口径会漂移 |
| F-02 | 主仓无 `ci/`；CI 脚本只在 `pod/e6-toolchain`（`81ec33d`），未合并 | `ls ci` 不存在；`wt/e6-toolchain/ci/run.sh` | CI 门禁当前**在主线上不生效** |
| F-03 | CI 10 项里 04–09 是 SKIP 桩（含「示例双路径」「台账再生成 diff」） | `wt/e6-toolchain/ci/run.sh:11,72-90` | 差分与台账漂移两项门禁均为空壳 |
| F-04 | CI 退出码语义：有 PASS、无 FAIL 即 0，SKIP 不参与判定 | `ci/lib.sh:119-130`（`elif CI_PASS -eq 0 && CI_SKIP -gt 0`） | 实测会得到「PASS=4 FAIL=0 SKIP=6 → exit 0」，构成假绿 |
| F-05 | CI 第 02 项 `go test -timeout 120s ./...`；实测 `internal/codegen` 单包 **91.8s** | `ci/run.sh:63`；本轮 `go test -timeout 120s ./internal/codegen -count=1` → `ok 91.832s` | 超时余量仅 24%，慢机器/冷缓存直接 FAIL（会被当成「代码坏了」） |
| F-06 | 无变异工具、无报告格式、无历史分数 | 全仓 `grep -ni mutation/变异` 只命中文档与 `收件箱/**`；`go-mutesting`/`gomutant` 未安装 | DM-06/DM-07 当前**无法评分** |
| F-07 | 测试规模：26 个 `*_test.go`、164 个 `Test*`、仅 5 处 `t.Run` | `grep -rc 'func Test'`；`grep -h 't.Run(' \| wc -l` | 表驱动程度低，单测粒度粗，变异击杀面窄 |
| F-08 | 覆盖率实测（本轮）：`internal/cli 46.7%`、`internal/devtool 86.1%`、`internal/diag 94.7%` | `go test ./internal/cli ./internal/devtool ./internal/diag -cover` | cli 低于董事会 Stage 1 阈值 `cli ≥60%`（验收标准 §4.1） |
| F-09 | **仓库级台账 golden 在真实布局下 SKIP**：`findLayout` 允许索引在 `Root/spec`，但测试只查 `Root/XNull规范索引` | `impl/internal/devtool/ledger_test.go:79-85`；`devtool.go:29-45`；本轮 `--- SKIP: TestBuildLedgerRepoGoldenScale` | 101 条 / PASS 10 的规模约束**从未执行**，台账可无声漂移 |
| F-10 | golden 常量硬编码 101 / 10 | `ledger_test.go:10-14,100` | 合法地把 `ERR-01` 改成 PASS 会让测试变红，诱导「改常量让绿」——与防假绿冲突 |
| F-11 | `status.tsv` 的 `PASS` 不校验测试文件是否存在，`state` 也不校验合法取值 | `ledger.go:249-269`（`table[cells[0]] = statusEntry{...}`，无 Stat、无枚举校验） | 「台账是单一事实源」实为**自证** |
| F-12 | 未知锚点、畸形行被静默丢弃 | `ledger.go:263`（`if len(cells) < 3 { continue }`）；未命中锚点的条目永不出现 | 手滑 ID 或漏列字段 → 假阴（少算 PASS）或假阳（畸形输入未测） |
| F-13 | `status.tsv` 表头声明「相对 `impl/Tests/`」，但 `impl/Tests/` 不存在；`MEM-02` 又用仓库相对路径 | `status.tsv:1`；`ls impl/Tests` → No such file；`status.tsv:27` | 三种路径口径混用，机器无法统一校验 |
| F-14 | 双路径期望值 = 解释器当次输出 | `codegen_test.go:86`（`want, wantCode := interpRun(...)`） | 共享前端/语义的同一 bug 在两条路径同时出现 → 测试仍绿（董事会验收标准 §4.4 反作弊第 4 条） |
| F-15 | 双路径只比 stdout 与退出码，不比 stderr | `codegen_test.go:88-93`；`multifile_test.go:135-175` | C 告警/运行期告警可长期逃逸 |
| F-16 | 9 个示例全部退出码 0，无失败路径差分 | `evidence/S1-22/dualpath/result.txt`（9 行 `interp=0 compiled=0`） | `throw`/`fatal`/未捕获 `try` 的退出码映射未被双路径覆盖 |
| F-17 | 条件跳过 10 处（缺 cc / 缺 bindings / 缺种子单元 / 无符号链接权限 / 仓库布局不符） | `emit_test.go:176,187`；`ffi/xdk_test.go:21`；`codegen/xdk_seed_test.go:23`；`devtool/resources_test.go:161,172,185,200`；`ledger_test.go:83`；`xpd/parser_test.go:155` | 缺依赖时「绿」等于「没跑」；CI 不统计 SKIP 数 |
| F-18 | 弱断言样例：`TestRunSingleFileDeterministic` 丢弃两次 `Run` 的返回码；`TestDevResGenerates` 只断言输出含 `"a.txt"` | `cli_test.go:78-88`；`dev_test.go:37-60` | 退出码回归、生成器内容错误均可漏过 |
| F-19 | 变异探针（本轮，临时副本）：M1 进制字面量、M2 后缀集、M3 PASS 计数、M5 资源排序 → KILLED；**M4 `status.tsv` 畸形行判定 → SURVIVED** | `$TMPDIR/ceo3qa2-mut/probe.sh` 及 `M*.log` | 测试基建自身缺负例；80% 仅作方法演示，不作分数 |
| F-20 | 台账存在两份内容相同的副本：主仓根（未跟踪）与 `xnull/spec/`（已跟踪），sha 均为 `142939d0…` | `shasum -a 256`；`.gitignore:/xnull/` | 两份都「可编辑」，CI 第 06 项又是 SKIP → 漂移无人发现 |

---

## 2. 验收清单（15 条）

> 全部命令默认在 `xnull/` 根执行；`XN=$TMPDIR/xnull`。证据进 `evidence/<task-id>/` 七件套并附 `sha.txt = 被测 commit`。

### 2.1 差分（DM-01—DM-05）

| 编号 | 验什么 | 怎么验 | 通过判据 / 阈值 | 反例（出现即不通过） |
|---|---|---|---|---|
| **DM-01** | 差分有唯一入口、集合固定、可复现 | `difftest/run.sh --list` 列出 `9 单文件 + examples/multi + 负向集`；每个 case 带 `id/oracle/timeout` | 集合清单可机读；同一 sha 两次运行 case 集合与结果完全一致；单例超时 ≤120s，超时计 FAIL | 靠 `examples/*.x` glob 隐式纳入；新增示例自动进集但报告不列集合；手写 shell 每次不同 |
| **DM-02** | 期望值独立锚定，不得用解释器当唯一 oracle | 为 9+multi 固化 golden（stdout、退出码、stderr 错误行）；三方比对 `compiled == golden == interp` | 两路径各自对 golden；golden 变更必须带条款 ID + 批准记录；`interp` 与 `compiled` 同错即暴露 | 直接复用 `codegen_test.go:86` 写法；把当前输出 `cp` 成 golden；改 golden 让红变绿 |
| **DM-03** | 失败路径差分 | 至少 6 个负向样例：未捕获 `throw`、`fatal`、`try` 未捕获、缺 `main`、语义错误、运行时 panic | 退出码按 S4 §7.2 逐一相等；stdout 逐字节；stderr 的 `error[CODE]` 行相等（路径白名单化）；无栈回溯 | 只测 happy path；把「编译失败」当「解释失败」；负例只断言非 0 |
| **DM-04** | 多文件/多模块差分 | `examples/multi` 显式进集；`LoadUnits` 顺序确定性；两次 `EmitC` 取 sha | stdout/退出码一致；加载顺序固定；两次 C 源码 hash 相同；跨文件符号冲突有负例 | 只测单文件；用「能编译」代替「输出一致」 |
| **DM-05** | 确定性与 flaky 门 | 全量差分连跑 10 次，收集输出 sha 集合 | `len(sha 集合) == 1`，10/10 通过，flaky = 0/10；失败必须附 10 次原始日志 | 两次结果不同仍判过；用 `-count=1` 掩盖顺序依赖；把偶发失败标注「已知问题」放行 |

### 2.2 变异（DM-06—DM-09）

| 编号 | 验什么 | 怎么验 | 通过判据 / 阈值 | 反例 |
|---|---|---|---|---|
| **DM-06** | 变异工具固定、报告可机读 | 固定工具与版本（写入 `difftest/mutation/toolchain.txt`）；输出 `id/package/operator/status/kill_reason/ms` | 报告含 `total/killed/survived/equivalent/timeout` 分列；每条变异可单条复现；工具版本与命令可复制 | 只贴总分；等价变异不单列；超时混入 killed 不标注 |
| **DM-07** | 分层阈值（董事会 §4.1，不得现场下调） | 逐包跑，分包计分 | **Stage 1**：interp ≥80%、sema ≥80%；**Stage 2+**：codegen ≥60%、tools（devtool/cli/CI）≥60%；`exitcode`/`diag`/`status.tsv` 解析 **≥90%**（小包高要求） | 只报全仓总分；把 tools 并入核心算；样本 <50 体就宣称达标 |
| **DM-08** | 关键路径变异 **100% 击杀** | 单独标注关键算子：双路径输出、退出码映射、诊断码、`status.tsv` 解析、`gofmt/vet` 门禁、CI 退出码 | 关键路径存活数 = 0；任一存活即阻断 | 用总分数掩盖关键路径存活；「等价」豁免不收口 |
| **DM-09** | 变异不可作弊 | 每个变异体独立应用并还原；跑前跑后对 `*_test.go`、`examples/**`、golden、`status.tsv` 做 sha256 | 测试资产 sha 前后一致；工作区干净；超时率 ≤5%；存活体三分类（真缺陷/缺测试/等价，等价需二人复核） | 变异体连带改测试；批量应用不隔离；改 golden 后重跑 |

**变异算子最小集**：算术替换、比较/边界替换（`<`↔`<=`）、逻辑替换（`&&`↔`||`）、常量替换（0/1/空串）、布尔返回翻转、条件取反、语句删除、字符串字面量替换。每包至少覆盖前 6 类。

### 2.3 防假绿（DM-10—DM-13）

| 编号 | 验什么 | 怎么验 | 通过判据 / 阈值 | 反例 |
|---|---|---|---|---|
| **DM-10** | 跳过预算：SKIP ≠ PASS | 每次门禁统计 `--- SKIP` 条数并对每条登记「原因/依赖/负责人/补跑条件」 | **无条件 skip = 0**；条件 skip 缺依赖时判 **FAIL（环境不满足）**，不判 SKIP；SKIP 数进门禁报告 | 依赖缺失静默变绿；`t.Skip` 未登记；用 `-short` 跳过慢测 |
| **DM-11** | 断言可区分性 | 每阶段随机抽 ≥20% 用例人工审查（种子公开）；扫描恒真断言与「只断言不 panic」 | 恒真断言 0；无 `assert(true)` 式；期望值可溯源到条款 ID；无硬编码被测输出 | 把实际输出抄进断言；只判 `err == nil`；断言被 `if false` 包住 |
| **DM-12** | 台账 `PASS` 必须可机验 | 建立 `锚点 → 测试文件 → 测试函数/命令 → 最近一次结果 → sha` 五列映射；生成器校验：锚点存在、状态枚举合法、测试文件存在、测试函数存在 | 任一 `PASS` 行缺可执行证据即 FAIL；未知锚点/畸形行**报错退出非 0**；`impl/Tests/` 口径统一或删除该表述 | 手填 `PASS` 指向不存在文件；未知 ID 静默丢弃；状态写成 `pass`/`PASS ` 仍出表 |
| **DM-13** | CI 门禁语义正确 | `bash ci/run.sh` 后读 `steps.jsonl` | **任一 SKIP 必须使整体退出码非 0**（或显式 `--allow-skip` 白名单且记入报告）；FAIL=0 且 SKIP=0 才允许 0；CI 脚本必须已在主线 | 6 SKIP 仍 exit 0；CI 只在他人 worktree；`--only` 单步结果冒充全量 |

### 2.4 门禁与覆盖率（DM-14—DM-15）

| 编号 | 验什么 | 怎么验 | 通过判据 / 阈值 | 反例 |
|---|---|---|---|---|
| **DM-14** | 覆盖率门（工具包） | `go test ./internal/cli ./internal/devtool -cover`；与基线比 | Stage 1：cli ≥60%、tools ≥70%；Stage 2：≥75%；**不得低于上一阶段**；下降必须书面说明 | 用 `-coverpkg` 虚增；把 `cli` 排除在范围外；覆盖率下降无说明 |
| **DM-15** | 测试资产完整性 | `git diff --stat <base>..<sha>`；`git diff --diff-filter=D --name-only`；比对 `*_test.go`、`examples/*.x`、golden、`status.tsv` | 无未批准删除；期望值变更逐条有理由与条款 ID；新增能力带新示例（红线 3）；台账两份副本 sha 一致 | 删用例降耗时；放宽断言；只改 `status.tsv` 不改测试就宣告 PASS |

---

## 3. 现状与阈值的差距（本轮实测）

| 项 | 现状 | 阈值 | 差距 |
|---|---|---|---|
| 差分框架 | 主仓无 `difftest/`；仅 2 个 Go 测试内联实现 | DM-01 | **阻断** |
| 差分 oracle | 期望值 = 解释器输出 | DM-02 | **阻断** |
| 失败路径差分 | 0 个 | DM-03 要求 ≥6 | **阻断** |
| multi 差分 | 有 1 个 Go 用例 | DM-04 | 部分满足（未纳入统一报告） |
| 变异分数 | 无工具，无法评分 | DM-07 | **阻断** |
| SKIP 统计 | 10 处条件跳过，CI 不统计 | DM-10 | **阻断** |
| 台账可机验 | `PASS` 自证（已实测可指向不存在文件） | DM-12 | **阻断** |
| CI 退出码 | 6 SKIP 仍 exit 0 | DM-13 | **阻断** |
| cli 覆盖率 | 46.7% | ≥60% | 差 13.3 个点 |
| devtool 覆盖率 | 86.1% | ≥70% | 达标 |
| diag 覆盖率 | 94.7% | ≥90%（小包要求） | 达标 |
| 全量测试 | 164 个 Test 全绿（本机 macOS/amd64，go1.27.3） | — | 绿不等于有效，见 §2.3 |

---

## 4. 缺口登记（只登记，不派工）

| # | 缺口 | 证据 | 严重度 | 建议归属（仅建议） |
|---|---|---|---|---|
| G-01 | 差分框架未入库，口径靠手写 | F-01 | P0 | CEO3-RD3 测试基建 |
| G-02 | 无变异工具与报告格式，阈值无法评分 | F-06 | P0 | CEO3-RD3 + QA2 共同定义 |
| G-03 | 台账 `PASS` 无机器校验，可自证 | F-11/F-12 | P0 | CEO3-RD1（devtool）+ QA2 验 |
| G-04 | 仓库级台账 golden 静默 SKIP | F-09 | P0 | CEO3-RD1 |
| G-05 | CI 未入主线且 SKIP 不影响退出码 | F-02/F-03/F-04 | P0 | CEO3-RD2 |
| G-06 | 双路径以解释器为 oracle、不比 stderr、无失败路径 | F-14/F-15/F-16 | P1 | CEO1-QA2 主责，三司提供夹具 |
| G-07 | `status.tsv` 三种路径口径 | F-13 | P1 | CEO3-RD1 |
| G-08 | 条件跳过 10 处未纳入门禁统计 | F-17 | P1 | 各司 QA + CEO3-RD3 |
| G-09 | cli 覆盖率 46.7% 低于 Stage 1 | F-08 | P1 | CEO3-RD1 |
| G-10 | CI 第 02 项 120s 与实测 91.8s 余量过小 | F-05 | P2 | CEO3-RD2 |
| G-11 | 台账两份副本（根 / `xnull/spec`） | F-20 | P2 | CEO3-RD2 + PJ 定「哪份是唯一源」 |
| G-12 | 弱断言：确定性用例丢返回码、资源生成只查子串 | F-18 | P2 | 对应域 RD + QA |

---

## 5. 复现命令（本轮实际执行）

```bash
# 1) 基线
cd xnull && git rev-parse HEAD && git status --porcelain      # b8ebfa3，干净

# 2) 全量测试（全绿，但注意 SKIP）
cd impl && go vet ./... && go test ./... -count=1

# 3) 覆盖率（三司工具包）
cd impl && go test ./internal/cli ./internal/devtool ./internal/diag -count=1 -cover
# cli 46.7% / devtool 86.1% / diag 94.7%

# 4) 台账 golden 跳过实证
cd impl && go test ./internal/devtool -count=1 -v | grep -A0 'SKIP:'
# --- SKIP: TestBuildLedgerRepoGoldenScale

# 5) CI 超时余量
cd impl && go test -timeout 120s ./internal/codegen -count=1   # ok 91.832s

# 6) 变异探针（临时副本，不改仓库）
bash "$TMPDIR/ceo3qa2-mut/probe.sh"
# M1 KILLED / M2 KILLED / M3 KILLED / M4 SURVIVED / M5 KILLED

# 7) 台账自证实证（临时副本）
#    把 LEX-01 指向 nonexistent/such_test.go + 追加 ZZZ-99 与畸形行
cd impl && go run ./cmd/xnull dev ledger
# 结果：exit=0；LEX-01 仍为 PASS；总计 PASS 11；ZZZ-99 未入库；畸形行无告警
```

---

## 6. 本轮不做 / 边界

- 不改生产代码、不改测试、不 commit、不派工；只写本文件。
- 变异探针只在 `$TMPDIR/ceo3qa2-mut/repo` 副本执行，仓库 `git status` 保持干净（已核）。
- 不评价他人域的实现质量（xfront/sema/interp/codegen 的正确性归各司），只评价「测试是否能抓住错误」。
- 不把本清单当门禁结论；DM-01—DM-15 的关闭与否由 CEO3 汇总后交董事会。

## 7. 需要 CEO3 决策的三件事（一次列全）

1. **唯一台账源**：主仓根副本与 `xnull/spec` 副本，哪一份作为 CI 比对基准？（G-11，影响 F-10 的 golden 常量处理）
2. **CI 是否进主线**：`pod/e6-toolchain` 的 `ci/` 是否先只合 01–03 + 10，还是等 04–06 实现齐再合？（G-05）
3. **变异工具选型**：引入 `go-mutesting`（Go 生态、维护弱）还是自研最小算子集（可控、需 RD3 工时）？DM-07 的 tools ≥60% 在工具落地前无法评分，需明确这是「阻断」还是「带账推进」。
