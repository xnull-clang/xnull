# S6-09（E5）：xdk.net 运行时（socket plain/Async + net.http 最小面）

- 卡片：S6-09（ADR-009；S6 §4.7 / XDK-09）
- 基线：`pod/e5-runtime`（S8-07 之后）
- 结论：新增 `rt_std_net.c`（socket plain/Async、HTTP 请求/响应/状态码）+
  `bindings/xdk/net.xfb`；错误码/close 合同/内部测试落地

## 先红

基线未实现 net 时，`test_net.c` 链接失败：
`_xdkc_socket_connect/send/recv/close` 等未定义（`red.log`）。

## 实现

### `impl/runtime/rt_std_net.c`

- **socket plain**：
  - `xdkc_socket_connect(host,len,port,&code)` → `void*`（getaddrinfo + connect）
  - `xdkc_socket_send/recv(sock,buf,n,&code)` → 字节数 / -1
  - `xdkc_socket_close(sock)` → 0（句柄层保证幂等）
- **socket Async（Context 首参，可取消）**：
  - `xdkc_socket_connect_async` / `send_async` / `recv_async`
  - 非阻塞 fd + `poll` 5ms 轮询 `xrt_context_check_cancel`；取消返回 `code=3`（Cancelled），
    不把缓冲区交给后台线程（无 UAF/悬挂写）。
- **net.http 最小面**：
  - `xdkc_http_request(method,host,port,path,body,&code)` → 响应对象
  - `xdkc_http_request_async(ctx,...)`
  - `xdkc_http_status(resp)`、`xdkc_http_body(resp,&len)`、`xdkc_http_body_text(resp)`、
    `xdkc_http_response_close(resp)`
  - HTTP/1.1，`Connection: close`，解析状态行与 body。
- **错误码**（与 `errorMap` 对齐）：
  `0 ok / 1 InvalidArgument / 2 Io / 3 Cancelled / 4 Timeout / 5 Unavailable`。

### `bindings/xdk/net.xfb`

- `handle Socket { close = socketClose }`、`handle HttpResponse { close = httpResponseClose }`
- plain：`socketConnect/socketSend/socketRecv/socketClose`、
  `httpRequest/httpStatus/httpBodyText/httpResponseClose`
- `errorMap` 1..5 → ErrorKind；全部入口有 `@blocking`。
- Async 形态（Context 首参）由 codegen 内建发射面接 `xdkc_*_async`（运行时已就绪）。

### 构建/测试

- `impl/internal/codegen/build.go` 的 `runtimeCSources` 纳入 `rt_std_net.c`；
  `build_test`/FFI 测试源清单同步。
- `impl/runtime/build_rt.sh` 新增 `test_net` 套件。
- `test_net.c`：本地回环 TCP/HTTP 服务；覆盖 plain/Async、取消、错误码、
  句柄 close 幂等、HTTP 200/body。
- `ffi/xdk_test.go` 入口清单与 `impl/docs/blocking-classification.md` 同步 net 8 项。

## 后绿

- `sh impl/runtime/build_rt.sh`：exit 0（含 `net tests passed ...`）。
- `go test ./internal/codegen/ffi -run 'TestXdkBindingsLoadAndEmit|TestBlockingClassificationDocInSync|TestXdkWrappersRun'`：PASS。
- 全量 `go test ./internal/codegen`：PASS。
- `go test ./internal/cli`：PASS；`go vet`：exit 0。

## 边界/后续

- **net.http 语言子包**：FFI 入口与 C 运行时已就绪；`xdk.net.http` 的 XNull 包装/
  `Context`/`Result` 发射属 E4/E2（`.xfb` 不能表达 Context/Result）。
- Async socket I/O 用 poll 轮询而非调度器挂起；可取消、不占后台线程，但占用当前载体
  （S5 调度器暂不支持挂起式 I/O）。后续可接非阻塞事件循环。
- HTTP 最小面只支持 HTTP/1.1 + `Connection: close`；不做 chunked/重定向/TLS。
- 资源关闭：Socket/HttpResponse 均由 `xrt_handle` 包装，close 显式、句柄层幂等；
  C 层 close 只应由 close_fn 调用一次。
- 顺手修复 main 合并残留：`impl/internal/cli/lock.go` 与 `manifest.go` 的
  `findManifestRoot` 重复声明解除（构建阻塞，非 net 语义）。
