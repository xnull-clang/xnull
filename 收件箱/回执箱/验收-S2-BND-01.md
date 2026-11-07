# 验收：S2-BND-01（成员级可见性）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（编译期门；跨包成员可见性通过）
> **复验点**：main `f975810`（`4f3e7f9` 已并入）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/BND-01/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

BND-01 的台账判定面是**编译期可见性强制**：

| 验收点 | 结果 |
|---|---|
| 同包 `public` / `protected` / `private` 字段/方法规则 | **PASS**（sema） |
| 类外访问 private / protected | **PASS**：`TY-207` / `TY-209` + 位置 |
| 子类访问父类 private | **PASS**：`TY-209` |
| 子类经其他实例访问 protected | **PASS**：`TY-209` |
| 跨包 public 访问 | **PASS**（解释 + 编译） |
| 跨包 protected / private 访问 | **PASS**：`TY-209` + 位置 |
| 官方用例 `TestS2BND01VisibilityMatrix` | **PASS** |

**判定：PASS。** 可见性矩阵的编译期检查全部成立；编译路径正例输出正确。  
**边界（不属于 BND-01）**：解释路径的合法正例因 E3 “非限定字段名”缺口失败（`S2-E3-02`），见 §三；该缺口归 FIELD-01/E3，不作为 BND-01 的可见性失败。

---

## 二、逐项实测

### 2.1 正例

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `S2-BND01-A01` 同包 public/protected/private 合法访问 | `12 / 3 / 3` | **FAIL**：`未定义的名称：_a`（E3-02） | `12 / 3 / 3`，rc=0 | 编译/语义 PASS；解释边界 |
| `S2-BND01-A02` 子类内访问 protected | `14` | **FAIL**：`未定义的名称：x`（E3-02） | `14`，rc=0 | 编译/语义 PASS；解释边界 |
| `S2-BND01-X01` 跨包 public | `3` | `3`，rc=0 | `3`，rc=0 | PASS |

### 2.2 负例（`xnull check`）

| 用例 | 实测诊断 | 判定 |
|---|---|---|
| `R01` 类外访问 private 字段 | `r01_private_outside.x:6:12: error[TY-207]: 外部访问私有字段 \`x\`（规范名 \`_x\`）` | PASS |
| `R02` 类外访问 protected 方法 | `r02_protected_outside.x:6:12: error[TY-209]: 受保护方法 \`f\` 不可访问` | PASS |
| `R03` 子类访问父类 private | `r03_subclass_private.x:5:26: error[TY-209]: \`self.x\` 访问父类私有字段被拒绝` | PASS |
| `R04` 子类经其他实例访问 protected | `r04_other_instance_protected.x:5:34: error[TY-209]: 受保护字段 \`x\` 不可访问` | PASS |
| `X02` 跨包 protected 方法 | `main_prot.x:4:12: error[TY-209]: 受保护方法 \`prot\` 不可访问` | PASS |
| `X03` 跨包 private 方法 | `main_priv.x:4:12: error[TY-209]: 私有方法 \`priv\` 不可访问` | PASS |

全部负例 rc=1，诊断带 `file:line:col`；无“只报未实现”。

---

## 三、边界：解释路径非限定字段（E3-02）

`a01_member_visibility.x` 的 `private Int a` 在类内按规范名裸写 `_a`，`a02` 的 `protected Int f() { return x }` 裸写 `x`。解释器当前不回退到 `self` 字段，报“未定义的名称”，与 `S2审计-E3.md` 的 `S2-E3-02` 一致。

- 影响：BND-01 正例无法在解释路径完整跑通；编译路径与 sema 均通过。
- 归属：FIELD-01 / E3（§5.8 非限定字段解析），不是可见性规则错误。
- 建议：E3 修复 `IdentExpr` 的 `self` 字段回退后，重跑 `a01`/`a02` 双路径。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND01VisibilityMatrix' -count=1` | PASS |
| `go vet ./...` | exit 0 |
| `go test ./...` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 13（golden 18）。`f975810` 把 golden 改为 18，但当前 `status.tsv` 仅 13 PASS；与本锚点无关，但阻断 GATE-01。 |

---

## 五、证据

- `evidence/S2-QA/BND-01/S2-BND01-A01/`、`A02/`、`R01/`–`R04/`、`X01/`–`X03/`
- `evidence/S2-QA/matrix.tsv`
- `evidence/S2-QA/sema-s2bnd.log`、`full-test.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §7.3、§7.4、§16 BND-01
