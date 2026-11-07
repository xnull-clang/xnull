# 一司 QA1 首轮：条款追溯 / 诊断 / 负向 验收清单

> **角色**：CEO1-QA1-合规（一司，v1.6.0 §2.1：条款追溯、诊断/负向；写入域=测试文件需分派）
> **依据**：董事会判决 v1.6.0 第 2.1、5 条；董事会验收标准 v1.0.0 §2.1 G-03/G-04/G-05；《质量红线》1/3/7
> **基线**：main `dfcf033`（2026-11-07 本轮只读核查）
> **只读声明**：未改生产代码、未改测试、未改台账/规范/看板/缺陷表、未 commit、未派工、未动他人文件；本文件是唯一写入。
> **命名说明**：本次指令要求 `收件箱/CEO1/CEO1QA1-首轮.md`；CEO1 派工单与《首轮判定》写的是 `QA1-首轮.md`。按指令交付本文件名，是否改名由 CEO1 决定，我不自行复制第二份。

---

## 0. 结论（先给可判定的）

1. **条款级追溯当前不可判。** 全仓无 `spec-clauses.tsv`；S1-00 / S0-14（条款 ID）在看板上仍为“未派”（`收件箱/任务看板-v1.0.0.md:55`）。因此 G-03 的“条款 ID 覆盖率 100%、测试映射 100%”没有分母，任何“已覆盖”结论都是假绿。现有 101 条只是**锚点**，不是条款。
2. **诊断可追溯性不足。** 实现侧有 71 个唯一诊断码、8 个家族，但无 `diagnostics.tsv`；S1/S2 规范不定义码段位（只有 S8 附录 C.5 定义 `XPD-0xx—8xx`）。负例断言普遍只比码，全库只有 1 处断言精确 `line:col`。
3. **假绿有实证，不是风险假设。** P0-5 未关闭：`impl/internal/interp/interp_test.go:254-281` 的 CTRL-01 用例在“末次迭代 break”与“continue 到外层”两种实现下输出相同，测试无法区分。S1-02 的 break 修复没有仓内回归用例，证据只在外部 `repro.sh`。
4. **S2 分母失真。** 台账 S2 为 29 行，规范 S2 §18 是 20 锚点 + 15 BND = 35；缺 `FACTORY-01` 与 S2 的 `TYPE-01/GEN-01/TUPLE-01/NEG-01/DET-01`，且有 5 组跨文档同号。按 29 打 Stage 2 门会漏验工厂类型与 S2 确定性/布局。

**定位**：本文件是验收清单与初筛，不是 L2 门禁结论，不改变台账、缺陷状态与任何人的写权。

---

## 1. 验收清单（22 条）

口径：每条都有“通过判据”和“反例（出现即判不通过）”。反例不是提醒，是打回条件。

### 1.1 条款追溯（TR，6 条）

| ID | 验收项 | 通过判据 | 反例（判不通过） | 本轮基线 |
|---|---|---|---|---|
| **TR-01** | 条款有稳定 ID | 每条含“必须/不得/禁止/只能/不允许”的规范语句有唯一 ID（形如 `S1-2.6-003`），落 `spec-clauses.tsv`；同一句不得两号 | 只有章节号 `§2.6`；ID 只存在于任务卡/映射表；同句多号 | 文件不存在；条款 ID 工具未派 |
| **TR-02** | 条款→测试三列可复算 | `clause_id → test_id → file:func` 三列齐全；覆盖率由脚本从映射表重算，分母来自 `spec-clauses.tsv` | 用 101 锚点代替条款；映射只到文件不到函数；覆盖率手填 | 条款级映射 0 条；锚点级见 §2 |
| **TR-03** | 锚点同号消歧、分母完整 | 跨文档同号用 `S1:` / `S2:` 复合键；S2 §18 的 20 条 + 15 条 BND 全部入账，分母 ≥35 | 裸写 `TYPE-01` 同时映射两文档；Stage 2 用 29 作分母；缺行不补 | 5 组同号；S2 缺 6 条；29 vs 35（PM §5.1–5.2 已列，我复核一致） |
| **TR-04** | 用例可被 ID 检索 | 每个测试函数或表驱动 case 名含锚点/条款 ID，`grep 'TYPE-01'` 能定位到具体用例 | 测试名只有行为名；ID 只在注释/台账列；靠人工记忆关联 | 多数为行为名（如 `TestTyAssignableOK`），ID 只在文件分区注释 |
| **TR-05** | 台账状态有可执行证据 | 每行 `PASS` 在干净 checkout 可执行且 exit 0；`dev ledger` 再生成 diff=0；路径真实存在 | 路径不存在；PASS 行对应测试被 Skip；手改状态无证据 | 10 条 PASS；其中 CTRL-01 对应 P0-5 假绿，说明 PASS ≠ 有效覆盖 |
| **TR-06** | 条款三态可机械对账 | 每条为定案/否决/非承诺；非承诺写三要素并标“不测”；否决有留痕 | “未定义/待定/视情况”；非承诺仍进 PASS 分母 | 规范索引 §0 有三态制度；无条款 ID，无法逐条对账 |

