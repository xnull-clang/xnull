# 回执：S8-CLIFIX 编译去重（E4）

- 问题：main 合并 S8-03/S8-04 后 `findManifestRoot` 在
  `impl/internal/cli/manifest.go` 与 `impl/internal/cli/lock.go` 重复定义，
  `go build ./internal/cli` 失败。
- 处理：保留 `lock.go` 的 `findManifestRoot`（S8-03 先入 main），
  删除 `manifest.go` 中的同实现副本；两个调用方（清单构建、锁校验）共用一份。
- 验证：
  - `cd impl && go build ./...` → 通过；
  - `go test ./internal/cli -count=1` → ok。
- 无行为变更；S8-04 清单模式与 S8-03 锁命令均保持原调用路径。
