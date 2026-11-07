# S7-05（E5）：ABI v1 转正

- 卡片：S7-05（S7 §6.1/§6.2/§6.3；FFI-06）
- 基线：main `3e7f225`（S7 盘点后）；代码提交 `4c1e5db`
- 结论：`xrt.h` 转稳定 v1；初始化顺序、弱表 bindings-only、原生链接测试落地

## 先红

| 项 | 基线行为 | 证据 |
| --- | --- | --- |
| `xrt_alloc` 未初始化 | 正常分配并返回 0 | `red-init-order.log` |
| 应用层引用 `xrt_weak_*` | 编译通过 | `red-weak-gate.log` |
| `xrt.h` 状态 | **ABI v1 候选冻结** | `red-status.log` |
| 生成 `main` | 无 `xrt_runtime_init()` | `red-status.log` |

## 实现

### 1. `xrt.h` 转稳定 v1

- 头注释由“候选冻结”改为“稳定 v1（2026-11-08 转正；S7-05）”。
- 新增 `#define XRT_ABI_VERSION 1`。
- 弱表入口（`xrt_weak_bind/read/clear`）改为仅在 `XRT_BINDINGS_LAYER` 定义时声明：
  应用层/原生代码直接引用即编译失败（S7 §6.2）。

### 2. 初始化顺序（S7 §6.3）

- `xrt_abi.c`：`xrt_alloc` 在 `g_runtime_inited == 0` 时 `rt_fatal`
  （“运行时未初始化；先调 xrt_runtime_init”）。
- codegen `main` 首行生成 `xrt_runtime_init();`，先于 vtable/枚举/全局/单例与入口调用。
- `rt.c` 提供 `xrt_runtime_init` 弱兜底：只链接内部运行时的手工 codegen 测试也能解析
  生成 main 的调用；完整 ABI 构建链接 `xrt_abi.c` 时由强符号覆盖。

### 3. 弱表 bindings-only 构建检查

- `xrt_abi.c`、`test_abi.c`、`test_std.c`、`test_task.c`、`test_abi_link.c`
  在包含 `xrt.h` 前定义 `XRT_BINDINGS_LAYER 1`。
- `impl/internal/codegen/ffi/emit.go` 的绑定层支撑代码在 include 前定义该宏。
- `build_rt.sh` 增加编译门禁：
  - 应用层片段引用 `xrt_weak_bind` → **必须编译失败**；
  - 定义 `XRT_BINDINGS_LAYER` 的绑定层片段 → 编译成功。

### 4. 原生链接测试

新增 `impl/runtime/test_abi_link.c`：只 `#include "xrt.h"`（不包含 `rt.h`/`rt_gc.h`），
链接 `rt.c/rt_gc.c/rt_weak.c/xrt_abi.c/rt_std_bytes.c`，覆盖：

- `XRT_ABI_VERSION == 1`、`xrt_runtime_init` 幂等；
- ARC `xrt_alloc/retain/release/refcount`；
- 弱表 bind/read/clear；
- GC 分配 + root/barrier/safepoint；
- 句柄 `xrt_handle_new/close/is_closed/native/mark_closed`（关闭幂等、已关闭不再触达）；
- 回调 env `new/invoke/destroy`（注销后调用 fatal）；
- `xrt_string_*` / `xrt_bytes_*` 访问器；
- 子进程负例：未 init 的 `xrt_alloc` 必须 fatal；注销后回调必须 fatal。

## 后绿

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| `test_abi_link` | PASS（原生链接 + init 顺序 + 弱表 + 句柄/回调） | `green-abi-link.log` |
| 未 init 的 `xrt_alloc` | fatal（exit 134） | `green-init-order.log` |
| 应用层 `xrt_weak_*` | 编译失败；绑定层宏后编译成功 | `green-weak-gate.log` |
| `sh impl/runtime/build_rt.sh` | 全套 exit 0 | `green-build_rt.log` |
| `go test ./internal/codegen -run TestS7_05` | PASS | `green-gotest.log` |
| `go test ./internal/codegen -run 'TestS6_0[234]'` | PASS | `green-gotest-s6.log` |
| 全量 `go test ./internal/codegen` | PASS | 本次验证 |
| `go test ./internal/codegen/ffi` | PASS | 本次验证 |
| `go test ./internal/cli ./internal/interp ./internal/sema` | PASS | 本次验证 |

## 边界

- 弱表门禁是**头文件/编译门禁**：原生代码若手工声明符号仍可链接；
  这是 S7 §6.2 的合同层防线，不是符号隐藏（不改变 ABI 导出）。
- 当前生成代码是单 TU：`EmitSupport` 的 `XRT_BINDINGS_LAYER` 在其 include 前定义；
  若未来绑定层需要直接调用弱表，应拆独立 TU 并在顶部定义宏。
- `xrt_runtime_init` 强实现仍在 `xrt_abi.c`；`rt.c` 的弱兜底仅服务手工测试，
  产品构建（`runtimeCSources` 含 `xrt_abi.c`）始终使用强符号。
- FFI-06 的 ABI 稳定命名/初始化顺序/弱表门禁已补齐；QA 可据此重评 FFI-06。
