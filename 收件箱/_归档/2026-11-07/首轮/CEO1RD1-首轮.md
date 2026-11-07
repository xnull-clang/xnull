# CEO1-RD1（前端）首轮盘点

> **角色：** CEO1-RD1-前端（一司，增援 E1；主责仍为 E1）
> **依据：** 董事会判决 v1.6.0 第 2 条（编制）、第 5 条（首轮只读）；CEO1 派工单《派工-首轮-2026-11-07》卡 1
> **域：** `impl/internal/xfront/**`（只读）　**基线：** `dfcf033`
> **日期：** 2026-11-07　**性质：** 只读盘点，不含门禁签字

---

## 0. 结论（先看这里）

1. **域内可运行、可测试**：11 个文件 / 5204 行，44 个 Test 函数全部通过，语句覆盖 **73.6%**；`go vet` 无输出。
2. **发现 1 个阻断级解析缺陷**：嵌套泛型 `>>` 未拆分，`g<List<Int>>(x)`、`Map<String, List<Int>> m = [:]` 均解析失败（S1 附录 A「显式泛型实参」、S2 §13.3）。现有 `TestTypeRefs` 只断言词法诊断，**掩盖了该缺陷**（假绿）。
3. **S2 声明语法有 5 处未实现 / 静默丢失**：`factory` 未进类型声明关键字表（报 SYN-101 级联而非 SYN-110）；`singleton`/`extension`/`@annotation` 仍 SYN-110；泛型方法 `<T>` 无解析；`out`/`in` 型变被丢弃；协议可见性在 AST 层就没有落点（`ProtocolDecl` 无 `Mod` 字段），端到端静默通过。
4. **诊断可信度有 4 处硬伤**：18 个语句节点的 `Pos()` 全部返回 `Pos{}`；插值子表达式的诊断行列按片段自身计数（与宿主文件错位）；多行字符串内的 CRLF 未归一化；`switch` 的 default 顺序在 AST 中丢失，导致 §6.8「default 必须最后」无法校验。
5. **测试结构缺口**：`types.go`（S2 类型声明解析，24 个函数）在 xfront 包内平均覆盖 **3.3%**（23/24 为 0%）；`unit_test.go:146-148` 只有标题没有用例。跨包 `sema/typedecl_test.go` 能间接跑到这些函数，但 xfront 自身的解析缺陷无法被定位。
6. **只读纪律**：未改生产代码、未 commit、未 push；新增文件仅本报告一份。`evidence/S0-28/` 不存在 → 本轮写权未解禁，与 CEO1 判定一致。

---

## 1. 文件清单（全部 `.go`）

| 文件 | 行数 | 职责 | 关键入口 |
|---|---:|---|---|
| `token.go` | 136 | Token/Kind/Pos/关键字表/运算符表 | `Kind.String` `token.go:30`；`operators` `:129` |
| `lexer.go` | 732 | 词法、字符串五形态、插值、自动分号 | `Lex` `lexer.go:36` |
| `ast.go` | 457 | 表达式/语句/类型 AST | 各类节点 `:28-359`；接口实现 `:363-457` |
| `parser.go` | 1181 | 表达式/语句/类型解析、诊断码 | `ParseExpr` `:28`；`ParseStmts` `:37`；`parseStmt` `:702` |
| `types.go` | 603 | S2 类型声明解析（class/struct/protocol/enum） | `parseTypeDecl` `:183` |
| `unit.go` | 503 | 编译单元、package/import、顶层函数/字段 | `ParseUnit` `unit.go:108` |
| `printer.go` | 508 | `--emit ast` 形态的 S 表达式打印 | `PrintExpr` `:10`；`PrintStmt` `:49`；`PrintUnit` `:350`；`PrintType` `:458` |
| `lexer_test.go` | 407 | 词法用例 | 18 个 Test |
| `parser_test.go` | 293 | 表达式/优先级/闭包/插值用例 | 12 个 Test |
| `stmt_test.go` | 216 | 语句/控制流用例 | 8 个 Test |
| `unit_test.go` | 168 | 编译单元/顶层声明用例 | 6 个 Test |
| **合计** | **5204** | 生产 4120 行 + 测试 1084 行 | — |

---