### 1.2 诊断（DG，6 条）

| ID | 验收项 | 通过判据 | 反例（判不通过） | 本轮基线 |
|---|---|---|---|---|
| **DG-01** | 诊断码注册表 | `diagnostics.tsv` 含 code / 条款 ID / 触发条件 / 层（lex·parse·sema·codegen）/ 可恢复 / 优先级 / test_id；代码中的码与表双向 0 孤儿 | 码散落在各包；新增码不改表；表里有码但无触发用例 | 71 个唯一码，无注册表；S1/S2 无码段位 |
| **DG-02** | 负例断言五要素 | 每条负例断言 `code + file + line + col + 稳定消息关键字`；位置错也失败 | 只断言 `err != nil` / 退出码非 0 / 只比 code | `expectCode` 只比码+消息前缀（`impl/internal/sema/sema_test.go:32-42`）；`wantErr` 只比码（`impl/internal/xfront/lexer_test.go:33-40`）；全库精确行列断言仅 `sema_test.go:110` |
| **DG-03** | 诊断格式统一 | 所有拒绝走 `diag.Diagnostic.String()`：`file:line:col: error[CODE]: msg` + 源码行 + 插入符；codegen/CLI 的拒绝也必须带码 | `xnull: 代码生成失败：...`；panic；直接透传 cc 错误 | `impl/internal/codegen/build.go:34-37` 直接打印 `%v`；codegen 非测试代码 **114 处 `fmt.Errorf`** vs **7 处 `diag.Diagnostic`**；`multifile.go:130` “跨包导入暂不支持”无码 |
| **DG-04** | 多诊断与顺序确定 | 一次编译报告全部独立错误；顺序按 file/line/col 或文档规定；同一输入 10 次同码同位置；不崩溃 | 首错即停；map 顺序导致码序变化；fuzz 输入 panic | xfront 有 `TestMultipleErrorsWithPosition`、`TestUnitMultiDiags`；sema 无多诊断顺序断言；确定性只有 `TestPolicyDeterministic`（策略 JSON），未覆盖诊断顺序 |
| **DG-05** | 未支持项显式拒绝 | S1 §0.6 的 **19 类** + S2 各节禁止面，每类至少一个最小负例；拒绝时不得输出结果、不得静默忽略 | 接受后忽略；运行期才失败；直接崩溃 | 19 类中仅少量有专测（独立块 `stmt_test.go:196`；`@arc/@gc` `policy_test.go:182`；struct 引用字段 `typedecl_test.go:280` 部分）；无逐行清单 |
| **DG-06** | 诊断码稳定性 | 改文案不改码；码有段位归属；删除/重命名有迁移记录 | 把消息当码用；同义错误两个码；跨段位新增无记录 | 码为 Go 常量（如 `impl/internal/xfront/parser.go:13-20`），稳定性尚可；无段位/迁移文档 |

### 1.3 负向（NG，5 条）

