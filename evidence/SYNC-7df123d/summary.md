# SYNC main=7df123d

- 合并冲突：`impl/internal/sema/ty.go`、`impl/internal/interp/interp.go`。
- 解决原则：保留 main 的 ERR-01/可选提升/`identical`/泛型重载，叠加本分支 TUPLE-01、List.remove 返回 V、Int32/Int64 字面量适配。
- `go test ./... -count=1 -timeout 300s` → EXIT=0。
- 锚点矩阵：TUPLE-01（13+5 用例）、M6-B0-05 sema、M6-B0-07a numeric → 全 PASS。
- B0-06 numeric 变体（run.sh 不带 --text）→ **0/2**：先被 `RES-101 Bytes/file*`（sema XDK 符号表未含 sys/text FFI 面）阻断；codegen 另有 P-09 `File/Bytes/@errorCode` 与 `Int32/Int64` 未支持。非本次 merge 回归，main=7df123d 同样 0/2。
