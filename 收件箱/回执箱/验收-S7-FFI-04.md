# 验收：S7-FFI-04（@unsafe 门禁）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `29ef79f`（含 E4 `3a6d4e1` @unsafe link.unsafe 门禁）
> **时间**：2026-11-08
> **证据**：`evidence/S7-QA/FFI-04/`
> **依据**：S7 §8、FFI-04；S8 §7；S7-04 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `link.unsafe` 未开启（无清单/false/缺省/非法值/重复） | **PASS**：全部 exit 1，原因明确 |
| `link.unsafe=true` 构建 | **PASS**：构建成功，stderr 记录 `link.unsafe=true` 与受控入口 |
| `@unsafe` 仅存在于 `bindings/` | **PASS**：`src/evil.xfb` → `FFI-110` |
| 合同文本必填 | **PASS**：缺 `contract` → `FFI-110` |
| 应用代码不可创建 `@unsafe` | **PASS**：语言层无 `@unsafe` 语法；路径负例固化 |
| 启用后受控入口调用 | **PASS**：输出 `42` |
| `TestS704*` | **PASS**：5 组全过 |

**判定：PASS。** `link.unsafe` 门禁、bindings-only、合同文本与运行路径全部成立。

---

## 二、实测

```text
$ go test ./internal/codegen -run TestS704 -count=1 -v
PASS TestS704UnsafeGateEnabled
PASS TestS704UnsafeGateRejectsDefault
  PASS 无工程清单 / link.unsafe=false / 缺省 unsafe / 非法值 / 重复字段
PASS TestS704UnsafeOnlyInBindings
PASS TestS704UnsafeContractRequired
PASS TestS704RunUnsafeEntry        # 输出 42
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| `link.libraries` 交叉校验 | 属 S8-07，未在本卡 |
| 清单模式 build | E6 尚未实现；`BuildWithOptions` 为共用入口 |
| `@unsafe` 阻塞分类 | 仍按既有 `@blocking` 合同校验 |

---

## 四、证据

- `evidence/S7-QA/FFI-04/matrix.tsv`
- `codegen-s704.log`（5 组测试）
- `source-contract.txt`（s704_test 合同）
- `impl/internal/codegen/unsafe_gate.go`
- `收件箱/回执箱/回执-S7-04.md`
