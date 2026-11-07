# 验收：S2-STRUCT-01（结构体值类型）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（sema 面完整；编译路径的嵌套值初值与可空值成员未实现，A02/D01 不通过）
> **复验点**：main `47fedb8`（`47fedb8ad1659925af04a677a9e82b861c2dffcd`）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/STRUCT-01/`、`evidence/S2-QA/probes/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 只接受值字段：标量 / 简单枚举 / 嵌套 struct / 值元组 / `T?` | **PASS**（sema + A01 双路径） |
| 拒绝引用字段（`String` / `class`） | **PASS**：`TY-204` + 位置 |
| 拒绝可空引用字段、容器、数组、`Result` | **PASS**：`TY-204` + 位置 |
| 拒绝 `deinit` | **PASS**：`TY-204` + 位置 |
| 拒绝闭包捕获 `self` | **PASS**：`TY-204`（sema） |
| 拒绝非值泛型实参 | **PASS**：`TY-204` + 位置 |
| 拒绝递归值包含 | **PASS**：`TY-204` + 位置 |
| 复制独立（赋值 / 传参 / 返回 / 嵌套字段） | **PASS**（A01 + codegen 官方用例） |
| `S2-STRUCT-A02` 嵌套值 struct / 可空值字段 | **FAIL**（解释路径通过，编译路径 rc=1） |
| `S2-STRUCT-D01` A01/A02 双路径一致 | **FAIL**（A02 不一致） |

**判定：FAIL。** 结构体的**类型检查面已闭合**，负例全部带 `TY-204` 与 `file:line:col`；失败集中在 **E4 codegen**：嵌套 struct 字段初始化式与 `T?` 值成员读取尚未发射。台账 STRUCT-01 保持「部分」，不得改 PASS。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `S2-STRUCT-A01` 赋值复制独立 | `1\n10\n3\n12\n` | `1\n10\n3\n12\n`，rc=0 | `1\n10\n3\n12\n`，rc=0 | **PASS** |
| `S2-STRUCT-A02` 嵌套值 struct + `Int?` 可空值字段 | `1\n5\n` | `1\n5\n`，rc=0 | rc=1，`codegen：可空表达式 *xfront.Member 未支持（M6-B0-05 范围）` | **FAIL** |

A02 失败位置：

```text
difftest/s2/struct01/a02_nested_nullable.x:5:11
struct Outer {
    Inner inner = new Inner();   // 嵌套 struct 字段初始化式
    Int? opt = null;             // 可空值字段
}
```

隔离探针（`evidence/S2-QA/probes/`）确认是两个独立的 codegen 缺口，而非夹具问题：

| 探针 | 解释路径 | 编译路径 | 归属 |
|---|---|---|---|
| `struct_nullable_simple.x`：`struct S { Int? v = 1; }` + `print(s.v)` | `1`，rc=0 | rc=1，`可空表达式 *xfront.Member 未支持（M6-B0-05 范围）` | E4 / M6-B0-05 |
| `struct_nested_only.x`：`struct Outer { Inner inner = new Inner(); }` | `1`，rc=0 | rc=1，`类字段 Outer.inner 的初值类型 xn_Struct_Inner 暂未支持（B0-04）` | E4 / B0-04 |

两者都是 §3.2/§3.5 明确允许的合法结构体构造；编译路径拒绝即锚点失败。

### 2.2 负例（`xnull check`）

