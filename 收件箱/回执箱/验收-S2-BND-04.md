# 验收：S2-BND-04（结构体值字段）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（值字段矩阵、泛型值实参、`self` 捕获、复制独立全部成立）
> **复验点**：main `47fedb8`（`47fedb8ad1659925af04a677a9e82b861c2dffcd`）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/BND-04/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 只接受 3.2 值字段（标量 / 简单枚举 / 嵌套 struct / 值元组 / `T?`） | **PASS**（sema） |
| 拒绝引用字段（`String` / `class`） | **PASS**：`TY-204` + 位置 |
| 拒绝可空引用字段 | **PASS**：`TY-204` + 位置 |
| 拒绝容器 / 数组 / `Result` 字段 | **PASS**：`TY-204` + 位置 |
| 拒绝 `deinit` | **PASS**：`TY-204` + 位置 |
| 拒绝闭包捕获 `self` | **PASS**：`TY-204` + 位置 |
| 拒绝非值泛型字段实参 | **PASS**：`TY-204` + 位置 |
| 拒绝递归值包含 | **PASS**：`TY-204` + 位置 |
| 赋值 / 传参 / 返回值复制独立 | **PASS**：双路径 `1/10/9/1/30/4` |
| `S2-BND04-D01` 双路径一致 | **PASS**：A01 0 mismatch |

**判定：PASS。** BND-04 的编译期值字段门与副本独立性均成立；台账 BND-04 可从「未实现」登记为 PASS。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `S2-BND04-A01` 赋值 / 传参 / 返回复制独立 | `1\n10\n9\n1\n30\n4\n` | 同左，rc=0 | 同左，rc=0 | **PASS** |

语义：`Point b = a; b.x = 10` 后 `a.x=1`；`copyOf(a)` 内改参不回溯；`make(3)` 返回后改 `c.x=30`，`c.y` 仍为 4。

### 2.2 负例（`xnull check`）

| 用例 | 夹具 | 实测诊断 | 判定 |
|---|---|---|---|
| `R01a` String 字段 | `String name` | `r01_string.x:2:12: error[TY-204]: ... 不是值字段类型（§3.2…）` | **PASS** |
| `R01b` class 字段 | `C c` | `r01_class.x:3:7: error[TY-204]: ... 不是值字段类型（§3.2…）` | **PASS** |
| `R01c` 数组字段 | `Int[] xs` | `r01_array.x:2:11: error[TY-204]: ... 不是值字段类型（§3.2…）` | **PASS** |
| `R01d` List 字段 | `List<Int> xs` | `r01_list.x:1:22: error[TY-204]: ... 不是值字段类型（§3.2…）` | **PASS** |
| `R01e` Result 字段 | `Result<Int,String> r` | `r01_result.x:1:32: error[TY-204]: ... 不是值字段类型（§3.2…）` | **PASS** |
| `R01f` 可空引用字段 | `C? c` | `r01_nullable_ref.x:2:15: error[TY-204]: ... 不是值字段类型（§3.2…）` | **PASS** |
| `R02a` `deinit` | `void deinit()` | `r02_deinit.x:3:10: error[TY-204]: 结构体不能声明 deinit（§3.1）` | **PASS** |
| `R02b` 捕获 `self` | 闭包内 `self.v` | `r02_self.x:1:8: error[TY-204]: 结构体方法不得在闭包中捕获 self（§3.1）` | **PASS** |
| `R02c` 非值泛型实参 | `Pair<String,Int>` 字段 | `r02_generic_ref.x:2:35: error[TY-204]: ... 不是值字段类型（§3.2…）` | **PASS** |
| `R02d` 递归值包含 | `S s` | `r02_recursive.x:2:7: error[TY-204]: ... 不是值字段类型（§3.2…）` | **PASS** |

全部 check/interp/compiled 三路径 rc=1，诊断带 `file:line:col` 与 `TY-204`。

### 2.3 官方用例

| 用例 | 覆盖 | 结果 |
|---|---|---|
| `internal/sema/s2_bnd04_test.go:TestS2BND04StructValueRules` | 泛型 struct 声明；`Pair<Int,Int>`、`Pair<(Int,Int),Bool>` 合法；`Pair<String,Int>` 字段/局部拒绝；`List<T>` 字段拒绝 | **PASS** |
| `internal/sema/typedecl_test.go:TestStructValueRules` | `String`/`String?`/`List`/`Int[]`/`Result`/`deinit`/递归（直接、可空） | **PASS** |
| `internal/sema/policy_test.go:TestPolicyStructSelfCapture` | 闭包捕获 `self` → `TY-204` | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2StructValueCopy` | 赋值 / 传参 / 嵌套字段复制独立 | **PASS** |

规则位置：`impl/internal/sema/typedecl.go:474`（`checkValueField`）、`:370`（`checkStruct`）、`:145`（捕获 `self`）。

---

## 三、边界（不属于 BND-04 门）

1. **嵌套 struct 字段初始化式** `Inner inner = new Inner()` 编译路径暂不支持（`codegen ... B0-04`），归 STRUCT-01 / E4；BND-04 的 A01 用无初始化式嵌套字段，已验证复制独立。
2. **`final` 字段写入**未在 sema 强制（`final Int x=1; c.x=2` check rc=0），归 PCTOR-01 / E2；不影响 BND-04 的值字段判定。
3. 跨包 struct 未单列（BND-04 黄金用例不含 X 类），跨包属于 PKG-01/BND-01 范畴。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND04StructValueRules\|TestStructValueRules\|TestPolicyStructSelfCapture' -count=1` | **PASS** |
| `go test ./internal/codegen -run 'TestS2StructValueCopy' -count=1` | **PASS** |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 1200s` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`（台账 PASS 13 / golden 18），与本锚点无关但阻断 GATE-01。 |

---

## 五、证据

- `evidence/S2-QA/BND-04/A01/`、`R01a/`–`R02d/`（每条含 `cmd.txt`、`check.*`、`interp.*`、`compiled.*`、`sha.txt`）
- `evidence/S2-QA/qa-c-sema.log`、`qa-c-codegen.log`、`qa-c-fulltest.log`、`qa-c-vet.log`
- `evidence/S2-QA/matrix.tsv`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §3.1–§3.3、§16 BND-04
