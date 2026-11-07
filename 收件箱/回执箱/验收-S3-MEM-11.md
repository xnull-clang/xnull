# 验收：S3-MEM-11（FFI）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `412fcac`（S3 计划 v0.2 `31bf5f1`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s3b`，sha256 `d7fe3b72506598e04df2df831494680d6519b03be5e1a5c8a9c4480c3341dcba`
> **证据**：`evidence/S3-QA/MEM-11/`
> **依据**：`收件箱/门/S3验收计划-E2.md` MEM-11；S3 §19
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 句柄传递（handle） | **PASS**：`TestXdkBindingsLoadAndEmit`、`TestXdkWrappersRun`、`TestXDKSysFileOpenWrite` |
| 缓冲区传递（borrow/transfer/reclaim） | **PASS**：`TestContractNegatives` 的 buffer 合同用例 |
| 租约合同校验 | **PASS**：缺租约、移交无归还、borrow/transfer 组合均按合同拒绝/通过 |
| 无租约声明入口拒绝 | **PASS**：`TestContractNegatives/缺租约` |
| 裸指针/Result 跨界/重复入口等负例 | **PASS**：`TestContractNegatives` 全子用例 |
| `go test ./internal/codegen/ffi` | **PASS** |

**判定：PASS。** FFI 合同、句柄/缓冲区租约与 XDK 绑定的正负例均通过。

---

## 二、实测

```text
$ cd impl && go test ./internal/codegen/ffi -count=1
ok  xnull.dev/xnull/internal/codegen/ffi
exit 0
```

覆盖：`TestContractNegatives`（缺租约/移交无归还/String 移交/嵌套数组/Result 跨界/裸指针/重复入口等）、`TestXdkBindingsLoadAndEmit`、`TestXdkWrappersRun`、`TestXDKTextFileAPI`、`TestXDKSysFileOpenWrite`。

---

## 三、证据

- `evidence/S3-QA/MEM-11/gotest.out`、`gotest.exit`
- `evidence/S3-QA/MEM-11/matrix.tsv`
- 测试：`impl/internal/codegen/ffi/emit_test.go`、`ffi_test.go`
- 绑定：`bindings/xdk/runtime.xfb`、`bindings/xdk/sys.xfb`
