# 一司（编译器）首轮任务分解 v1.0.0

> **角色：CEO1-PJ-项目（一司项目）**　**日期：2026-11-07**　**依据：董事会判决 v1.6.0 第 2.1、4.2、4.3、4.4、5 条**
> **性质：只读盘点后的拆卡建议。不是派工单、不是任务看板、不是门禁结论、不是验收报告。**
> **写入域：`收件箱/CEO1/**`。本轮仅新增本文件；未改生产代码、未 commit、未派工、未碰他人文件。**
> **一句话：先把 S1 收口拆成能独立验收的小卡，再让 S2 起步卡在 Stage 1 门后排队；不拿 3—4 人日的大卡冒充一张卡。**

---

## 0. 结论

- 首批拆 **10 张卡**，全部 **≤2 人日**，覆盖 RD1 / RD2 / RD3 / QA1 / QA2 / PM 六个角色，合计 **17 人日**。
- 其中 **7 张属 S1 收口**（可立即起手或同流接力），**3 张属 S2 起步**（硬依赖 Stage 1 门通过）。
- 按依赖分 **4 个波次（W0—W3）**，不排日历日；每名研发/QA 严格 WIP=1，PM/PJ 各 ≤2。
- **没有把 S1-14（闭包，原估 3 人日）、S1-15（泛型，原估 4 人日）塞进首批**：已拆出候选子卡，但闭包受二司运行时 `rt_closure` 契约阻塞，泛型必须先做单态化设计。
- 当前最大管理风险不是人手，是 **S1-00/S1-01 正式条款 ID 未交付**、**QA2 无独立 worktree**、**Stage 1 门未过**。三项都在第 7 节给了绕行/升级方案。

---

## 1. 边界

| 项 | 本文件做 | 本文件不做 |
|---|---|---|
| 任务管理 | 拆卡、估人日、排依赖、定 WIP、定证据路径 | 不派工、不建看板、不改台账状态 |
| 质量 | 给每张卡定机械验收命令与独立必签人 | 不签 L1/L2、不宣布通过、不登记缺陷 |
| 代码 | 只引用现有文件与行号 | 不改 `impl/**`、不改测试、不 commit |
| 证据 | 规定证据目录与七件套 | 本轮不创建证据目录、不产出实现证据 |

**唯一主责规则**：每张卡一个 A（主责），必签人只签不干；同一文件同一时间只有一个写入者。RD 写自己包的代码与单元测试；QA 只写**新建的独立验收测试文件**（`*_accept_test.go` 或 `*_matrix_test.go`），不编辑 RD 已有测试文件。

---

## 2. 只读基线（2026-11-07 实测）

### 2.1 仓库与 worktree

| 项 | 事实 | 对拆卡的影响 |
|---|---|---|
| main HEAD | `dfcf033`（S1-22 改名后） | 所有卡从 `dfcf033` 起分支 |
| 一司研发 worktree | `wt/c1-rd1`、`wt/c1-rd2`、`wt/c1-rd3` 均存在，分支 `pod/c1-rd1/2/3`，均指向 `dfcf033` | RD1/2/3 可直接用；无需等 S0-28 重建 |
| 旧研发 worktree | `wt/e1-front`、`wt/e2-sema`、`wt/e4-codegen` 仍在 | 旧 E1/E2/E4 与新 RD 同域；未获 CEO1 书面改派前，只用 `c1-rd*`，不抢旧树 |
| QA worktree | 只有旧 `wt/qa-1`；无 `wt/qa-2`，无 `pod/qa-2` 分支 | QA2 的测试文件落地前必须由 CEO2 指定独立目录；否则只能出矩阵设计 |
| `impl/Tests/` | 不存在；测试在 `impl/internal/<pkg>/*_test.go` | 台账“用例文件”列写 `internal/...`，不要新建 `impl/Tests/` |

### 2.2 测试与台账