## 2. 入口与调用链

| 入口 | 位置 | 生产调用方 |
|---|---|---|
| `xfront.Lex` | `lexer.go:36` | 仅 `ParseUnit`/`ParseExpr`/`ParseStmts` 内部调用 |
| `xfront.ParseUnit` | `unit.go:108` | `cli.policyFile` `cli.go:265`；`codegen.LoadUnits` `multifile.go:67`（`build`/`run`/`run --interp` 共用）；`cmd/xnpt` `main.go:22` |
| `xfront.ParseExpr` | `parser.go:28` | `parseInterpText` `parser.go:504`；`cmd/xnpt` 间接（经 ParseUnit 后取表达式） |
| `xfront.ParseStmts` | `parser.go:37` | 仅测试使用，无语音调用 |
| `PrintUnit/PrintExpr/PrintStmt/PrintType` | `printer.go:350/10/49/458` | `interp` 报错信息 `interp.go:522,657`；`cmd/xnpt:41`；**`PrintUnit` 无生产调用方** |

**入口层缺口：** `cli.go:157` 接受 `--emit` 标志，但全仓无任何 `emit` 消费逻辑（`grep -rn 'emit' impl/internal/cli` 仅命中白名单），`--emit ast` 实际不生效，`printer.go` 的完整打印能力在 CLI 上不可达。

---

## 3. 测试清单与覆盖

### 3.1 用例清单（44 个 Test 函数）

| 文件 | 用例名 |
|---|---|
| `lexer_test.go`（18） | `TestIntegerLiterals` `TestIntegerLiteralErrors` `TestFloatLiterals` `TestFloatLiteralErrors` `TestCharLiterals` `TestCharLiteralErrors` `TestStringForms` `TestStringErrors` `TestComments` `TestIdentifiersAndKeywords` `TestOperatorsLongestMatch` `TestAutomaticSemis` `TestNoSemiBeforeElseAndDoWhile` `TestSemiAfterLiteralsAndCalls` `TestSourceFileRules` `TestMultipleErrorsWithPosition` `TestReservedListed` `TestAdjacentStringsNoConcat` |
| `parser_test.go`（12） | `TestPrecedenceTable` `TestAssociativity` `TestNonChainable` `TestEqualityChaining` `TestTypeOps` `TestPostfix` `TestLiteralsAndCollections` `TestLambda` `TestInterpolatedString` `TestTypeRefs` `TestErrors` `TestSpecExamplesExpr` |
| `stmt_test.go`（8） | `TestLocalDecls` `TestAssignments` `TestControlFlow` `TestSwitch` `TestJumps` `TestDefer` `TestStatementTermination` `TestClosureStatements` |
| `unit_test.go`（6） | `TestPackageDecl` `TestImportDecl` `TestTopFuncs` `TestTopFields` `TestFullUnit` `TestUnitMultiDiags` |

### 3.2 覆盖率（`-count=1`，本机 go 1.27）

| 文件 | 函数平均覆盖 | 说明 |
|---|---:|---|
| `lexer.go` | 97.0% | 主要未覆盖为错误恢复分支 |
| `printer.go` | 91.6% | 类型声明打印分支不存在（见 G-U5） |
| `parser.go` | 88.2% | `parseNewType`/`tryTupleTypeDecl`/`parseLocalDecl` 偏低 |
| `unit.go` | 53.5% | `parseTopDecl` 类型声明分支、`parseTopType` 低 |
| `ast.go` | 8.0% | 87 个函数多为 `Pos()`/`exprNode()`；**语句 `Pos()` 全为零**（G-P8） |
| `token.go` | 21.1% | `Kind.String` 仅少量分支 |
| `types.go` | **3.3%** | **24 个函数中 23 个 0%**；仅 `typeKeywordAhead` 80% |
| 包整体 | **73.6%** | 语句覆盖 |

**测试结构缺口：** `unit_test.go:146-148` 有「类型声明：M2.5.1 起 class/struct/protocol/enum 正式解析」标题与注释，但**下面没有任何测试函数**；`types.go` 的全部功能只能靠 `sema/typedecl_test.go` 跨包间接覆盖，xfront 包内无法回归解析器本身。

---

## 4. 诊断码覆盖表

