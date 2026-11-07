# 验收：M1-TUPLE-01 元组（CEO3-QA1 独立）

> **验收人：CEO3-QA1-独立验收**　**时间：2026-11-07**　**结论：不通过（FAIL）**
> **被测：`wt/e2-sema` @ `53c32c7`**（代码提交 `ba4458a`；真实父提交 `81ec33d`；`53c32c7` 仅改证据/回执，`impl/` 与 `ba4458a` 无差异。E2 acceptance 写「基线 db74cc7」为过期记录，`ba4458a^` 实为 `81ec33d`。）
> **依据**：台账 TUPLE-01；S1 §2.11、§2.8；S2 §18（TUPLE-01）、§2（Object `==`/`===`）；验收标准 v1.0.0 §2/§3/§4.3/§6；董事会判决 v1.7.0 第 2.1 条。
> **纪律**：只读被测工作树；独立用例在仓外 clone 运行；未改 E2 的测试/实现/回执；未 commit、未派工。

---

## 一、结论

**FAIL。** 台账验收点除 **T3（元素访问，部分未覆盖）** 与 **T6a（相等，硬失败）** 外均通过；另有 2 项范围外缺口、1 项全局遗留风险、1 项跨域并行实现待核。

| # | 验收点 | 判定 | 一句话 |
|---|---|---|---|
| T1 | 类型身份 | **PASS** | 同长同元素逐一相同为同型；换序/换长/嵌套结构不同均拒绝 |
| T2 | 字面量 | **PASS**（附风险） | 元组字面量按目标元素类型适配；`Byte=300` 表示性未查（全局 M2-C） |
| T3 | 元素访问 | **FAIL** | `.0/.1/?.[非空]` 通过；可空元组 `(T1,T2)?` 无法声明，`?.` 的 null 分支不可达 |
| T4 | 推断 | **PASS** | `var t=(1,"a")` 得 `(Int,String)`，后续赋值按该类型检查 |
| T5 | 可赋值性 | **PASS** | 仅同型可赋；`(Int,String)→(Long,String)` 拒绝；元组参数类型合法 |
| T6a | 相等 | **FAIL** | 引用元素（类/数组）`==` 恒 false（`a==a`、同一句柄 `a==b` 均为 false）；String 元素 `===` 按内容而非身份 |
| T6b | 插值 | **PASS** | `$"a={a}"`、嵌套元组递归格式；数组元素插入被 `TY-106` 拒绝 |
| T7 | 越界选择器 | **PASS** | 读/写/`?.` 越界均 `TY-106` |
| T8 | 单元素/零元元组 | **PASS** | 均被拒绝（`(1,)` 报 SYN-101，`()` 报 SYN-104） |
| T9 | 解构 | **PASS** | 语法层拒绝（SYN-101） |
| T10 | 元组 `switch` | **PASS** | `TY-106` |
| T11 | 元组 `const` | **PASS** | 语法层拒绝（SYN-101） |
| A | 值语义（附加） | **PASS** | 赋值/传参/嵌套元素复制后与原值独立 |
| B | 元组参数（附加） | **PASS** | `static Int f((Int,String) p)` 可声明、可调用 |
| C | 返回/字段/容器/泛型/可空声明 | **未执行** | 语法层不支持；E2 已列为未测项，需跨域开卡 |
| W | 写入域（过程） | **待核** | `ba4458a` 改 `impl/internal/interp/{interp.go,values.go}`；按 v1.6.0 属 E3/CEO2-RD1 域，E3 分支另有 `461a47a` 平行实现，需 CEO1/CEO2 确认授权与合并口径 |

**一句话**：值元素路径已经全绿；**引用元素相等与 String 同一性仍是错的**，`?.` 的 null 分支也还不存在。按「范围内有一项不通过即整体不通过」，本卡不能签 PASS。

---

## 二、独立验收清单（自写：12 行，覆盖台账 13 个验收点 + 2 个附加项 + 1 个过程项）

> 清单在跑测前写定；判据来自台账与 S1 §2.11，不采用 E2 测试的期望值。
> 独立用例：`收件箱/CEO3/evidence-M1-TUPLE-01/qa-tests/`（sema 9 个、interp 8 个）。
> 注：T8 一行覆盖台账的「单元素」与「零元」两个验收点。

