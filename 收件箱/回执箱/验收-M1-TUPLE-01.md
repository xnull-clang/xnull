# 验收：M1-TUPLE-01（元组，S1 §2.11）

>
> 本文件同步自主工作树 `wt/qa-1`（分支 `pod/qa-1`）；执行器与原始日志见
> `wt/qa-1/evidence/QA1-verify-2026-11-07/`。


> **验收人**：QA1（独立质量线）
> **结论：FAIL（收窄至 §2.11 类型位置/可空元组；核心 17/17 PASS，F1/F2 已转绿）**
> **复验点**：main `7262ff0`（含 TUPLE F1/F2 修复 `f53f6fb`）
> **用例**：`evidence/M1-TUPLE-01-qa/qa-tests/`（QA1 自写 17 项）+ §2.11 定点探针 7 项
> **时间**：2026-11-07

---

## 一、结论

| 验收面 | 判定 | 依据 |
|---|---|---|
| QA 独立用例（sema 9 + interp 8） | **PASS 17/17** | 原 5/8 → 8/8；F1 引用元素 `==`、F2 String `===` 已修 |
| §2.11 元素访问（含可空元组 `?.`） | **FAIL** | `(T1,T2)?` 无法声明，`?.` null 分支不可达 |
| §2.11 类型位置（返回值/字段/容器元素） | **FAIL** | 语法层拒绝：`static (Int,Int) f()`、类字段、`List<(Int,Int)>` |
| §2.11 泛型实参与 tuple codegen | **FAIL（编译路径）** | 解释路径通过；编译路径 `codegen：类型 *xfront.TupleTypeRef 未支持` |
| 字面量表示性（`Byte=300`） | 挂 M2-C | 非 TUPLE 阻断项，沿用原验收口径 |

**整体 FAIL 的原因不是 F1/F2 回归**，而是原验收单已登记的 F3（可空元组）与“元组作类型位置”语法缺口仍在。
核心清单（类型身份、字面量、元素访问、推断、可赋值性、相等、插值、越界/单零元/解构/switch/const 拒绝）17/17 全绿。

---

## 二、QA 独立用例（17/17 PASS）

### 2.1 sema（9/9）

| # | 用例 | 验收点 | 结果 |
|---:|---|---|---|
| 1 | TestQATupleTypeIdentity | 同长同元素同型；换序/换长/嵌套不同均拒绝 | PASS |
| 2 | TestQATupleLiteral | 字面量按目标元组元素类型适配 | PASS |
| 3 | TestQATupleElementAccess | `.0/.1` 通过；越界拒绝；`?.` 非空分支 | PASS |
| 4 | TestQATupleInference | `var t=(1,"a")` 推断 `(Int,String)` | PASS |
| 5 | TestQATupleAssignability | 仅同型可赋；元组参数合法 | PASS |
| 6 | TestQATupleEqualityStatic | `==`/`===` 两侧须同型 | PASS |
| 7 | TestQATupleInterpolationStatic | 可格式化递归；不可格式化 `TY-106` | PASS |
| 8 | TestQATupleRejections | 单元素/零元/解构/switch/const/`.length` 拒绝 | PASS |
| 9 | TestQATupleParenAndParam | `(T)` 是括号而非元组；元组参数 | PASS |

### 2.2 interp（8/8）

| # | 用例 | 验收点 | 结果 |
|---:|---|---|---|
| 10 | TestQATupleValueEqualityAndInterp | 值元素 `==`/`===` 与插值 | PASS |
| 11 | **TestQATupleReferenceElementEquality（原 F1）** | 引用元素 `==` 按对象身份 | **PASS** |
| 12 | TestQATupleCopySemantics | 赋值/传参复制，副本独立 | PASS |
| 13 | TestQATupleInferenceRuntime | 推断后的运行期访问 | PASS |
| 14 | TestQATupleElementAccessRuntime | `.0/.1` 运行期取值 | PASS |
| 15 | TestQATupleOutOfRangeRuntimeFallback | 越界在 sema 拦截，运行期不可达 | PASS |
| 16 | **TestQATupleStringIdentity（原 F2）** | String `===` 按对象身份（非内容） | **PASS** |
| 17 | **TestQATupleArrayElementEquality（原 F2 同类）** | 数组元素 `==` 按句柄身份 | **PASS** |