| 码 | 常量 | 发出位置 | xfront 测试 | 状态 |
|---|---|---|---|---|
| LEX-101 | `lexIllegalChar` | `lexer.go:260` | 负向 2 处 | 有 |
| LEX-102 | `lexUnterminated` | `lexer.go:146,470,497,639` | 负向 6 处 | 有 |
| LEX-103 | `lexBadEscape` | `lexer.go:493,547,561,566,571,579,585` | 负向 6 处 | 有 |
| LEX-104 | `lexBadNumber` | `lexer.go:341,351,361,400,433,439,459` | 负向 15 处（最充分） | 有 |
| LEX-105 | `lexBadInterp` | `lexer.go:629,637,650` | 负向 2 处 | 有 |
| LEX-106 | `lexCharContents` | `lexer.go:475,488,501` | 负向 3 处 | 有 |
| SYN-101 | `synExpect` | `parser.go:99,111` 等 41 处 | 负向 10 处 | 有 |
| SYN-102 | `synChainCompare` | `parser.go:236` | 负向 2 处 | 有 |
| SYN-103 | `synChainRange` | `parser.go:272` | 负向 2 处 | 有 |
| SYN-104 | `synTupleArity` | `parser.go:581,1114` | 负向 1 处（`()`），类型位置未单独覆盖 | 部分 |
| SYN-105 | `synNewForm` | `parser.go:563` | 负向 1 处 | 有 |
| SYN-106 | `synTrailing` | **从未发出**（仅常量 `parser.go:18`） | 0 | **死码** |
| SYN-107 | `synRangeContext` | **从未发出**（仅常量 `parser.go:19`；注释称语义层执行，sema 无实现） | 0 | **死码 + 全链无检查** |
| SYN-108 | `synStmtTerm` | `parser.go:685` | 负向 3 处 | 有 |
| SYN-109 | `synAssignTarget` | `parser.go:822` | 负向 3 处 | 有 |
| SYN-110 | `synTypeDecl` | `unit.go:270` | 负向 1 处（singleton） | 部分（factory 走不到） |
| SYN-111 | `synXdkPackage` | `unit.go:191` | 负向 2 处 | 有 |

---

## 5. 缺口表

> 分类：**U 未实现** / **P 部分实现或静默丢失** / **S 可疑（可能的假绿或死码）**
> 每条给 `文件:行`；复核命令见 §6 的 E1–E7 代码块。

### 5.1 未实现

| ID | 缺口 | 文件:行 | 影响 | 复核 |
|---|---|---|---|---|
| **G-U1** | 嵌套泛型 `>>` 未拆分：`>>` 被词法吃成移位 token，`tryTypeArgs`/`parseNamedType` 只认单 `>` | `token.go:129-136`；`lexer.go:232-256`；`parser.go:392-415,1164-1179` | **阻断**：`g<List<Int>>(x)`、`Map<String, List<Int>> m = [:]`、`new Map<String, List<Int>>()` 全部解析失败；S2 §13.3 泛型实参不可用 | E2 |
| **G-U2** | `factory` 不在 `typeDeclKeywords`，也未进关键字分支，报 SYN-101 级联（6 条）而非 SYN-110 | `unit.go:209-212`；`unit.go:254-285`；`token.go:115` | S2 §10 完全不可写；与 singleton/extension 的「待实现」口径不一致，诊断噪声大 | E4（f 组） |
| **G-U3** | `singleton` / `extension` / `@annotation` 仍按 SYN-110 拒绝 | `unit.go:269-284`；`annoDeclStart` `unit.go:155-160` 里的 `annotation` 永远不会以 Keyword 出现 | S2 §9 / §11 / §12 未实现；`@annotation Marker {}` 退化为「注解前缀 + 无主标识符」，实测报 SYN-101 ×3（`Marker`、`{`、`}`），无 SYN-110 提示 | E4（g/h 组） |
| **G-U4** | 泛型方法名后的 `<T>` 无解析 | `types.go:340-356`（`parseMethodRest` 只解析参数表） | `class Util { U convert<U>(U value) }`（S2 §13.1 原例）产生 11 条 SYN-101 级联，整段成员被丢弃 | E4（b 组） |
| **G-U5** | `out` / `in` 型变被消费后丢弃：`parseGenericPars` 只返回 `[]string` | `types.go:207-229`；`ClassDecl.TypePars []string` `types.go:62` | `class Producer<out T>` 解析成功但型变信息不可恢复，S2 §13.2 无法在 sema/codegen 落地 | E4（a 组） |
| **G-U6** | `PrintUnit` 没有 class/struct/protocol/enum 分支 | `printer.go:371-429`（`writeTopDecl` 只处理 package/import/func/field） | 含类型声明的单元打印为 `(unit )`，`--emit ast`/证据链会把类型声明整段吞掉；`--emit` 本身也未接线（`cli.go:157`） | E5 |

