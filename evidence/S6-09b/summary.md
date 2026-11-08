# S6-09b（E5）：XDK-09 net 运行时链接补口

- 卡片：XDK-09b（QA FAIL：net 运行时缺 `xdkc_socket_*` / `xrt_bytes_from_c`，`build_rt.sh` exit 1）
- 基线：main `4adbce3`（E4 net 绑定/发射 + E5 net 运行时的合并点）
- 结论：`build_rt.sh` 转绿；补兼容 C 符号；测试对齐 E4 的 `xdkc_net_*`/`xdkc_http_*` API

## 先红

main `4adbce3` 上 `sh impl/runtime/build_rt.sh` 链接失败：
`_xdkc_socket_connect/send/recv/close`、`_xdkc_http_request/status/body/...`、
`_xrt_bytes_from_c` 未定义（`red.log`）。

根因：
1. `test_net.c` 仍引用 E5 早期 C 名 `xdkc_socket_*`/`xdkc_http_request_*`；
   E4 绑定面使用 `xdkc_net_*`/`xdkc_http_get|post`。
2. `test_net` 链接未包含 `rt_std_bytes.c`，而 `rt_std_net.c` 的 HTTP 返回
   `xrt_bytes_from_c`。
3. main 合并后 `findManifestRoot` 缺失，导致 `go run ./cmd/xnull dev res`
   （build_rt 资源表步骤）无法编译。

## 修复（仅 runtime/构建夹具）

- `impl/runtime/build_rt.sh`：`test_net` 链接加入 `rt_std_bytes.c`，闭合
  `xrt_bytes_from_c`。
- `impl/runtime/test_net.c`：改用 E4 绑定面的 C 名
  `xdkc_net_connect/read/write/close`、`xdkc_http_get/post`；
  覆盖 plain socket、句柄 close 幂等、错误码、HTTP 200/404/POST。
- `impl/runtime/rt_std_net.c`：追加 `xdkc_socket_*` 兼容别名
  （`connect/send/recv/close` 及 Async 变体），旧测试/绑定不再缺符号；
  Async 别名调用前检查 Context。
- `impl/internal/cli/lock.go`：补回 `findManifestRoot`（构建夹具编译阻塞），
  不改 net 语义。

## 后绿

- `sh impl/runtime/build_rt.sh`：全套 exit 0（`green-build_rt.log`）。
- `test_net`：`socket plain/close + http get/post/status` PASS（`green-net.log`）。
- `go test ./internal/codegen/ffi`：PASS（`green-ffi.log`）。
- `TestBuildCCArgsIncludesRuntimeABIAndStd`：PASS（`green-buildtest.log`）。
- `go test ./internal/cli`：PASS（`green-cli.log`）。

## 透明项

main 上 `TestS609HTTPGetAsync` / `TestS609*` 仍失败：
`codegen：返回表达式 *xfront.Member 未支持（M4.1 范围）`（E4 net 发射面，非本卡）。
本卡只修 runtime 链接/build_rt，不改 codegen。

## 边界

- 兼容别名只是链接面；E4 绑定仍走 `xdkc_net_*`。
- Async 别名的取消是调用前检查；真正的调度器取消由 E4 codegen 调用点负责。
- HTTP 状态码由 `xdkc_http_get/post` 内部映射：非 2xx 返回 NULL + code（404→NotFound）。