---

## 三、§2.11 定点探针（7 项）

| # | 探针 | 条款 | 期望 | 解释路径 | 编译路径 | 判定 |
|---:|---|---|---|---|---|---|
| P1 | `(Int,Int)? p = null` | §2.11 成员访问 | 可声明 | `SYN-101` 遇 `(` | `SYN-101` | **FAIL** |
| P2 | `p?.0` | §2.11 成员访问 | null 时得 `null` | `SYN-101` | `SYN-101` | **FAIL** |
| P3 | `static (Int,Int) f()` | §2.11 形式与身份 | 元组可作返回值 | `SYN-101` | `SYN-101` | **FAIL** |
| P4 | `class C { (Int,Int) p = ... }` | §2.11 形式与身份 | 元组可作字段 | `SYN-101` | `SYN-101` | **FAIL** |
| P5 | `List<(Int,Int)>` | §2.11 形式与身份 | 元组可作容器元素 | `SYN-102` 链式比较 | `SYN-102` | **FAIL** |
| P6 | `id<(Int,Int)>(t)` | §2.11 形式与身份 | 元组可作泛型实参 | rc=0，输出 `1` | `TupleTypeRef 未支持` | **FAIL（编译）** |
| P7 | `(Int,Int) u = t` | §2.11 值语义 | 同型赋值 | rc=0，输出 `2` | `TupleTypeRef 未支持` | **FAIL（编译）** |

原始输出：`evidence/QA1-verify-2026-11-07/tuple-probes.log`。

---

## 四、缺陷与归属

| # | 缺陷 | 归属 | 阻断 |
|---|---|---|---|
| T-F3 | 可空元组 `(T1,T2)?` 与 `?.` 不可声明/不可达 | xfront | 是 |
| T-P1 | 元组作返回值/类字段/容器元素的类型语法未支持 | xfront | 是 |
| T-C1 | 元组 codegen 未实现（`TupleTypeRef`），赋值/泛型实参编译路径失败 | codegen（M4.1） | 是（编译路径） |
| T-F4 | `Byte=300` 字面量表示性未验 | 全局 M2-C | 否（挂账） |

---

## 五、已跑命令与结果

```bash
cd /Users/vjs/Desktop/XNull-Lang
SHA=$(git rev-parse main)   # 7262ff0
git archive "$SHA" | tar -x -C $T/src
cp evidence/M1-TUPLE-01-qa/qa-tests/qa-sema_tuple_test.go   $T/src/impl/internal/sema/qa_tuple_accept_test.go
cp evidence/M1-TUPLE-01-qa/qa-tests/qa-interp_tuple_test.go $T/src/impl/internal/interp/qa_tuple_accept_test.go
cd $T/src/impl
go test ./internal/sema   -run 'TestQATuple' -count=1 -v   # PASS 9/9
go test ./internal/interp -run 'TestQATuple' -count=1 -v   # PASS 8/8
```

原样输出：

```
ok  xnull.dev/xnull/internal/sema     1.164s
ok  xnull.dev/xnull/internal/interp   0.826s
```

探针命令见 §三；原始输出 `tuple-probes.log`。

---

## 六、证据路径

- 独立用例：`evidence/M1-TUPLE-01-qa/qa-tests/qa-sema_tuple_test.go`、`qa-interp_tuple_test.go`
- 本轮日志：`evidence/QA1-verify-2026-11-07/tuple-sema.log`、`tuple-interp.log`、`tuple-probes.log`
- 被测 sha：`7262ff0`（见 `evidence/QA1-verify-2026-11-07/sha.txt` 同批）
- 历史验收：`收件箱/回执箱/CEO3/验收-M1-TUPLE-01.md`（旧 FAIL，F1/F2/F3）

---

## 七、未跑 / 边界

1. 元组作 `Map`/`Set` 键、`switch` 值、`const` 的**拒绝**已由 sema 用例覆盖；**允许**场景不适用。
2. 元组 `is`/`as` 同型恒等：解释路径通过，编译路径同 T-C1 失败，未单列。
3. 元组字段内存布局（第 2 部分）不在 S1 本卡。
4. 变异/覆盖率/性能未跑。
