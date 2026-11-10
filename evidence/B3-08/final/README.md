# B3-08 最终证据（2026-11-09）

- 判定提交：`d933dde`（main，合入 pod/e2-sema@76fd1f9）
- 范围：`收件箱/门/B3-08范围-v1.0.0.md`
- xnullc：`impl/lib/b3/xnullc.x`（C.1–C.9b emitter 重构后）

## 1. text 逐字节

`tests/b3/fixtures/bundle_text/app.x`：

```text
go_bytes:   109514
xn_bytes:   109514
diff_lines: 0
determinism: SAME（两次生成）
go_sha256: 8040680868f54df07992ec1e2e90effd7b84f06d66254035235806c745d3884b
xn_sha256: 8040680868f54df07992ec1e2e90effd7b84f06d66254035235806c745d3884b
```

详见 `text-hash.txt`。

## 2. 门禁组

`groups.log`（冻结 76fd1f9 快照，逐组）：

```text
xnullc-bundle  PASS=4 FAIL=0（旧脚本仍打印 text=KNOWN-DIFF；main 新脚本见 bundle.log）
xnullc-ffi     PASS=5 FAIL=0
xnullc-mem     PASS=11 FAIL=0
xnullc-err     PASS=5 FAIL=0
xnullc-obj     PASS=4 FAIL=0
xnullc-obj2    PASS=5 FAIL=0
xnullc-obj3    PASS=5 FAIL=0
xnullc-containers PASS=5 FAIL=0
xnullc-expr-stmt PASS=6 FAIL=0
xnullc-gen     PASS=3 FAIL=0
xnullc-tuple   PASS=5 FAIL=0
xnullc-type    PASS=2 FAIL=0
```

`bundle.log`（main `d933dde`，新脚本要求 text cmp 0）：

```text
PASS bundle_sync
PASS bundle_tasks
PASS bundle_collections
PASS bundle_text
xnullc-bundle 汇总：PASS=4 FAIL=0
```

## 3. 复现

```bash
cd /Users/vjs/Desktop/XNull-Lang
bash tests/b3/xnullc-bundle.sh
XNULLC_FILE=impl/lib/b3/xnullc.x bash tests/b3/xnullc-mem.sh
# 其余组同 tests/b3/xnullc-*.sh
```

## 4. 备注

- 旧 `groups.log` 中的 bundle 行由合并前的旧脚本产生；`bundle.log` 是
  main 新脚本（`run_case text pass`）的结果，text 已纳入 0 diff 断言。
- `internal/codegen` 的 `go test ./...` 单包会 300s 超时；门禁用
  `xnull dev test --parallel 4 ./internal/codegen`（4/4 shard 绿）。
