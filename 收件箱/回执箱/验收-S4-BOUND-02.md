# 验收：S4-BOUND-02（FFI 边界）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `9161cd1`（含 S4-05 用例；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/ffi-s4.log`、`BOUND-02-contract.txt`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 含 `Result` 的签名不得通过 FFI 暴露 | **PASS**：`FFI-105` 负例通过 |
| 未知错误码不得映射为 `Ok` | **PASS**：未知码 99 → `Internal`，不是 `Ok` |
| 已知错误码按 errorMap 映射 | **PASS**：`NotFound` 等按绑定表输出 |
| FFI 合同负例矩阵无崩溃 | **PASS**：`TestContractNegatives` 11 子项全过 |

**判定：PASS。** `Result` 跨界在合同解析阶段被 `FFI-105` 拒绝；FFI 错误分类默认落到 `Internal`，未知码不会静默变成 `Ok`。

---

## 二、Result 跨界拒绝

`internal/codegen/ffi/check.go` 的 banned 名单包含：

```text
"Result": "Result 不跨语言边界（S7 §3.6 / INV-FFI-2）：错误经错误码出参交付"
```

合同负例 `TestContractNegatives/Result_跨界`（`Int32 f(Result r);`）期望 `FFI-105`，实测 **PASS**。

---

## 三、未知错误码 → Internal

`internal/codegen/ffi/emit.go` 生成的分类函数：

```c
default: return "Internal";
default: return XRT_ERR_INTERNAL;
```

合同测试 `TestXdkWrappersRun` 断言：

```text
unknown=Internal
```

实测通过；已知码 `read rc=5 kind=NotFound` 也符合绑定表。未知码没有走 `Ok` 路径。

---

## 四、边界

本轮未覆盖“XNull 源码 `FFICall` → `Result`”的端到端链路（E4 `FFICall` 未落地）；BOUND-02 以合同测试验证 `Result` banned 与 `errorMap`/未知码 helper 映射。若董事会要求端到端 FFI 调用证据，需在 E4 `FFICall` 落地后补用例。

## 五、官方用例

| 用例 | 结果 |
|---|---|
| `internal/codegen/ffi:TestContractNegatives`（含 `Result_跨界`） | **PASS** |
| `internal/codegen/ffi:TestXdkWrappersRun`（含 `unknown=Internal`） | **PASS** |
| `go test ./internal/codegen/ffi -count=1` 全包 | **PASS** |

---

## 六、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/ffi-s4.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S4A/BOUND-02-contract.txt`（代码/测试断言片段）
- 断言依据：S4 §7.3、§10 BOUND-02；S7 §3.6 / INV-FFI-2
