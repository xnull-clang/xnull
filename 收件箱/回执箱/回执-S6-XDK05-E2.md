# 回执：S6-XDK-05 双路径 E2E

- **状态**：sema `DONE`；E2E 用例已落盘；解释/编译路径 `BLOCKED`（E3/E4，非 E5 运行时）
- **sema 修复**：补 `Mutex<T>(v)`、`Channel<T>(cap)`、`AtomicInt(v)`、`AtomicBool(v)`、`AtomicRef<T>(v)` 构造签名；`Mutex<struct>` / `AtomicRef<值类型>` → `TY-228`；`xnull check` 通过。
- **用例**：`tests/s6/xdk05/sync_basic.x`（期望 `0/7/6/true`）+ `impl/internal/cli/xdk05_e2e_test.go`，覆盖 sema / interp / compiled 三段；解释与编译未支持时显式 SKIP 并打印原因，支持落地后自动转为输出断言。
- **实测缺口**：interp `未定义的函数：Mutex`（E3）；compiled `codegen：Result 错误类型暂仅支持 String`（E4，随后还需 sync 发射）。运行时 `impl/runtime/test_sync.c` 已由 E5 覆盖。
- **证据**：`evidence/S6-XDK05/`（红→绿、E2E SKIP、四包+cli）；交接：`handoff/S6-XDK05-E2E.md`。
- **说明**：本卡只改 sema/测试，未动 interp/codegen/runtime；XDK-05 端到端在 E3/E4 接线后才能签 PASS。
