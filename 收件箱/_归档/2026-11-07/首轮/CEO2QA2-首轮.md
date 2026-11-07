# CEO2-QA2-性能 · 首轮盘点（只读）

> **角色**：QA2 `CEO2-QA2-性能`（二司·运行时：interp / runtime / ffi）
> **依据**：`收件箱/董事会判决-三司编制与团队扩招-v1.6.0-2026-11-07.md` 第 2 条（2.2 二司编制）、第 5 条（首轮只读任务）
> **性质**：只读盘点。未改生产代码、未 commit、未派工、未碰他人文件。
> **日期**：2026-11-07　**基线提交**：`dfcf033`（main 工作区干净，实测）
> **本文件写入域**：`收件箱/CEO2/**`（本角色唯一可写面；测试代码需董事会/CEO2 派卡后才能落地）

---

## 0. 结论先行

1. **项目当前没有任何性能基线基建**：`impl/**` 内 `Benchmark` 用例 **0 个**，CI 10 项中 **0 项**测性能，`runtime/` 无任何耗时/分配/GC 统计导出（`rt_gc.h` 只有 alloc 接口）。
2. **今天能给出的是一份"冷启动实测基线"**（本文件第 3 节，15 项，全部可复跑），不是门禁。它在 Stage 0 只用于**记录**，不用于卡人。
3. **已发现 3 个必须先记账的事实**，任何"性能通过"结论在它们解决前都不成立：
   - **`xnull run` 端到端抖动 3.7 倍**（2.78s / 3.42s / 10.40s），主因是 macOS 首次执行新编译二进制触发 Gatekeeper/签名校验（首次 1.8–2.4s，二次 0.05s）；
   - **编译路径字符串拼接峰值内存 209MB**（20k 次拼接、结果 20KB），而解释路径同负载 17.9MB —— 峰值 ∝ n²/2，是运行时侧最需要盯的内存项；
   - **测试套件冷/热差 9.3 倍**：冷缓存逐包 243s（`codegen` 单包 129s），热缓存 26s（`codegen` 13–18s）。CI 第 02 项 `go test -timeout 120s ./...` 在冷机上会被单包 129s 直接打红 —— 这不是代码慢，是**门限与冷启动伪影冲突**。
4. **双路径能力差异要先于性能差异解决**：`Array` 在解释路径无 `push`（`该类型没有成员方法 push：Array`），`List` 两条路径都支持。性能只应在**双路径交集负载**上比较。

---

## 1. 范围与依据

| 项 | 内容 |
|---|---|
| 我的域 | 运行时：`impl/internal/interp/**`、`impl/runtime/**`（C 运行时/GC/ARC）、`impl/internal/codegen/ffi/**` |
| 规范锚点 | S3 §24 度量与基准（命名负载：每秒报文数、每批耗时、连接/任务规模、p50/p99、峰值内存、回收暂停分布、分配速率与 GC 频率）；S3 §25 验收表；S5 运行时任务与并发（本阶段语言层无 `async`/任务语法） |
| 门禁锚点 | `收件箱/董事会验收标准-预期效果与验收内容-v1.0.0-2026-11-07.md` §4.1 阈值表（性能：Stage 0 记录基线；Stage 1 编译 hello ≤5s、运行 ≤200ms；Stage 2+ 回归 ≤20%）、§4.5（flaky 10 次、超时即失败） |
| 红线约束 | `收件箱/质量红线.md` 第 2/3/7 条：不静默降级、双路径不豁免、边界如实 |
| 不在本文件内 | 不定义发布门槛（CEO1 签 L2）、不登记缺陷（CEO3）、不排期（CEO2-PJ） |

---

## 2. 工具面盘点（有什么 / 没什么）

