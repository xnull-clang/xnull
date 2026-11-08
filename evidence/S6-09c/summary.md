# S6-09c（E5）：XDK-09 精确符号链接补口

- 卡片：XDK-09c（main 上 `build_rt.sh` 链接缺 `xdkc_net_*`、`xdkc_http_get/post`）
- 基线：main `c446056`（复验点）
- 结论：补齐 codegen 绑定面引用的 C 符号；`build_rt.sh` exit 0

## 先红

main `c446056` 上 `sh impl/runtime/build_rt.sh` 链接失败：
`_xdkc_net_connect`、`_xdkc_net_read`、`_xdkc_net_write`、`_xdkc_net_close`、
`_xdkc_http_get`、`_xdkc_http_post` 未定义（`red.log`）。
`xrt_bytes_from_c` 已由 `build_rt.sh` 链接 `rt_std_bytes.c` 闭合。

## 修复（仅 runtime + 分类表）

- `impl/runtime/rt_std_net.c` 追加别名/包装：
  - `xdkc_net_connect` → `xdkc_socket_connect`
  - `xdkc_net_read` → `xdkc_socket_recv`
  - `xdkc_net_write` → `xdkc_socket_send`（返回 code 语义）
  - `xdkc_net_close` → `xdkc_socket_close`
  - `xdkc_http_get` / `xdkc_http_post`：解析 `http://host[:port]/path`，
    调用既有 `xdkc_http_request`，2xx 返回 `Bytes`；404 → code=3，其它非 2xx → code=2。
- `impl/docs/blocking-classification.md`：按 main 的 net 绑定入口
  （socketConnect/Listen/Accept/Read/Write/Close、listenerClose、httpGetPlain/httpPostPlain）
  更新分类行，`TestBlockingClassificationDocInSync` 恢复。

## 后绿

- `sh impl/runtime/build_rt.sh`：exit 0（`green-build_rt.log`）。
- `test_net`：`net tests passed (socket plain/close + http get/post/status)`。
- `go test ./internal/codegen/ffi -run 'TestXdkBindingsLoadAndEmit|TestBlockingClassificationDocInSync|TestS609'`：PASS。
- `TestBuildCCArgsIncludesRuntimeABIAndStd`：PASS。

## 透明项

- `go test ./internal/codegen/ffi` 全量仍有 `rt_string_from_c`/`rt_string` 相关失败；
  属 E4 发射面/头文件命名（非 net 链接），不在本卡范围。
- 本卡不新增 `xdkc_net_listen/accept` 实现；main 的 net.xfb 若链接这两项需后续补
  （当前 `build_rt.sh` 与 `test_net` 不引用）。
