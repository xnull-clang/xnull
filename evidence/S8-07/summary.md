# S8-07（E5）：link.libraries / unsafe 构建面

- 卡片：S8-07（S8 §7；S7 FFI 对齐）
- 基线：main `f26e0f9`
- 结论：读取 `link.libraries` 并接入构建链接参数；FFI 区域交叉校验；
  `link.unsafe=true` 启用即写构建日志

## 先红

`go test ./internal/codegen -run TestS807` 在实现前因
`readLinkLibraries`/`checkFFILibraries`/`mergeLinkArgs` 未定义失败（`red.log`）。

## 实现

- `impl/internal/codegen/link_manifest.go`：
  - `readLinkLibraries(root)`：解析 `project.link.libraries`，校验 `kind=static|dynamic`、
    `system=true|false`、库名非空/不重复、未知字段/块、非 app/library 非空 link。
  - `checkFFILibraries(reg, libs, has)`：`.xfb` 外部区域必须在 `link.libraries` 声明；
    `xdkc_*`/`xrt_*` 运行时内部区域豁免；无 `libraries` 块时跳过（bootstrap 兼容）。
  - `mergeLinkArgs`：清单库并入 `-L`/`-l`（去重升序，`-L` 在前）。
- `impl/internal/codegen/build.go`：构建时读取清单库、交叉校验、合并 `Options.LinkArgs`。
- `impl/internal/codegen/unsafe_gate.go`：`link.unsafe=true` 即使没有 `@unsafe` 入口
  也写 `xnull: link.unsafe=true（S8 §7）`；有入口时保留入口名日志。
- `impl/internal/codegen/s807_test.go`：库解析/非法库/交叉校验/合并参数/
  unsafe 无入口日志/manifest 静态库真实链接/未声明区域拒绝。

## 后绿

- `TestS807*` PASS（`green-s807.log`）。
- `TestS704*` 回归 PASS（`green-s704.log`）。
- 全量 `go test ./internal/codegen` PASS（`green-full-codegen.log`）。
- `go test ./internal/cli` PASS（`green-cli.log`）。
- `go vet ./internal/codegen` exit 0（`green-vet.log`）。

## 边界

- `kind`/`system` 已读取并校验，但打包复制/系统库策略属 S8-04；
  本卡只把 `-l<name>` 并入链接参数。
- FFI 交叉校验在存在 `libraries` 块时强制；无块时跳过，兼容尚无清单库的旧夹具。
- `xdkc_*`/`xrt_*` 为运行时内部区域，不要求 `link.libraries`。
