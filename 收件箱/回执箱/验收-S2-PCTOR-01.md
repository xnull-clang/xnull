# 验收：S2-PCTOR-01（主构造器）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（主构造器绑定通过；super 顺序、显式构造器、5 类拒绝项未闭合）
> **复验点**：main `f975810`（`81e146e` 已并入）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/PCTOR-01/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 主构造器头部参数绑定同名字段 | **PASS**（解释 + 编译） |
| `super(...)` 后按声明顺序执行 | **FAIL**（双路径均失败） |
| `final` 字段恰好赋值一次 | **FAIL**（负例被接受） |
| 与非主构造器混用被拒绝 | **FAIL**（`check` rc=0） |
| 非 `final` 主构造器参数被拒绝 | **FAIL**（`check` rc=0） |
| 非 `class` 使用主构造器被拒绝 | **FAIL**（`check` rc=0） |
| 显式构造器体（无参/带参） | **FAIL**（解释不执行；编译 `self` 未登记） |

**判定：FAIL。** 只有“主构造器参数绑定”一项完整通过；其余 6 项均有缺口。  
台账 PCTOR-01 不能从“部分”改为 PASS。

---

## 二、逐项实测

### 2.1 正例

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `A01` 主构造器 `class Worker(final Int id)` + `new Worker(5)` | `5` | `5`，rc=0 | `5`，rc=0 | **PASS** |
| `A02` 显式无参构造器 `E() { self.v = 5 }` | `5` | `1`，rc=0 | rc=1，`codegen：未登记标识符 self` | **FAIL** |
| `A03` 显式带参构造器 `D(Int x) { self.v = x }` + `new D(5)` | `5` | rc=1，`类 D 没有带参构造器（§6.1）` | rc=1，`codegen：未登记标识符 self` | **FAIL** |
| `A04` 字段初值 → 构造器体顺序 | `1\n2\n` | `1\n`（构造器体未执行） | `1\n2\n` | **FAIL（解释）** |
| `A05` `super(v)` + 字段绑定 | `5\n6\n` | rc=1，`类 D 没有带参构造器` | rc=1，`codegen：未登记标识符 self` | **FAIL** |

补充探针（隔离 `self` 与解释器构造器）：

```x
class E { Int v = 1; E() { v = 5 } }
```

| 路径 | 实测 |
|---|---|
| `run --interp` | `1`（构造器体未执行，E3-01） |
| `run`（编译） | `5`（非限定字段可写；`self` 绑定仍缺） |

### 2.2 负例（`xnull check`，期望 rc≠0）

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `R01` 主构造器 + 普通构造器混用 | 拒绝 + 码/位置 | **rc=0，无诊断** | **FAIL** |
| `R02` 主构造器参数非 `final` | 拒绝 + 码/位置 | **rc=0，无诊断** | **FAIL** |
| `R03` `struct` 使用主构造器 | 拒绝 + 码/位置 | **rc=0，无诊断** | **FAIL** |
| `R04` `super(...)` 非首个动作 | 拒绝 + 码/位置 | **rc=0，无诊断** | **FAIL** |
| `R05` `final` 字段初始化式 + 构造器重复赋值 | 拒绝 + 码/位置 | **rc=0，无诊断** | **FAIL** |

---

## 三、缺口与归属

| # | 缺口 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | 解释器不执行显式构造器体（无参/带参） | `A02` interp `1`（期望 5）；`A03`/`A05` fatal | E3（`S2-E3-01`） |
| P-02 | 编译路径构造器内 `self` 未登记 | `A02`/`A03`/`A05` compiled `未登记标识符 self` | E4 |
| P-03 | 主构造器 + 普通构造器混用未拒绝 | `R01` rc=0 | E2 sema |
| P-04 | 非 `final` 主构造器参数未拒绝 | `R02` rc=0 | E2 sema |
| P-05 | 非 `class` 使用主构造器未拒绝 | `R03` rc=0 | E2 sema |
| P-06 | `super(...)` 非首位未拒绝 | `R04` rc=0 | E2 sema |
| P-07 | `final` 字段重复赋值未拒绝 | `R05` rc=0 | E2 sema |
| P-08 | 解释器构造器体顺序（字段初值→体）未执行 | `A04` interp 仅 `1` | E3 |

已通过面：主构造器参数绑定（A01 双路径）；编译路径的非限定字段构造器体可写（补充探针 `5`）；E4 官方 `TestS2CtorBodies`（无 `self` 形态）通过。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/codegen -run 'TestS2CtorBodies|TestS2InheritanceLayout|TestS2ProtocolVtableLayout|TestS2DeinitBody' -count=1` | PASS（但未覆盖构造器内 `self`） |
| `go vet ./...` | exit 0 |
| `go test ./...` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 13（golden 18）。`f975810` 的 golden 更新与当前 `status.tsv` 不一致；与本锚点无关，但阻断 GATE-01。 |

---

## 五、放行条件

1. E2：R01–R05 五条负例全部带码+位置拒绝。
2. E3：显式无参/带参构造器体执行；`super(...)` 首位；字段初值→构造器体顺序。
3. E4：构造器内 `self` 绑定可用；`super(...)` 生成父构造调用。
4. 复跑 `A01`–`A05` 双路径一致，`R01`–`R05` 全部 rc≠0。

---

## 六、证据

- `evidence/S2-QA/PCTOR-01/A01/`–`A05/`、`R01/`–`R05/`
- `evidence/S2-QA/matrix.tsv`
- `evidence/S2-QA/codegen-s2.log`、`full-test.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §6.3、§6.5、§16 PCTOR-01
