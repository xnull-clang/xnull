# S3-07：FFI trampoline（回调根登记与生命周期）

- 卡片：S3-07（替换 `ErrTrampolineReserved`）
- 依据：S7 §5.1/§5.2/§5.3；S3 §19/§22（`task_root_bind/unbind`）；ffi-design §5
- 基线：`main=ba1b5c2`
- 结论：trampoline 生成面落地；env 创建登记根、销毁注销、注销后调用终止

## 先红

新增 `TestTrampolineGenerated`（期望 `EmitTrampoline` 成功并生成 env 生命周期符号），
在旧实现上失败：

```
trampoline 应可生成：ffi: 回调（trampoline）形态预留中——回调根登记需要调度器的栈 pin 语义（S7 §5.1），随调度器切片落地
FAIL
```

原始输出：`red.log`。

## 实现

**运行时（`xrt.h` / `xrt_abi.c`）**

```c
typedef int32_t (*xrt_callback_fn)(void *closure, const void *args, size_t nargs, void *result);
xrt_callback_env *xrt_callback_env_new(void *closure, xrt_callback_fn fn);   /* 登记根 */
int32_t xrt_callback_env_invoke(env, args, nargs, result);                   /* 已注销 → xrt_fatal */
void    xrt_callback_env_destroy(env);                                       /* 幂等；注销根 */
int     xrt_callback_env_alive(env);
void   *xrt_callback_env_closure(env);
```

- env 为 GC 对象，创建即 `rt_gc_root_add`，销毁即 `rt_gc_root_remove`（S7 §5.2）。
- 已注销/空 env 调用 `rt_fatal`（原生侧合同违规，不静默）。
- 闭包引用为裸指针，生命周期由绑定层管理（语言闭包 codegen 尚未落地）。

**FFI 生成面（`emit.go`）**

`EmitTrampoline(entry)` 生成：

```c
xn_tramp_<entry>_new(closure, fn)      → xrt_callback_env_new
xn_tramp_<entry>_destroy(env)          → xrt_callback_env_destroy
int32_t xn_tramp_<entry>(env,args,n,res) → xrt_callback_env_invoke
```

`ErrTrampolineReserved` 删除。

**测试**：`test_std.c` 新增 `test_callback_env`（创建/存活/闭包指针/调用返回/销毁幂等/
注销后调用 fork 断言终止）；`emit_test.go` 改为 `TestTrampolineGenerated`。

## 后绿

- `green-trampoline.log`：`TestTrampolineGenerated` PASS。
- `green-build_rt.log`：六套件 exit 0（含 std 的 callback 用例）。
- `go test ./internal/codegen/ffi/` 全绿。

## 边界

- 目标 ABI 的具体参数/返回编组由绑定层提供 `xrt_callback_fn`；当前不生成闭包调用体
  （语言闭包在 codegen 中尚未落地）。
- 回调内 panic 走既有 `rt_fatal`（S7 §5.3），不做任务级隔离。
- env 的 GC 回收在销毁 + 下次收集时发生（与全局根一致的 GC 时机）。

## 复现

```bash
cd impl && go test ./internal/codegen/ffi/ -run TestTrampolineGenerated -count=1 -v
cd impl/runtime && sh build_rt.sh
```
