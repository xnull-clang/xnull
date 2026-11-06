# GEN-01 检查表（逐项抄自台账 + S1 §8，不得漏项）

> **锚点**：`GEN-01`（S1，M1）｜**主责**：CEO1-RD3（会签 CEO1-QA2）
> **台账验收要点原文**（`XNull一致性用例台账-v1.0.0.md:27`）：
> 「泛型函数；显式实参、推断、冲突、未绑定、重载、单态化、无限展开诊断均符合第 8 节；`Result` 类型实参可实例化」
> **条款出处**：`XNull解决方案-第1部分-基础语法-v3.3.0.md` §8.1（L1187-1200）、§8.2（L1202-1219）、§8.3（L1221-1231）、§8.4（L1233-1237）
> **基线**：`pod/c1-rd3` @ `dfcf033`｜**判定时间**：2026-11-07

---

## 0. 计分方式

| 项 | 值 |
|---|---|
| 检查表总项 | **26** |
| 台账显式 8 项 | G1a/G1b/G2a-d/G3/G4/G5a-c/G6a/G6b/G7/G8（14 个可判用例，覆盖 8 个要点） |
| S1 §8 补充项 | G9–G19（12 项） |
| **当前达标** | **1 / 26**（G17 拒绝成立，但诊断质量为级联 SYN-101，需整改） |
| 未达标 | 24 / 26 |
| 不可测 | 1 / 26（G12，当前语言面无函数值语法） |

---

## 1. 台账 8 项（逐项拆到可判用例）

| ID | 条款 | 判据（可判定） | 现状 | 归属层 |
|---|---|---|---|---|
| **G1a** | §8.2 显式类型实参 | `identity<Int>(7)` 通过，输出 `7`，双路径一致 | ❌ 未实现（sema TY-101） | sema + codegen + interp |
| **G1b** | §8.2 显式实参数量必须一致 | `identity<Int, Int>(7)` 必须报「类型实参数不一致」 | ❌ 未实现（`Call.TypeArgs` 全仓无人读） | sema |
| **G2a** | §8.2 推断·直接匹配 | `identity(7)` 不写实参即得 `T=Int` | ❌ TY-101 | sema + codegen |
| **G2b** | §8.2 推断·嵌套逐层 | `head<T>(List<T>)` 由 `List<Int>` 得 `T=Int` | ❌ TY-101 | sema |
| **G2c** | §8.2 无后缀字面量绑定 | `pick(1, 2)` 绑定 `Int` | ❌ TY-101 | sema |
| **G2d** | §8.2 返回类型不参与推断 | `Int x = make()` 必须报「未绑定 T」 | ❌ 报的是 TY-101（错的理由） | sema |
| **G3** | §8.2 冲突绑定 | `pick(1, "s")` 必须报「T 冲突绑定」 | ❌ 报的是逐实参 TY-101 | sema |
| **G4** | §8.2 未绑定类型参数 | `firstOf<T,U>(1,2)` 必须报「U 未绑定」 | ❌ **解析层即失败**（多类型参数不解析，见 §4-B1） | xfront + sema |
| **G5a** | §8.2 重载·唯一候选 | 普通 `pick(Int)` 与泛型 `pick<T>` 共存，`pick(3)` 选中普通版 | ❌ TY-101 + codegen 重名报错 | sema + codegen |
| **G5b** | §8.2 重载·歧义 | 多候选适用必须报歧义 | ❌ 无歧义判定（`inferCall` 取第一个） | sema |
| **G5c** | §8.2 重载·零候选 | 无适用候选必须编译错误 | ⚠️ 恰好报错，但理由是逐候选 TY-101，非"零候选" | sema |
| **G6a** | §8.3 单态化 | `identity<Int>` 与 `identity<String>` 各自成实例并都正确 | ❌ 未实现 | sema + codegen |
| **G6b** | §8.3 实例内按具体类型检查 | `count<T>(List<T>)` 对 `List<Int>`/`List<String>` 各自通过静态检查 | ❌ 未实现 | sema + codegen |
| **G7** | §8.3 无限展开诊断 | `loop<T>(v){return loop<T>(v)}` 必须有诊断，不得挂死/静默截断 | ❌ 未实现（无展开，故也无上限） | sema + codegen |
| **G8** | 台账·`Result` 类型实参 | `unwrapOr<T>(Result<T,String>, T)` 可实例化 | ❌ TY-101 | sema + codegen |

## 2. S1 §8 补充项