| # | 验什么 | 判据 | 独立用例 | 实测 | 判定 |
|---|---|---|---|---|---|
| T1 | 类型身份 | 长度+元素逐一相同；换序/换长/嵌套结构不同拒绝 | `TestQATupleTypeIdentity` | 全部符合；异型走 `TY-101` | PASS |
| T2 | 字面量 | 按目标元素类型适配；元数/元素不符拒绝 | `TestQATupleLiteral` | `(Long,Byte,Double,Bool,Char)` 适配通过；3 元→2 元、换序均 `TY-101` | PASS |
| T3 | 元素访问 | `.0/.1` 读写、`?.N`、无成员、越界拒绝 | `TestQATupleElementAccess`、`TestQATupleElementAccessRuntime` | 非空路径全过；`pair.length`/`p.2`/`p.2=`/`p?.2` 均 `TY-106`；**null 接收者无法构造** | **FAIL** |
| T4 | 推断 | `var` 得元组类型；后续赋值按该类型 | `TestQATupleInference`、`TestQATupleInferenceRuntime` | 通过；`a=(2,3)` 被 `TY-101` 拒绝 | PASS |
| T5 | 可赋值性 | 仅长度+元素逐一相同；无子类型；字面量按目标适配 | `TestQATupleAssignability` | 同型通过；`(Int,String)→(Long,String)`、3 元→2 元、元组参数实参不符均 `TY-101` | PASS |
| T6a | 相等 | `==/!=` 逐元素用元素相等语义；`===/!==` 逐元素同一性；两侧同型 | `TestQATupleEqualityStatic`、`TestQATupleValueEqualityAndInterp`、`TestQATupleReferenceElementEquality`、`TestQATupleArrayElementEquality`、`TestQATupleStringIdentity` | 值元素全过；**引用元素（类/数组）`==` 恒 false；String `===` 按内容** | **FAIL** |
| T6b | 插值 | `(a, b)` 格式；元素递归格式化；不可格式化元素拒绝 | `TestQATupleInterpolationStatic`、`TestQATupleValueEqualityAndInterp` | `a=(1, x)`、`n=((1, x), true)`；`(Int[],Int)` 插值 `TY-106` | PASS |
| T7 | 越界 | 读/写/`?.` 越界编译错误 | `TestQATupleRejections`、`TestQATupleOutOfRangeRuntimeFallback` | 编译期 `TY-106`；绕过 sema 时运行期 fatal 134，不静默 | PASS |
| T8 | 单/零元 | 必须拒绝 | `TestQATupleRejections` | `()`→SYN-104；`(1,)`→SYN-101 | PASS |
| T9 | 解构 | 必须拒绝 | `TestQATupleRejections` | SYN-101 | PASS |
| T10 | 元组 switch | 必须拒绝 | `TestQATupleRejections` | `TY-106` | PASS |
| T11 | 元组 const | 必须拒绝 | `TestQATupleRejections` | SYN-101 | PASS |
| A | 值语义 | 赋值/传参/嵌套复制独立 | `TestQATupleCopySemantics` | `a=1,b=9,param=99,a 仍 1,嵌套仍 3` | PASS |
| B | 元组参数 | 参数类型合法 | `TestQATupleParenAndParam` | 通过 | PASS |

---

## 三、失败详情（可复现）

### F1（硬失败）引用元素 `==` 恒 false

```x
class Box { Int v = 0; }
Box o = new Box()
Box p = new Box()
(Box, Int) a = (o, 1)
(Box, Int) b = (o, 1)
(Box, Int) c = (p, 1)
print(o == o)   // 实测 false，期望 true
print(a == a)   // 实测 false，期望 true
print(a == b)   // 实测 false，期望 true（同一对象句柄）
print(a == c)   // 实测 false，期望 false

// 不依赖 S2 的 S1 用例：数组也是引用类型
Int[] arr = [1, 2]
(Int[], Int) p = (arr, 1)
(Int[], Int) q = (arr, 1)
print(p == p)   // 实测 false，期望 true
print(p == q)   // 实测 false，期望 true（同一数组句柄）
```

- 期望依据：S1 §2.8（引用类型 `==` 默认按对象身份）、§2.11（元组 `==` 逐元素使用元素相等语义）；S2 §2「Object 的 `==` / `===` 都是引用身份比较」。
- 根因：`impl/internal/interp/interp.go:820` `valuesEqual` 只覆盖 Bool/Int/Float/Char/Str/Tuple，`vObj`/`vArr`/`vMap`/`vClosure` 落到函数末尾 `return false`。元组相等直接委托该函数，因此任何含引用元素的元组 `==` 都恒 false。
- 影响：T6a 不通过；同样影响 `(数组,Int)`、`(Map,Int)`、`(闭包,Int)` 等元组。数组用例不依赖 S2，证明这是 S1 范围内的缺陷。

### F2（硬失败）String 元素 `===` 按内容而非对象身份

```x
String s1 = "a" + "b"
String s2 = "a" + "b"
print(s1 === s2)              // 实测 true，期望 false
(String, Int) p = (s1, 1)
(String, Int) q = (s2, 1)
print(p === q)                // 实测 true，期望 false
print(p !== q)                // 实测 false，期望 true
```

