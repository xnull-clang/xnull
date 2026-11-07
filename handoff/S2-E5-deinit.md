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
- **last-green**：`f975810`（验证时为只读；`build_rt.sh` 六套件与 `go test ./internal/codegen/...` 均绿）
