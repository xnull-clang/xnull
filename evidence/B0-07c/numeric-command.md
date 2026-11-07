# B0-06 numeric 变体复跑命令（E4 codegen + E5 runtime 修复）

基线：`pod/e4-codegen` = `0d8c985`（已含 main + B1 formatter）；运行时侧套用 `pod/e5-runtime` 的 `xrt_abi.c`（handle_deinit 修复）。

```bash
cd /Users/vjs/Desktop/XNull-Lang

# 1) 取 E4 当前分支的临时工作树（只读验证，不提交）
git worktree remove --force /tmp/e5-b0-07c-check 2>/dev/null
git worktree add --detach /tmp/e5-b0-07c-check 0d8c985

# 2) 套用 E5 运行时修复
cp wt/e5-runtime/impl/runtime/xrt_abi.c /tmp/e5-b0-07c-check/impl/runtime/xrt_abi.c

# 3) 构建 xnull
(cd /tmp/e5-b0-07c-check/impl && go build -o /tmp/xnull-e5check ./cmd/xnull)

# 4) 跑 B0-06 numeric 变体（in1.x / in2.x）
bash wt/qa-1/evidence/M6-B0-06/run.sh \
  --root /tmp/e5-b0-07c-check --bin /tmp/xnull-e5check
```

实测（2026-11-07 14:07）：exit 1，`PASS=0 FAIL=2`，日志 `evidence/B0-07c/numeric-after.log`
（sha256 `58f1caab955a30a62b6c576b028168835692b88236a3a2096f1b227b825cb725`）。

剩余阻塞（均非 E5 域）：`Bytes` 类型面（RES-101）、`fileRead/fileWrite` 的 `@errorCode`→Result（codegen 提示）、`File?`→`File`（TY-101）。
