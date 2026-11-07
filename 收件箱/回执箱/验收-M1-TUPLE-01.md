# 验收：M1-TUPLE-01（元组，S1 §2.11）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（四类类型位置、值语义、元组 codegen 主面均通过）
> **复验点**：main `91c89c0`（`df81c75`、`91c89c0` 已并入）
> **时间**：2026-11-07

---

## 一、结论

| 验收面 | 判定 | 依据 |
|---|---|---|
| 四类类型位置（可空/返回/字段/容器元素） | **PASS**（解释/语义面） | `t1`–`t5`、`c1`–`c4` |
| §2.11 值语义：赋值/传参/返回/**存入容器**复制 | **PASS**（双路径） | `t11_copy_paths`、`t13`、`TestTupleContainerCopy` |
| 元组 codegen 主面：字面量/访问/赋值/相等/插值/返回/字段/顶层字段/List/参数 | **PASS**（双路径） | `c1`、`c2`、`c4`、`c6`、`c7`、`c8`、`TestTupleCodegenRuns` |
| QA 独立用例（sema 9 + interp 8） | **PASS 17/17** | `sema-tuple.log`、`interp-tuple.log` |
| E2 TUPLE 用例（sema/interp/codegen） | **PASS** | 三包 `TestTuple*` 全绿 |
| 核心拒绝项（越界/单零元/解构/switch/const/Map-Set 键） | **PASS** | QA 用例 + `t7`/`t12` |

**判定：PASS。** 上一轮两项硬失败均已闭环：
1. `df81c75` 修复容器写入复制——`List` 字面量、`List.push`、数组字面量的元组写入均按值复制；
2. `91c89c0` 元组发射面——非空元组的字面量、元素访问、元素赋值、相等、插值、返回、字段、顶层字段、`List` 元素与参数传递在编译路径与解释路径逐字节一致。

---

## 二、值语义（PASS，双路径）

`t11_copy_paths.x` 期望/实测：

| 路径 | 实测 stdout | 判定 |
|---|---|---|
| `run --interp` | `1 / 9 / 8 / 7 / 7 / 7` | PASS |
| `run`（编译） | `1 / 9 / 8 / 7 / 7 / 7` | PASS |

覆盖：

- `List<(Int,Int)> l = [t]; t.0 = 9` → `l.get(0).0 == 1`（容器字面量复制）
- `p.push(t); t.0 = 8` → `p.get(0).0 == 9`（push 复制）
- `(Int,Int)[] a = [t]; t.0 = 7` → `a[0].0 == 8`（数组字面量复制）
- 赋值、传参、返回路径独立（`7 / 7 / 7`）

`t13_container_get_copy.x`：从容器取出后再修改副本，容器内值不变（`1 / 4`），双路径一致。  
`TestTupleContainerCopy`、`TestTupleClassFieldCopy` 均 PASS。

---

## 三、四类类型位置 + codegen

### 3.1 解释/语义面（PASS）

| # | 位置 | 用例 | 实测 |
|---:|---|---|---|
| 1 | 可空 `(T1,T2)?` + `?.` | `t1_nullable` | `true / 5 / a` |
| 2 | 顶层返回 `static (Int,Int) f()` | `t2_return` | `1 / 2 / true` |
| 3 | 类字段 `(Int,Int) p`、无初值零值 | `t3_field` | `1 2 0 0 true 1 4 1 5` |
| 4 | 容器 `List<(Int,Int)>`、`(Int,Int)[]`、`new (Int,Int)[n]` | `t4_container` | `7 / 7 / 10 / 0 / 0` |
| 5 | 顶层字段 `static (Int,Int) top` | `t5_topfield` | `11 / 12 / true` |

### 3.2 编译路径（PASS，非空元组主面）

| 用例 | 覆盖 | interp | compiled | 判定 |
|---|---|---|---|---|
| `c1_return` | 函数返回元组 + 元素访问 | `1 / 2` | `1 / 2` | PASS |
| `c2_field` | 类字段、零值、`List<(Int,Int)>`、字段复制/赋值 | `1 2 0 0 1 4 1 5` | 同左 | PASS |
| `c4_topfield` | 顶层元组字段 | `11 / 12` | `11 / 12` | PASS |
| `c6_copy_param` | 赋值/传参复制 | `1 / 1` | `1 / 1` | PASS |
| `c7_eq_value` | `==`/`!=`/`===`/`!==`、插值 | `true false false true true (1, 2)` | 同左 | PASS |
| `c8_element_assign` | `t.0 = 9` | `9 / 2` | `9 / 2` | PASS |
| `t9_interp_eq` | 插值 `(1, x)` | `(1, x)` | `(1, x)` | PASS |
| `TestTupleCodegenRuns` | codegen 发射 + 运行 | — | PASS | PASS |

`go test ./internal/codegen -run '^TestTuple'` → PASS。

---

## 四、拒绝项与核心清单

| 项 | 实测 | 判定 |
|---|---|---|
| 越界选择器 | `TY-106`（sema） | PASS |
| 单元素/零元元组 | `SYN` 拒绝 | PASS |
| 解构、元组 `switch`、元组 `const` | 拒绝 | PASS |
| 元组作 `Map` 键 | `TY-107`，双路径 rc=1 | PASS |
| 元组作 `Set` 元素 | `Set 元素只能是 Int / String`，解释路径 rc=1 | PASS |
| 类型身份/字面量/推断/可赋值性/相等/插值 | QA 17/17 | PASS |
| 引用元素 `==`、String `===` 身份 | QA 用例 PASS | PASS |

---

## 五、边界（不阻断本锚点，均已定位到其他范围）

1. **可空元组 codegen**：`(T1,T2)?` 编译路径报 `可空类型 xn_tup_… 未支持（M6-B0-05 范围）`；解释/语义面 PASS。归 M6-B0-05 可空类型发射。
2. **元组数组 / `new (Int,Int)[n]`**：编译路径报 `容器表达式 *xfront.NewArray 未支持（M4.4a 范围）`；解释路径 PASS。归 M4.4a 数组 codegen。
3. **元组作泛型实参**：编译路径报 `类型实参 *xfront.TupleTypeRef 未支持（§8.3 单态化）`；解释路径 PASS。归 §8.3 泛型实例化。
4. **同一 String 字面量的 `===` 口径**：`(1,"x") === (1,"x")` 解释路径为 `true`（字面量共享），编译路径为 `false`（两处常量对象）；用 `"x"+"y"` 构造不同对象时双路径均为 `false`（`c7_eq_value`）。规范未规定字面量必须同对象，建议另立 String 身份口径，不属元组表示缺陷。
5. `Byte=300` 字面量表示性挂 M2-C；`struct` 字段元组内存布局属 S2。
6. 变异 / 覆盖率不属本卡。

---

## 六、回归

| 项 | 结果 |
|---|---|
| QA 独立用例 | sema 9/9、interp 8/8 PASS |
| E2 TUPLE 用例 | sema/interp/codegen 全 PASS |
| 9 示例双路径 | 9/9 MATCH |
| `go vet ./...` | exit 0 |
| `go test ./...` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 计数 13（golden 10）。由 `status.tsv` 的 GEN/NEG/PKG 翻 PASS 引起，与本锚点无关。 |

---

## 七、证据

- 复验目录：`evidence/M1-TUPLE-01-reverify-91c89c0/`
  - `sema-tuple.log`、`interp-tuple.log`、`codegen-tuple.log`
  - `out/matrix.tsv`：四类位置 + 值语义 + codegen 双路径结果
  - `cases/t11_copy_paths.x`、`cases/c1_return.x` … `cases/c8_element_assign.x`
  - `dualpath-9.txt`、`full-test.log`、`vet.log`
  - `sha.txt`、`command.txt`
- 前一轮（`d620ea5`，FAIL）：`evidence/M1-TUPLE-01-reverify-d620ea5/`
- 断言依据：`XNull解决方案-第1部分-基础语法-v3.3.0.md` §2.11、§13 TUPLE-01
