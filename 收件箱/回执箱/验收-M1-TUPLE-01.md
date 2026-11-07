# 验收：M1-TUPLE-01（元组，S1 §2.11）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**
> **复验点**：main `d620ea5`（`46f36f2` 已并入）
> **时间**：2026-11-07

---

## 一、结论

| 验收面 | 判定 | 依据 |
|---|---|---|
| 四类类型位置：可空 / 返回 / 字段 / 容器元素 | **PASS** | sema + 解释路径全部通过；见 §二 |
| QA 独立用例（sema 9 + interp 8） | **PASS 17/17** | `qa-sema.log`、`qa-interp.log` |
| E2 TUPLE 用例（含新增类型位置） | **PASS** | `e2-sema-tuple.log`、`e2-interp-tuple.log` |
| 核心语义：身份/字面量/访问/推断/可赋值/相等/插值/拒绝项 | **PASS** | 17/17 + 13 项拒绝用例 |
| **§2.11 值语义：存入容器复制整个元组** | **FAIL** | 容器字面量 / `List.push` 存入后仍与原元组共享，修改原值会改变容器内元素 |
| 编译路径元组（codegen） | **FAIL（M4.1 边界）** | `codegen：类型 *xfront.TupleTypeRef 未支持` |

**锚点判定：FAIL。** 四类类型位置已修复，但 §2.11 明确要求“存入容器都复制整个元组；副本与原值独立”，当前容器写入路径未复制元组，属于值语义硬缺陷。

---

## 二、四类类型位置（PASS）

解释路径实测（`--interp`）：

| # | 位置 | 用例 | 实测 stdout | 判定 |
|---:|---|---|---|---|
| 1 | 可空元组 `(T1,T2)?` + `?.` | `t1_nullable` | `true` / `5` / `a`（null 分支得 null；非空取元素） | PASS |
| 2 | 顶层返回 `static (Int,Int) f()` | `t2_return` | `1` / `2` / `true`（可空返回 null） | PASS |
| 3 | 类字段 `(Int,Int) p` / 无初值零值 | `t3_field` | `1 2 0 0 true 1 4 1 5` | PASS |
| 4 | 容器元素 `List<(Int,Int)>`、`(Int,Int)[]`、`new (Int,Int)[n]` | `t4_container` | `7` / `7` / `10` / `0` / `0` | PASS |
| 5 | 顶层字段 `static (Int,Int) top` | `t5_topfield` | `11` / `12` / `true` | PASS |

补充（解释路径）：

| 用例 | 验收点 | 实测 | 判定 |
|---|---|---|---|
| `t6_generic_closure` | 元组作泛型实参、闭包捕获 | `1` / `a` / `2` | PASS |
| `t7_map_key` | 元组不能作 `Map` 键 | `TY-107`，rc=1 | PASS |
| `t12_set_key` | 元组不能作 `Set` 元素 | `Set 元素只能是 Int / String`，rc=1 | PASS |
| `t9_interp_eq` | 插值 `(1, x)`、`==`/`!=`、`===`/`!==` | `(1, x)` / true / true / false / false | PASS |
| `t10_nullable_value` | 可空元组 `?.` 值元素得 `T?` | `false` / `1` / `true` | PASS |
| `TestQATupleReferenceElementEquality` | 引用元素 `==` 按对象身份 | PASS | PASS |
| `TestQATupleStringIdentity` | String `===` 按对象身份 | PASS | PASS |

E2 新增 `TestTupleTypePositions`、`TestTupleTypePositionsRuntime`、`TestTupleClassFieldCopy` 均 PASS。

---

## 三、失败项：容器写入未复制元组（§2.11）

### 3.1 最小复现

```x
static Int main() {
    (Int, Int) t = (1, 2)
    List<(Int, Int)> l = [t]
    t.0 = 9
    print(l.get(0).0)   // 期望 1，实际 9
    return 0
}
```

| 路径 | 实测 |
|---|---|
| `run --interp` | `9`，rc=0 |

### 3.2 三条写入路径均失败

`t11_copy_paths.x`：

