# 回执：S6 XDK-05 codegen 同步原语（E4）

- 卡片：XDK-05 编译路径（Mutex/Channel/Atomic 类型与调用发射，对接 E5 rt_sync）
- 提交：`XDK05cg`（见回复 sha；仅 pod/e4-codegen，已同步 main 的 S6-01/02/05/06）
- 顺序：先红后绿：`evidence/S6-XDK05/red.log`（`codegen：类型 Mutex 未支持` →
  compiled 路径 SKIP/BLOCKED）；`green.log`（`TestXDK05CompiledE2E` PASS）。

## 一、红 → 绿

| 项 | 修前（红） | 修后（绿） |
|---|---|---|
| `Mutex<Int>(0)` | 类型 Mutex 未支持 | `xrt_mutex_new` + `withLock` 作用域回调 |
| `Channel<Int>(1)` | 类型未支持 | `xrt_channel_new/send/receive/close` |
| `AtomicInt/AtomicBool(v)` | 类型未支持 | `xrt_atomic_*_{new,load,store,cas}` |
| `AtomicRef<T>(v)` | 类型未支持 | `xrt_atomic_ref_*`（标量元素） |
| `Result<void,TaskError>` / `Result<_,CancelledError>` | 错误类型未支持 | `xrt_error_kind` 复用（Ok() 无参也支持） |
| `tests/s6/xdk05/sync_basic.x` 编译路径 | SKIP/BLOCKED | PASS：`0/7/6/true` |

interp 路径仍由 E3 负责（当前 SKIP，非本卡范围）。

## 二、实现要点

- `cType`：`Mutex/Channel/AtomicInt/AtomicBool/AtomicRef` → `xrt_*` 句柄；
  `CancelledError` → `xrt_error_kind`（S5-00 §八）。
- 构造：`Mutex<T>(v)`/`Channel<T>(cap)`/`AtomicRef<T>(v)`/`AtomicInt(v)`/
  `AtomicBool(v)` 直降运行时 `xrt_*_new`；标量按 intptr 装箱。
- 调用：`Channel.send/receive/close`、`Mutex.withLock(lambda)`、
  `Atomic.load/store/compareExchange` 按 C ABI 发射；Result 通道按
  `{ok,v,err=kind}` 映射。
- `Mutex.withLock`：生成 `xrt_with_lock_body` 回调（`data/env/ctx`），闭包
  `return Result` 翻译为状态码（Ok=0，Err=kind）；当前不支持捕获外部变量。
- 同步句柄为 ARC 资源，不进入 GC 根登记；元素类型记录于 `gen.syncElems`。

## 三、边界

- 仅标量元素（Int/Bool/Char/定宽整数）/标量 Mutex；引用元素的 `xrt_channel_ops`
  retain/release 与 GC 发布点随 S3-06/后续卡。
- `withLock` 闭包捕获外部变量显式报错（未做 env 装箱）。
- interp 路径（E3）未实现，测试按既有机制 SKIP。

## 四、验证

```bash
cd impl
go test ./internal/cli/ -run TestXDK05CompiledE2E -count=1 -v
go test ./internal/codegen/ ./internal/codegen/ffi/ ./internal/cli/ ./internal/interp/ ./internal/sema/ -count=1
```

全绿（compiled E2E + 五套件）。