| 项 | 数值/结论 | 来源 |
|---|---|---|
| 测试函数 | xfront 44、sema 34、codegen 9、ffi 13、cli 6 | `grep '^func Test'` 实测 |
| 台账锚点 | 101 条；S1 14、S2 29、S3 11、S4 10、S5 9、S6 10、S7 7、S8 11 | 台账头部 |
| `status.tsv` | 35 行数据：PASS 10 / 部分 19 / 未实现 6 | 文件实算 |
| 编译器域 PASS | 8 条：S1 6（LEX-01、STMT-01、EXPR-01、CTRL-01、TYPE-01、TYPE-02）+ S2 2（INH-01、FIELD-01） | `status.tsv` |
| 编译器域未实现 | 24 条：S1 2（GEN-01、NEG-01）+ S2 22（BND-01—15、DISP-01、PCTOR-01、INT-01、SINGLE-01、EXT-01、ANN-01、GATE-01） | `status.tsv` + 台账 |
| 基线门 | S0-04b 独立验收通过；CI 02 `go test ./...` PASS 39.2s | `收件箱/CEO1/验收-S0-04b.md`、`收件箱/CEO1/evidence-S0-04b/m4-full.out` |
| 本轮复跑 | 本会话只读抽检未在 180s 内跑完 codegen 全包（疑与并行取数/冷缓存争用），**不作为基线**；首批开工前由 QA2 重跑并落 `evidence/baseline-2026-11-07/` | 本轮实测 |

**口径差异（登记不修改）**：`impl/docs/conformance/ledger-restructure.md` 写“30 行”，`status.tsv` 实际 35 行；差异来自后续补登的 FFI/XDK 行未回写说明。PJ 只登记，不在本卡改文件；由 CEO1/CEO3 决定补说明还是重生成。

### 2.3 已确认的实现缺口（带文件:行）

| 缺口 | 证据 | 影响首批卡 |
|---|---|---|
| `singleton` / `factory` / `extension` / `@annotation` 声明仍报 `SYN-110` | `impl/internal/xfront/unit.go:270` | S2-01 |
| 协议实现检查、枚举 `switch` 穷尽性、factory/singleton/extension 语义未做 | `impl/internal/sema/typedecl.go:21` | S2-02、S2-06 |
| 类继承代码生成直接拒绝 | `impl/internal/codegen/classes.go:63` | S2-04（候补） |
| 协议实现代码生成直接拒绝 | `impl/internal/codegen/classes.go:66` | S2-05（候补） |
| 带参 / 主构造器代码生成直接拒绝 | `impl/internal/codegen/classes_expr.go:87` | S2-03 |
| 顶层函数重载代码生成拒绝 | `impl/internal/codegen/codegen.go:163` | 后续泛型/重载批次 |
| 跨包导入拒绝 | `impl/internal/codegen/multifile.go:130` | 后续工程清单批次 |
| `Float` / `Char` 代码生成拒绝 | `impl/internal/codegen/types.go:20`、`:22` | 后续基础类型补口 |
| S1 语义残项：ERR-01、TUPLE-01、PKG-01、ENTRY-01、DET-01、BLD-01 部分；GEN-01、NEG-01 未实现 | 台账 + `status.tsv` | S1-11a、S1-16a |
| S2 对象边界：BND-01—15 大部分未实现；STRUCT/PROTO/ENUM/MEM-01 部分 | 台账 + `status.tsv` | S2-01/02/03、候补 |

---

## 3. 首批 10 张卡

### 3.1 总览