```x
(Int, Int) t = (1, 2)
List<(Int, Int)> l = [t]
t.0 = 9
print(l.get(0).0)       // 期望 1，实际 9

List<(Int, Int)> p = []
p.push(t)
t.0 = 8
print(p.get(0).0)       // 期望 9，实际 8

(Int, Int)[] a = [t]
t.0 = 7
print(a[0].0)           // 期望 8，实际 7
```

实测输出：`9 / 8 / 7`。  
对照：赋值 `c = t`、传参 `mutate(t)`、返回 `ret(t)` 三条路径均正确复制（实测 `7 / 7 / 7`），问题只在容器写入。

### 3.3 根因定位

- `impl/internal/interp/values.go:521-524` `List.push`：`append(recv.A, args[0])`，未调用 `cloneTupleValue`。
- `impl/internal/interp/values.go:536-543` `insert`/`set`：直接写入 `args[1]`，未复制。
- `impl/internal/interp/values.go:242-248` `evalArrayLit`：`elems[i] = in.eval(e, sc)`，未复制。
- `impl/internal/interp/values.go:250-258` `evalMapLit`：值未复制。

对照 `impl/internal/interp/interp.go:172,180,191` 的作用域绑定/赋值/传参已调用 `cloneTupleValue`，容器路径遗漏。

### 3.4 影响

违反 §2.11：“赋值、传参、返回、**存入容器**都复制整个元组；副本与原值独立。”  
当前行为等价于容器持有原元组的别名，后续 `t.N = ...` 会静默改写容器内元素。

---

## 四、编译路径（边界申报）

四类位置在编译路径均失败，错误一致：

```
xnull: 代码生成失败：codegen：类型 *xfront.TupleTypeRef 未支持（M4.1 范围）
```

涉及 `t1_nullable`、`t2_return`、`t3_field`、`t4_container`、`t5_topfield` 五例。  
该项属 `T-C1` / M4.1 codegen 范围，不是本轮四类类型位置修复的目标；若 Stage 1 门把“元组编译路径”纳入判据，则本锚点应继续 FAIL。

---

## 五、回归

| 项 | 命令 | 结果 |
|---|---|---|
| QA 独立用例 | `go test ./internal/{sema,interp} -run TestQATuple` | 17/17 PASS |
| E2 TUPLE 用例 | `go test ./internal/{sema,interp} -run '^TestTuple'` | 全 PASS |
| `go vet ./...` | — | exit 0 |
| `go test ./...` | — | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 计数 13（golden 10）。由 `status.tsv` 的 GEN/NEG/PKG 翻 PASS 引起，与本锚点无关，需另修 golden 或回退状态。 |

---

## 六、证据

- 复验目录：`evidence/M1-TUPLE-01-reverify-d620ea5/`
  - `qa-sema.log`、`qa-interp.log`：QA 独立 17 项
  - `e2-sema-tuple.log`、`e2-interp-tuple.log`：E2 TUPLE 用例
  - `out/matrix.tsv`：四类位置 + 补充探针双路径结果
  - `cases/t8_copy_container.x`、`cases/t11_copy_paths.x`、`cases/t13_container_get_copy.x`：值语义复现
  - `full-test.log`、`vet.log`
- 被测 sha：main `d620ea5`（`46f36f2` 已并入）
- 断言依据：`XNull解决方案-第1部分-基础语法-v3.3.0.md` §2.11、§13 TUPLE-01

---

## 七、放行条件

1. 容器写入复制：`List` 字面量、`List.push/insert/set`、数组字面量、`Map` 值写入均对元组调用 `cloneTupleValue`。
2. 复跑 `t11_copy_paths.x` 应为 `1 / 9 / 8 / 7 / 7 / 7`。
3. 四类类型位置与 17 项 QA 用例不得回退。
4. 编译路径是否纳入 TUPLE-01 由门禁口径裁定；若纳入，需另开 codegen 卡。

---

## 八、未测 / 边界