### 5.2 部分实现 / 静默丢失

| ID | 缺口 | 文件:行 | 影响 | 复核 |
|---|---|---|---|---|
| **G-P1** | `ProtocolDecl` 无 `Mod` 字段，协议分支丢弃修饰符 | `types.go:84-91`；`types.go:194-197`；`unit.go:254-267` | `public/private/protected protocol` 与 `abstract protocol` 全部静默接受；sema `checkProtocol` 也不查（`sema/typedecl.go:416-433`），`private protocol` 被当公开导出 | E4（d/e）、E5 |
| **G-P2** | `switch` 的 default 子句单独存放，源码顺序丢失 | `ast.go:283-289`（`Cases []*SwitchCase` + `Default *SwitchCase`）；`parser.go:1032-1039` | §6.8「default 最多一个且必须位于最后」无法校验；`default` 写在前面也能通过，打印时被重排到末尾 | E5 |
| **G-P3** | 插值子表达式诊断行列错位：`host` 参数未使用 | `parser.go:503-511`（`_ = host`；`ParseExpr(p.file, text)` 从 1:1 起算） | `$"{1 +}"` 的诊断落在 `1:4` 而非宿主位置；S1 §1.7 要求文件/行/列，插值内错位会误导 QA 与用户 | E5 |
| **G-P4** | 多行字符串内 CRLF 未归一化：`\r` 只在 trivia 中被跳过 | `lexer.go:118-153`（trivia）；`lexer.go:604-712`（字符串逐 rune 原样写入） | S1 §1.1 要求「CRLF 在词法阶段归一化为 LF」；Windows 源文件的多行字符串会把 `\r` 带进 `Value`，影响语义/代码生成与差分 | E5 |
| **G-P5** | 类型声明修饰符不校验：`static class`、`const class`、`public private class`、重复修饰符 | `unit.go:222-267,373-394`；`types.go:132-180` | S2 §1.6 明确 `static`/`const` 不是类型修饰符、可见性互斥、重复非法；`static class` 与 `public private class` 端到端静默通过（后者取 public），`const class` 走字段路径报误导性 SYN-101 | E4（c/d） |
| **G-P6** | 主构造器参数必须写 `final` 无人执行 | `types.go:268-271`（`parseParamList` 不校）；`sema/typedecl.go:244-252`（`materializePrimary` 不看 `p.Final`） | `class Worker(Int id) { }` 端到端无诊断（S2 §6.3 要求必须 `final`），final 恰好赋值一次被绕过 | E4（a） |
| **G-P7** | 18 个语句节点的 `Pos()` 返回 `Pos{}` | `ast.go:417-434` | 语句级诊断/证据无法定位；与各节点自带的 `P` 字段不一致，属复制粘贴遗漏 | E5 |
| **G-P8** | 范围上下文（SYN-107）全链无检查：parser 注释称语义层执行 | `parser.go:19`；`sema` 仅把 `Range` 当类型名（`sema/ty.go:899`） | §6.7「区间只允许出现在 for-in 源位置」当前无任何一层拒绝；归属跨域（RD2），需 CEO1 定口 | E6 |
| **G-P9** | 简单枚举允许成员语法，靠 sema 兜底；xfront 包内无对应负向用例 | `types.go:520-561`；sema 兜底 `sema/typedecl.go:498` | xfront 单测无法发现「简单枚举带方法」的解析问题；端到端已被 sema 拒绝（实测 TY-206），故仅记覆盖缺口 | E4（i） |

### 5.3 可疑（假绿 / 死码）

