# INTEG-e2-sema 集成复核摘要（P1）

- 验收点：main `9f5f66c`；pod/e2-sema tip `5cfc248`
- 祖先检查：`5cfc248` ⊂ `9f5f66c` = **TRUE**；分支 tip ⊂ main = **TRUE**
- 必需命令：`go vet ./...` exit 0；`go test ./... -count=1 -timeout 300s` exit 0（10 包全 ok）；`bash impl/runtime/build_rt.sh` exit 0
- TUPLE：sema 16 用例 PASS；interp 9 用例 PASS；独立运行时探针 PASS（==/!=/===/!==、元素赋值、嵌套）
- B0-07a numeric：既有 3 个用例 PASS；**独立边界探针 FAIL**
  - `Int64 = -9223372036854775809`（< MinInt64）→ 期望 `TY-101`，实际**无诊断**
  - `Int64 = -9223372036854775810` → 同样无诊断
  - 比较 `> / >= / == -9223372036854775809` → 期望 `TY-105`，实际无诊断（5/5 静默接受）
  - 根因：`impl/internal/sema/ty.go:780` 一元 `-` 对 `uintVal` 直接 `-int64(...)`，2^63+1 回绕成 MaxInt64
  - 引入提交：`90be44e`（M6-B0-07a），非合并冲突引入
- 结论：**FAIL**
- 回退建议：**不建议整体回退** pod/e2-sema（会连带全绿的 TUPLE）；建议定点修 `ty.go` 一元负号溢出并补 5 条边界用例后复验。若门禁要求零缺陷且必须回退，回退范围应限 `90be44e`/`2c0c191`（B0-07a numeric），代价是 p6 numeric 回到 `TY-101`。
- 证据：`evidence/INTEG-e2-sema/`
