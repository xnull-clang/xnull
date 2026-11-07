# FIX-E2-INT64 自检

- 基线：`main=9f5f66c`（已 fast-forward/merge 到 `pod/e2-sema`）
- 缺陷：一元负号对 `|literal| > 2^63` 的无符号字面量执行 `-int64(uintVal)`，发生补码回绕，`Int64 v = -9223372036854775809` 被误判合法。
- 修复：`texpr.intBad` 标记不可表达值；仅 `uintVal == 2^63` 允许转成 `MinInt64`，更大值标记越界；`-MinInt64` 同样标记越界；`intLiteralFits` 对 `intBad` 返回 false。
- 用例：新增 `-9223372036854775809`、`-18446744073709551615` 赋值负例，以及 `Int64 v > -9223372036854775809` 比较负例；既有 `-9223372036854775808` 正例保持 PASS。
- 结果：红 → 绿；`go test ./internal/sema/` exit 0；`go test ./... -count=1 -timeout 300s` exit 0。
- 未改既有测试期望；只改 `sema/ty.go` 与 `numeric_variant_test.go`。