| ID | 可疑点 | 文件:行 | 理由 | 复核 |
|---|---|---|---|---|
| **G-S1** | `TestTypeRefs` 只断言词法诊断，不检查 `p.errs` | `parser_test.go:240-250` | 按代码路径推演，`Map<String, List<Int>>` 在内层/外层 `expectOp(">")` 各失败一次（`parser.go:1178`，共 2 条 SYN-101），用例仍判 PASS，掩盖 G-U1；属本轮最危险的假绿（`parser` 未导出，包外无法直接观测，卡 1 内补一条 `len(p.errs)==0` 断言即可证实） | E1/E2 |
| **G-S2** | `dropSemiInAnnotation` 的状态机泄漏：`annoDeclStart` 不含普通类型名 | `unit.go:129-160` | `@Deprecated` 后跟 `Int f()` 时 `pending` 一直为真，会丢弃函数体内的**显式** `;`：`@Deprecated\nInt f(){ Int x = 1; return x }` → SYN-108 | E3 |
| **G-S3** | `parsePrimaryType` 里 `p.atKw("void")` 永不命中（`void` 是 Ident） | `parser.go:1128-1130` | 与已修的 `unit.go:308-310` 同类 bug；当前靠 Ident 分支兜住，属死分支，掩盖「void 返回类型」的真实路径 | E6 |
| **G-S4** | `blocksSemi` 对任意 `}` 后的 `while` 都不插分号，不区分是否 `do` 体 | `lexer.go:169-176` | 目前被行号检查掩盖；若把 `while` 写成同行会报 SYN-108，语义边界依赖「恰好换行」 | E6 |
| **G-S5** | `parseEnumDecl` 先按项解析、遇 `;` 再按成员解析，`IsData` 由首个项反推 | `types.go:520-524` | 简单枚举 + 数据枚举混写只能靠 sema 兜底；解析器自身无一致性校验 | E4（i） |

**缺口合计 20 条**（U6 / P9 / S5），满足首轮「≥5 条」要求。

---

## 6. 复核命令（全部可复制）

### E1　包测试 + 覆盖率

```bash
cd /Users/vjs/Desktop/XNull-Lang/impl
go vet ./internal/xfront/
go test ./internal/xfront/ -cover -count=1
go test ./internal/xfront/ -coverprofile=/tmp/xfront.cover -count=1 >/dev/null
go tool cover -func=/tmp/xfront.cover | grep -E 'types.go|total'
```

### E2　嵌套泛型（G-U1 / G-S1）

```bash
cd /Users/vjs/Desktop/XNull-Lang/impl
go run ./cmd/xnpt 'm.get<Int,String>(k)'      # 通过：<Int, String> 单层
go run ./cmd/xnpt 'g<List<Int>>(x)'           # 失败：SYN-102/SYN-101/SYN-108
printf 'static Int f() { Map<String, List<Int>> m = [:]\nreturn 0 }\n' > /tmp/rd1-nest.x
go run ./cmd/xnull policy /tmp/rd1-nest.x     # 失败：SYN-108
```

### E3　注解丢分号（G-S2）

```bash
cd /Users/vjs/Desktop/XNull-Lang/impl
printf '@Deprecated\nInt f() { Int x = 1; return x }\n' > /tmp/rd1-anno.x
go run ./cmd/xnull policy /tmp/rd1-anno.x     # 失败：SYN-108 @2:22 + SYN-101
```

### E4　S2 声明语法矩阵（G-U2/U3/U4/U5、G-P1/P5/P6、G-S5）

```bash
cd /Users/vjs/Desktop/XNull-Lang/impl
mk(){ printf '%b\n\nstatic Int main() { return 0 }\n' "$2" > /tmp/rd1_$1.x; }
mk a 'class Worker(Int id) {\n}'                 # 期望报错：主构造器参数必须 final；实测静默通过
mk b 'class Util { U convert<U>(U value) { return value } }'   # 期望通过；实测 11 条 SYN-101
mk c 'static class X {\n}'                       # 期望报错：static 非类型修饰符；实测静默通过
mk d 'public private class X {\n}'               # 期望报错：可见性互斥；实测静默通过（取 public）
mk e 'abstract protocol P {\n}'                  # 期望报错：abstract 只修饰类；实测静默通过
mk f 'private protocol P {\n}'                   # 期望可见性生效；实测静默通过且无 AST 落点
mk g 'factory F for Device { static Device create() { return null } }'  # 期望 SYN-110；实测 SYN-101 级联
mk h 'enum E { A; Int f() { return 1 } }'        # 期望报错；实测 sema 兜底 TY-206
for x in a b c d e f g h; do echo "--- $x ---"; go run ./cmd/xnull policy /tmp/rd1_$x.x 2>&1 | head -4; done
```

