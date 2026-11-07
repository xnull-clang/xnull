# CEO3-RD3 首轮：差分 / 夹具 / 测试基建盘点 v1.0.0

本文件为只读盘点，无 commit、无生产代码改动。

> **角色：CEO3-RD3-测试基建**　**域：`difftest/**`、`impl/Tests/**`**　**日期：2026-11-07**
> **依据**：董事会判决-三司编制与团队扩招 v1.6.0 第 2.3 条（RD3 职责与写入域）、第 3 条（一文件一写入者）、第 5 条（首轮只读，48 小时）；董事会验收标准 v1.0.0 §2.1（G-02/G-05）、§3 D/E/G 类、§4.1 质量阈值。
> **性质：只读盘点 + 缺口登记 + 建议卡草案。未派工、未 commit、未改生产代码、未碰他人文件。**
> **唯一写入：`收件箱/CEO3/CEO3RD3-首轮.md`。**

---

## 0. 结论（先给）

1. **我的两个交付目录在主仓是空的**：`git ls-tree -r main` 中 `difftest/` = 0、`impl/Tests/` = 0。`impl/Tests/` 从建仓起就不存在，但台账与 `status.tsv` 的表头都写着「用例文件（相对 `impl/Tests/`）」——**目录契约空转**，实际路径相对 `impl/`。
2. **唯一的差分资产是未入库的遗留物**：6 个脚本 / 1189 行 + 13 个夹具 / 184 行，全部躺在 `wt/qa-1/difftest/`，`git status` 显示 `?? difftest/`。换机器、干净 clone、任何门禁都用不到。**G-02「编译路径与解释路径一致」目前只有一条 Go 测试在守，没有独立差分框架。**
3. **差分框架本身是半成品**：默认只跑 3 个示例（`run.sh:26`），只比 stdout + 退出码（`run.sh:179-193`），不比 stderr/诊断；证据落点 `evidence/S1-04/`（`run.sh:25`）**不存在**，说明它从未在主线留过证据。
4. **有一个已失效的脚本**：`verify-s1-03p.sh:50` 仍把夹具 materialize 成 `.xn`，而 S1-22 之后 CLI 只认 `.x`（`impl/internal/cli/cli.go:77-91`）。实测 `.xn` → `error[CLI-003] 找不到 xnull.project`，退 2。**该脚本现在 7/7 必红。**
5. **门槛缺口是硬的**：覆盖率实测 `interp 60.0%`（要求 ≥75）、`sema 75.7%`（≥80）、`xfront 73.6%`（≥80）、`cli 46.7%`（≥60），全部不达标；**变异测试 0 设施**（G-05 无载体）；**无 10 次连续跑/无 flaky 门**；`cmd/*`、`exitcode` 无测试载体。
6. **建议 3 张卡**：① difftest 入库 + 9 示例（含 `multi`）全量双路径；② 差分结果契约 + 负向/诊断夹具；③ 覆盖率 + 变异 + flaky 最小闭环。卡号 `S0-32/33/34` 仅为占位，最终编号由 CEO3/CEO2 定。

---

## 1. 盘点口径与实测基线

命令均在 `/Users/vjs/Desktop/XNull-Lang` 执行，全部只读（`go test` 缓存写在仓库外）。

| # | 项 | 命令 | 实测 |
|---|---|---|---|
| 1 | 差分入库 | `git ls-tree -r --name-only main \| grep -c '^difftest/'` | **0** |
| 2 | 测试目录入库 | `git ls-tree -r --name-only main \| grep -c '^impl/Tests/'` | **0** |
| 3 | 遗留副本 | `cd wt/qa-1 && git status --short` | `?? difftest/` |
| 4 | 脚本规模 | `wc -l wt/qa-1/difftest/*.sh` | 6 文件 / **1189 行** |
| 5 | 夹具规模 | `find wt/qa-1/difftest/cases -type f` | **13 个** / 184 行，2 组（s1-03、s1-06） |
| 6 | Go 测试载体 | `find impl -name '*_test.go'` | **26 文件 / 5153 行 / 164 个 Test 函数** |
| 7 | 生产代码 | `find impl -name '*.go' ! -name '*_test.go'` | 45 文件 / 16452 行（测试:生产 ≈ 1:3.2） |
| 8 | 全量测试 | `cd impl && go test ./... -count=1 -timeout 120s` | 全绿，wall **38.28s**；最慢包 codegen **37.3s** |
| 9 | 覆盖率 | `cd impl && go test ./... -count=1 -cover` | 见 §2.3（4 包不达标） |
| 10 | 台账 | `grep -c '^| [A-Z]\{2,6\}-[0-9]' XNull一致性用例台账-v1.0.0.md` | **101 条**：PASS 10 / 部分 19 / 未实现 **72** |

