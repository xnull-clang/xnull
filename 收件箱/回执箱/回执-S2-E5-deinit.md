# 回执：S2-E5-deinit（E4 deinit 发射契约的运行时侧验证）

- 卡片：S2-E5-deinit（验证）；被验交付：E4 `pod/e4-codegen@70f4385`，main 上的 handoff `a75226a`
- 基线：`main=f975810`
- 结论：**契约在 70f4385 成立；main 未合入该提交，三项中两项在 main 不成立**
- 证据：`evidence/S2-E5-deinit/`（summary + 7 份原始日志 + 4 个探针）
- 未改 E4 代码；E5 只写验证证据

## 逐项

| # | 契约点 | main f975810 | 70f4385 |
|---|---|---|---|
| 1 | 用户 deinit 体先执行，字段释放后执行 | **PASS** | **PASS** |
| 2 | 引用字段赋值 retain 新值 / release 旧值 | **FAIL**（裸赋值） | **PASS** |
| 3 | handle/Bytes 字段释放 | **FAIL**（Holder deinit 空体） | **PASS（handle）**；Bytes 由单测覆盖（sema 仍阻断） |
| 4 | 置 null/别名安全 | N/A（可空类字段未支持） | 部分：`h.a = h.a` 被拒；Ident 别名可用 |
| 5 | deinit 发布 self 检查 | 归 E2 | 归 E2 |

## 阻断项（需要 E4 处理）

1. **main 未包含 70f4385**（`git merge-base --is-ancestor 70f4385 main` = NO）；main 的 deinit 来自 `81e146e`，只实现「用户体先执行」。
2. 70f4385 落后 main 32 个提交，且与 81e146e 同改 `classes.go`/`classes_expr.go`/`codegen.go` → 直接合入必冲突。请以 main 为基重放增量（字段赋值 retain/release + handle/Bytes 字段释放），并带上 E5 `c1ffd20`（弱槽修复）。
3. 两处偏离 E5 确认**可接受**：容器字段赋值显式报错（B2 引用语义容器再解）；继承/`super.deinit()` 去重待继承卡。
4. 小缺口：成员表达式自赋值 `h.a = h.a` 被拒；若契约声称「安全」应改为接受（或把文档口径改为「Ident 别名安全」）。

## 复现

```bash
# main
cd impl && go build -o /tmp/xnull-main-f975 ./cmd/xnull
XNULL_RUNTIME=<repo>/impl/runtime /tmp/xnull-main-f975 build order.x -o order && ./order
# 70f4385
git worktree add --detach /tmp/e4-deinit 70f4385
cd /tmp/e4-deinit/impl && go test ./internal/codegen/ -run 'TestS2Deinit|TestS2FieldAssign' -count=1 -v
```

## 下一步

- E4：以 main 为基重放 70f4385 增量；完成后通知 E5 复跑本回执的 3 个探针。
- E5：main 合入后复跑 `evidence/S2-E5-deinit/` 探针并回签；不在本卡改 codegen。
- E2：`SEMA-BYTES` 落地后补 Bytes 字段端到端；`deinit` 发布 self 的静态检查。
