# 回执-FIX-E2-INT64

**状态：DONE**

1. **合并**：`main=9f5f66c` 已合入 `pod/e2-sema`（无冲突）。
2. **修复**：`impl/internal/sema/ty.go` 一元负号仅允许 `2^63 → MinInt64`；`|literal| > 2^63` 与 `-MinInt64` 标记 `intBad`，范围检查拒绝，不再补码回绕。
3. **用例**：新增 Int64 负向越界赋值/比较负例；`-9223372036854775808` 正例保持。
4. **复测**：`go test ./internal/sema/` exit 0；`go test ./... -count=1 -timeout 300s` exit 0。
5. **证据**：`evidence/FIX-E2-INT64/`；未 push、未合 main。

## 边界

- 只改 sema/ty.go 与对应测试，未改其他域。