| 用例 | 夹具 | 实测诊断 | 判定 |
|---|---|---|---|
| `R01a` 数组字段 | `Int[] xs` | `r01_array.x:2:11: error[TY-204]: 结构体 \`S\` 的字段 \`xs\` 不是值字段类型（§3.2…）` | **PASS** |
| `R01b` class 字段 | `C c` | `r01_class.x:3:7: error[TY-204]: 结构体 \`S\` 的字段 \`c\` 不是值字段类型（§3.2…）` | **PASS** |
| `R01c` String 字段 | `String name` | `r01_string.x:2:12: error[TY-204]: 结构体 \`S\` 的字段 \`name\` 不是值字段类型（§3.2…）` | **PASS** |
| `R02a` `deinit` | `void deinit()` | `r02_deinit.x:3:10: error[TY-204]: 结构体不能声明 deinit（§3.1）` | **PASS** |
| `R02b` 非值泛型实参 | `Box<String> b` | `r02_generic.x:5:17: error[TY-204]: 结构体 \`S\` 的字段 \`b\` 不是值字段类型（§3.2…）` | **PASS** |
| `R02c` 递归值包含 | `S s` | `r02_recursive.x:2:7: error[TY-204]: 结构体 \`S\` 的字段 \`s\` 不是值字段类型（§3.2…）` | **PASS** |

全部 rc=1，带诊断码与 `file:line:col`，无「只报未实现」。

### 2.3 sema / codegen 官方用例

| 用例 | 覆盖 | 结果 |
|---|---|---|
| `internal/sema/typedecl_test.go:TestStructValueRules` | `String`、`String?`、`List`、`Int[]`、`Result`、`deinit`、直接/可空递归、继承拒绝 | **PASS** |
| `internal/sema/s2_bnd04_test.go:TestS2BND04StructValueRules` | 泛型 struct 声明合法；`Pair<Int,Int>`、值元组实参合法；`Pair<String,Int>` 字段/局部拒绝；`List<T>` 字段拒绝 | **PASS** |
| `internal/sema/policy_test.go:TestPolicyStructSelfCapture` | 结构体方法闭包捕获 `self` → `TY-204` | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2StructValueCopy` | 赋值 / 传参 / 嵌套字段复制独立 | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2BND11StructSretCopy` | 返回 / 传参 sret 复制独立 | **PASS** |

sema 规则位置：`impl/internal/sema/typedecl.go:474`（`checkValueField`）、`:370`（`checkStruct`）、`:145`（结构体闭包捕获 `self`）。

---

## 三、失败项与归属

| # | 失败项 | 证据 | 归属 |
|---:|---|---|---|
| S-01 | 嵌套 struct 字段初始化式 `Inner inner = new Inner()` 编译路径不支持 | `probes/struct_nested_only`：compiled rc=1，`B0-04` | E4 |
| S-02 | `T?` 值字段成员读取 `s.v` 编译路径不支持 | `STRUCT-01/A02`、`probes/struct_nullable_simple`：compiled rc=1，`M6-B0-05` | E4 |
| S-03 | `S2-STRUCT-A02` 双路径不一致，`D01` 失败 | `STRUCT-01/A02/interp.exit=0`、`compiled.exit=1` | E4 |

sema 无缺口：值字段矩阵、泛型实参、`self` 捕获、递归包含均有 `TY-204` 证据。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestStructValueRules\|TestS2BND04StructValueRules\|TestPolicyStructSelfCapture' -count=1` | **PASS** |
| `go test ./internal/codegen -run 'TestS2StructValueCopy\|TestS2BND11StructSretCopy' -count=1` | **PASS** |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 1200s` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 13（golden 18）。与本锚点无关，但阻断 GATE-01。 |

---

## 五、放行条件

1. E4：发射嵌套 struct 字段初始化式（B0-04）。
2. E4：发射 `T?` 值字段读取/赋值（M6-B0-05）。
3. 复跑 `S2-STRUCT-A02` 双路径 `1\n5\n`、rc=0；`D01` 0 mismatch。
4. 其余 A/R 用例保持当前结果。

---

## 六、证据

- `evidence/S2-QA/STRUCT-01/A01/`、`A02/`、`R01a/`–`R02c/`（每条含 `cmd.txt`、`interp.*`、`compiled.*`、`check.*`、`sha.txt`）
- `evidence/S2-QA/probes/struct_nested_only/`、`struct_nullable_simple/`
- `evidence/S2-QA/qa-a-sema.log`、`qa-a-codegen.log`、`qa-a-fulltest.log`、`qa-a-vet.log`
- `evidence/S2-QA/matrix.tsv`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §3.1–§3.6、§16 STRUCT-01