| 卡号 | 标题 | 主责 / 必签 | 人日 | 依赖 | 开工条件 | 工作目录 | 状态 |
|---|---|---|---:|---|---|---|---|
| S1-00b | S1/S2 条款清单与验收口径表 | PM / PJ | 2.0 | 无 | 无 | 根目录 | 待派 |
| S1-10a | S1 词法/语句终止条款逐条审计并补测 | RD1 / QA1 | 1.5 | 软依赖 S1-00b | 无 | `wt/c1-rd1` | 待派 |
| S1-11a | S1 类型系统条款审计并补测 | RD2 / QA2 | 2.0 | 软依赖 S1-00b | 无 | `wt/c1-rd2` | 待派 |
| S1-13a | S1 语句/控制流条款审计（静态可判定面） | RD1 / QA1 | 1.5 | 硬依赖 S1-10a | S1-10a 通过 | `wt/c1-rd1` | 待派 |
| S1-16a | S1 诊断触发矩阵（每码至少一个负例） | QA1 / QA2 | 2.0 | 硬依赖 S1-00b | 无 | QA 目录待 CEO2 指定 | 待派 |
| S1-04a | 双路径差分矩阵扩展（对象/容器/多文件/错误路径） | QA2 / QA1 | 2.0 | 无 | QA2 独立目录建好 | `wt/qa-2`（待建） | 待派 |
| S1-19a | 编译产物确定性（两次生成逐字节一致） | RD3 / QA2 | 1.0 | 软依赖 S1-04a | 无 | `wt/c1-rd3` | 待派 |
| S2-01 | xfront 补口：singleton/factory/extension/@annotation 声明解析 | RD1 / QA1 | 1.5 | 硬依赖 S1-13a；Stage 1 门 | 门通过 | `wt/c1-rd1` | 待派（门后） |
| S2-02 | sema 补口：协议实现完备性 + 父协议展开 | RD2 / QA2 | 1.5 | 硬依赖 S1-11a；Stage 1 门 | 门通过 | `wt/c1-rd2` | 待派（门后） |
| S2-03 | codegen 补口：主构造器与带参构造 | RD3 / QA1 | 2.0 | 硬依赖 S1-19a；Stage 1 门 | 门通过 | `wt/c1-rd3` | 待派（门后） |

**合计：17.0 人日；S1 7 张、S2 3 张；无单卡超过 2 人日。**

### 3.2 输出、验收与证据

> 下表“台账锚点”是该卡直接服务的验收行；只有整条链路通过且必签人签了验收，才由 PJ 起草状态差量。单卡不得自行把台账翻 PASS。