---

## 2. 现状

### 2.1 `difftest/**` 现有资产（全部未跟踪，位于 `wt/qa-1`）

| 文件 | 行数 | 用途 | 现状判断 |
|---|---:|---|---|
| `run.sh` | 261 | 通用差分：`run --interp` vs `build` + 执行，比 stdout/退出码 | **可用但覆盖窄**：默认 3 示例（`:26`），无 stderr 比对，无 JSON，证据落 `evidence/S1-04`（`:25`，不存在） |
| `accept-b-full.sh` | 502 | S0-22P 七项硬指标 + 3 负例/3 正例自测 | **半失效**：第 5/6 项依赖 `evidence/S0-22P/golden`（`:44`），该目录不存在；第 6 项 golden 由已删的 Python 工具产出 |
| `gen-golden-s0-22p.sh` | 121 | 用 Python 三脚本生成 golden | **死刑**：`:26-28` 要求 `impl/tools/{check_specs,gen_ledger,gen_resources}.py`，Python 工具已在 `a96d380` 删除 → golden 不可再生 |
| `verify-s1-03p.sh` | 83 | S1-03P break/continue 独立验证（7 例） | **已失效**：`:50` 生成 `.xn`，CLI 只认 `.x`（`cli.go:77-91`）→ 实测 `CLI-003` exit 2 |
| `verify-s1-06p.sh` | 120 | S1-06P 多文件独立验证（2 例 + 1 发现） | 可用：materialize 保持 `.x`（`:63-73`），但硬编码 `E4_ROOT` |
| `verify-s0-25.sh` | 102 | S0-25 资源子目录会签（9 例） | 可用但硬编码 `evidence/S0-25/bin/xnull`、`evidence/S0-25/fixtures` |

**夹具清单（13 个，全部 `.xn.fixture`，S1-22 后与主仓 `.x` 口径不一致）**

| 组 | 文件 | 断言来源 |
|---|---|---|
| s1-03（7） | `while_direct`、`while_nested_if`、`do_while`、`for_in_container`、`break_labeled_outer`、`continue_while`、`continue_labeled_outer` | `verify-s1-03p.sh` 内联期望值（`$'3\n3'` 等） |
| s1-06（6） | `mutual/{main,lib/alpha,lib/beta}`、`stress/{main,lib/alpha,lib/beta}` | `verify-s1-06p.sh` 内联期望 `12/5`；`stress` 是已知失败变体 |

**结论：现有夹具 13 个全部是正向用例，0 个负向/诊断夹具；期望值写死在脚本里，不在夹具旁；没有任何用例 ID ↔ 条款映射。**

### 2.2 Go 测试载体（主仓唯一可执行的质量资产）

| 包 | 测试文件 | 测试函数 | 说明 |
|---|---:|---:|---|
| `xfront` | 4 | 44 | 词法/语法/语句/编译单元 |
| `interp` | 3 | 28 | 含 `hard_test.go` 硬语义 |
| `sema` | 6 | 34 | 类型/声明/策略/XDK |
| `codegen`（含 ffi） | 6 | 16 | **唯一的自动化双路径：`TestExamplesCompileMatchesInterp`** |
| `cli` | 2 | 6 | 命令/退出码 |
| `devtool` | 3 | 22 | 台账/资源/规范守门 |
| `diag` / `xpd` | 2 | 8 | 诊断/工程文件 |
| `cmd/xnull`、`cmd/xnpt`、`exitcode` | 0 | 0 | **无测试文件** |