| ID | 验收项 | 通过判据 | 反例（判不通过） | 本轮基线 |
|---|---|---|---|---|
| **NG-01** | 禁止构造逐条覆盖 | S1 §0.6 的 19 类 19/19；S2 `BND-01—15` 每条至少一个负例；不得一个用例合并多条充数 | “负例总集”只算一条；同一输入覆盖多条只记一次；缺项不列 | `NEG-01`、`BND-14` 均“未实现”（台账 `:33`、`:47`）；无逐条分母 |
| **NG-02** | 负例分层 | 每条负例标注拦截层（lex/parse/sema/codegen/interp）；后期层也必须拒绝，不能只靠 parser | 只测 parser；sema 实际接受；codegen 到 cc 才报错 | 负例集中在 xfront/sema；codegen 的“拒绝”多为无码错误（见 DG-03） |
| **NG-03** | 负例必须是“红测” | 注入“接受禁止输入”或改错期望码后，套件必须失败；每阶段至少 3 个诊断码做变异 | 注入后仍全绿（断言不咬人）；只做覆盖率不做变异 | main 无变异基线；`wt/qa-1` 有 difftest 但未入 main |
| **NG-04** | 优雅失败 | 非零退出码符合 S9 §5.1；无 panic、无部分 stdout、无半成品产物 | 崩溃栈；先输出错误结果再报错；留下 `.c`/二进制半成品 | `codegen.Build` 先写 `outPath+".c"`（`build.go:39-40`）再调用 cc；cc 失败时中间产物残留 |
| **NG-05** | 边界负例 | EOF、未闭合、嵌套、溢出、空输入、位置精确各有用例；列号错也失败 | 只测“普通错误”；行列只查 ≥1 | 位置精度仅 `lexer_test.go:373-383`（≥1）与 `sema_test.go:110`（1 例精确） |

### 1.4 防假绿（FG，5 条）

| ID | 验收项 | 通过判据 | 反例（判不通过） | 本轮基线 |
|---|---|---|---|---|
| **FG-01** | SKIP 不算 PASS | 门禁运行 `SKIP=0`；环境依赖跳过必须显式隔离并登记责任人；CI 汇总不得把 SKIP 计入 PASS | 用 `t.Skip` 掩盖缺失工具；汇总只报 “PASS=10” 不报 SKIP | `impl/internal` 共 **10 处 `t.Skip`**：ffi emit 2、xdk_test 1、xdk_seed 1、devtool resources 4、ledger 1、xpd 1 |
| **FG-02** | Oracle 独立 | 期望值来自规范/手算，不从实现输出回抄；双路径只证明“一致”，不证明“正确” | 用解释器输出当编译期望；golden 由被测实现生成后冻结 | `TestExamplesCompileMatchesInterp` 只比两条路径；两边同时错会一起绿 |
| **FG-03** | 变异达标 | 变异分数 ≥ 验收标准阈值（80%）；诊断码/负例分支必须被变异覆盖 | 只跑覆盖率；变异只做正例；阈值口头达标 | 无 main 基线；`difftest` 未入 main |
| **FG-04** | 无 flaky | 同 sha、`-count=1`、10 次连续跑输出一致；无时间/随机/map 顺序依赖；两次构建 hash 一致 | 用缓存结果当通过；一次绿即放行；重跑才绿 | 本轮 xfront/sema 各跑 1 次通过；未见稳定性门 |
| **FG-05** | 证据可复现 | 七件套（command/stdout/stderr/exit_code/sha/artifact.sha256/acceptance）+ 干净 checkout；验收人≠实现者 | 无 sha；结论无命令；“实测通过”不可复现；自验 | 首轮无门禁；历史 `evidence/` 格式不统一 |

**数量核对**：6 + 6 + 5 + 5 = **22 条**，满足“≥10 条”，其中负向/防假绿 10 条。

---

## 2. 条款→测试三层映射（锚点级初筛）

### 2.1 分层定义

| 层 | 定义 | 可否计入 Stage 门 |
|---|---|---|
| **有** | 能指到具体 Test 函数；有正例，负例断言到诊断码；台账路径与实际一致 | 仍需补条款 ID 与位置断言，暂只能算“锚点有” |
| **弱** | 有测试文件，但仅正例/仅码无位置/台账为“部分”/存在假绿反例 | 不能 |
| **无** | 台账“未实现”，或规范有而台账无 | 不能 |

> 条款级（`spec-clauses.tsv`）尚不存在，所以**条款级“有”=0**；下表全部是锚点级初筛。“有”也不等于可过门，见 TR-01/02。

### 2.2 有（6 条，已抽检 Test 函数）