| 能力 | 现状 | 证据 |
|---|---|---|
| Go 基准用例 `Benchmark*` | **无** | `impl/**` 全树 grep `Benchmark` = 0 命中 |
| 命名负载/基准脚本 | **无**（只有 `examples/*.x` 10 个功能示例，无规模参数） | `ls examples` |
| 运行时统计（耗时/分配/GC 暂停） | **无** | `impl/runtime/rt_gc.h` 仅 `rt_gc_new`/`rt_arc_new` 等接口，无计数器 |
| CI 性能步骤 | **无** | `wt/e6-toolchain/ci/run.sh` 10 项：gofmt+vet / go test / C 构建 / 双路径 / check_specs / 台账 / 泄漏 / 产物 sha / 汇总 / 文件名扫描；04–09 仍为 SKIP 桩 |
| 内存峰值采集 | **有（外部）** | `/usr/bin/time -l`（macOS）可得 `peak memory footprint` / `instructions retired`，本文件基线即用它 |
| 解释器时钟/单步计数 | **无** | `impl/internal/interp/interp.go` 无 profiling 钩子 |
| 并发/任务负载 | **无** | interp 内 `spawn`/`task`/`thread` = 0；S5 规定语言层无任务语法，并发负载本阶段无法测 |

---

## 3. Stage 0 性能基线（实测，15 项）

### 3.1 测量环境与协议

```
机器：macOS (darwin/amd64) / go1.27.3 / clang (系统 cc)
工作区：/Users/vjs/Desktop/XNull-Lang @ dfcf033，git 干净
探针：go build -o /tmp/xnull-probe ./impl/cmd/xnull（6603552 B）
方法：每项 N=5（标注者除外），每次独立进程；取中位数；
      编译产物首次执行单独记录并**从运行基线中剔除**（Gatekeeper 干扰）；
      全程 nohup 之外无并行负载，电源接电。
负载文件：/tmp/xn-bench/{loop,alloc2,str}.x（本文附录给全文；未入库）
```

**必须知道的环境伪影**：新编译二进制第一次执行耗时 **1.82s–2.35s**，第二次起 **0.046–0.070s**。同一文件复制到新 temp 目录后首执再次变慢（实测 1.985s）。任何"运行耗时"基线都必须先预热一次，否则测的是代码签名校验，不是运行时。

### 3.2 基线表

| # | 项 | 负载 | 指标 | 实测（中位/区间） | 备注 |
|---:|---|---|---|---|---|
| B-01 | 解释器启动 + hello | `examples/hello.x --interp` | wall | **0.070s**（0.068–0.072，n=5） | 5 次离散 ≤6% |
| B-02 | 解释器 hello 内存 | 同上 | peak footprint | **2.28 MB** | 32.0M cycles / 23.1M insns |
| B-03 | 编译 hello（含 cc） | `xnull build examples/hello.x` | wall | **0.656s**（0.622–0.806，n=5） | 远低于董事会 ≤5s |
| B-04 | 编译产物 hello 运行（热身） | `/tmp/probe-hello` | wall | **0.070s**（0.061–0.070） | 首执 1.82s，见 3.1；peak 360KB / 9.0M insns |
| B-05 | `xnull run` 端到端 | `xnull run examples/hello.x` | wall | **3.42s**（2.78 / 3.42 / 10.40，n=3） | **抖动 3.7x**；≈ B-03(0.65) + 首执(~2.0)；**10.40s 离群未归因**（猜测磁盘/扫描抖动，未验证）。不得直接当门禁 |
| B-06 | 解释器循环吞吐 | 1M 次 while 累加 | wall | **1.368s**（≈0.73 M 迭代/s） | 9.58MB / 5.04G insns |
| B-07 | 编译循环吞吐 | 同一 `.x` 编译后运行 | wall | **0.047s**（0.047–0.066） | ≈21 M 迭代/s；比解释快 **29x** |
| B-08 | 解释器容器负载 | `List<Int>` push 200k + 遍历求和 | wall | **0.549s**（real 0.47s） | **63.2MB** / 2.28G insns；分配压力最大的现有项 |
| B-09 | 编译容器负载 | 同上 | wall / 内存 | **0.046s** / **2.04MB** | 12.2M insns；比解释快 **10–12x**，内存省 **31x**；首执 2.35s |
| B-10 | 解释器字符串拼接 | 20k 次 `s = s + "x"` | wall / 内存 | **0.164s** / **17.9MB** | |
| B-11 | 编译字符串拼接 | 同上 | wall / 内存 | **0.276–0.285s** / **209 MB** | **比解释路径更慢且内存 12x**；峰值 ∝ n²/2 |
| B-12 | 完整测试套件（**冷缓存**） | `go test -count=1 ./internal/... ./cmd/...`（逐包串行计时，首次） | wall | **≈243s** | cli 34.1 / **codegen 129.2** / ffi 22.6 / devtool 4.3 / diag 6.0 / interp 8.2 / sema 10.1 / xfront 16.6 / xpd 6.3 |
| B-13 | 完整测试套件（**热缓存**） | 同上，二次及以后 | wall | **≈26s** | cli 2.6 / **codegen 13.0（再跑 14.3/16.1/17.6）** / ffi 3.8 / devtool 1.2 / 其余各 1.1 |
| B-14 | `go test ./...` 单次调用（冷） | 同上并发跑 | wall | **>180s（180s 超时未完成）** | 与 CI 第 02 项 `-timeout 120s` 冲突，见 4.3 |
| B-15 | `go test ./...`（热） | 同上 | wall | 未满跑；按 B-13 推算 ≈26s 量级 | 单包热缓存 `codegen` 13–18s，余量大 |