自动化双路径现状（`impl/internal/codegen/codegen_test.go:73-96`）：`filepath.Glob("../../../examples/*.x")` → 覆盖 9 个单文件示例，**不覆盖 `examples/multi`**（`grep -rn "examples/multi" --include=*.go impl` 无结果）。我手工补测 `multi` 双路径：解释/编译 stdout 均 `[xnull]/25/[norm=25]`，逐字节一致，退出码 0——**能被测，但没人测**。

### 2.3 覆盖率实测（`go test ./... -cover`，2026-11-07，dfcf033）

| 包 | 实测 | 验收标准 v1.0.0 §4.1 阈值 | 判定 |
|---|---:|---:|---|
| `internal/xfront` | **73.6%** | ≥80%（Stage 1） | **不达标** |
| `internal/sema` | **75.7%** | ≥80%（Stage 1） | **不达标** |
| `internal/interp` | **60.0%** | ≥75%（Stage 1） | **不达标** |
| `internal/cli` | **46.7%** | ≥60%（工具包） | **不达标** |
| `internal/codegen` | 72.4% | ≥70%（Stage 2） | 达标（余量 2.4pt） |
| `internal/codegen/ffi` | 80.2% | — | 达标 |
| `internal/devtool` | 86.1% | ≥70%（工具包） | 达标 |
| `internal/diag` | 94.7% | — | 达标 |
| `internal/xpd` | 76.5% | — | 达标 |
| `cmd/xnull`、`cmd/xnpt` | 0.0% | — | 无测试文件 |
| `internal/exitcode` | 无测试文件 | — | 无载体 |

**耗时注意**：覆盖率插桩使 codegen 从 37.3s 膨胀到 274s、cli 从 12.6s 到 105s。CI 现行 `-timeout 120s`（`wt/e6-toolchain/ci/run.sh:71`）**不能直接套在 `-cover` 上**，否则 codegen 必被误杀。

### 2.4 台账与映射

| 口径 | 数值 | 来源 |
|---|---|---|
| 台账锚点 | 101 条（PASS 10 / 部分 19 / 未实现 72） | `XNull一致性用例台账-v1.0.0.md` |
| 证据旁表 | 35 行（PASS 10 / 部分 19 / 未实现 6） | `impl/docs/conformance/status.tsv` |
| 有测试文件的锚点 | 29 条（其余 72 条为 `—`） | 台账「用例文件」列 |
| 条款表 / 诊断表 / 映射表 | `spec-clauses.tsv`、`diagnostics.tsv`、`clause-test-map.tsv` **均不存在** | `find . -name 'spec-clauses*' -o -name 'diagnostics.tsv' -o -name 'clause-test-map*'` → 0 |

口径漂移：`impl/docs/conformance/ledger-restructure.md` 记「PASS 8 / 部分 16 / 未实现 77」，与当前台账「10/19/72」不一致，属文档未同步（**不是我域内要修的东西，登记给 CEO3**）。

---

## 3. 缺口（12 条，分「未实现 / 部分 / 可疑」）

> 每条给 `文件:行` 或测试名 + 可复制复核命令；严重度按对阶段门的影响排序。

### 3.1 未实现（4 条）

| # | 缺口 | 证据 | 复核命令 | 影响 |
|---|---|---|---|---|
| **G-01** | `difftest/**` 未入库；唯一副本在 `wt/qa-1` 未跟踪 | `git ls-tree -r main \| grep -c '^difftest/'` = 0；`cd wt/qa-1 && git status --short` → `?? difftest/` | 同左 | 干净 clone 无差分；C3/D5 只能人工双跑；`wt/` 副本按 L1 口径不算入库 |
| **G-02** | `impl/Tests/` 不存在，但台账与旁表都声明「相对 `impl/Tests/`」 | `XNull一致性用例台账-v1.0.0.md:3`、`impl/docs/conformance/status.tsv:1`；`ls impl/Tests` → No such file | `ls impl/Tests; git ls-tree -r main --name-only \| grep -c '^impl/Tests/'` | 72 条「未实现」无落点；新测试该放哪、谁签，无目录契约 |
| **G-03** | **变异测试 0 设施** | 全仓 `grep -ril "mutation\|变异"` 只命中 md 文档，无脚本/无工具/cmd | `grep -rl "mutation" --include='*.go' --include='*.sh' .` → 0 | G-05「不存在假绿」、§4.1「interp/sema ≥80%」无载体，阶段门永远判不了 |
| **G-04** | 无 10 次连续跑 / 无 flaky 门 | 无脚本；`Difftest`/CI 均无重复执行 | `grep -rn "10 次\|flaky" --include='*.sh' --include='*.go' .` → 0 | E 类「确定性」、§4.1「Flaky 0/10」无证据来源 |