| 卡号 | 输出（代码/文档） | 机械验收 | 证据路径 | 台账锚点 |
|---|---|---|---|---|
| S1-00b | `收件箱/CEO1/条款清单-S1S2-v1.0.0.tsv` + `.md`；每行含章节、临时条款键、规范性语句、可判定性、建议测试类型、归属卡、母本行号（7 列） | `awk -F'\t' 'NR>1{if(NF<7){print NR;bad=1} if($2==""){print NR;bad=1} if($3==""){print NR;bad=1}} END{exit bad}'` 退出 0；43 个台账锚点全覆盖；`! grep -q 'TODO' 文件`；不出现自造 `S1-xx` 正式编号 | `收件箱/CEO1/条款清单-S1S2-v1.0.0.tsv` + `evidence/S1-00b/check.out` | S1 14 + S2 29 全部 |
| S1-10a | `impl/internal/xfront/lexer_test.go`、`stmt_test.go` 补测；`evidence/S1-10a/audit.md` 逐条映射“条款→测试名→结果→缺口”，附 `inventory.md` 列 xfront 缺口 | `cd impl && test -z "$(gofmt -l internal/xfront)" && go vet ./internal/xfront && go test ./internal/xfront -count=1 -timeout 120s`；audit 无空行、无未归属缺口 | `evidence/S1-10a/` | LEX-01、STMT-01 |
| S1-11a | `impl/internal/sema/ty_test.go` 补测；`evidence/S1-11a/audit.md` 覆盖类型/泛型/元组/包/入口/确定性 | `cd impl && test -z "$(gofmt -l internal/sema)" && go vet ./internal/sema && go test ./internal/sema -count=1 -timeout 120s`；audit 每条锚点有 PASS/部分/阻塞 + 理由 + 归属 | `evidence/S1-11a/` | TYPE-01/02、GEN-01、TUPLE-01、PKG-01、ENTRY-01、DET-01 |
| S1-13a | `impl/internal/xfront/stmt_test.go` 补测；`evidence/S1-13a/audit.md` 含“运行时面移交二司”清单 | `cd impl && test -z "$(gofmt -l internal/xfront)" && go test ./internal/xfront ./internal/sema -count=1 -timeout 120s`；移交清单每条有接收角色 | `evidence/S1-13a/` | STMT-01、CTRL-01、EXPR-01、ERR-01 |
| S1-16a | 新建 `impl/internal/xfront/diag_matrix_s1_test.go`、`impl/internal/sema/diag_matrix_s1_test.go`；`evidence/S1-16a/diag-matrix.tsv` + `acceptance-checklist.md` | `cd impl && go test ./internal/xfront ./internal/sema -run TestDiagMatrixS1 -count=1`；每个已实现/计划码至少一个负例；断言必须含 code + line/col，不得只断 message | `evidence/S1-16a/` | NEG-01 + S1 全部 |
| S1-04a | 新建 `impl/internal/codegen/diff_matrix_test.go`；`evidence/S1-04a/matrix.tsv`（用例、输入、期望 stdout、退出码、耗时） | `cd impl && go test ./internal/codegen -run TestDiffMatrix -count=1 -timeout 180s`；每例编译路径与解释路径 stdout + 退出码逐字节一致；超时即 fail；至少 8 个新用例 | `evidence/S1-04a/` | EXPR-01、CTRL-01、ERR-01、TUPLE-01、BLD-01、ENTRY-01、PKG-01 |
| S1-19a | `impl/internal/codegen/determinism_test.go`；两次 `EmitC` 输出保存为 `evidence/S1-19a/a.c` / `b.c`；附 `inventory.md` 列 codegen 缺口与归属 | `cd impl && go test ./internal/codegen -count=1 -timeout 180s`；`shasum -a 256 evidence/S1-19a/a.c evidence/S1-19a/b.c` 相等（Linux 用 `sha256sum`）；若二进制含 build-id 导致 hash 不等，显式记录“不可判定项”，不得伪装 | `evidence/S1-19a/` | DET-01 |
| S2-01 | `impl/internal/xfront/types.go`、`unit.go`、`printer.go` 新增四类声明 AST 与解析；`parser_test.go` 补测 | `cd impl && test -z "$(gofmt -l internal/xfront)" && go vet ./internal/xfront && go test ./internal/xfront -run 'TestDecl' -count=1`；AST 打印往返稳定；不得与 `@name` 注解使用混淆 | `evidence/S2-01/` | SINGLE-01、EXT-01、ANN-01、BND-07/08/13 |
| S2-02 | `impl/internal/sema/typedecl.go` 新增 `TY-208`（协议实现不完整）与父协议展开；`typedecl_test.go` 补测 | `cd impl && test -z "$(gofmt -l internal/sema)" && go vet ./internal/sema && go test ./internal/sema -run 'TestProtocol' -count=1`；缺方法/签名不符/父协议未实现/目标非协议四类负例均报 `TY-208` 或既有码 | `evidence/S2-02/` | PROTO-01、BND-05 |
| S2-03 | `impl/internal/codegen/classes.go`、`classes_expr.go` 支持主构造器与带参构造；新增 `examples/ctor.x`；`codegen_test.go` 补测 | `cd impl && go test ./internal/codegen -run 'Test.*Ctor' -count=1 -timeout 180s`；`examples/ctor.x` 双路径逐字节一致；继承/协议仍显式报错不静默 | `evidence/S2-03/` | PCTOR-01、INT-01 |

### 3.3 四张关键卡的额外约束

**S1-00b（PM）**
- 只做“本司审计输入”，**不替代 CTO-2 的 S1-00/S1-01 正式条款 ID 化**；临时键统一写成 `S1§2.6-03` 形态，禁止自造 `S1-25` 之类正式卡号。
- 每条“必须/禁止”必须能指回母本章节；指向不了的一律标“非验收面 + 理由”，不得留空。
- 交付后由 PJ 校验 43 个台账锚点全覆盖；缺一条即打回。

**S1-16a（QA1）**
- 只覆盖**当前已实现 + 首批计划实现**的诊断码；未实现的码登记为“未实现 + 归属卡”，不得写空断言冒充覆盖。
- 断言必须同时校验 `code` 与 `行:列`；只匹配文案的测试不计。
- 新建文件归 QA 所有；RD1/RD2 不得在同一分支编辑该文件。