### E5　AST/诊断探针（G-U6、G-P2/P3/P4/P7）

```bash
cd /Users/vjs/Desktop/XNull-Lang
mkdir -p impl/.rd1probe
cat > impl/.rd1probe/main.go <<'EOF'
package main

import (
	"fmt"
	"reflect"

	"xnull.dev/xnull/internal/xfront"
)

func main() {
	stmts, _ := xfront.ParseStmts("t.x", "Int x = 1\nreturn x")
	for _, s := range stmts {
		fmt.Printf("%T pos=%+v\n", s, s.Pos()) // 期望非零，实测 {0 0}
	}

	u, _ := xfront.ParseUnit("t.x", "static void f() { switch v { default: a() case 1: b() } }")
	fmt.Println("switch ast:", xfront.PrintUnit(u)) // default 被重排到末尾

	u2, _ := xfront.ParseUnit("t.x", "class C { Int v; void m() { } }")
	fmt.Println("class ast:", xfront.PrintUnit(u2)) // 实测 (unit )，类型声明被吞

	_, ok := reflect.TypeOf(xfront.ProtocolDecl{}).FieldByName("Mod")
	fmt.Println("ProtocolDecl.Mod exists:", ok) // 实测 false

	toks, _ := xfront.Lex("t.x", "\"\"\"a\r\nb\"\"\"")
	fmt.Printf("multiline crlf value=%q\n", toks[0].Value) // 实测含 \r

	_, ds := xfront.ParseUnit("t.x", "static void f() { Int x = $\"{1 +}\" }")
	for _, d := range ds {
		fmt.Printf("interp diag %s @%d:%d\n", d.Code, d.Line, d.Col) // 实测 1:4，应为宿主列
	}
}
EOF
(cd impl && go run ./.rd1probe)
rm -rf impl/.rd1probe
```

### E6　死码 / 未接线静态复核（G-P8、G-S3、G-S4、G-U6）

```bash
cd /Users/vjs/Desktop/XNull-Lang/impl
grep -n 'synTrailing\|synRangeContext' internal/xfront/*.go        # 仅常量定义
grep -rn '范围只允许\|synRangeContext' internal/sema               # 无命中 → 全链无检查
grep -n 'atKw("void")' internal/xfront/parser.go                  # 1128 死分支
grep -n 'blocksSemi' -A 8 internal/xfront/lexer.go                # 不区分 do-body
grep -rn 'emit' internal/cli/cli.go                               # 仅 157 行白名单，无消费
grep -rn 'PrintUnit' --include='*.go' . | grep -v internal/xfront # 无生产调用方
```

### E7　只读与写权证据

```bash
cd /Users/vjs/Desktop/XNull-Lang
git status --short
git log --oneline -1                     # dfcf033
git worktree list | grep c1-rd1          # 存在，基线 dfcf033
ls evidence/S0-28                         # 不存在 → 写权未解禁
```

---

## 7. 前 3 张建议卡（供 CEO1 拆卡，不构成派工）

> 排序理由：先修「让真实代码写不出来」的阻断项，再修「让 S2 条款写不进 AST」的保真项，最后修「让门禁证据不可信」的诊断项。
> 卡片字段沿用《派工-首轮》卡 5：ID/标题/主责/必签/输入/输出/验收/依赖/预估/证据路径。

### 卡 1　C1-RD1-01　嵌套泛型 `>>` 拆分与类型实参回归