| ID | 条款 | 判据 | 现状 | 归属层 |
|---|---|---|---|---|
| **G9** | §8.1 L1189 作用域 | 函数外引用 `T` 必须报「未定义」 | ❌ 报 TY-101（错的理由） | sema |
| **G10** | §8.1 L1190 不得重名 | `f<T,T>` 必须报「类型参数重名」 | ❌ **解析层即失败**（B1） | xfront + sema |
| **G11** | §8.1 L1191 可用于局部/嵌套 | `T local = v; List<T> box = [v]` 通过 | ❌ 未实现 | sema + codegen |
| **G12** | §8.1 L1198 不能作为值 | 泛型函数当值用必须拒绝 | ⚠️ **不可表达**（无函数值语法，闭包未落地）→ 记未测 | — |
| **G13** | §8.3 L1225 不能是 void | `f<void>()` 必须报 void 非法 | ❌ 报 TY-101 | sema |
| **G14** | §8.3 L1226 `is T`/`as T` | `v is Int` 在 `T=Int` 实例按具体类型检查 | ❌ 未实现（`is` 本体已在，泛型结合未做） | sema |
| **G15** | §8.3 L1227 不能 `new T()` | 必须报「类型参数不可构造」 | ❌ 未实现（落到 TY-101/解析错） | sema |
| **G16** | §8.3 L1230 实例化点可见 | 跨文件 `import` 后实例化可行 | ❌ 未实现（`TestGEN01CrossFile` 红） | xfront+sema+codegen |
| **G17** | §8.4 L1234 约束 | `<T: Comparable>` 必须拒绝 | ✅ **拒绝成立**（级联 SYN-101）；诊断质量不合格 | xfront |
| **G18** | §8.2 L1211 重载解析 | 泛型与普通同名函数共存时普通调用仍可用 | ❌ TY-101 | sema + codegen |
| **G19** | §8.2 L1219 null 实参 | `id(null)` 不能推出 `T`，必须报错 | ❌ 报 TY-101（错的理由） | sema |

## 3. 判定汇总（先红实测，命令与原始输出见 `before/`）

```
go test ./internal/codegen/ -run 'TestGEN01' -count=1 -v -timeout 300s
FAIL  TestGEN01（23 FAIL / 1 SKIP / 1 PASS）+ TestGEN01CrossFile（FAIL）
```

- 原始输出：`before/go-test-gen01-before.log`
- CLI 双侧探针：`before/cli-probes.log`
- 既有套件在基线仍是绿的（证明缺口未被覆盖）：`before/baseline-existing-suite.log`

## 4. 阻断项（触发停止条件）

### B1　多类型参数泛型函数在解析层就失败（xfront，RD1 域）

`genericParamsFollows()`（`impl/internal/xfront/unit.go:352-368`）只接受 `Ident` 与 `Op && Text == ","`；
但逗号是独立 token 种类 `Comma`（`token.go:27`），不是 `Op`。

```x
static T pair<T, U>(T a, U b) { return a }   // → SYN-101 ×10，顶层声明位置报「遇到 `<`」
```

实测：`before/cli-probes.log` 的 `m1.x`/`m2.x`（带空格与不带空格都失败）。
→ **G4 / G10 在解析层不可达**，修 `genericParamsFollows` 才能测。

### B1b　嵌套类型实参的 `>>` 被当成运算符（xfront，RD1 域；T+1 新发现）

```x
static T grow<T>(T v) { return grow<List<T>>(v) }
// → SYN-102「比较运算不可链式使用」：`>>` 被词法/语法当成两级大于
```

影响：§8.3「无限展开诊断」(G7) 的**源码级**用例写不出来（只能用嵌套实参触发无限展开）；
任何 `f<List<Int>>(x)`、`Map<String, List<T>>` 的实参位置都不可解析。
修法：`tryTypeArgs`（`parser.go:392`）在类型实参上下文把 `>>` 拆成两个 `>`（或尖括号配平回溯）。估时 1h。

### B2　sema 未实现类型参数（RD2 域，GEN-01 的主体）

1. **类型参数没进作用域**：`AnalyzeWith` 只 `sc.define(p.Name)` 参数（`sema.go:74-77`），
   而 `nscope` 的注释明确写着「第 1 级：局部变量、参数、**类型参数**」（`sema.go:113`）。漏了一个 `fn.TypePars` 循环。
2. **`Call.TypeArgs` 全仓无人读**：`grep -rn TypeArgs internal/` 只命中 `xfront`（ast/parser/printer）——
   sema / codegen / interp **零命中**。
3. **重载解析形态错误**：`inferCall`（`ty.go:680-700`）按参数个数过滤后，对**每个候选**逐实参报 TY-101，
   取**第一个**候选的返回类型返回。§8.2 要求「过滤 → 适用性检查（含推断）→ 唯一/歧义/零候选」。
4. **无单态化基础设施**：无实例表、无实例名编码、无 `T→具体类型` 替换、无展开深度计数。

### B3　interp 未实现泛型（二司 RD1 域）

`grep -rn "TypePars\|TypeArgs" impl/internal/interp` = 0 命中。
M1 的「双路径逐字节一致」要求解释器也能跑泛型，否则 G1a/G2a/G6a/G6b/G8/G11/G18 永远无法双路径验收。

### B4　codegen 侧（本域）缺什么