**S2-01 + S2-02（RD1 + RD2）**
- 两张卡**必须同波合入**。S2-01 单独合入会让 `singleton/factory/extension/@annotation` 进入 sema 空白区，属于“静默接受”风险。
- 合入前跑一次“只解析、不过 sema”的负例：新声明在 S2-02 未落地时必须被显式拒绝，不得被忽略。
- 文件边界：RD1 只改 `xfront/**`；RD2 只改 `sema/**`；不得互改。

**S2-03（RD3）**
- 范围仅限**单类、无继承、无协议**的主构造器与带参构造；继承/协议仍走现有显式报错。
- 字段初始化顺序按 S2 §6.5；`final` 字段“恰好赋值一次”的语义检查若 sema 未覆盖，卡内只做代码生成，诊断缺口登记到后续 sema 卡（不在 S2-02 范围），不得在 codegen 里补语义检查。
- 必须新增 `examples/ctor.x` 并纳入双路径对照。

---

## 4. 依赖图与波次

```
S1-00b ──> S1-10a ──> S1-13a ──> S2-01
   │           │
   ├──> S1-11a ──> S2-02 ──> S2-05（候补）
   │        └──> S1-12a（候补）
   ├──> S1-16a ──> S1-17a（候补）
   └──> S1-04a ──> S1-19a ──> S2-03 ──> S2-04（候补）

虚线：S2-01 / S2-02 / S2-03 另需 Stage 1 门通过。
```

| 波次 | 并行卡 | 出口条件 | 说明 |
|---|---|---|---|
| W0 | S1-00b、S1-10a、S1-11a、S1-16a、S1-04a、S1-19a | 各自机械验收通过 | QA2 的 S1-04a 在独立目录建好前只做矩阵设计；QA1 的 S1-16a 在 QA 目录指定前只做清单 |
| W1 | S1-13a、S1-12a（候补）、S1-17a（候补）、S1-21a（候补） | 依赖卡通过 | RD1 串行接 S1-13a；其余填 Stage 1 门等待窗口 |
| W2 | S2-01、S2-02、S2-03 | Stage 1 门通过 + 各自依赖通过 | 三张卡分属三个研发域，可并行 |
| W3 | S2-04、S2-05、S2-06（候补） | W2 通过 | 继承/vtable/枚举穷尽性，按 RD3/RD2 WIP 串行 |

**不排日历日**：只按依赖波次推进；每张卡的“完成”以机械验收 + 独立必签为准，不以日期为准。

---

## 5. WIP 分配（v1.6 §4.2）

| 角色 | 上限 | 当前占用 | 当前卡 | 下一张 | 备注 |
|---|---:|---:|---|---|---|
| RD1（前端） | 1 | 1 | S1-10a | S1-13a →（门后）S2-01 | 闭包 codegen 不排首批 |
| RD2（语义） | 1 | 1 | S1-11a | S1-12a（候补）→（门后）S2-02 → S2-06 | 泛型先做审计，不直接开工 |
| RD3（代码生成） | 1 | 1 | S1-19a | （门后）S2-03 → S2-04 → S2-05 | 门未过时只做 S2-03 只读设计，不写代码 |
| QA1（合规） | 1 | 1 | S1-16a | S1-17a（候补）→ 验 S2-01/S2-03 | 新建测试文件，编辑 RD 文件禁止 |
| QA2（回归） | 1 | 1 | S1-04a（设计起步） | S1-21a（候补）→ 验 S2-02 | `wt/qa-2` 未建，测试落地前只做矩阵 |
| PM（产品） | 2 | 1 | S1-00b | S2 条款边界表 | 文档类占用 |
| PJ（项目） | 2 | 2 | 本文件 | 证据索引维护 | 不写生产文件、不派工 |
| CEO1（司长） | — | — | 签 L1/L2、门禁 | — | 不占队内 WIP，不参与实现 |