**B-12↔B-13 的 9.3 倍差是本文最重要的一条**：codegen 测试每个用例都会 `cc` 编译并 **exec** 一个新二进制，每个新二进制首次执行都要过一次代码签名扫描。冷机跑 CI 相当于让第 02 项承担 129s，而门限写的是 120s。**判"是不是回归"必须先声明冷/热**，否则测的是操作系统，不是代码。

### 3.3 命名负载定义（需派卡后才落地为文件）

| ID | 负载 | 参数（固定写死，禁止自适应） | 主指标 | 次指标 |
|---|---|---|---|---|
| N-01 | `hello` | `examples/hello.x` | wall | peak RSS |
| N-02 | `loop-int` | 1M 次 while 累加，结果 `499999500000` | wall | peak RSS、insns |
| N-03 | `container-push` | `List<Int>` push 200k + 求和，结果 `200000 / 19999900000` | wall | peak RSS |
| N-04 | `string-build` | 20k 次单字符拼接，长度 `20000` | wall | **peak RSS（当前最差项）** |
| N-05 | `parse-rt`（待建） | 固定 1MB 报文（S3 §24「每秒报文数」口径），NDK 未定 | 报文/s、p50/p99 | peak RSS |
| N-06 | `task-scale`（阻塞） | S5 连接/任务规模 | p50/p99、暂停分布 | — 语言层当前无任务语法，**本阶段不可测，不得报 PASS** |

**统一契约**：每个负载必须（a）打印固定校验值，双层防线防止"跑得快是因为算错了"；（b）编译与解释两条路径都跑；（c）参数写死在文件里，不读环境变量。

---

## 4. 回归阈值

### 4.1 总则

1. **绝对阈值宽松、相对阈值严格**：Stage 0/1 用本节绝对值兜底（约 2–3x 基线，容错机器差异）；Stage 2+ 一律用"相对基线 ±20%"（董事会 §4.1 已定）。
2. **一律中位数，禁用最小值**：`min` 会掩盖抖动；N=5 取 p50，同时记录 p95。
3. **首次执行不计入**：见 3.1；先热身 exec 一次。
4. **无基线不得判 PASS**：新负载首次运行只写基线（status=`BASELINED`），下一次运行才可判回归（防止「先跑一次就当基线被绕过」）。
5. **回归判定需要连续 3 次超阈值**（见 F-14）；单次超阈值只发警告。
6. **阈值调整只能董事会发新版**（董事会 §4.1 原文），QA2 只能提数据不能改门。

### 4.2 阈值表（Stage 0 记录 / Stage 1 兜底 / Stage 2+ 相对）

