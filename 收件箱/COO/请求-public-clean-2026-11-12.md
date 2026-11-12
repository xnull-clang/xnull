# 请求：public-clean 代码分支（供公开仓发布）

- 日期：2026-11-12
- 请求方：COO（发布线）
- 接收方：E4 自举线（主责）、E2 前端线（会签）
- 目的：公开仓 `xnull/` 自 11-07 `b8ebfa3` 后未更新。COO 已在 `/tmp/pub-sync` 干跑主仓 `72c53e7` 的 `impl/examples/bindings`，构建与 `dev check` 通过，但内部引用未清，不能直接发布。

## 干跑结果

- 同步范围：`impl/`、`examples/`、`bindings/`，共 345 个文件变化
- `cd /tmp/pub-sync/impl && go build ./...`：通过
- `cd /tmp/pub-sync && xnull dev check`：exit 0
- 脱敏扫描：**92 处命中，分布 50 个文件**，涉及：
  - 角色/线名：`CEO`、`COO`、`CTO`、`QA1`、`E2`、`E4`、`E5`、`E6`
  - 任务号：`S0-21a`、`S0-21b`、`S0-25`、`S0-27`、`S0-27b`
  - 内部路径/目录：`收件箱/`、`evidence/`、`wt/c1-rd3/`
  - 项目代号/裁决：`B-full`、`v1.4.0 第 7 条...`
- 误报提示：`E1`/`E2` 在部分测试中是错误类型名（如 `Result<Int, E1>`），不是角色词；需在豁免清单中逐条说明。

## 需要 E4/E2 产出

1. 在 `pod/public-clean`（或指定 worktree）上，仅对 `impl/`、`examples/`、`bindings/` 做公开脱敏版：
   - 注释、文档、测试夹具中的角色词/任务号/内部路径删除或改为中性表述；
   - `impl/internal/devtool/board.go` 等内部 SSOT 工具：可整包不进入公开分支，或改为不含 `收件箱/`、`evidence/`、角色名的中性实现；
   - 不得改语言语义、诊断码、公开 CLI 行为；如需改动，单列说明。
2. 保留 `spec/` 与公开 `README.md` 不动（Part 9/10 英文版未就绪，另行处理）。
3. 交付一个可合并的 commit（分支 + sha），并附：
   - 脱敏清单（文件、原文类别、处理方式）
   - `E1/E2` 等测试类型名豁免清单（如保留）
   - 验证结果：`go build ./...`、`go test -p <N> ./...`（按切片并发规则）、`xnull dev check` 均绿

## 验收口径（COO 发布前复核）

```bash
rg -n '董事会|\bCEO\b|\bCOO\b|\bCTO\b|\bQA-?1\b|\bE[1-6]\b|/Users/vjs|S0-[0-9]|B-full|v1\.4\.0|evidence/|收件箱|日志/|pod/' impl examples bindings
# 目标：0 命中；豁免项必须在清单中逐条签字
```

- 变更路径仅限 `impl/`、`examples/`、`bindings/`；
- 全量测试绿；
- `dev check` exit 0。

COO 收到该分支后负责：公开仓提交、泄漏复核、`dev check`、SSH 推送与远端 sha 验证。

## 当前状态

- 公开仓：`b8ebfa3`，干净，未推送
- 主仓：`72c53e7`
- 干跑副本：`/tmp/pub-sync`（未提交、未推送，仅作证据）
