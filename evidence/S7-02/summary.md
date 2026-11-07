# S7-02（E5）：FFI 错误码 → Result 的 runtime 侧

- 卡片：S7-02 runtime 面（S7 §7.1/§7.2；FFI-01/FFI-05、BOUND-02/03）
- 基线：main `451bf41`
- 结论：调用点不再 `exit(134)`；原始码回写调用点；映射函数已知→ErrorKind、
  未知→Internal、Cancelled/Timeout 不降级；E4 用 `ffiErrorKindExpr` 构造 Result.err

## 先红

- `TestS7_02ErrorCodeNoFatal` 在基线 `451bf41` 失败：
  生成 C 含 `fatal: FFI 入口 ffiRead 错误码 ... exit(134)`（`red-callsite.log`）。
- 映射函数本身已存在，`TestS7_02ErrorKindMappingRuntime` 在基线即 PASS
  （`red-mapping.log`）——本卡把“映射可用”接到“调用点不终止”。

## 实现

### 调用点（`impl/internal/codegen/ffi_gen.go`）

- 删除 `@errorCode` 出参路径的 `exit(134)`。
- 保留 `codeVar = rc`：原始错误码回写调用点变量，入口继续执行。
- 新增对接表达式：
  ```go
  ffiErrorKindExpr(region, code) => "xn_ffi_<region>_error_kind_id(<code>)"
  ```
  E4 的调用点改造用它构造 `Result.err`（已知码 → ErrorKind；未知 → Internal；
  Cancelled/Timeout 不降级）。
- `@errorCodeRet`（fileWrite/close）保持原语义：返回原始码 / `Bool(rc==0)`；
  E4 可在 Result 化时同样映射。

### 映射函数（`ffi/emit.go`，既有 + 运行时验证）

`xn_ffi_<region>_error_kind[_id](code)`：
- `errorMap` 命中 → 对应 `ErrorKind`；
- 未命中 → `Internal`（绝不当 Ok）；
- `Cancelled`/`Timeout` → `XRT_ERR_CANCELLED`/`XRT_ERR_TIMEOUT`，不降级。

## 后绿

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 调用点：原生码 5 → 程序 exit 0，`code=5`，结果槽 0 | PASS | `green-gotest-codegen.log` |
| 映射运行时：5→NotFound、99→Internal、14→Cancelled、15→Timeout | PASS | `green-gotest-ffi.log` |
| `ffiErrorKindExpr("native","rc")` | PASS | `green-gotest-codegen.log` |
| S4 旧 fatal 用例改造（`s4_04`/`s4_05`） | PASS | `green-gotest-codegen.log` |
| 全量 `go test ./internal/codegen` | PASS | `green-full-codegen.log` |
| `ffi`/`cli`/`interp`/`sema` | PASS | `green-other.log` |
| `sh impl/runtime/build_rt.sh` | exit 0 | `green-build_rt.log` |

## 与 E4 的对接

- 调用点拿到的 `rc`/`codeVar` 是**原始码**，不再被终止。
- 构造 `Result` 时：
  ```c
  xrt_error_kind kind = xn_ffi_<region>_error_kind_id(rc);
  /* ok = (rc == 0); err = kind; */
  ```
- `ffiErrorKindExpr(e.Region, rc)` 生成上述表达式，E4 可直接在 `ffiCallLines`
  的 Result 分支使用；函数签名/Result 类型由 E4/E2 的调用点改造决定。

## 边界

- 本卡只做 runtime/生成侧映射与“去 fatal”；语言签名改成 `Result<T,Error>`
  仍属 E4/E2 的调用点改造。
- `@errorCode` 出参成功时结果槽为 0；失败时结果槽不保证有效（调用方先看 code）。
- 未知码仍映射 `Internal`，不会静默成 Ok；取消/超时不降级。