| # | 指标 | 基线 | Stage 0（记录） | Stage 1 绝对上限 | Stage 2+ |
|---:|---|---:|---|---|---|
| R-01 | B-01 hello 解释 wall | 0.070s | 记录 | ≤0.20s | ±20% vs 基线 |
| R-02 | B-03 编译 hello wall | 0.656s | 记录 | ≤5.0s（董事会） | ±20% |
| R-03 | B-04 编译产物 hello warm wall | 0.070s | 记录 | ≤0.20s（董事会「运行 ≤200ms」） | ±20% |
| R-04 | B-05 `xnull run` 端到端 p50 | 3.42s（抖动大） | 记录 | ≤5.0s；p95 ≤8.0s | ±20%（**须先消除 Gatekeeper 伪影**） |
| R-05 | B-06 loop 1M interp | 1.368s | 记录 | ≤2.0s | ±20% |
| R-06 | B-07 loop 1M compiled | 0.047s | 记录 | ≤0.15s | ±20% |
| R-07 | B-08 container interp wall | 0.549s | 记录 | ≤1.10s | ±20% |
| R-08 | B-08 container interp peak | 63.2MB | 记录 | ≤96MB | ±20% 或 ±8MB（取大） |
| R-09 | B-09 container compiled wall | 0.046s | 记录 | ≤0.15s | ±20% |
| R-10 | B-09 container compiled peak | 2.04MB | 记录 | ≤8MB | ±20% 或 ±2MB（取大） |
| R-11 | B-11 string-build compiled peak | **209MB** | 记录（挂缺陷） | ≤256MB（不得继续恶化） | ±20%，且目标 Stage 3 前降到 ≤16MB（**我提的提案值，需 RD 评估可行性**） |
| R-12 | 编译/解释耗时比（container） | 12x | 记录 | 不得扩大 | 比值 ±20% |
| R-13 | 完整套件 wall（**冷**） | 243s | 记录 | ≤360s | ±20% |
| R-14 | 完整套件 wall（**热**） | 26s | 记录 | ≤60s | ±20% |
| R-15 | 单包 wall 上限（热） | codegen 13–18s | 记录 | ≤40s | ±20% |
| R-16 | 测试超时门限 | CI 120s/包（对冷态 129s **无余量**） | **不合格** | 门限 ≥ 3× 该包冷态中位（codegen 应 ≥390s），或声明 CI 只跑热缓存 | 同左 |

### 4.3 已定位的阈值冲突（需 CEO2 决定，不派工）

- CI 第 02 项 `go test -timeout 120s ./...`（`wt/e6-toolchain/ci/run.sh` 步骤 02）对 `internal/codegen` 冷态 129s **没有余量**，热态 13–18s 有大量余量。也就是说：**同一份代码在冷机上红、热机上绿**。这不是"代码变慢"，是门限没区分冷/热，属结构性 flaky。
- 处置选项（供 CEO2 选，不由我定）：① 门限按 R-16 调到 ≥3× 冷态（codegen ≥390s）；② CI 先做一次预热（跑一遍再计入结果），门限按热态；③ 减少 codegen 测试对 `cc`+`exec` 的依赖（RD 侧，治本）。**在处置前，任何 codegen 超时红失败都不得判为性能回归。**

---

## 5. Flaky 规则（15 条）

> 判定口径与董事会 §4.5 一致：**同一提交连续 10 次，任一失败即不稳定**。以下为二司运行时域的落地细则。