**超 WIP 处理**：不接新卡、不口头预留、不排队；必须等当前卡验收关闭释放后再派。

---

## 6. 证据与验收口径

### 6.1 路径约定

| 类型 | 路径 | 写入人 |
|---|---|---|
| 实现卡原始证据 | `evidence/<卡号>/` | 卡主责（RD/QA） |
| 证据七件套 | `command.txt`、`stdout.txt`、`stderr.txt`、`exit_code.txt`、`sha.txt`、`artifact.sha256`、`acceptance.md` | 卡主责 |
| 独立验收结论 | `收件箱/CEO1/验收-<卡号>.md` | 必签人（QA1/QA2/PJ） |
| PJ 证据索引 | `收件箱/CEO1/证据索引-v1.0.0.tsv` | PJ |
| 条款清单 | `收件箱/CEO1/条款清单-S1S2-v1.0.0.tsv` + `.md` | PM |

`evidence/<卡号>/` 不属生产代码；按卡授权写入。未获授权的目录只读。

### 6.2 验收硬规则

1. 结论只有 **通过 / 不通过**，不设“条件通过”。
2. 实现者不自验；必签人独立跑命令，不引用回执作结论。
3. 回执五行齐全：改了什么（文件 + 条款 ID）、怎么验（可复制命令）、commit sha、产物/证据路径、未测项。
4. `sha.txt` 必须是被测 commit 的完整 sha；干净 checkout 复跑，工作区 0 行。
5. 未支持面必须显式报错并标归属；静默降级即不通过。
6. 台账 `status.tsv` **不由实现者改**。验收通过后由 PJ 起草状态差量，CEO1 指定唯一落盘人；未指定前只交证据，不写台账。
7. 门禁：L1 由本司 QA 签，L2 由 CEO1 签；CEO1 只签不派。

---

## 7. 风险、阻塞与升级

| # | 风险/阻塞 | 影响 | 处置 | 升级对象 |
|---:|---|---|---|---|
| 1 | S1-00 / S1-01 正式条款 ID 未交付（CTO-2 线） | S1-10a/11a/13a/16a 的审计口径可能返工 | PM 的 S1-00b 只做本司临时清单；正式 ID 到达后做一次对齐，不推翻测试 | CEO2 → 董事会 |
| 2 | Stage 1 门未过（S1-23/S1-24 未做） | S2-01/02/03 不得开工，RD1/2/3 在 W1 后可能空转 | W1 填 S1-12a/S1-17a/S1-21a；RD3 只做 S2-03 只读设计；不抢跑 S2 | CEO1 / 董事会 |
| 3 | QA2 无独立 worktree / 无 `pod/qa-2` | S1-04a 测试文件无法落地 | CEO2 建 `wt/qa-2` 或指定独立分支；在此之前只做矩阵设计 | CEO2 |
| 4 | 闭包 codegen 缺运行时 `rt_closure` 表示；`rt.h` 当前无闭包/元组结构 | S1-14 不能按 2 人日完成，硬塞会私改冻结契约 | 拆 S1-14a/14b；先由 CEO2 二司出 `rt_closure` 契约，再排 codegen | CEO2 / 董事会 |
| 5 | 继承/协议 vtable 触及对象布局与运行时契约 | S2-04/S2-05 可能被契约评审卡住 | 卡内先读 `impl/docs/runtime-contract.md`；布局变更走提案，不私改 | CEO2 / CTO |
| 6 | codegen 测试依赖 `cc`，CI 02 预算 120s | 新增差分用例可能拖垮超时 | S1-04a 每例设超时；总时长 >120s 即拆包或标记为独立套件，不伪装 PASS | QA2 / CEO1 |
| 7 | `status.tsv` 35 行 vs `ledger-restructure.md` 30 行口径漂移 | 台账可信度受质疑 | PJ 登记差异；CEO1/CEO3 决定补说明或重生成；本轮不改 | CEO1 / CEO3 |
| 8 | 一文件多写者 | 同域多人踩文件 | 严格按卡授权：RD 只改自己包；QA 只新建独立测试文件；跨卡共享文件串行 | CEO1 |