1. `struct` 字段的元组内存布局与“含引用元素元组字段被拒绝”（S2 / 第 2 部分 TUPLE-01）。
2. `Map` 值、嵌套容器、闭包捕获后写入容器的复制路径未逐一展开（同根因）。
3. `Byte=300` 字面量表示性挂 M2-C。
4. 变异 / 覆盖率不属本卡。

---

## 九、E2 补修：容器写入复制整个元组（已修复，待 QA 复验）

> **修复提交**：main `df81c75`（`pod/e2-sema` 同内容提交 `6d02489`）
> **范围**：仅 §三 的容器写入路径；四类类型位置与 17 项 QA 用例未改动。

红态（修复前 `TestTupleContainerCopy`）：

```text
out="9\n8\n5\n5\n6\n7\n8\n8\n3\n4\n42\n"
want="1\n2\n9\n9\n5\n6\n7\n7\n0\n8\n42\n"
```

修复点（`impl/internal/interp`）：

- `cloneTupleValue` 递归复制嵌套元组；引用元素仍只复制句柄。
- 统一在容器写入点复制：数组/Map 字面量、`List.push/insert/set`、`Map.put`、下标赋值、`new T[n]` 的元组零值槽位。

对应 §七 放行条件：

1. 容器写入复制：已覆盖 List 字面量、`push/insert/set`、数组字面量、Map 值写入（`Map.put` 与 Map 字面量）。**PASS**
2. `t11_copy_paths.x` 期望 `1 / 9 / 8 / 7 / 7 / 7`：由 `TestTupleContainerCopy` 覆盖同类路径并全绿。**PASS**
3. 四类类型位置与 QA 17 项不回退：`go test ./internal/sema ./internal/interp -count=1` 全绿。**PASS**
4. codegen 元组仍归 E4，不在本次范围。

```text
cd impl
go test ./internal/sema ./internal/interp -count=1
ok  xnull.dev/xnull/internal/sema
ok  xnull.dev/xnull/internal/interp
```

```
结论：解释器侧 §2.11 容器值语义已修复；最终 PASS 由 QA 复验签发。
被测：main df81c75
签名 / 时间：E2 / 2026-11-07
```

---

## 九、E2 补修：容器存入复制整个元组（§2.11 值语义）

> **范围**：QA 剩余 FAIL 项——元组存入容器（容器字面量 / `List.push` 等）必须复制整个元组。
> **域**：解释器（`impl/internal/interp`）；codegen 元组未支持仍归 E4。

修复前（红）：`TestTupleContainerCopy` 实测

```text
out="9\n8\n5\n5\n6\n7\n8\n8\n3\n4\n42\n"
want="1\n2\n9\n9\n5\n6\n7\n7\n0\n8\n42\n"
```

泄漏点：

- `(Int,Int)[] arr = [t]` 与 `List<(Int,Int)> xs = [t]` 保存的是 `t` 的同一元组指针；改 `t.0` 会改容器元素。
- `List.push/insert/set` 与 `Map.put` 直接存实参指针。
- `new (Int,Int)[n]` 所有槽位共用同一个零值元组。
- 嵌套元组只复制外层切片，内层仍共享。

修复点（`impl/internal/interp/values.go`）：

- `cloneTupleValue` 改为递归复制嵌套元组；引用元素仍只复制句柄（§2.11）。
- 容器存储点统一调用 `cloneTupleValue`：数组字面量、Map 字面量、`List.push/insert/set`、`Map.put`、下标赋值（`arr[i] = t` / `xs[i] = t`）、`new T[n]` 的零值槽位。

新增用例：`impl/internal/interp/tuple_test.go` 的 `TestTupleContainerCopy`，覆盖数组/List/Map 字面量与 `push/insert/set/put`、下标赋值、定长数组多槽位独立性、嵌套元组复制、引用元素句柄共享。

绿态：

```text
cd impl
go test ./internal/sema ./internal/interp -count=1
ok  xnull.dev/xnull/internal/sema
ok  xnull.dev/xnull/internal/interp
```

```
结论：解释器侧 §2.11 容器值语义 PASS
分支：pod/e2-sema
签名 / 时间：E2 / 2026-11-07
```