- 无泛型相关代码（`grep` = 0）。
- 顶层同名函数**直接报错**：`codegen.go:163`「顶层函数 `x` 重载未支持」——需改成实例名 mangle + 调用点按实例名发射。
- `mangle` 已有可复用基础（`containers.go:23` 的类型→后缀），但函数实例命名需新增（`xn_<name>_<T编码>`）。
- **前置依赖**：codegen 只消费 sema 产物（`m4-codegen-design.md:28`）。sema 不给实例信息，codegen 无输入可消费。

## 5. 结论

**GEN-01 无法在 `impl/internal/codegen/**` 单域内完成。**
本域可承担的只有「单态化实例的 C 发射与命名」这一小块（约 G6a/G6b/G8/G11/G16 的发射半段），
其余 21 项的主体判据分布在 `xfront`（B1/B1b）、`sema`（B2）、`interp`（B3）。

按本卡「停止条件」第 1 条（需要跨域改文件）**停手**，升级 CEO2 协调。**未做任何生产代码改动，未改现有测试期望，未删测试。**

## 6. T+2h 更新：codegen 半边已交付（本域，绿）

按 v1.7.1「并行不串行」，在等跨域派单的同时把本域那一半做完了。

| 交付 | 位置 | 测试 |
|---|---|---|
| 单态化实例注册与展开（含递归轮次上限 `maxInstDepth=64`） | `impl/internal/codegen/generics.go` | `TestGEN01MonoExplicit` / `…OverloadCoexist` |
| 实例名内部编码（`xn_<fn>_<编码>`，Int→i、String→s、`List<X>`→`L<X>`、`Result<A,B>`→`R<A>_<B>`） | 同上 `typeArgCode` | `TestGEN01MonoTypeArgEncoding` |
| 类型参数深替换（`T` / `List<T>` / `Result<T,String>` / `T[]`） | 同上 `substitute` + `cType` 入口 | `TestGEN01MonoNested` |
| 7 处调用点改走实例名（`emitExprStmt`/`emitReturn`/`strExpr`/`resultExpr`/`intExpr`/`emitTryInto`/`classCallExpr`） | `codegen.go` | 同上 |
| 泛型与同名普通函数共存不再报「重载未支持」 | `codegen.go` 签名表 | `TestGEN01MonoOverloadCoexist` |
| 缺实参 / 数量不符 / 未解析类型参数 → 准确报错（不静默、不报「未知函数」） | `generics.go` | `TestGEN01MonoMissingTypeArgs` / `…WrongTypeArgCount` |
| 确定性：两次 `EmitC` 逐字节一致 | — | `TestGEN01MonoDeterministic` |
| **顺带修一个存量缺陷**：`Result` 成员的接收者未加 `xn_p_` 前缀（`intExpr`），参数是 `Result` 时生成 `r.ok` 而非 `xn_p_r.ok` → C 编译失败 | `codegen.go` `varRef` | `TestGEN01MonoNested` |

**验收状态**：`go test -run TestGEN01Mono` = **7/7 PASS**（`after-codegen-half.log`）；
既有 9 个测试 + 新增 7 个 = **16/16 PASS**（`regression.log`，退出码 0），**未改任何现有测试期望**。

**未交付（等跨域）**：
- 端到端 `TestGEN01` 仍 RED（24/26），因为 sema 在 codegen 之前就以 TY-101 拒绝程序；
- G7 的"无限展开"源码级用例（B1b：`>>` 解析）；
- G12（泛型函数作值，当前语言面不可表达）。

**接线成本**：sema 一旦按 §2 契约把推断结果写回 `Call.TypeArgs`，本域**零改动**即可覆盖
G1a/G2a/G6a/G6b/G8/G11/G18 的发射与运行（已用绕过 sema 的用例预先验证）。

---

## 7. main=2c00cf5 合入后复跑（T+?，merge `dab4d5c`）

| 指标 | 合入前 | 合入后 |
|---|---:|---:|
| PASS | 1 | **2**（+G5a：重载唯一候选，借 interp 重载选择 + sema 普通函数路径） |
| FAIL | 24 | **22** |
| SKIP / 不可测 | 1 | **2**（+G7） |

**剩余红项根因归口**：xfront B1 → G4/G10（2 项）；sema B2 → 其余 20 项；G7 → 本域嵌套容器限制（`List<List<Int>>` 不支持）。

**B3（interp）已解除**：主线新增 `selectFunc`，解释器泛型重载 11 子用例全过。
但 `cli.go` 的 `interpFile()` 先跑 `sema.Analyze`（`cli.go:243-250`），所以 `--interp` 仍被 TY-101 挡住——
**interp 泛型能力目前只在 Go 测试里可达**，等 sema 解锁即可，无需再派单。

**G7 追加阻断**：即便 xfront 修好 `>>`，`grow<List<T>>(v)` 仍会在 codegen 报
「容器元素类型暂支持 Int/Bool/String/类引用」——嵌套容器/嵌套 Result 不在当前类型面。
上限代码（`maxInstDepth=64`）保留为防御，端到端用例待嵌套容器切片。
