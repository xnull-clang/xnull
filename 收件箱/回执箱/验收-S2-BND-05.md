# 验收：S2-BND-05（协议限制与实现检查）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `f975810`（`4f3e7f9` 已并入）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/BND-05/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 完整实现协议（同包/继承） | **PASS**（解释 + 编译） |
| 缺方法 / 签名或返回类型不符 | **PASS**：`TY-208` + 位置 |
| 父协议方法未实现 | **PASS**：`TY-208` + 位置 |
| private/protected 实现不满足协议 | **PASS**：`TY-208` + 位置 |
| `@Override` 未对应协议方法 | **PASS**：`TY-208` + 位置 |
| 多协议同名同参返回冲突 | **PASS**：`TY-208` + 位置 |
| 协议字段 / 方法体 / 泛型协议 | **PASS**：`SYN-101` + 位置 |
| 官方用例 `TestS2BND05ProtocolImplementation` | **PASS** |

**判定：PASS。** 协议只允许方法签名；实现检查覆盖父协议、签名、可见性、`@Override` 与多协议冲突；负例均带具体诊断和位置。

---

## 二、逐项实测

### 2.1 正例

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `S2-BND05-A01` 类 implements 协议（完整实现） | `true` | `true`，rc=0 | `true`，rc=0 | PASS |
| `S2-BND05-A02` 继承的公开方法满足协议 | `true` | `true`，rc=0 | `true`，rc=0 | PASS |

### 2.2 负例（`xnull check`）

| 用例 | 实测诊断 | 判定 |
|---|---|---|
| `R01` 缺方法 | `r01_missing.x:4:7: error[TY-208]: 类 \`C\` 未实现协议 \`Ready\` 的方法 \`ready\`` | PASS |
| `R02` 返回类型不符 | `r02_sig_mismatch.x:5:9: error[TY-208]: 协议方法 \`ready\` 返回类型不符：期望 Bool，实际 Int` | PASS |
| `R03` 父协议未实现 | `r03_parent_missing.x:7:7: error[TY-208]: 类 \`C\` 未实现协议 \`Base\` 的方法 \`base\`` | PASS |
| `R04` private 实现 | `r04_private_impl.x:5:18: error[TY-208]: 协议方法 \`ready\` 的实现必须公开` | PASS |
| `R05` `@Override` 无对应协议方法 | `r05_override_unknown.x:7:10: error[TY-208]: @Override 未对应任何协议方法` | PASS |
| `R06` 多协议返回冲突 | `r06_multi_conflict.x:7:7: error[TY-208]: 协议方法 \`f\` 的返回类型冲突（A vs B）` | PASS |
| `R07` 协议字段 | `r07_field.x:2:14: error[SYN-101]: 协议不能声明字段` | PASS |
| `R08` 协议方法体 | `r08_method_body.x:2:15: error[SYN-101]: 协议方法不能有方法体` | PASS |
| `R09` 泛型协议 | `r09_generic_protocol.x:1:11: error[SYN-101]: 期望协议体 \`{\`…` | PASS |

全部负例 rc=1，带 `file:line:col` 与诊断码。

---

## 三、边界

1. **协议变量动态派发**（协议类型接收者、vtable 槽）属 DISP-01 / BND-03；本锚点只验“协议形式限制 + 实现检查”，不把动态派发计入 BND-05。
2. 关联类型/约束在当前文法中无对应 production，解析即拒绝；未单列独立用例，归入 `R07`–`R09` 同族负例。
3. 编译路径的协议 vtable 目前只有布局槽；协议接收者调用未开放，见 E4 交接卡。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND05ProtocolImplementation' -count=1` | PASS |
| `go vet ./...` | exit 0 |
| `go test ./...` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`，台账 PASS 13（golden 18）。`f975810` 的 golden 更新与当前 `status.tsv` 不一致；与本锚点无关，但阻断 GATE-01。 |

---

## 五、证据

- `evidence/S2-QA/BND-05/S2-BND05-A01/`、`A02/`、`R01/`–`R09/`
- `evidence/S2-QA/matrix.tsv`
- `evidence/S2-QA/sema-s2bnd.log`、`full-test.log`、`vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §4.1–4.3、§16 BND-05
