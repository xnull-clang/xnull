# 验收回执：M1-TUPLE-01 类型位置补修（E2）

> **卡片：M1-TUPLE-01（元组，S1 §2.11）**　**范围：QA 判 FAIL 的四类类型位置**
> **分支：`pod/e2-sema`**　**日期：2026-11-07**
> **结论：四类全部修复，先红后绿；既有 TUPLE 期望未改。**

---

## 一、结论

QA 指出的四类类型位置失败项已修复，均为解析层未把元组类型放进对应类型位置所致；语义层与解释器补齐了容器元素类型与元组零值。

| # | 失败项 | 红态 | 绿态 |
|---|---|---|---|
| 1 | `(T1,T2)?` 声明 + `?.` null 分支 | 顶层/返回位置的 `(T1,T2)?` 报 `SYN-101 期望顶层声明` | 局部、类字段、顶层字段、函数返回均可声明；`p?.N` 在 `null` 时返回 `null` |
| 2 | `static (Int,Int) f()` 返回类型 | `SYN-101`：`parseTopType` 只认命名类型 | 顶层函数/字段接受元组及 `?` / `[]` 后缀 |
| 3 | 类字段元组 | `(Int,Int) p` 声明可解析，但无初值时字段为 `null`，`p.0` 运行时报错 | 有初值按值复制；无初值按元素取零值 `(0,0)` |
| 4 | `List<(Int,Int)>` 容器元素 | `parseNamedType` 把泛型实参里的 `(` 当作未闭合；`List<(Int,Int)>` 报 `SYN-101`/`SYN-102` | `List<(Int,Int)>` 的局部、类字段、参数、返回、`new (Int,Int)[n]` 全部可用；`.get(i).N` 元素类型正确 |

补充说明：item1 的 `(T1,T2)?` 局部声明由既有提交 `a8e5a88` 保留，未重复实现；item2/item3 的引用元素 `==` 与 String `===` 身份语义由既有 `f53f6fb` 覆盖，本次未改动。

---

## 二、红 → 绿

红态（修复前，新增用例）：

- sema：`TestTupleTypePositions` 解析失败，`SYN-101 期望顶层声明（函数、字段或类型），遇到 (`。
- interp：`TestTupleTypePositionsRuntime` 解析失败，同类 `SYN-101`；`List<(Int, Int)>` 报 `SYN-101 泛型实参列表未闭合` 与 `SYN-102 比较运算不可链式使用`。
- 类字段无初值：`(Int, Int) p` 运行时字段为 `null`，`.N 元素访问只用于元组：null`。

修复点：

- `impl/internal/xfront/parser.go`
  - `parseNamedType` 泛型实参不再把 `(` 判为未闭合（元组类型合法起点）。
  - 提取 `parseTupleType`，`parseTopType` / `parseNewType` 均支持元组类型。
  - `tryTupleTypeDecl` 支持 `[]` 后缀（`(Int,Int)[]`）。
- `impl/internal/xfront/unit.go`
  - 顶层返回类型/字段类型接受元组；保留 `const (T1,T2)` 语法拒绝。
- `impl/internal/sema/ty.go`
  - `methodRet` 的泛型实参按顶层逗号切分，`List<(Int,Int)>.get` 返回完整元组类型。
- `impl/internal/interp/interp.go`
  - `zeroValue` 对元组按元素递归取零值。

绿态命令与结果：

```text
cd impl
go test ./internal/xfront ./internal/sema ./internal/interp
ok  xnull.dev/xnull/internal/xfront
ok  xnull.dev/xnull/internal/sema
ok  xnull.dev/xnull/internal/interp
```

新增/更新的用例：

- `impl/internal/sema/tuple_test.go`：`TestTupleTypePositions`（四类类型位置静态检查）。
- `impl/internal/interp/tuple_test.go`：`TestTupleTypePositionsRuntime`、`TestTupleClassFieldCopy`（运行时与值语义）。

---

## 三、边界

1. 本次只修 QA 列出的四类类型位置；未改既有 TUPLE 用例期望。
2. 非主构造器的构造器体仍不由解释器执行（既有运行时边界，与元组无关）。
3. `Map<(Int,Int), V>` 仍按 §2.11 拒绝（元组不能作 Map 键）；本次只放开容器元素位置。

```
结论：四类类型位置 PASS
分支：pod/e2-sema
签名 / 时间：E2 / 2026-11-07
```