| 锚点 | 台账 | 测试文件:函数 | 缺口 |
|---|---|---|---|
| LEX-01 | PASS | `impl/internal/xfront/lexer_test.go`：`TestIntegerLiterals`、`TestFloatLiterals`、`TestCharLiterals`、`TestStringForms`、`TestStringErrors` 等 18 个 Test | 位置只做 ≥1 检查（`:373-383`） |
| STMT-01 | PASS | `lexer_test.go:TestAutomaticSemis` + `stmt_test.go:TestStatementTermination` | 只覆盖语法终止，不含运行期 break 行为 |
| TYPE-01 | PASS | `impl/internal/sema/ty_test.go:TestTyAssignableOK` / `TestTyAssignableFail` | 只断言码+消息前缀，无行列 |
| TYPE-02 | PASS | `ty_test.go:TestTyNullRules` | 同上 |
| INH-01 | PASS | `impl/internal/sema/typedecl_test.go:TestInheritanceRules` | 同上 |
| FIELD-01 | PASS | `typedecl_test.go:TestPrivateFieldRules` | 同上 |

### 2.3 弱（13 条）

| 锚点 | 台账 | 现有用例 | 判弱理由 |
|---|---|---|---|
| EXPR-01 | PASS | `interp_test.go:TestShortCircuitEvalOrder`、`TestTryPropagationOrder` | 只比 stdout，无诊断/负例 |
| CTRL-01 | PASS | `stmt_test.go`、`interp_test.go:TestLabeledBreakContinue`、`assign_test.go` | **P0-5 假绿**，break 与 continue 在末次迭代不可区分 |
| ERR-01 | 部分 | `interp_test.go`、`hard_test.go` | `@mustUse`、非法 `value()/error()` 访问未覆盖 |
| BLD-01 | 部分 | `values_test.go:TestArray/List/Map/Set/StringMethods` | 边界/复杂度/`Map.get` 缺失键未全测 |
| TUPLE-01 | 部分 | `interp_test.go:TestTuple`、`TestTupleSyntaxRejections` | 内存/可赋值性/插值未全覆盖 |
| PKG-01 | 部分 | `unit_test.go`、`xdk_test.go` | 导入环、简单名歧义缺负例 |
| ENTRY-01 | 部分 | `interp_test.go:TestMainWithArgs/TestMissingMain`、`cli_test.go` | 重复入口/初始化顺序缺 |
| DET-01 | 部分 | `policy_test.go:TestPolicyDeterministic` | 只覆盖策略 JSON，不覆盖诊断/运行结果 |
| STRUCT-01 | 部分 | `typedecl_test.go:TestStructValueRules` | 复制独立/递归值包含未测 |
| PROTO-01 | 部分 | `typedecl_test.go:TestProtocolRules` | 父协议实现检查/持有语义未测 |
| ENUM-01 | 部分 | `typedecl_test.go:TestEnumRules` | 穷尽性/重复项/未知项负例不全 |
| MEM-01 | 部分 | `policy_test.go:TestPolicyTable` | 判定表输入未全枚举 |
| MEM-02 | 部分 | `impl/runtime/test_gc.c`、`test_hard.c` | 混合图/弱引用/环未逐项 |

### 2.4 无（24 条台账 + 6 条规范侧漏账）

- **S1（2）**：`GEN-01`（泛型函数）、`NEG-01`（跨切面负例总集）。
- **S2 台账（22）**：`BND-01—15` 全部；`DISP-01`、`PCTOR-01`、`INT-01`、`SINGLE-01`、`EXT-01`、`ANN-01`、`GATE-01`。
- **S2 规范有、台账无（6）**：S2 `TYPE-01`、`FACTORY-01`、`GEN-01`、`TUPLE-01`、`NEG-01`、`DET-01`（见 S2 §18）。

**计数**：台账 43 条 = 有 6 / 弱 13 / 无 24；加 S2 漏账 6 条，实际待覆盖 49 条 = 有 6 / 弱 13 / 无 30。S1 自身 14 = 4 有 / 8 弱 / 2 无；S2 29 = 2 有 / 5 弱 / 22 无。

---

## 3. 历史假绿复检建议（S1-02 / CTRL-01）

### 3.1 CTRL-01：现用例无法区分 break 与 continue

