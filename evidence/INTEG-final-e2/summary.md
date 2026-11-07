# INTEG-final-e2 最终复核摘要

- 验收树：`git archive f63fcba`
- e2-sema 集成：`49cbb27`（merge pod/e2-sema SYNCED 9848d06）；修复提交 `92ef021` 已在树内
- 全量门禁：`go vet ./...` 0；`go test ./... -count=1 -timeout 300s` 0（10 包 ok）；`build_rt.sh` 0
- Int64 负向越界 5 探针：**5/5 PASS**（assign min-1/min-2、cmp gt/ge/eq min-1 均报 `TY-101`/`TY-105`）
- numeric 其它边界（Int8/16/32、UInt8/32、正向上界、比较适配）：PASS
- TUPLE 回归：sema 13/13、interp 9/9、独立运行时探针 PASS
- 额外验证：`-MinInt64`（`-(−9223372036854775808)`）标记不可表示；`2^63` 仍正确映射 MinInt64
- 结论：**PASS**
- 未跑/边界：codegen 级 Int32/Int64（卡面未支持）；UInt64 `> 2^64-1` 解析边界未测；未跑覆盖率/变异
- 精确诊断码复核追加：`probe/probe-int64-exact-codes.out`（6/6，含 -18446744073709551615）