| # | 规则 | 判据 / 处置 |
|---:|---|---|
| **F-01** | 定义 | 同 commit、同环境、同命令连续 10 次运行，任一次结果与其他不同（PASS↔FAIL、输出不一致、耗时越阈）即为 flaky；**不允许用"再跑一次就过了"关闭**。 |
| **F-02** | 取样必须独立进程 | 功能项用 `-count=1` 起 10 个独立进程（或 CI 10 次 job）；性能项禁止在同进程内重复取 `-count=10`，避免预热与缓存掩盖首跑成本。 |
| **F-03** | 性能 flaky 与功能 flaky 分账 | 性能波动**不得**用来解释或掩盖功能失败；反之功能全绿也不能豁免性能回归。两条账各自记录、各自上报。 |
| **F-04** | 禁止自动重试掩盖 | 允许"取证式重试"（记录首次结果后重跑最多 2 次以定性），但**门禁结论以首次为准**；CI 自动 `--retry` 属作弊，触发反作弊条款 §4.4-2。 |
| **F-05** | 冷启动必须剔除或单独记账 | 新编译二进制首次 exec 有 1.8–2.4s 的代码签名/Gatekeeper 成本（实测）；测试套件冷/热差 **9.3 倍**（243s vs 26s）。基线必须先热身一次再计时；无法热身时必须显式标注"冷态"，且不得与热态数字比阈值 |
| **F-06** | 噪声门 | 同组 N=5 的 `CV = stdev/median > 5%` ⇒ 该次测量**无效**（不是代码变差），换安静环境重测；连续 3 次无效 ⇒ 上报"环境不可测"而不是"通过"。 |
| **F-07** | 取样与聚合固定 | N≥5（最低 3，且必须在报告中标注）；聚合一律用中位数并同时报 p95；**禁止只报 min**（最容易被机器抖动骗过）。 |
| **F-08** | 超时即失败 | 任何用例挂起/超时判 FAIL，不接受"它只是慢"（董事会 §4.5）；超时门限必须 ≥3× 该用例基线中位数，门限低于基线的（如当前 codegen 120s）先改门限再谈回归。 |
| **F-09** | 并发度固定 | 性能项独占执行（`-p 1`，不与 cc/其他包并行）；功能项并行度写死并记录。CI 同机并发导致的抖动不计入回归，但必须记录并发度，否则作废。 |
| **F-10** | 环境指纹必录 | 每次测量写入：commit sha、go version、cc version、OS/CPU 型号、是否接电、后台负载、并发度。缺指纹的报告不可作为门禁证据（红线第 1 条：可溯源）。 |
| **F-11** | 用例必须自隔离 | 每个用例独占 `t.TempDir()`，禁止固定文件名（`prog`/`out.c`）、固定端口、共享全局状态、依赖执行顺序。发现依赖顺序即判 flaky 并要求改测试（董事会反作弊 §4.4-5）。 |
| **F-12** | 外部不确定性必须注入种子 | 时间、随机、文件 mtime、环境变量必须可注入并记录种子；未记录种子 = 不可复现 = 直接判 flaky。 |
| **F-13** | 隔离区流程 | 确认 flaky 后 24h 内：登记缺陷（CEO3）→ 用例进 quarantine（显式 skip + 缺陷号 + 到期日）→ 修复后 10 次全绿才准出。**禁止无限期 xfail/skip**（反作弊 §4.4-2）。 |
| **F-14** | 性能回归需连击 | 性能项连续 3 次独立运行（跨 commit 不变、环境不变）超阈值才判回归；单次超阈只发警告并自动重测一次。功能项不适用本条（功能一次失败即失败）。 |
| **F-15** | CI 结果自洽 | 同一 commit 两次 CI 出现步骤状态变化（SKIP→PASS、PASS→SKIP、步骤数变化）同样按 flaky 记；SKIP 不得计入通过数（现存 04–09 为 SKIP 桩，汇总口径必须显式排除）。 |

---

## 6. 缺口与明确边界（红线第 7 条）

**本文件不成立的结论**：

1. **没有性能门禁**。本文只是基线记录 + 阈值提案；门由 CEO1 签、阈值只能董事会改。
2. **没有测并发/FFI 性能**。S5 的语言层任务语法未实现（interp 中 `spawn/task/thread` = 0），FFI 侧只有合同层测试（`codegen/ffi/*_test.go`），**跨边界调用开销、回调 trampoline 成本、租约续期成本全部未测**，属"未测"不是"通过"。
3. **没有 GC 暂停分布**。S3 §24 要求的"回收暂停时长分布 / 分配速率 / GC 频率"当前**无法测**：`rt_gc.c` 无计数器、无时间戳。这项要 RD 加探针（`@arc`/`gc` 策略转储已有，统计面无）。
4. **N-05 报文负载与 N-06 任务规模未定义**（NDK/任务 API 未定），不得以现有数字冒充 S3 §24 的命名负载。
5. **数字来自单机 macOS/amd64**。跨平台（linux/windows）未测，现有 `收件箱/CEO/门-S0-21.md` 已声明同一缺口；本文件不改变该边界。
6. **`Array.push` 双路径不一致**（interp 报错、编译路径可用）：这是**能力缺口**（红线第 3 条），不是性能问题；在它修复前，容器性能只能在 `List` 上比较。
7. **B-11（编译路径字符串拼接 209MB / 比解释慢）需要 RD 归因**，我只记账：现象、度量方式、复现文件已给；根因（每次拼接新分配 + GC 不及时 / 未走缓冲追加）是假设，**未经验证**。

