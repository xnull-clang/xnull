# 接力棒：S2-E5-deinit

- **卡片ID**：S2-E5-deinit（验证 E4 deinit 发射契约的运行时行为，不改 codegen）
- **输入**（上游产物/条款/接口）：
  - E4 交付：`pod/e4-codegen@70f4385`（用户体先执行、引用字段 retain/release、handle/Bytes 释放）；main handoff `a75226a`
  - 条款：S2 §6.4、S3 §14/§15、E5 回签的五项契约（见 `收件箱/回执箱/回执-S2-E5-weak.md`）
  - 基线：`main=f975810`
- **输出文件**（精确路径）：
  - `evidence/S2-E5-deinit/summary.md`
  - `evidence/S2-E5-deinit/{main-order.log,main-assign-c.txt,main-handle-deinit-c.txt,branch-assign-c.txt,branch-handle-deinit-c.txt,branch-selfassign.log,branch-tests.log}`
  - `evidence/S2-E5-deinit/probes/{order.x,assign.x,assign-no-selfassign.x,hold.x}`
  - `收件箱/回执箱/回执-S2-E5-deinit.md`
- **commit**：见本次提交（pod/e5-runtime）
- **验证命令**（可复制）：
  ```bash
  cd impl && go build -o /tmp/xnull-main-f975 ./cmd/xnull
  XNULL_RUNTIME=<repo>/impl/runtime /tmp/xnull-main-f975 build evidence/S2-E5-deinit/probes/order.x -o /tmp/order && /tmp/order
  grep -n 'h->a' <生成 C>                     # main: 裸赋值；70f4385: retain/release
  git worktree add --detach /tmp/e4-deinit 70f4385
  cd /tmp/e4-deinit/impl && go test ./internal/codegen/ -run 'TestS2Deinit|TestS2FieldAssign' -count=1 -v
  ```
- **已知缺口/风险**：
  - **main 未合入 70f4385**：`81e146e` 只做用户体先执行；字段赋值无 retain/release；handle/Bytes 字段无释放。
  - 70f4385 落后 main 32 提交、与 81e146e 同改三文件，直接合入必冲突；需 E4 以 main 为基重放增量。
  - `h.a = h.a`（成员表达式）被 70f4385 拒绝；「别名安全」目前只对 Ident 成立。
  - 可空类字段未支持 → 「deinit 内置 null」无法端到端；`rt_release(NULL)` 由运行时保证。
  - Bytes 字段端到端仍被 `SEMA-BYTES` 阻断（E2）。
- **下一步**（谁接、做什么）：
  1. E4：以 main 为基重放 70f4385 增量（字段赋值 retain/release + handle/Bytes 字段释放），带上 `c1ffd20` 弱槽修复；
  2. E5：main 合入后复跑本目录 3 个探针并回签；
  3. E2：`SEMA-BYTES` 与 deinit 发布 self 检查。
- **上一棒**：`handoff/S2-E5-weak.md`（commit `9e6de30`）
- **下一棒**：E4 的 deinit 发射重放卡 → `evidence/S2-E5-deinit/` 复签
- **last-green**：`ea913dd`（含 `beba3f6` 重放；E5 复签 5/5，`build_rt.sh` 六套件 exit 0，日志 `evidence/S2-E5-deinit/replay-beba3f6-*`）

## E4 重放交付（2026-11-07，main `beba3f6`）

- **基线**：main `6ca3775`（含 `81e146e` 构造器/deinit 体 + 单继承布局、E5 `c1ffd20` 弱槽修复）。
  以 main 为基重放 `70f4385` 增量，不再使用旧分支提交。
- **实现**（`impl/internal/codegen`）：
  1. 字段赋值（类引用/String/handle/Bytes）：求值 → 新值 +1 → `rt_release` 旧值 → 写入；
     新增 **成员表达式 RHS**（`h.a = h.a`、`h.a = other.a`）：先落临时并 `rt_retain`，再释放旧值，别名安全。
  2. 字段释放：`isRefField()` 覆盖 `rt_string *` / 类引用 / `xrt_handle *` / `xrt_bytes_obj *`；
     容器字段仍 `_free`；用户 deinit 体（含父类链）先于字段释放（沿用 `81e146e` 顺序）。
  3. `bytesExpr` 的 Ident 分支改为 `rt_retain` +1，局部声明/字段赋值共用所有权纪律；构造器指针字段零值 `NULL`。
- **显式拒绝（E5 已确认可接受）**：容器字段赋值（值结构浅拷贝会双释放）→ B2 引用语义容器；
  `Class?` 可空类字段未支持（deinit 内置 null 端到端待该项）。
- **测试**：`impl/internal/codegen/s2_deinit_test.go`
  - 用户体先于字段释放（行为 + 生成 C 顺序）；
  - 类引用字段 `rt_retain(x); rt_release(o->inner); o->inner = x;`；
  - **成员表达式自赋值** `h.a = h.a`（行为 + retain 先于 release）；
  - handle/Bytes 字段在钩子中 `rt_release` 且用户体先执行。
- **验证**：`go test ./... -count=1` 全绿（main `beba3f6`）。
  注：`TestBuildLedgerRepoGoldenScale` 依赖工作区 `impl/docs/conformance/status.tsv` 的最新落盘；
  干净检出 main 时该文件为旧版会红，属台账落盘节奏，与本卡代码无关。
- **下一步**：E5 按 `evidence/S2-E5-deinit/probes/` 同一组探针复签。

## E5 复签（2026-11-07，`beba3f6` 重放）：通过

- 复跑环境：干净 worktree `/tmp/e5-deinit-verify` @ `beba3f6`（根工作区当时处于 `7b907ba` 在途合并，`UU` 索引，不影响该提交树）。
- 结果：**5/5 PASS**
  - 用户 deinit 体先于字段释放：`replay-beba3f6-order.log`；
  - 类引用字段 retain/release：`replay-beba3f6-assign-c.txt`；
  - `h.a = h.a` 成员自赋值：同一日志（临时 + retain + release + 写回）；
  - handle 字段赋值/deinit 释放：`replay-beba3f6-hold-c.txt`；
  - Bytes 字段（单测口径）：`replay-beba3f6-tests.log`；端到端仍等 E2 `SEMA-BYTES`（`bytes-sema-block.log`）。
- 回归：`build_rt.sh` 六套件 exit 0（`replay-beba3f6-build_rt.log`）；E4 的 `TestS2*` 六例全 PASS。
- 结论：deinit 发射契约 E5 侧复签通过，无 E4 遗留阻断；容器字段赋值（B2）与 `Class?` 未支持按声明接受。
- 下一步：E2 的 `SEMA-BYTES` / 发布 self 检查；E5 待命。
