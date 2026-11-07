# 验收：S2-PCTOR-01（主构造器）

> **验收人**：QA1（独立质量线）
> **结论：PASS（15/15 双路径）**
> **复验点**：main `e2f943c`（`e2f943cf01319544c655469f9f9a81df690964d9`）
> **时间**：2026-11-07
> **二进制**：`/tmp/xnull-s2-e2f943c`，sha256 `baa515e915fb4d1cb653e1dbda5efbc15bab98cf74849b22df832b81a6e9c42d`
> **证据**：`evidence/S2-QA/PCTOR-01-e2f943c/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §6.1、§6.3、§6.5、§16 PCTOR-01
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`，并核对源码含 `TY-215/216/217`（`1b1d12e` sema）。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 主构造器头部参数绑定同名字段 | **PASS**：A01 双路径 `5` |
| 显式无参构造器体执行 | **PASS**：A02 双路径 `5` |
| 显式带参构造器 + `new D(5)` | **PASS**：A03 双路径 `5` |
| 字段初值 → 构造器体顺序 | **PASS**：A04 双路径 `1\n2` |
| `super(...)` 后按声明顺序执行 | **PASS**：A05 双路径 `5\n6` |
| 主构造器 + 普通构造器混用拒绝 | **PASS**：`TY-212` + 位置 |
| 主构造器参数非 `final` 拒绝 | **PASS**：`TY-212` + 位置 |
| 非 `class` 使用主构造器拒绝 | **PASS**：`TY-212` + 位置 |
| `super(...)` 非首位拒绝 | **PASS**：`TY-212` + 位置 |
| `final` 字段重复赋值拒绝 | **PASS**：`TY-212` + 位置 |

**判定：PASS。** 5 个正例解释/编译双路径共 10 次全部 rc=0 且输出一致；5 个负例全部 rc=1 且命中 `TY-212` + `file:line:col`。合计 15/15。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `a01_primary` 主构造器 `class Worker(final Int id)` + `new Worker(5)` | `5` | `5`，rc=0 | `5`，rc=0 | **PASS** |
| `a02_explicit_noarg` 显式无参构造器 `E() { self.v = 5 }` | `5` | `5`，rc=0 | `5`，rc=0 | **PASS** |
| `a03_explicit_param` 显式带参构造器 `D(Int x) { self.v = x }` | `5` | `5`，rc=0 | `5`，rc=0 | **PASS** |
| `a04_ctor_order` 字段初值 → 构造器体 | `1\n2` | `1\n2`，rc=0 | `1\n2`，rc=0 | **PASS** |
| `a05_super` `super(v)` + 字段绑定 | `5\n6` | `5\n6`，rc=0 | `5\n6`，rc=0 | **PASS** |

### 2.2 负例（`xnull check`）

| 用例 | 期望 | 实测诊断 | 判定 |
|---|---|---|---|
| `r01_mix` 主构造器 + 普通构造器混用 | rc≠0 + 码/位置 | `1:8 error[TY-212]：主构造器不能与普通构造器混用` + `2:6 TY-212` | **PASS** |
| `r02_nonfinal` 主构造器参数非 `final` | rc≠0 + 码/位置 | `1:9 error[TY-212]：参数 id 必须是 final` | **PASS** |
| `r03_nonclass` `struct` 使用主构造器 | rc≠0 + 码/位置 | `1:9 error[TY-212]：结构体不能使用主构造器` | **PASS** |
| `r04_super_not_first` `super(...)` 非首位 | rc≠0 + 码/位置 | `5:6 error[TY-212]：super(...) 必须是构造器首个动作` | **PASS** |
| `r05_final_twice` `final` 字段重复赋值 | rc≠0 + 码/位置 | `3:6 error[TY-212]：final 字段 x 必须恰好赋值一次（实际 2 次）` | **PASS** |

全部负例 rc=1，带 `TY-212` 与 `file:line:col`。

---

## 三、官方用例与回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2PCTORRules' -count=1` | PASS |
| `go test ./internal/codegen -run 'TestS2CtorBodies' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1` | exit 0（当前主工作树） |

---

## 四、证据

- `evidence/S2-QA/PCTOR-01-e2f943c/matrix.tsv`
- `evidence/S2-QA/PCTOR-01-e2f943c/S2-PCTOR-a01_primary/{interp,compiled}/` … `a05_super/{interp,compiled}/`
- `evidence/S2-QA/PCTOR-01-e2f943c/S2-PCTOR-r01_mix/check/` … `r05_final_twice/check/`
- `evidence/S2-QA/PCTOR-01-e2f943c/gotest-sema/`、`gotest-codegen/`
- `evidence/S2-QA/PCTOR-01-e2f943c/regression-targeted/`、`regression-vet/`、`regression-full/`
- 夹具：`difftest/s2/pctor01/`