---

## 8. 候补卡与“不塞进首批”的理由

| 卡号 | 标题 | 主责 | 人日 | 依赖/阻塞 | 启用条件 |
|---|---|---|---:|---|---|
| S1-12a | S1 表达式/求值顺序条款审计 | RD2 | 1.5 | S1-11a | W1 填门等待窗口 |
| S1-17a | S1 否决项负向测试 | QA2 | 1.5 | S1-16a | Stage 1 门前必须做 |
| S1-21a | 变异测试基线（xfront/sema） | QA2 | 2.0 | S1-04a；变异工具未定 | 工具选定后 |
| S2-04 | 单继承字段布局 + 构造链 + 静态派发 | RD3 | 2.0 | S2-03 | Stage 1 门后 |
| S2-05 | 协议 vtable + 动态派发 | RD3 | 2.0 | S2-02、S2-04 | Stage 1 门后 |
| S2-06 | 枚举 switch 穷尽性/重复/未知/default 位置 | RD2 | 1.5 | Stage 1 门（sema 可独立） | 门后或 W1 空档 |

**明确不放进首批的大卡**：

- **S1-14 闭包 codegen**：原估 3 人日，且需要二司运行时 `rt_closure` 契约；拆成“捕获分析 + 表示生成”“函数值调用 + 生命周期”两张子卡后才可排。当前 `rt.h` 无闭包结构，**禁止 codegen 私定 ABI**。
- **S1-15 泛型单态化**：原估 4 人日；拆成“sema 实例化表/约束检查”“codegen 特化”两张子卡。首批只做 S1-11a 的条款审计，不直接开工。
- **S1-07a 入口传参**：涉及 `cli`（三司域）+ `codegen`（一司域），必须拆成跨司两张子卡；当前不塞进一司首批。
- **S1-20 覆盖率门 / S1-23 独立验收 / S1-24 阶段门报告**：属 QA/CEO1 的门禁动作，不是研发卡；由 CEO1 在 Stage 1 门阶段单独安排。

---

## 9. 请 CEO1 / CEO2 决定的事项

1. **S2 卡是否硬等 Stage 1 门**：PJ 建议硬等（避免 P3 抢跑）；若 CEO1 要提前启动，需书面改判并写明回退条件。
2. **QA1/QA2 工作目录**：v1.6 只定了 3 个研发 worktree；请 CEO2 指定 QA 独立目录/分支，至少保证 QA1 与 QA2 不共用同一工作树。
3. **`status.tsv` 唯一落盘人**：v1.6 未指定；PJ 建议“PJ 起草差量 + CEO1 指定一人落盘”，禁止实现者自改。
4. **S1-00/S1-01 未交付的绕行**：是否允许 PM 的 S1-00b 临时清单作为审计输入；PJ 建议允许，但必须标注“临时键，不替代正式 ID”。
5. **S1-14/S1-15 的跨司排期**：请 CEO2 明确二司何时能给 `rt_closure` 契约；在契约落地前，一司不排闭包 codegen 的生产卡。

---

## 10. 合规自检

| v1.6 条款 | 本文件对应 |
|---|---|
| §2.1 一司 7 人编制 | 10 张卡覆盖 RD1/RD2/RD3/PM/PJ/QA1/QA2；PJ 不占研发 WIP |
| §4.2 WIP：研发 1、QA 1、PM/PJ 2 | 第 5 节逐角色列占用，无超限 |
| §4.3 唯一主责 + 同域只做子卡 | 每卡一个主责；QA 只新建独立测试文件；S2-01/02 分域 |
| §4.4 3 个研发 worktree | 使用已存在的 `wt/c1-rd1/2/3`；未重建、未抢旧树 |
| §5 首轮只读、不写生产代码、不 commit、不派工 | 本轮只新增本文件；未改 `impl/**`；未 commit；未派工 |

**本文件不是派工单**：卡号已预留，状态均为“待派”；实际派工由 CEO1 以任务卡发出，看板由 CEO2 维护。