- 位置：`impl/internal/interp/interp_test.go:254-281`。
- 结构：外层 `for i in 0..<3`，内层 `for j in 0..<3`；`j == 1` 时 `continue outer`；`i == 2` 时 `break outer`；期望 `hits = 2`。
- 问题：`i == 2` 是外层**末次迭代**。若 `break outer` 被错误实现为 `continue outer`，外层同样结束，`hits` 仍为 2，输出 `2\ncase1\n` 完全相同。P0-5 记录的正是这一点（`收件箱/CEO/缺陷登记表-v1.0.0.md:17`）。
- 复检用例（建议，不代写）：
  1. 把 break 放在**非末次**迭代：`outer: for i in 0..<4 { for j in 0..<3 { if i == 1 { break outer } ; hits += 1 } }`。正确 `hits = 4`（i=0 跑 3 次 + i=1 首次 1 次）；若 break 退化为 continue，则 `hits = 4 + 3 + 3 = 10` 或进入后续迭代，必然不同。
  2. 无标签 `break` 只退出最近层循环，外层继续。
  3. 循环内 `switch` 的 `break` 只退出 switch，不退出循环。
  4. `do-while` 首轮 break、`for-in` 首个元素 break。
  5. 编译路径也要跑同一组，不能只测解释器。

### 3.2 S1-02：修复无仓内回归测试

- 事实：`收件箱/E3/回执-S1-02.md:7` 声明“未新增测试文件”；修复证据是外部 `evidence/S1-02/repro.sh`（4 场景），`go test ./internal/interp/...` 通过只说明旧套件没红。
- 风险：S1-02 的 break 传播再次回归时，仓内唯一相关用例是 §3.1 的假绿用例，**可能仍然全绿**。
- 复检建议：
  1. 把 repro 的 4 个场景（while 直接 break、嵌套 if、do-while、for-in 容器）转成 const table，期望值由规范语义手算，不从修复后输出回抄。
  2. 加“非末次迭代 break”与“switch break 不退出循环”两条。
  3. 同一组用例在解释器与编译路径各跑一次；退出码和 stdout 都比。
  4. 修复 commit `2597b36` / main `dff308d` 上重跑，确认仍通过；把命令与 sha 写进证据。
- 现成命令：`go test -count=1 -run 'TestLabeledBreakContinue' -v ./internal/interp`。注意：它现在会 PASS，但**不能证明** break 正确。

---

## 4. 首批负向用例清单（14 条，按 §0.6 / S2 禁止面取）

> 现有诊断码没有注册表，下表“期望码”一列凡写“待注册”的，都必须先由 DG-01 定码；在此之前只允许断言“显式拒绝 + 非零退出 + 位置”，不得自造码。

| ID | 禁止构造 | 最小输入 | 期望拦截层 | 期望码 | 现有用例 |
|---|---|---|---|---|---|
| NEG-01 | 命名实参/默认参数/可变参数 | `f(x: 1)` / `f(Int a = 1)` / `f(...xs)` | parse→sema | 待注册 | 无 |
| NEG-02 | C 风格 for | `for (Int i = 0; i < 3; i++) {}` | parse | `SYN-101/108` 待定 | 无 |
| NEG-03 | catch/finally | `try {} catch {}` | parse | 待注册 | 无 |
| NEG-04 | 运算符重载 / 隐式转换 | `operator +(...)` / 隐式转换声明 | parse | 待注册 | 无 |
| NEG-05 | 指针 / 地址符 / `@arc` / `@gc` | `*Int p` / `&x` / `@arc class C {}` | lex/parse/sema | `TY-*`（@arc/@gc 已测） | `policy_test.go:182` 仅注解 |
| NEG-06 | 属性访问器 | `Int x { get { ... } }` | parse | 待注册 | 无 |
| NEG-07 | 用户索引器 / 事件 | `this[Int i]` / `event E` | parse | 待注册 | 无 |
| NEG-08 | if/switch 表达式、独立块 | `Int x = if c { 1 } else { 2 }` / `{ x = 1 }` | parse | `SYN-101`（独立块） | `stmt_test.go:196` 仅独立块 |
| NEG-09 | match / 模式匹配 | `match x { ... }` | parse | 待注册 | 无 |
| NEG-10 | 元组解构/单元素/零元 | `(Int a, Int b) = t` / `(1,)` / `()` | parse/sema | `SYN-104`（元组元数） | `parser_test.go TestErrors`、`interp_test.go:325` 部分 |
| NEG-11 | `??=` / `?.()` / `?.[]` | `x ??= 1` / `f?.()` / `a?.[0]` | parse | 待注册 | 无 |
| NEG-12 | async/await/生成器 | `async Int f()` / `await t` / `yield 1` | lex/parse | 待注册 | 无 |
| NEG-13 | 类型约束 / where / 泛型闭包 | `Int f<T: X>()` / `where T: X` / 泛型 lambda | parse/sema | 待注册 | 无 |
| NEG-14 | 结构体引用字段 / 协议方法体 / 枚举实现协议 / 单例 new | `struct S { String s }` / `protocol P { Int f() { 1 } }` / `enum E: P {}` / `new S()` | sema | `TY-2xx` 待核 | `typedecl_test.go:280/323/345` 部分 |