---

## 7. 交给 CEO2 的输入（不派工、不排期）

| # | 事项 | 建议归属 | 我需要什么 |
|---:|---|---|---|
| 1 | 建基准基建：`Benchmark` 用例 + 命名负载 N-01..N-04 入库（`Tests/` 或 `difftest/`） | CEO3-RD3 测试基建 建骨架，我出规格 | 派卡给我（测试文件写入需分派，v1.6.0 第 2.2 条） |
| 2 | CI 增加性能 lane（串行、N=5、中位数、指纹） | CEO3-RD2 构建与 CI | 我提供脚本规格与阈值表 |
| 3 | codegen 单包 129s vs CI 120s 门限冲突处置 | CEO2 决策 → CEO3-RD2/CEO1 | 见 §4.3，三选一 |
| 4 | 运行时统计探针（分配计数、GC 暂停时长） | CEO2-RD2 运行时 | 我出指标口径与验收用例 |
| 5 | 编译路径字符串拼接 209MB 归因 | CEO2-RD2/RD3 | 我先补一个最小复现与内存曲线 |
| 6 | flaky 规则并入 CI（10 次重跑、隔离区） | CEO3-RD2 | 本文件 §5 可直接作为验收条款引用 |

---

## 附录 A：负载文件全文（未入库，仅复跑用）

`/tmp/xn-bench/loop.x`

```
static Int main() {
    Int total = 0
    Int i = 0
    while i < 1000000 {
        total = total + i
        i = i + 1
    }
    print(total)
    return 0
}
```

`/tmp/xn-bench/alloc2.x`

```
static Int main() {
    Int i = 0
    Int n = 200000
    List<Int> xs = []
    while i < n {
        xs.push(i)
        i = i + 1
    }
    Int total = 0
    for v in xs {
        total = total + v
    }
    print(xs.length())
    print(total)
    return 0
}
```

`/tmp/xn-bench/str.x`

```
static Int main() {
    Int i = 0
    String s = ""
    while i < 20000 {
        s = s + "x"
        i = i + 1
    }
    print(s.length())
    return 0
}
```

## 附录 B：复跑命令

```bash
# 探针
cd impl && go build -o /tmp/xnull-probe ./cmd/xnull

# B-01/B-02
/usr/bin/time -l /tmp/xnull-probe run examples/hello.x --interp

# B-03/B-04（首执单独计，不计入基线）
/usr/bin/time -l /tmp/xnull-probe build examples/hello.x -o /tmp/xn-bench/hello
/tmp/xn-bench/hello >/dev/null   # 热身一次
/usr/bin/time -l /tmp/xn-bench/hello

# B-06/B-07
/tmp/xnull-probe run /tmp/xn-bench/loop.x --interp
/tmp/xnull-probe build /tmp/xn-bench/loop.x -o /tmp/xn-bench/loop && /tmp/xn-bench/loop

# B-08/B-09
/usr/bin/time -l /tmp/xnull-probe run /tmp/xn-bench/alloc2.x --interp
/tmp/xnull-probe build /tmp/xn-bench/alloc2.x -o /tmp/xn-bench/alloc2 && /tmp/xn-bench/alloc2

# B-10/B-11
/usr/bin/time -l /tmp/xnull-probe run /tmp/xn-bench/str.x --interp
/tmp/xnull-probe build /tmp/xn-bench/str.x -o /tmp/xn-bench/str && /usr/bin/time -l /tmp/xn-bench/str

# B-12（冷：先 `go clean -testcache` 等缓存失效再跑） / B-13/B-14/B-15（热：连跑两次，取第二次）
for p in $(go list ./internal/... ./cmd/...); do
  /usr/bin/time -p go test -count=1 -timeout 300s "$p"
done
```