- 期望依据：S1 §2.8 表：`===` 对值是按值、对 `String` 是按对象身份、对引用是按对象身份；§2.11 元组 `===` 逐元素比较同一性。
- 根因：`impl/internal/interp/interp.go:853` `valuesIdentical` 的 `case vBool, vInt, vFloat, vChar, vStr: return valuesEqual(...)`，把 String 当值类型；元组 `===` 因此把不同字符串对象判为同一。
- 影响：T6a 不通过；元组 `===/!==` 对 String 元素语义错误。

### F3（部分未覆盖）可空元组的 `?.` null 分支不可达

```x
(Int, String)? p = null
```

- 实测：`SYN-101`（`parser.go:843` `tryTupleTypeDecl` 只接受 `)` 后紧跟声明名，不消费 `?`）；当前也无法通过返回值/字段/泛型构造可空元组。
- 期望依据：S1 §2.11「对可空元组 `T?` 使用 `?.`：`pair?.0` 在 `pair` 为 `null` 时返回 `null`，元素是值类型时结果为 `T?`」。
- 影响：T3 只能证明非空分支；null 传播是规范明写行为，不能算已实现。属 `xfront` 域缺口，需 RD1 开卡或明确拆分本锚点。

### F4（风险，不单独作为判据）字面量表示性未检查

- `(Byte, Int) b = (300, 1)`、`(-129, 1)`、`(UByte,Int)=(256,1)` 均被接受（探针输出见 `out/probes.out`）。
- 根因：`impl/internal/sema/ty.go:153` `assignable` 只按整数族接受字面量，注释写明「表示性检查在常量求值切片」。
- 定性：这是全局 M2-C 遗留，不是元组独有；本轮记为挂账，不并入 F1/F2 的硬失败，但 T2 不能声称「字面量完全闭合」。

### F5（过程/待核）跨域并行实现，候选未合并 E3 支援

- `wt/e3-interp` 有 `461a47a feat(interp): tuple equality and identity semantics (M1-TUPLE-01)`，同样改 `impl/internal/interp/interp.go` 并新增 4 个测试；`wt/e2-sema` 候选**未包含**该提交。
- `ba4458a` 自身也改 `impl/internal/interp/{interp.go,values.go}`。按 v1.6.0 §2.2，`interp/**` 属二司（E3/CEO2-RD1），E2 域为 `sema/**`；M1 看板也写「interp 相等需 E3 支援（支援卡 C）」。
- 需 CEO1/CEO2 确认两件事：① 本卡是否把 interp 支援转授权给 E2；② 最终交付是否应取 E2+E3 的合并 sha。**本次按被测 sha `53c32c7` 判 FAIL**；若最终交付是合并结果，必须用合并 sha 重验。
- 备注：E3 `461a47a` 也不能关闭 F1/F2——其 `valuesEqual` 仍未处理 `vObj`，`identical` 对 `vStr` 仍回落内容相等。

---

## 四、命令与结果

| 检查 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 静态 | `cd impl && go vet ./...` | exit 0 | `out/evidence.txt` |
| 候选全量（排除 QA 独立用例） | `go test ./internal/sema ./internal/interp -count=1 -skip 'TestQATuple'` | 两包 ok，0 SKIP，exit 0 | `out/full-pkgs.out` |
| 候选自有 TUPLE 用例 | `go test ./internal/sema ./internal/interp -run '^TestTuple' -v` | 18/18 PASS（sema 13、interp 5） | `out/e2-tests.out` |
| 独立验收用例 | `go test ./internal/sema ./internal/interp -run 'TestQATuple' -v` | sema 9/9 PASS；interp 5/8 PASS、**3 FAIL**；exit 1 | `out/qa-tests.out` |
| 9 示例双路径 | 编译/解释各跑一次，比较 stdout 与退出码 | **9/9 MATCH** | `out/dualpath.txt` |
| 红态独立复跑 | 真实父提交 `81ec33d` + 最终测试（另在 `db74cc7` 复跑同结果） | **9 个失败**（sema 8、interp 1），与 E2 `before/` 一致 | `out/red-replay-parent.out`、`out/red-replay.out` |
| 证据七件套 | `git cat-file -e 53c32c7:evidence/M1-TUPLE-01/<f>` | 7/7 present | `out/evidence.txt` |
| 产物哈希 | `shasum -a 256 -c evidence/M1-TUPLE-01/artifact.sha256` | 5/5 OK，exit 0 | `out/evidence.txt` |

**红 → 绿完整性**：`ba4458a^` 实为 `81ec33d`（不是 E2 acceptance 所写 `db74cc7`）。在 `81ec33d` 用最终测试独立复跑，得到 9 个失败，与 `evidence/M1-TUPLE-01/before/` 的失败集合一致；`555ac6b..53c32c7` 测试文件无改动；`ba4458a..53c32c7` 的 `impl/` 无差异。E2 的「先红后绿」成立，但**基线记录需改正为 `81ec33d`**。