### 3.2 部分（6 条）

| # | 缺口 | 证据 | 复核命令 | 影响 |
|---|---|---|---|---|
| **G-05** | 差分默认只跑 3 个示例，`examples/multi` 不在任何自动化里 | `difftest/run.sh:26`（`DEFAULT_CASES`）；`grep -rn "examples/multi" --include='*.go' impl` → 无结果 | `bash difftest/run.sh`（需先入库） | G-02「所有纳入示例逐字节一致」不成立；`multi` 我手工验过一致，但无回归保护 |
| **G-06** | `run.sh` 只比 stdout + 退出码，不比 stderr/诊断 | `difftest/run.sh:179-193`（`cmp -s io co` + `rc` 比较，`err` 两文件只落盘不比较） | 读脚本 | D 类要求「诊断一致」；诊断文本/码漂移漏检 |
| **G-07** | 证据落点不存在，差分从未留证 | `difftest/run.sh:25` 指向 `evidence/S1-04/artifacts`；`ls evidence/S1-04` → No such file | `ls evidence/S1-04 2>&1` | 七件套口径无产物；「跑过」无 sha、无 stdout、无 exit_code |
| **G-08** | `verify-s1-03p.sh` 在 S1-22 后已失效 | `difftest/verify-s1-03p.sh:50` 生成 `.$name.xn`；CLI 只认 `.x`：`impl/internal/cli/cli.go:77-91` | `cp cases/s1-03/while_direct.xn.fixture /tmp/a.xn && xnull run --interp /tmp/a.xn` → `error[CLI-003]` exit 2 | 7 条 break/continue 回归**当前不可跑**；若有人信它的历史结论，是假绿 |
| **G-09** | golden 链断裂：`accept-b-full.sh` 第 5/6 项永久不可跑 | `difftest/gen-golden-s0-22p.sh:26-28` 依赖已删的 `impl/tools/*.py`（删除提交 `a96d380`）；`difftest/accept-b-full.sh:44` 默认 golden = `evidence/S0-22P/golden`，`ls evidence/S0-22P` → No such file | 两条命令 | 「台账逐行一致」「Go vs Python 资源输出一致」两项证据不可再生；只能引用历史结论，不能复验 |
| **G-10** | 覆盖率 4 包不达标，且覆盖率没有执行入口 | §2.3 实测；`difftest/` 无 `cover.sh`，CI 无覆盖步骤 | `cd impl && go test ./... -count=1 -cover` | F 类「覆盖率不低于基线」无基线文件；Stage 1 门直接不通过 |

### 3.3 可疑（2 条）

| # | 缺口 | 证据 | 复核命令 | 影响 |
|---|---|---|---|---|
| **G-11** | 10 处环境依赖 `t.Skip`，换机器可静默跳过整段 | `codegen/ffi/emit_test.go:176,187`；`codegen/ffi/xdk_test.go:21`；`codegen/xdk_seed_test.go:23`；`devtool/resources_test.go:161,172,185,200`（符号链接）；`devtool/ledger_test.go:83`；`xpd/parser_test.go:155` | `grep -rn "t.Skip" --include='*_test.go' impl \| wc -l` → 10 | 本机实测 **0 skip**（`go test ./... -v \| grep -c SKIP` = 0），但容器/无符号链接环境会绿得莫名其妙；E2「无未批准跳过」缺机械门 |
| **G-12** | `difftest/.bin` 未被忽略，入库时会把二进制带进版本库 | `.gitignore` 无 `difftest` / `.bin` 条目；脚本在 `run.sh:90,96` 创建该目录 | `grep -n "difftest\|\.bin" .gitignore` → 无 | 一旦 `git add difftest`，macOS 二进制入库；跨平台失效 |