**通过判据**：每个用例都必须给出“拒绝层 + 码 + 文件:行:列 + 非零退出 + stdout 为空 + 无 panic”。只报“编译失败”不算通过。

---

## 5. 本轮实测记录（可复制）

| 命令 | 实际结果 |
|---|---|
| `git rev-parse --short HEAD` | `dfcf033` |
| `find . -name 'spec-clauses.tsv' -o -name 'diagnostics.tsv'` | 0 命中 |
| 台账统计（`XNull一致性用例台账-v1.0.0.md`） | 101 条 / PASS 10；S1 14 = 6/6/2；S2 29 = 2/5/22 |
| `grep -rhoE '\"[A-Z]+-[0-9]{3}\"' impl/internal \| sort -u` | 71 个唯一码：LEX 6、SYN 11、TY 11、RES 10、DA 3、FFI 12、XPD 14、CLI 4 |
| `grep -rn 'fmt.Errorf' impl/internal/codegen --include='*.go' \| grep -v _test \| wc -l` | 114 |
| `grep -rn 'diag.Diagnostic' impl/internal/codegen --include='*.go' \| grep -v _test \| wc -l` | 7 |
| `grep -rn 'func Test' impl/internal --include='*_test.go' \| wc -l` | 164（xfront 44、sema 34） |
| `grep -rn 't.Skip' impl/internal \| wc -l` | 10 |
| `go test -count=1 -timeout 60s ./internal/xfront ./internal/sema` | `ok xfront 41.145s` / `ok sema 40.269s` |
| S1 §0.6 表行数 | 19 类不支持 |

**未测声明**：本轮未跑完 `internal/codegen` 全量套件（外层命令 120s 超时被杀，不作为通过/失败结论）；未做变异、未做条款级全量审计、未改任何代码。首轮只读，结论按“已核查/未核查”分栏，不把未核查写成通过。

---

## 6. 需要先定的三件事（不是派工）

| 编号 | 待定项 | 不定会怎样 | 建议归属（只提建议） |
|---|---|---|---|
| D-01 | 条款 ID 方案与 `spec-clauses.tsv` 生成器（S1-00 / S0-14 未派） | G-03 无法计算；所有“条款覆盖”结论不可判 | 董事会/CEO2 定卡，E6 实施 |
| D-02 | S2 分母：29 还是 35；6 条漏账与 5 组同号如何处理 | Stage 2 门会漏验工厂类型/S2 确定性；映射表二义 | 董事会 v1.0.1 裁决；我不自行改台账 |
| D-03 | 诊断码注册表 `diagnostics.tsv` 与 S1/S2 码段位 | 负例只能断言“失败”，不能断言“符合规范的拒绝” | CTO/PM 出规范，E6/QA 落地 |

---

## 7. 边界

- 本文件只覆盖一司域（xfront / sema / codegen）的条款追溯、诊断、负向；二司/三司的运行时、FFI、CI、差分不在本域。
- 本文件不是门禁签字，不改变 `XNull一致性用例台账`、`缺陷登记表`、看板与会话台账。
- 所有“有/弱/无”是锚点级初筛；“有”仍需补条款 ID、位置断言与独立复验后才能进 L1。
- 未引用他人回执作为通过证据；§3.2 引用 E3 回执只为说明“测试缺口”，不采信其结论。