---

## 五、证据七件套核对

| # | 文件 | 状态 | 说明 |
|---|---|---|---|
| 1 | `command.txt` | 有 | 采集命令完整 |
| 2 | `stdout.txt` | 有 | 绿态输出；非全部原始输出，逐项原始输出在 `after/`、`dualpath/`、`cli/` |
| 3 | `stderr.txt` | 有 | 含 go test/vet 与 CLI 负例说明 |
| 4 | `exit_code.txt` | 有 | `0` |
| 5 | `sha.txt` | 有（格式缺陷） | `ba4458a8e843` 为 12 位缩写，指向代码提交而非最终 `53c32c7`；HEAD 仅改证据/回执，`impl/` 无差异，故不单独打回，但 B2/B4 记格式整改 |
| 6 | `artifact.sha256` | 有 | 5 个代码/测试文件哈希，`-c` 全 OK；当前 HEAD 复算通过 |
| 7 | `acceptance.md` | 有（无独立签名） | 执行侧自检；本文件为独立验收签名，E2 可在通过后回填「独立验收」小节 |

**结论**：七件套齐全，产物可复算；sha 缩写与 acceptance 无签名是格式项，本次不作为主判据，但修复合入后必须补齐。

---

## 六、未测项与范围声明

1. **可空元组**：声明语法不支持，`?.` null 分支未测（F3，跨 `xfront`）。
2. **元组作返回值/顶层字段/容器元素/泛型实参**：语法层均不支持（探针：`tuple-return`、`tuple-field`、`tuple-array`、`tuple-list` 全为解析错误）；E2 回执已列为未测项。
3. **codegen 元组路径**：`internal/codegen` 无元组实现；本次 9 示例双路径只是回归，不证明元组在编译路径正确。
4. **嵌套链式访问**：`n.0.0` 会被词法解析成浮点 `.0.0` 而失败；`(n.0).0` 可用。规范未禁止链式，建议后续修词法或明确要求括号；本轮记格式/可用性风险，不作为主判据。
5. **性能/覆盖率/变异**：本卡未要求，未测。
6. **L2 阶段门**：本文件只是 L1，不构成 Stage 1 门结论。

---

## 七、打回与复验

**打回动作**：

1. 不签 `evidence/M1-TUPLE-01/acceptance.md`；本验收单结论为「不通过」。
2. 缺项表：F1（引用元素 `==`）、F2（String `===`）、F3（可空元组 null 分支）、F4（字面量表示性，挂 M2-C）、F5（跨域并行实现，待授权/合并确认）。
3. 交 CEO3 登记缺陷，归口司修：F1/F2 在 `interp` 域；F3 需 `xfront` 域开卡；F4 归 M2-C；F5 由 CEO1/CEO2 定授权与合并口径。
4. 不代补证据、不改 E2 文件、不 commit。

**复验要求**：

- 必须用新 sha；不得复用 `ba4458a/53c32c7` 的证据与结论。若最终交付为 E2+E3 合并结果，必须以合并 sha 重验，并说明 `pod/e3-interp` `461a47a` 是否并入。
- F1/F2 修复后，最小新增用例必须覆盖：`(Box,Int)` 的 `a==a`、同一对象 `a==b`、不同对象 `a==c`；`String` 拼接后的 `s1===s2` 与元组 `p===q`。
- 复验同时重跑：sema/interp 全量、独立用例、9 示例双路径、artifact `-c`。
- 同一卡连续 2 次不通过 → 升级 CEO1/CEO3，不得由原验收人私下放行。

---

## 八、签名与自查

```
任务 ID：M1-TUPLE-01
主责 / 验收人：E2 / CEO3-QA1（独立）
被测 sha：53c32c7（代码 ba4458a，真实父提交 81ec33d；E2 acceptance 记 db74cc7 为过期记录）
验收命令：见 evidence-M1-TUPLE-01/commands.txt
实际结果：sema 9/9、interp 5/8；3 项失败；9 示例双路径 9/9
证据目录：收件箱/CEO3/evidence-M1-TUPLE-01/
未测项：见 §六
结论：不通过
签名 / 时间：CEO3-QA1 / 2026-11-07
```

自查：只读 `wt/e2-sema`；独立用例与运行均在仓外 clone（`/private/var/.../tuple-qa`）；验收后 `wt/e2-sema` 仅剩 E2 自己的在途项，无本会话改动；唯一写入 `收件箱/CEO3/验收-M1-TUPLE-01.md` 与 `收件箱/CEO3/evidence-M1-TUPLE-01/**`。
