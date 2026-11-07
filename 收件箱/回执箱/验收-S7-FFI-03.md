# 验收：S7-FFI-03（租约与所有权）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `eeb7b04`（含 S7-01 `21a60a0` 调用点编组）
> **时间**：2026-11-08
> **证据**：`evidence/S7-QA/FFI-03/`
> **依据**：S7 §3.6/§3.7、FFI-03；S7-01 E4 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `.transfer` 句柄 out | **PASS**：open rc=0 handle=1；fail handle=0 |
| `.transfer` Bytes 所有权移交 | **PASS**：`ffiFill` 返回 2，不二次释放 |
| `.reclaim` Bytes 归还路径 | **PASS**：`reclaim=0 reclaim_total=1 closed=1` |
| `.borrow` 边界 pin | **PASS**：canary 越界写子进程终止，无 `canary-missed` |
| layout 尺寸检查 | **PASS**：layout 模式终止；正常 `layout_ok=1` |
| 租约合同负例 | **PASS**：缺租约/移交无归还/裸指针/layout 非法 |
| FFI 包回归 | **PASS**：`go test ./internal/codegen/ffi` |

**判定：PASS。** S7-01 补齐 `.transfer` 句柄 out 与 Bytes transfer/reclaim；调用点编组与 canary/layout 合同端到端成立。

---

## 二、实测

```text
$ go test ./internal/codegen/ffi -run TestEmitSupportEndToEnd -count=1 -v
PASS
stdout:
add rc=0 v=5
open rc=0 handle=1
openfail rc=0 handle=0
reclaim=0 reclaim_total=1 closed=1
layout_ok=1
...
$ go test ./internal/codegen/ffi -count=1
PASS（含 TestContractNegatives）
```

canary/layout 子进程：进程终止，未出现 `canary-missed` / `layout-missed`。

---

## 三、边界

| 项 | 说明 |
|---|---|
| `.borrow` 返回后指针失效 | 语言面不暴露裸指针；合同由包装层 pin/canary 承担，越界写可见 fatal |
| Bytes 移交 | 显式所有权转移，不经 canary；reclaim 后包装对象关闭 |
| 句柄 out | 所有权由包装层 `xrt_handle_new` 接管；reclaim 归还闭合 |

---

## 四、证据

- `evidence/S7-QA/FFI-03/matrix.tsv`
- `emit-e2e.log`（TestEmitSupportEndToEnd，canary/layout/reclaim）
- `ffi-tests.log`（TestContractNegatives 等）
- `runtime-build.log`
- `收件箱/回执箱/回执-S7-01-E4.md`
