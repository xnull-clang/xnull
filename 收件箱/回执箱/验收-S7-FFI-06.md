# 验收：S7-FFI-06（ABI v1）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `451bf41`（含 S7-05b ABI v1 转正）
> **时间**：2026-11-08
> **证据**：`evidence/S7-QA/FFI-06/`、`evidence/S7-05/`
> **依据**：S7 §6.1–§6.3、FFI-06；S7-05 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `xrt.h` 稳定 v1 + `XRT_ABI_VERSION 1` | **PASS**：版本宏 + 不匹配 `#error` |
| 初始化顺序：main 首行 `xrt_runtime_init` | **PASS**：codegen 生成；未 init `xrt_alloc` → fatal 134 |
| 稳定命名符号可被原生代码链接 | **PASS**：`test_abi_link.c` 仅 include `xrt.h`，PASS |
| 签名与 §6.1 一致、原生只经 ABI 管理内存 | **PASS**：alloc/retain/release/refcount/weak/root/handle/callback/string/bytes |
| 弱表 bindings-only 构建门禁 | **PASS**：应用层引用 `xrt_weak_*` 编译失败；绑定层 `XRT_BINDINGS_LAYER=1` 成功 |
| `TestS7_05*` | **PASS**：RuntimeInitFirst / HeaderStableV1 / WeakTableBindingsOnly |
| FFI 回归 | **PASS**：`go test ./internal/codegen/ffi` |

**判定：PASS。** ABI v1 的版本宏、初始化顺序、原生链接与弱表门禁三项最小验收全部成立；`build_rt.sh` 全套 exit 0。

---

## 二、实测

```text
$ sh impl/runtime/build_rt.sh
abi link tests passed (xrt.h only, init order, weak gate, handle/callback)
abi v1 tests passed (XRT_ABI_VERSION=1, init order)
... 全部套件 exit 0

$ go test ./internal/codegen -run 'TestS7_05' -count=1
PASS（RuntimeInitFirst / HeaderStableV1 / WeakTableBindingsOnly）

$ go test ./internal/codegen/ffi -count=1
PASS
```

未 init 负例：`xrt_alloc：运行时未初始化（S7 §6.3）`，EXIT=134。  
弱表门禁：应用层 `xrt_weak_bind` 未声明 → 编译失败；绑定层宏后 EXIT=0。

---

## 三、边界

| 项 | 说明 |
|---|---|
| 弱表门禁 | 头文件/编译合同层，不隐藏 ABI 符号；手工声明仍可链接（合同违规） |
| 单 TU | 生成代码单 TU；绑定层宏在 include 前定义 |
| `xrt_alloc` 之外便捷构造器 | §6.3 规范入口按 `xrt_alloc` 执行，未逐一加 init 检查 |

---

## 四、证据

- `evidence/S7-QA/FFI-06/matrix.tsv`
- `runtime-build.log`（abi link / abi v1 / 全运行时套件）
- `gotest-s705.log`、`ffi-tests.log`
- `contracts.txt`（xrt.h 版本/弱表门禁 + codegen init 行）
- `evidence/S7-05/` 原始红→绿
- `收件箱/回执箱/回执-S7-05.md`
