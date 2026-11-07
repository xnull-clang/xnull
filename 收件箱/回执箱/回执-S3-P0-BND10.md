# 回执：S3-P0-BND10（GC 清扫跨对象悬挂）

- 执行位：运行时线 E5
- 基线：`main=c9d9759`
- 分支：`fix/p0-bnd10`（仅运行时修复，不含 S3-04 WIP）
- 结论：**已修复**；`TestBND10GCMixedARCFieldValid` 与 `go test ./...` 全绿
- 证据：`evidence/S3-P0-BND10/`（红日志、回栈、绿日志、冒烟）

## 现象

`go test ./internal/codegen -run TestBND10GCMixedARCFieldValid -count=1 -v` 在 main 上失败：
进程 exit -1/139，运行期崩溃。l9 回栈：

```
EXC_BAD_ACCESS (EXC_I386_GPFLT)
frame #0: rt_retain  (obj=0xd000000000000000 / 0xb000000000000000)
```

程序（GC 环双 Node + 各自 String 字段）实际输出先出现 `helper-deinit` ×2，随后在
Node deinit 读 `self.h.name` 时崩溃。

## 根因

- S3-01 + 策略更新后：`Helper`（含 String 字段）按 GC 分配，`Node`（引用环）也是 GC。
- 单趟 sweep 逐对象执行「deinit → scan → free」：Helper 先被 deinit+free，随后 Node
  的 deinit 读取 `self.h.name`，命中已释放的 Helper（及已被 Helper deinit 释放的 String）
  → `rt_retain` 收到毒化指针。
- 触发条件：死亡 GC 对象之间的引用（Node → Helper）在同一清扫周期内被提前释放。

## 修复

`impl/runtime/rt_gc.c::sweep` 改为**两阶段**：

1. 从存活表摘下全部死亡对象；
2. 阶段 1：逐个 `terminated` → 清弱槽 → 调用 deinit（**不释放任何死亡对象内存**）；
3. 阶段 2：统一 `scan(sweep_release_arc_ref)` 释放 ARC 引用并 `free`。

deinit 按分配序执行（确定性）；内存只在全部 deinit 完成后释放，跨死亡对象的字段读取保持有效（S2 §6.4）。

附加：`test_gc.c` 新增第 7 段（target/holder 均为死亡 GC 对象，holder deinit 读 target 字段）。

## 验证

- `green-test.log`：目标用例 PASS。
- `smoke.log`：输出 `main` / `node-deinit helper`×2 / `helper-deinit`×2，exit 0。
- `green-all.log`：`go test ./...` 全绿。
- `green-build_rt.log`：运行时六套件 exit 0。

## 范围

- 只改 `impl/runtime/rt_gc.c` 与 `impl/runtime/test_gc.c`；未改 codegen/sema，未含 S3-04
  分支改动（S3-04 的 kind-aware release 属后续卡）。
- main 在修复前未合并；修复后可 fast-forward。
