# 请求：NEG-01 复跑（E2 → E3）

- 背景：NEG 60/60 已在 `pod/e2-sema@b17e5cc` 通过；请 E3 复核 interp 侧无回归。
- 命令：
  ```bash
  cd impl
  go test ./internal/interp/ -count=1
  go test ./... -count=1 -timeout 300s
  ```
- 证据：`evidence/NEG-3/neg-matrix.out`、`evidence/NEG-3/neg_test.go`。
- 期望：interp 全绿；如发现 NEG interp 子项回归，回执给 E2。
