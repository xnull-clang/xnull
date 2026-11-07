# 验收：S2-STRUCT-01（结构体值类型）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（黄金矩阵 A01/A02/R01/R02/D01 全过；A02 已由 `438c28b` 修复）
> **复验点**：main `fa4fbf9`（INTEG-S2-BATCH3；含 `438c28b` STRUCT-01 codegen、`1b1d12e` BND-07/08 sema）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-fa4fbf9`，sha256 `237b1a56b8ca3f84ec12f64c2d79305cbf5a03d77370c71cb08a1d6b76d35585`
> **证据**：`evidence/S2-QA/STRUCT-01-fa4fbf9/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §3.1–§3.7、§16 STRUCT-01；`收件箱/门/S2验收计划-QA.md` §2.3 STRUCT-01

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 只接受值字段：标量 / 简单枚举 / 嵌套 struct / 值元组 / `T?` | **PASS** |
| 拒绝引用字段（`String` / `class`） | **PASS**：`TY-204` + 位置 |
| 拒绝可空引用字段（`String?`） | **PASS**：`TY-204` + 位置 |
| 拒绝容器 / 数组 / `Result` 字段 | **PASS**：`TY-204` + 位置 |
| 拒绝 `deinit` | **PASS**：`TY-204` + 位置 |
| 拒绝闭包捕获 `self` | **PASS**：`TY-204`（sema 官方用例） |
| 拒绝非值泛型实参 | **PASS**：`TY-204` + 位置 |
| 拒绝递归值包含 | **PASS**：`TY-204` + 位置 |
| 复制独立（赋值 / 传参 / 返回 / 嵌套字段） | **PASS**（A01 + `TestS2StructValueCopy`、`TestS2BND11StructSretCopy`） |
| `S2-STRUCT-A02` 嵌套值 struct / 可空值字段 | **PASS**：解释/编译双路径 `1\n5`，rc=0 |
| `S2-STRUCT-D01` 双路径一致 | **PASS**：A01/A02 输出与 rc 全一致 |

**判定：PASS。** 前一轮 A02 的 `可空表达式 *xfront.Member 未支持` 已由 `438c28b` 关闭；本轮 A01/A02 双路径、全部负例与 D01 均通过。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `S2-STRUCT-A01` 赋值复制独立 | `1\n10\n3\n12` | `1\n10\n3\n12`，rc=0 | `1\n10\n3\n12`，rc=0 | **PASS** |
| `S2-STRUCT-A02` 嵌套值 struct + `Int?` 可空值字段 | `1\n5` | `1\n5`，rc=0 | `1\n5`，rc=0 | **PASS** |

A02 夹具包含：

```text
struct Outer {
    Inner inner = new Inner();   // 嵌套 struct 字段初始化式
    Int? opt = null;             // 可空值字段
}
```

编译路径现已输出 `1` / `5`，与解释路径一致。

### 2.2 负例（`xnull check`）

| 用例 | 夹具 | 实测诊断 | 判定 |
|---|---|---|---|
| `R01-array` 数组字段 | `Int[] xs` | `2:11 error[TY-204]` | **PASS** |
| `R01-class` class 字段 | `C c` | `3:7 error[TY-204]` | **PASS** |
| `R01-string` String 字段 | `String name` | `2:12 error[TY-204]` | **PASS** |
| `R02-deinit` | `void deinit()` | `3:10 error[TY-204] 结构体不能声明 deinit（§3.1）` | **PASS** |
| `R02-generic` 非值泛型实参 | `Box<String> b` | `5:17 error[TY-204]` | **PASS** |
| `R02-recursive` 递归值包含 | `S s` | `2:7 error[TY-204]` | **PASS** |
| 补充 `String?` | `String? s` | `1:20 error[TY-204]` | **PASS** |
| 补充 `List<Int>` | `List<Int> xs` | `1:22 error[TY-204]` | **PASS** |
| 补充 `Result<Int,String>` | `Result<Int,String> r` | `1:32 error[TY-204]` | **PASS** |

全部 rc=1，带诊断码与 `file:line:col`，无“只报未实现”。

### 2.3 官方用例

| 用例 | 结果 |
|---|---|
| `internal/sema/typedecl_test.go:TestStructValueRules` | PASS |
| `internal/sema/s2_bnd04_test.go:TestS2BND04StructValueRules` | PASS |
| `internal/sema/policy_test.go:TestPolicyStructSelfCapture` | PASS |
| `internal/codegen/s2_object_test.go:TestS2StructValueCopy` | PASS |
| `internal/codegen/s2_object_test.go:TestS2BND11StructSretCopy` | PASS |
| `internal/codegen/s2_object_test.go:TestS2STRUCT01NestedNullable` | PASS |
| `internal/codegen/s2_object_test.go:TestS2STRUCT01NullableInit` | PASS |

---

## 三、边界（不影响本轮判定）

额外探针 `struct_enum_tuple_ok.x`：`Color c = Color.Red; (Int,Int) t = (1,2); Int? q = null`。

- 解释路径：`Red\nnull`，rc=0。
- 编译路径：rc=1，`codegen：类字段 S.c 的初始化式访问了成员 Red（不能引用 self 或其他实例字段）`。
- 同一问题在 `class C { Color c = Color.Red; }` 复现，属**字段初始化式成员表达式**的通用 codegen 缺口，不是 STRUCT-01 本轮黄金矩阵（A01/A02/R01/R02/D01）范围。
- 对照：`struct S { Color c; }` + `s.c = Color.Red` 双路径 `Red`，rc=0。

建议：单开 codegen 字段初值卡（枚举项/元组/成员表达式）；GATE-01 前关闭。本轮 STRUCT-01 判定不因此改变。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestStructValueRules\|TestS2BND04StructValueRules\|TestPolicyStructSelfCapture' -count=1` | PASS |
| `go test ./internal/codegen -run 'TestS2STRUCT01\|TestS2StructValueCopy\|TestS2BND11StructSretCopy' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | **1 红**：`internal/devtool TestBuildLedgerRepoGoldenScale`（台账 PASS 13，golden 18）；与本锚点无关，阻断 GATE-01 |

---

## 五、证据

- `evidence/S2-QA/STRUCT-01-fa4fbf9/matrix.tsv`
- `evidence/S2-QA/STRUCT-01-fa4fbf9/S2-STRUCT-A01/{interp,compiled}/`
- `evidence/S2-QA/STRUCT-01-fa4fbf9/S2-STRUCT-A02/{interp,compiled}/`
- `evidence/S2-QA/STRUCT-01-fa4fbf9/S2-STRUCT-R01-{array,class,string}/check/`
- `evidence/S2-QA/STRUCT-01-fa4fbf9/S2-STRUCT-R02-{deinit,generic,recursive}/check/`
- `evidence/S2-QA/STRUCT-01-fa4fbf9/probe-*/`
- `evidence/S2-QA/STRUCT-01-fa4fbf9/gotest-sema/`、`gotest-codegen/`、`regression-*/`
- 夹具：`difftest/s2/struct01/`
