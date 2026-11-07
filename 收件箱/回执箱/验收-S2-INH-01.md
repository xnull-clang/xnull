# 验收：S2-INH-01（继承与接口）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `05e680c`（`05e680c2367058c617127eb9ce95dc081acf430e`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s2-base`，sha256 `5721de8325a4c4804180b9ae5ef26095ad2d7273d18602e9700e076f16dadbf3`
> **证据**：`evidence/S2-QA/INH-01-05e680c/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §2.1/§2.5/§4.1/§5.1、§18 INH-01；`internal/sema/typedecl_test.go:TestInheritanceRules`
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 单父类 + 多协议实现/运行期 | **PASS**：双路径 `1/3/1/3/1` |
| 多级继承字段/方法复用 | **PASS**：双路径 `1/2/3/6` |
| 非法 `:` 目标（struct 作父类） | **PASS**：`TY-202` @2:7 |
| `implements` 目标非 protocol | **PASS**：`TY-202` @2:7 |
| 类继承环 | **PASS**：`TY-202` @1:7 |
| 协议继承环 | **PASS**：`TY-202` @1:10 |
| 子类同签名方法 | **PASS**：`TY-203` @2:24 |
| 跨包继承 | **PASS**：双路径 `2` |
| 官方 `TestInheritanceRules` | **PASS** |

**判定：PASS。** A01/A02 双路径一致；全部非法构造带 `TY-202`/`TY-203` 与 `file:line:col`；跨包继承正例通过。

---

## 二、逐项实测

### 2.1 正例

| 用例 | 期望 | interp | compiled | 判定 |
|---|---|---|---|---|
| `a01_single_parent_multi_proto` 单父类 + `implements P, Q` | `1\n3\n1\n3\n1` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `a02_multilevel` A→B→C 字段/方法复用 | `1\n2\n3\n6` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `X01-cross-package` 跨包继承 | `2` | 一致，rc=0 | 一致，rc=0 | **PASS** |

### 2.2 负例（三路径一致）

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `r01_colon_struct` `class C : S`（S struct） | 码+位置 | `2:7 error[TY-202]` | **PASS** |
| `r01_implements_class` `implements C`（C class） | 码+位置 | `2:7 error[TY-202]` | **PASS** |
| `r02_class_cycle` A↔B | 码+位置 | `1:7 error[TY-202]：继承环` | **PASS** |
| `r02_proto_cycle` P↔Q | 码+位置 | `1:10 error[TY-202]：协议继承环` | **PASS** |
| `r02_same_sig` 子类同签名 | 码+位置 | `2:24 error[TY-203]` | **PASS** |

---

## 三、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestInheritanceRules' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 1200s` | **未完成**：`internal/codegen` 在机器争用下触发 20m 超时；与本锚点无关，GATE-01 需固定低负载/拆分重跑 |

---

## 四、证据

- `evidence/S2-QA/INH-01-05e680c/matrix.tsv`
- `evidence/S2-QA/INH-01-05e680c/S2-INH-a01_single_parent_multi_proto/{check,interp,compiled}/` … `a02_multilevel/`
- `evidence/S2-QA/INH-01-05e680c/S2-INH-r01_*`、`r02_*`、`X01-cross-package/`
- `evidence/S2-QA/INH-01-05e680c/gotest-sema/`、`regression-*/`
- 夹具：`wt/qa-1/difftest/s2/inh01/`（含 `xpkg/`）