| 项 | 内容 |
|---|---|
| 主责 | RD1（E1 必签） |
| 必签 | E1 |
| 输入 | `token.go:129-136`、`lexer.go:232-256`、`parser.go:392-415/1155-1181`、`parser_test.go:223-251`；S1 §1.5 + 附录 A「显式泛型实参」；S2 §13.3 |
| 输出 | ① 词法/解析协作方案（推荐：词法仍产出 `>>`/`>>=`，parser 在类型实参态按需拆角；不得改变移位运算语义）② 补齐 `parseNamedType`/`tryTypeArgs` 的嵌套实参路径 ③ 新用例：`Map<String, List<Int>>` 声明、`g<List<Int>>(x)`、`new Map<String, List<Int>>()`、`List<List<Int>>[]` ④ **修 G-S1**：`TestTypeRefs` 增加零诊断断言 |
| 验收 | `go test ./internal/xfront/ -run 'TestTypeRefs|TestNestedTypeArgs' -count=1`；`go run ./cmd/xnpt 'g<List<Int>>(x)'` 输出 `(call (ident g) <List<Int>> (ident x))` 且退出码 0；`a >> 2` / `a >>= 1` 不回归；`go test ./...` 全绿 |
| 依赖 | 无（改 token 消费方式，需评估 sema/codegen 只读影响） |
| 预估 | 1 人日 |
| 证据路径 | `evidence/C1-RD1-01/`（before/after 的 `go test` 输出 + xnpt 对照） |

### 卡 2　C1-RD1-02　泛型声明保真：方法类型参数、`out`/`in` 型变、协议可见性

| 项 | 内容 |
|---|---|
| 主责 | RD1（E1 必签） |
| 必签 | E1 |
| 输入 | `types.go:62/84-91/194-197/207-229/340-356`、`unit.go:254-267`；S2 §1.6、§4、§13.1、§13.2 |
| 输出 | ① `MethodDecl` 增 `TypePars []string` 并解析 `name<T>(...)` ② `ClassDecl.TypePars` 升级为带型变的结构（`{Name, Variance}`，保留 `out`/`in`），`StructDecl` 同步但拒绝型变 ③ `ProtocolDecl` 增 `Mod TypeModifiers`，`parseTypeDecl` 传入 ④ 新增 xfront 单测：`class Producer<out T>`、`class Util { U convert<U>(U value) }`、`private protocol P` ⑤ 输出 sema 侧影响清单（sema 读新字段需另卡，不在本卡写 sema） |
| 验收 | 新单测断言 `TypePars` 含型变、方法 `TypePars==["U"]`、协议 `Mod.Vis=="private"`；`go test ./internal/xfront/ -count=1`；`go test ./...` 不回归；`go run ./cmd/xnull policy` 对 `private protocol P` 不再静默（sema 跟进卡后） |
| 依赖 | 无；与卡 3 的 `PrintUnit` 改动可同批合入但**文件清单分开**（一文件一写入者） |
| 预估 | 2 人日 |
| 证据路径 | `evidence/C1-RD1-02/`（AST 结构 dump + 新单测输出） |

### 卡 3　C1-RD1-03　诊断与 AST 保真（位置 / 顺序 / CRLF / 打印）

| 项 | 内容 |
|---|---|
| 主责 | RD1（E1 必签） |
| 必签 | E1 |
| 输入 | `ast.go:283-289,417-434`、`parser.go:503-511,1013-1043`、`lexer.go:604-712`、`printer.go:371-429`；S1 §1.1/§1.7/§6.8/§7.8 |
| 输出 | ① 18 个 `Stmt.Pos()` 返回自带 `P` ② `SwitchStmt` 改为有序子句（或增加 order 索引），解析期直接拒绝「default 非最后」 ③ 插值片段按 `host` 行/列偏移换算诊断位置 ④ 字符串内 `\r` 随 LF 归一丢弃 ⑤ `PrintUnit` 增加 class/struct/protocol/enum 分支（含 Mod/TypePars/成员/主构造器）⑥ 清理 SYN-106 死常量与 `atKw("void")` 死分支 |
| 验收 | 新单测：`ParseStmts` 每条 `Pos().Line>0`；`$"{1 +}"` 诊断列落在宿主表达式内；`switch v { default: a() case 1: b() }` 报错；CRLF 多行串 `Value` 不含 `\r`；`PrintUnit` 输出含 `(class`；`go test ./...` 全绿 |
| 依赖 | 卡 2（`ProtocolDecl.Mod` 字段）；`--emit ast` 的 CLI 接线属三司/`cli` 域，CEO2 协调另卡，本卡只补 `Printer` 侧 |
| 预估 | 2 人日 |
| 证据路径 | `evidence/C1-RD1-03/`（探针 E5 的 before/after 输出） |

