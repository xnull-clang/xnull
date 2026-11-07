# S6-XDK-05 双路径 E2E 交接（E2 → E3/E4）

- 用例：`tests/s6/xdk05/sync_basic.x`（期望 `sync_basic.expect`：`0/7/6/true`）
- sema：已补 `Mutex<T>(v)`、`Channel<T>(cap)`、`AtomicInt(v)`、`AtomicBool(v)`、`AtomicRef<T>(v)` 构造签名；`Mutex<struct>`/`AtomicRef<值类型>` → `TY-228`。`xnull check` 通过。
- 解释路径（E3）：`xnull run --interp` 失败于 `未定义的函数：Mutex`；需 interp 提供 Mutex/Channel/Atomic* 值与方法。
- 编译路径（E4）：`xnull run` 失败于 `codegen：Result 错误类型暂仅支持 String`；随后还需 Mutex/Channel/Atomic* 的 C 发射。
- 运行时（E5）：`impl/runtime/test_sync.c` 已覆盖 Channel/Mutex/Atomic*；语言面接线后可直接复用。
- 测试行为：`impl/internal/cli/xdk05_e2e_test.go` 在两端未支持时显式 SKIP（打印上述原因）；支持落地后自动转为输出断言，无需改测试。
