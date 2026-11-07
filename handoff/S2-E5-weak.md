# 接力棒：S2-E5-weak

- **卡片ID**：S2-E5-weak（S2 审计 S2-E5-06：弱槽位目标死亡后的 UAF）
- **输入**（上游产物/条款/接口）：
  - 审计：`收件箱/门/S2审计-E5.md` §三 S2-E5-06
  - 条款：S3 §16（弱表不阻止回收、清除后槽位可复用、禁止观察已终结目标）、S2 §6.4（弱引用在 deinit 前清除）、S7 §6.2（`xrt_weak_*` 入口面）
  - 基线：`main=e97dc8e`
- **输出文件**（精确路径）：
  - `impl/runtime/rt_weak.c`（clear/destroy/get 解绑与安全检查）
  - `impl/runtime/rt.h`（内部诊断 `rt_weak_is_detached`，不进 `xrt.h` ABI）
  - `impl/runtime/test_hard.c`（第 5 段：release → `rt_quarantine_flush()` → 断言解绑 → destroy）
  - `evidence/S2-E5/red.log`、`green.log`、`summary.md`
- **commit**：`9e6de30`（pod/e5-runtime）
- **验证命令**（可复制）：
  ```bash
  cd impl/runtime && sh build_rt.sh          # 六套件 exit 0（先红：red.log / 后绿：green.log）
  cd impl && go test ./internal/codegen/... -count=1   # 全绿
  ```
- **已知缺口/风险**：
  - 目标死亡后 `rt_weak_is_detached` 为真、destroy 不再解引用目标；弱槽位仍无复用池（S2-E5-11，后置）。
  - 并发原子性未做（单线程骨架；S3 §16 的原子要求随调度器切片）。
  - 内存策略消费（BND-10/MEM-01）与 GC 根/收集（S2-E5-02/03）按指令后置。
  - deinit 发射（S2-E5-01/04/05）属 E4 codegen；本卡只对齐契约，未改 `internal/codegen/**`。
- **下一步**（谁接、做什么）：
  1. E4：按回执中的 deinit 发射契约实现（用户 deinit 体 → 字段释放；字段赋值 retain/release；handle/Bytes 字段释放）；
  2. E5：S2 实现第二卡（内存策略消费 / GC 根与收集）待派；
  3. QA1：弱槽位死亡后操作的独立复验（可复用 `test_hard` 第 5 段）。
- **上一棒**：`handoff/B0-07c.md`（numeric 前置）→ `收件箱/门/S2审计-E5.md`（审计）
- **下一棒**：`handoff/S2-E5-memory.md`（待建）→ E4 的 deinit 发射卡
- **last-green**：`9e6de30`（`build_rt.sh` 六套件 exit 0；`go test ./internal/codegen/...` 全绿；日志 `evidence/S2-E5/green.log`）

## E4 交付：deinit 发射契约（2026-11-07，commit `70f4385`，pod/e4-codegen）

- **实现**（`impl/internal/codegen/classes.go`、`classes_expr.go`、`codegen.go`、`ffi_gen.go`）：
  1. **字段赋值**（类引用/String/handle/Bytes）：先求值 → 新值持 +1 → `rt_release` 旧值 → 写入；
     与旧值别名时先 retain 新值再释放（`o.inner = o.inner` 安全）。
     `bytesExpr` 的 Ident 分支改为 `rt_retain` 返回 +1，局部声明与字段赋值共用同一所有权纪律。
  2. **deinit 顺序**：`<cname>_deinit` 钩子先调用用户体 `<cname>_deinit_user`（静态派发），
     再释放仍非空字段；用户体把字段置 null 时 `rt_release(NULL)` 安全（保留提前释放语义）。
  3. **字段释放**：`isRefField()` 覆盖 `rt_string *` / 类引用 / `xrt_handle *` / `xrt_bytes_obj *`；
     容器字段仍走 `_free`。句柄只释放对象，显式 close 仍由合同要求。
  4. 构造器零值：指针类字段统一 `NULL`。
- **未覆盖/显式拒绝**：
  - 容器字段赋值（`o.list = other`）：本层容器是值结构，浅拷贝会双释放；
    在引用语义容器落地前显式报错（`codegen：容器字段 … 的赋值需要引用语义容器（B2 范围，显式拒绝）`），不静默生成。
  - 父类链：本分支 `collectClass` 仍拒绝继承（M4.4b 单类），`super.deinit()` 去重逻辑待继承卡；
    用户体先于字段释放的顺序已按契约固定。
- **测试**：`impl/internal/codegen/s2_deinit_test.go`
  - `TestS2DeinitUserBodyBeforeFieldRelease`：行为 `two / deinit:two` + 生成 C 中 `_deinit_user(o);` 在 `rt_release(o->name);` 之前；
  - `TestS2FieldAssignClassRefRetainRelease`：`rt_retain(x); rt_release(o->inner); o->inner = x;`；
  - `TestS2DeinitReleasesHandleAndBytes`：句柄/Bytes 字段均 `rt_release`，且用户体先执行。
- **验证**：`go test ./... -count=1` 全绿。
- **已通知 E5**：`ses_e4e568a1effejGcw2Ap4Y2oxMv`（复跑 S2 生命周期用例）。
- **归属**：deinit 禁止发布 self 的静态检查仍归 E2；运行时 retain 已终结对象 → fatal 已有兜底。