---

## 4. 变异与防假绿基线（现状 = 0）

| 维度 | 现状 | 最低可行方案（不新增依赖） |
|---|---|---|
| 变异算子 | 0 | Go 源码文本级 3 算子：比较符翻转（`<`↔`>=`）、整型常量 ±1、条件取反。固定 seed + 白名单文件 |
| 变异范围 | — | `internal/interp/**`、`internal/sema/**`（阈值 ≥80%，§4.1） |
| 分数计算 | — | 被杀变异数 / 可编译变异数；报告落 `evidence/<卡号>/mutation.tsv` |
| 防假绿 | 无 | 三个探针：① 篡改期望值 1 字节 → 必 FAIL；② 删 1 个断言 → 变异分数必降；③ 注入 `t.Skip` → 门必 FAIL |
| 确定性 | 无 10 次跑 | `for i in $(seq 10)` 跑同一用例集，比 stdout sha + exit code，任一不同即 FAIL |
| 夹具自证 | `accept-b-full.sh --self-test` 有 3 负例/3 正例，但只覆盖台账/资源两项 | 把同一模式推广到差分：改 stdout 1 字节、改退出码、改诊断码 → 三项都必须被抓 |

---

## 5. 前 3 张建议卡（占位编号 S0-32/33/34，最终编号由 CEO3/CEO2 定）

> 三卡都在我的写入域内（`difftest/**`），彼此不重叠文件；依赖关系 卡1 → 卡2/卡3。

### 卡 1（拟 S0-32）`RD3-difftest入库与全量双路径`　严重度 **P0**

| 项 | 内容 |
|---|---|
| 背景 | G-01/G-05/G-07/G-08/G-12：差分资产不入库、只跑 3 例、不覆盖 multi、脚本已失效 |
| 交付物 | ① `difftest/` 入库（run.sh、cases/、README）；② 修 `verify-s1-03p.sh` 的 `.xn`→`.x`；③ `run.sh` 支持目录/多文件（`examples/multi`）与全量 9 示例；④ 复制夹具到 `difftest/cases/` 并改后缀 `.x.fixture`；⑤ `difftest/.bin/` 进 `.gitignore`；⑥ 证据落 `evidence/S0-32/` 七件套 |
| 验收 | 干净 clone `bash difftest/run.sh examples/*.x examples/multi/main.x` → **10/10 MATCH**，exit 0；`git ls-files difftest \| wc -l` ≥ 8；`git check-ignore difftest/.bin/xnull` 命中；S1-03 的 7 例重跑 **7/7 PASS** |
| 证据 | `evidence/S0-32/` 七件套 + `run.sh` 原始输出 |
| 写入域 | `difftest/**`（卡 1 唯一写者）；`.gitignore` 一行属根文件，须由卡面另列唯一写者（建议 RD2），我不越域 |
| 依赖 | 无（可立即开工，但要等 S0-28 写权生效） |

### 卡 2（拟 S0-33）`RD3-差分结果契约与负向夹具`　严重度 **P0**

| 项 | 内容 |
|---|---|
| 背景 | G-06：只比 stdout+退出码；0 个负向/诊断夹具；无 machine-readable 结果 |
| 交付物 | ① `run.sh` 增 JSONL 输出（`case`/`stdout_sha`/`stderr_sha`/`exit`/`status`/`ms`）；② stderr 比对（诊断码 + 位置，来自 `diagnostics.tsv`，缺失时按「仅比对诊断码文本」降级并标注）；③ `difftest/cases/neg/*`（≥8 例：类型错误、未绑定名、非法转义、缺入口、导入环、越界、非空类型 null、禁构造）；④ 夹具头统一 `// case: <ID> clause: <条款ID> expect-exit: <n>`；⑤ SKIP 一律计 FAIL |
| 验收 | 负向 **8/8** 捕获：每条断言「非 0 + 指定诊断码 + `文件:行:列`」；自测 3 负例（改 stdout 1 字节 / 改退出码 / 改诊断码）全部被抓；正例对照 3/3 通过；JSONL 可被 `jq -e` 解析 |
| 证据 | `evidence/S0-33/` 七件套 + `results.jsonl` |
| 写入域 | `difftest/**` |
| 依赖 | `diagnostics.tsv` 由一司/PM 提供（CEO3 协调）；未提供前按降级口径并在验收单「未测项」声明 |

