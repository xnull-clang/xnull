# 验收回执：M1-TUPLE-01（CEO3-QA1 独立）

> **卡片：M1-TUPLE-01（元组，S1 §2.11）**　**主责：E2**　**验收人：CEO3-QA1**
> **被测：`wt/e2-sema` @ `53c32c7`**（代码提交 `ba4458a`，真实父提交 `81ec33d`）
> **时间：2026-11-07**　**结论：FAIL（不通过）**
> 完整验收单：`收件箱/CEO3/验收-M1-TUPLE-01.md`　证据：`收件箱/CEO3/evidence-M1-TUPLE-01/`

---

## 一、结论

**FAIL。** 值元素路径全绿；**引用元素 `==` 与 String 元素 `===` 两项硬失败**，可空元组的 `?.` null 分支未实现/不可达。

| 验收点 | 判定 | 实测摘要 |
|---|---|---|
| 类型身份 | PASS | 同长同元素为同型；换序/换长/嵌套结构不同均拒绝 |
| 字面量 | PASS（附风险） | 目标类型适配通过；`Byte=300` 表示性未查（全局 M2-C 挂账） |
| 元素访问 | **FAIL** | `.0/.1/?.[非空]` 通过；`(T1,T2)?` 无法声明，`?.` null 分支不可达 |
| 推断 | PASS | `var t=(1,"a")` 得 `(Int,String)` |
| 可赋值性 | PASS | 仅同型可赋；元组参数合法 |
| 相等 | **FAIL** | 引用元素（类/数组）`==` 恒 false；String `===` 按内容而非身份 |
| 插值 | PASS | `(1, x)`、嵌套递归；不可格式化元素 `TY-106` |
| 越界 | PASS | 读/写/`?.` 越界均 `TY-106` |
| 单/零元、解构、switch、const | PASS | 均被拒绝 |

**三个失败用例（期望 → 实测）**：

1. `TestQATupleReferenceElementEquality`：`(Box,Int)` 的 `a==a`、同一对象 `a==b`，期望 `true`，实测 `false`。
2. `TestQATupleArrayElementEquality`：`(Int[],Int)` 的 `p==p`、同一数组句柄 `p==q`，期望 `true`，实测 `false`（S1 数组，不依赖 S2）。
3. `TestQATupleStringIdentity`：`"a"+"b"` 两个对象的 `s1===s2`、元组 `p===q`，期望 `false`，实测 `true`。

根因：`impl/internal/interp/interp.go:820` `valuesEqual` 未覆盖 `vObj/vArr/vMap/vClosure`，落到 `return false`；`interp.go:853` `valuesIdentical` 把 `vStr` 当值类型。

---

## 二、已跑命令与结果

| # | 命令 | 结果 |
|---|---|---|
| 1 | `cd impl && go vet ./...` | exit 0 |
| 2 | `go test ./internal/sema ./internal/interp -count=1 -skip 'TestQATuple'` | 两包 ok，0 SKIP，exit 0 |
| 3 | `go test ./internal/sema ./internal/interp -run '^TestTuple' -v` | E2 自有 18/18 PASS（sema 13、interp 5） |
| 4 | `go test ./internal/sema ./internal/interp -run 'TestQATuple' -v` | sema 9/9 PASS；interp 5/8 PASS、**3 FAIL**；exit 1 |
| 5 | 9 示例双路径：`run --interp` vs `run`，比较 stdout + 退出码 | **9/9 MATCH** |
| 6 | 红态复跑：`81ec33d` + 最终测试 | **9 个失败**（sema 8、interp 1），与 E2 `before/` 一致 |
| 7 | `shasum -a 256 -c evidence/M1-TUPLE-01/artifact.sha256` | 5/5 OK，exit 0 |
| 8 | 七件套存在性：`git cat-file -e 53c32c7:evidence/M1-TUPLE-01/<f>` | 7/7 present |

说明：`sha.txt` 为 12 位缩写 `ba4458a8e843`，指向代码提交而非最终 `53c32c7`；HEAD 仅改证据/回执，`impl/` 无差异，记格式整改，不单独打回。

---

## 三、未跑清单

1. **codegen 元组路径**：`internal/codegen` 无元组实现；9 示例双路径只是回归，不证明元组编译路径。
2. **可空元组 null 分支**：`(T1,T2)?` 声明语法不支持，`?.` null 传播未测。
3. **元组作返回值/顶层字段/容器元素/泛型实参**：语法层均不支持（解析错误），E2 已列为未测项。
4. **变异、覆盖率、性能**：本卡未要求，未跑。
5. **L2 阶段门**：本次只做 L1，不构成 Stage 1 门结论。
6. **全仓 `go test ./...`**：按要求只跑 sema + interp；全仓结果未复跑。

---

## 四、证据路径

- 完整验收单：`收件箱/CEO3/验收-M1-TUPLE-01.md`
- 证据目录：`收件箱/CEO3/evidence-M1-TUPLE-01/`
  - 独立用例：`qa-tests/qa-sema_tuple_test.go`、`qa-tests/qa-interp_tuple_test.go`
  - 运行输出：`out/qa-tests.out`、`out/e2-tests.out`、`out/full-pkgs.out`、`out/dualpath.txt`、`out/red-replay-parent.out`、`out/probes.out`、`out/evidence.txt`
  - 复现命令：`commands.txt`
- 被测证据：`wt/e2-sema` @ `53c32c7` 的 `evidence/M1-TUPLE-01/`（七件套齐全，artifact 复算通过）

---

## 五、处置

1. **不签** `evidence/M1-TUPLE-01/acceptance.md`；本回执结论为「不通过」。
2. 修复项：F1 引用元素 `==`、F2 String `===`（`interp` 域）；F3 可空元组（`xfront` 域，需开卡）；F4 字面量表示性（M2-C 挂账）。
3. 过程待核：候选未含 `wt/e3-interp` 的 `461a47a`；`interp/**` 按 v1.6.0 属 E3/CEO2-RD1 域，需 CEO1/CEO2 确认授权与最终合并 sha。E3 `461a47a` 也不能关闭 F1/F2。
4. 复验须用新 sha，重跑 sema/interp 全量、独立用例、9 示例双路径、artifact `-c`。

```
结论：不通过（FAIL）
被测 sha：53c32c7（代码 ba4458a，父提交 81ec33d）
签名 / 时间：CEO3-QA1 / 2026-11-07
```