**未进前 3 的缺口去向建议**（只给建议，不派工）：

| 缺口 | 建议 |
|---|---|
| G-U2/U3 `factory`/`singleton`/`extension`/`@annotation` | 单独立「S2 声明语法补全」卡，需 PM 先给 §9–§12 条款清单与优先级（卡 2 只做 class/struct/protocol/enum 的保真，不扩范围） |
| G-P6 主构造器 `final` | 与 G-U2 同批或并入卡 2 的「成员/参数规则」子项；若判为 sema 职责，转 RD2 |
| G-P8 范围上下文 | 归口 RD2（sema）；parser 侧删除失效注释或保留 SYN-107 说明，由 CEO1 定口 |
| G-P5 修饰符矩阵 | 可并入卡 2（同一 `types.go`/`unit.go` 文件簇），但需在卡上列明文件，避免与卡 3 冲突 |

---

## 8. 不确定项 / 需 CEO1 或 PM 裁决

1. **规范冲突：插值串 `}}` 的含义。**
   S1 §1.4.4 写「不在插值中的 `}` 按字面量处理」，则 `$"{{lit}}"` 的静态文本应为 `{lit}}`（两个 `}`）；
   附录 A 写 `InterpPart = ... | "{{" | "}}"`，则 `}}` 应产生一个 `}`（`{lit}`）。两者矛盾。
   当前实现与 `lexer_test.go:177-190` 断言 `{lit}}`（即 §1.4.4 读法）。**需 PM 裁决并锁定条款**，否则任何修法都会打翻一版测试。
2. **`SYN-107` 归口。** parser 注释明确「文法接受、语义拒绝」，但 sema 无对应实现。按域应归 RD2，但缺陷登记归 CEO3；本报告只记录「全链无检查」，不自行派工。
3. **文件名口径。** CEO1《首轮判定》期望 `收件箱/CEO1/RD1-首轮.md`，本轮指令指定 `收件箱/CEO1/CEO1RD1-首轮.md`。本报告按**本轮指令**落盘，未复制第二份（避免双文件歧义）；若需统一命名，请 CEO1 指定唯一文件名后由本人改名。
4. **`1.` / `.5` 的错误归类。** 现实现词法接受 `1` 后再报语法错误（`SYN-101`），规范只说「不是合法浮点字面量」，未规定必须报词法错误。当前实现可接受，未计入缺口。
5. **`annotation` 是否应为关键字。** S1 §1.3 关键字表未列 `annotation`，声明写作 `@annotation`；因此 `annoDeclStart["annotation"]` 永不命中。若 S2 §12 要求把 `annotation` 当声明关键字，需先改 S1 关键字表（跨规范），本报告未按缺陷计。
6. **覆盖率数字**基于本机 `go 1.27`、`-count=1`；`types.go` 的 3.3% 是「xfront 包内」覆盖，不含 `sema` 跨包测试，解读时勿混淆。

---

## 9. 只读证据

```text
本会话新增：收件箱/CEO1/CEO1RD1-首轮.md（本文件）
本会话删除：impl/.rd1check/、impl/.rd1probe/（临时探针，已 rm）
未执行：git add / commit / push / 分支操作 / 生产代码编辑
```

- 基线 `dfcf033`；`wt/c1-rd1` 存在但 `evidence/S0-28/` 缺失，**写权未解禁**，本轮全部只读。
- 工作区其他未跟踪文件（`收件箱/CEO*`、`evidence/S0-18/`、`日志/` 等）为他人既有产出，未触碰。

---

**结论：本域可用性 = 可测但不可信**——主干词法/表达式/语句解析质量较高（73.6% 覆盖、44 个用例），但 S2 声明语法与诊断保真存在阻断级和系统性缺口；建议按 §7 三张卡开工，且卡 1 必须先于任何依赖「嵌套泛型」的 sema/codegen 任务。