### 卡 3（拟 S0-34）`RD3-覆盖率/变异/flaky 最小闭环`　严重度 **P1**

| 项 | 内容 |
|---|---|
| 背景 | G-03/G-04/G-10：覆盖率 4 包不达标且无入口；变异 0 设施；无 10 次连续跑 |
| 交付物 | ① `difftest/cover.sh`：`-coverprofile` + 阈值表（xfront/sema 80、interp 75、cli 60、codegen 70），超时 600s，输出 `coverage.txt` + 不达标清单；② `difftest/mutate.sh`：3 算子、固定 seed、白名单，输出 `mutation.tsv` 与分数；③ `difftest/flaky.sh`：10 次连跑比 sha；④ `difftest/baseline/coverage-baseline.txt`（记录当前值，作为「不下降」基线） |
| 验收 | `cover.sh` 当前 **exit 1** 并精确列出 4 个不达标包（xfront/sema/interp/cli）；`mutate.sh` 同 seed 两次分数一致；`flaky.sh` 10/10 一致；基线文件入库 |
| 证据 | `evidence/S0-34/` 七件套 + `coverage.txt` + `mutation.tsv` |
| 写入域 | `difftest/**` |
| 依赖 | 卡 1（目录已入库）；变异算子涉及读 `impl/internal/**`（只读，不写） |
| 风险 | `-cover` 下 codegen 274s，脚本超时必须 ≥600s，且**不得**并入 `ci/run.sh` 的 `-timeout 120s` 步骤 |

---

## 6. 未测项（如实声明）

1. 未实跑 `wt/qa-1/difftest/run.sh` 与 `accept-b-full.sh`：前者会写 `evidence/S1-04/`（域外），后者 golden 缺失且第 1 项会跑全量测试；只做静态审查 + 关键假设点验证（`.xn` 实测失效）。
2. 未跑 `verify-s1-06p.sh`（依赖 `wt/e4-codegen` 与 overlay，其结论已有 `收件箱/QA1/验证-S1-06.md`）。
3. 未跑变异（无设施）——本文件给的是方案，不是分数。
4. 未做 10 次连续跑（单次全量 38s，10 次约 6.5 分钟，属卡 3 交付范围）。
5. 未审 `impl/docs/conformance/**` 除 `status.tsv`/`ledger-restructure.md` 外的内容。
6. 未对 164 个 Test 函数做断言质量抽查（恒真/顺序依赖），只统计了 `t.Skip` 与覆盖率。
7. 覆盖率数据来自本机 macOS/amd64、Go 1.27.3，未在 Linux CI 环境复测。
8. 本文件不构成任何卡的「通过」，不签 L1/L2。

---

## 7. 自查

```
$ cd /Users/vjs/Desktop/XNull-Lang && git status --porcelain impl difftest examples ci
（空）

$ git ls-tree -r --name-only main | grep -c '^difftest/'
0
$ git ls-tree -r --name-only main | grep -c '^impl/Tests/'
0
```

- 只读：仅执行 `git ls-tree` / `git status` / `find` / `grep` / `wc` / `go vet` / `go test` / `go build`（产物落 `mktemp -d`，已删）；未改生产代码、未改测试、未删证据、未 commit、未派工、未碰他人文件。
- 唯一写入：`收件箱/CEO3/CEO3RD3-首轮.md`。
- 与 `CEO3QA1-首轮.md` 的分工：QA1 出 L1 验收清单与判据；本文件出**差分/夹具/测试基建的现状、缺口与建卡建议**，不重复其清单。

---

## 8. 变更记录

| 时间 | 动作 | 明细 |
|---|---|---|
| 2026-11-07 | 首轮 | difftest 6 脚本/1189 行 + 13 夹具盘点；覆盖率与耗时实测；12 条缺口（4 未实现/6 部分/2 可疑）；变异基线方案；3 张建议卡 |
