# S4-E5：诊断通道合同 + ErrorKind/FFI 映射骨架

- 卡片：S4-06（诊断通道合同）+ S4-04 预备（Cancelled/Timeout 错误面骨架）
- 依据：S4 §9（无堆分配/最小单行/不静默）、§4.3（诊断不含敏感信息）、§3/附录 A、
  §5/§6（Cancelled/Timeout）、§7.3（FFI 映射不得降级）
- 基线：`main=95b06c1`（S3 门后）
- 结论：诊断通道无堆分配且单行；ErrorKind 稳定枚举与 FFI 枚举映射骨架落地

## S4-06 诊断通道

**实现**
- `rt_fatal`（`rt.c`）改用 `write(STDERR_FILENO, ...)` + 256B 栈缓冲：
  无 malloc；前缀 `xnull runtime fatal: `；reason 中的 `\n`/`\r` 折叠为空格，
  其他控制字符折叠为 `?`；只输出调用方 reason，不附加环境/参数/堆信息；
  超长截断，避免诊断本身分配。
- `xdkc_diagnose` 已为 write + 512B 栈块（无堆），保持单行；未改动。
- 敏感信息：运行时只输出调用方提供文本；错误类型设计者对 `describe()` 内容负责（S4 §4.3），
  已在合同留痕。

**测试（`test_std.c`）**
- 无堆分配：开启 `xrt_stats`，`xdkc_diagnose` 前后 `allocs` 不变。
- 单行：子进程重定向 stderr，`"l1\nl2\rx"` → 输出一行、无 `\r`。
- fatal：子进程 `rt_fatal("bad\nline\x01x")` → 非零退出、前缀正确、
  `bad line?x`、仅 1 个换行（无调用栈/附加行）。

## S4-04 预备（ErrorKind / FFI 映射骨架）

**`xrt.h`（稳定 ABI）**
```c
typedef enum xrt_error_kind {
    XRT_ERR_INVALID_ARGUMENT = 0, XRT_ERR_NOT_FOUND, XRT_ERR_ALREADY_EXISTS,
    XRT_ERR_PERMISSION_DENIED, XRT_ERR_IO, XRT_ERR_NETWORK, XRT_ERR_TIMEOUT,
    XRT_ERR_CANCELLED, XRT_ERR_BUSY, XRT_ERR_UNAVAILABLE, XRT_ERR_DATA_CORRUPTED,
    XRT_ERR_UNSUPPORTED, XRT_ERR_OUT_OF_MEMORY, XRT_ERR_INTERNAL
} xrt_error_kind;
const char *xrt_error_kind_name(xrt_error_kind);
xrt_error_kind xrt_error_kind_parse(const char *name); /* 未知 → Internal */
```
- 数值与 S4 §3.1 顺序一致，只追加（§3.3）；Cancelled=7、Timeout=6。

**FFI 生成面**
- `emitErrorKind` 额外生成 `xn_ffi_<region>_error_kind_id(int32_t code)`：
  绑定 errorMap 短名 → `XRT_ERR_*`；未知 → `XRT_ERR_INTERNAL`；
  `Cancelled`/`Timeout` 原样保留，不降级。
- 既有字符串分类函数保持不变（兼容 P-09 当前调用点）。

**预留（B3）**
- 取消/超时机制（令牌、任务树、定时器）、副作用停止验收属调度器切片；
  本卡只落错误面枚举与映射骨架。

## 先红 / 后绿

- 红：旧树 `test_std.c` 编译失败（`xrt_error_kind*` 未定义）；FFI 测试缺 `_error_kind_id`
  （`evidence/S4-E5/red-runtime.log`、`red-ffi.log`）。
- 绿：`green-build_rt.log`（六套件 exit 0）、`green-ffi.log`（PASS）、
  `green-all.log`（`go test ./...` 全绿）。

## 复现

```bash
cd impl/runtime && sh build_rt.sh
cd impl/internal/codegen/ffi && go test . -run TestErrorKindEnumHelper -count=1 -v
cd impl && go test ./... -count=1
```
