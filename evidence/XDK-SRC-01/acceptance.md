# XDK 源码层标准类实现（XDK-SRC-01）

- **日期**：2026-11-13
- **范围**：`impl/lib/xdk/{text,sys,net}.x` + `bindings/xdk/{sys_raw,net_raw}.xfb` +
  `impl/runtime/{rt_std_sys,rt_std_res,rt_std_net}.c` + 编译桥
  `tests/b4/xdk-bundle.py`、`tests/b4/xnull-build.sh`。
- **门**：B5 过渡（不改变 B4c golden 默认路径）。

## 1. 结论

XDK 源码层缺失的标准类按 S6 §4.7/§4.8 补齐，并有端到端用例：

| 包 | 类/API | 状态 |
| --- | --- | --- |
| `xdk.text` | `Format`、`parseInt/parseFloat`、`Regex`、UTF-8↔UTF-16（`Utf16`） | 可用 |
| `xdk.sys` | `File`（整文件文本）、`Dir`、`Process` | 可用 |
| `xdk.sys` | `resourceExists/resourceSize/readResource/readResourceText/listResources` | 可用 |
| `xdk.net` | `Socket`、`Request/Response`、`httpGet/httpPost` | 可用（文本形态） |
| `xdk.net` | `Listener` | 类与 `close()` 可用；`accept()` 显式 `Unsupported` |
| `xdk.errors` | 既有实现 | 不变 |
| `xdk.collections` | 既有实现 | 不变（仍由编译器内建面/源码单元提供） |

仍未覆盖：`TaskGroup`、`AtomicRef<T>`（需编译器发射面，B5）；`Mutex/Channel/
AtomicInt/AtomicBool/Context/Task` 继续由编译器内建面提供。

## 2. 验证

```text
bash tests/s6/xdk-source/run.sh
PASS text
PASS sys_file
PASS resources
PASS net_http
XDK 源码层：PASS=4 FAIL=0

bin/xnull --bootstrap examples
PASS=9 FAIL=0（C 与 golden 一致）
```

日志：`e2e.log`、`examples.log`。

## 3. 设计要点

1. **按需编译源码层**：`XNULL_XDK_SOURCE=1` 时 `xdk-bundle.py` 生成 AST bundle，
   单元真正参与编译；默认关闭，B4c golden 不受影响。
2. **raw 绑定桥**：产品编译器的 FFI 调用面尚不支持 Bytes 借出与 errorCode 出参，
   且混合绑定集会错位参数。`sys_raw.xfb`/`net_raw.xfb` 把句柄收敛为 Int64，
   参数只用 String/标量；资源字节用 hex 桥保证二进制安全。
3. **固定 bundle 布局**：编译器的 FFI 原型发射与 bundle 文件数相关；恒定包含
   7 个 XDK 单元 + 入口，避免随 import 变化而错位。
4. **静态方法限制**：`File.openRead(...)` 形式当前会被原样发射，因此工厂以顶层
   函数提供（`openFileRead` 等）；类内静态方法保留待 B5。
5. **`readFileText` 兼容**：编译器对 `readFileText` 有 K-07 专用发射（调用点丢参），
   实现拆到 `readFileTextImpl`，保留同名入口供自举使用。

## 4. 文件清单

- `bindings/xdk/sys_raw.xfb`（新增）
- `bindings/xdk/net_raw.xfb`（新增）
- `impl/lib/xdk/sys.x`（重写：File/Dir/Process + 资源）
- `impl/lib/xdk/net.x`（重写：Socket/HTTP；Listener 显式 Unsupported）
- `impl/lib/xdk/text.x`（追加顶层工厂 `formatInt/.../regexCompile`、`Utf16`）
- `impl/runtime/rt_std_sys.c`（raw 桥：文件文本/目录 id 表/进程）
- `impl/runtime/rt_std_res.c`（资源 hex 桥 + 文本桥）
- `impl/runtime/rt_std_net.c`（socket/HTTP 文本桥）
- `tests/b4/xdk-bundle.py`（新增编译桥）
- `tests/b4/xnull-build.sh`（`XNULL_XDK_SOURCE` / `XNULL_RESOURCES`）
- `tests/s6/xdk-source/`（4 组 E2E + README）

## 5. IO 收口（2026-11-13 追加）

用户追问“IO 写完了吗”后补齐：

| 能力 | 实现 |
| --- | --- |
| 二进制文件读 | `File.read/readAll`（hex 桥解码，NUL 安全） |
| 二进制文件写 | `File.write(Bytes)`、`openFileAppend`（上限 1 MiB/次） |
| 文本文件 | `readText/writeText/writeLine` |
| 定位/尺寸 | `seek/position/size` |
| 文件系统 | `fileExists/removeFile/renameFile/copyFile/makeDir/removeDir` |
| 目录 | `Dir.entries()` |
| 进制 | `Path`（isAbsolute/name/parent/ext）+ `pathJoin` |
| 进程输出 | `runProcessResult`（stdout + 退出码） |
| 二进制 socket | `Socket.sendBytes/recvBytes` |

验证（`e2e-v2.log`）：

```text
PASS text
PASS sys_file
PASS io_binary
PASS resources
PASS net_http
PASS net_socket
XDK 源码层：PASS=6 FAIL=0
B4c-02a bootstrap examples：PASS=9 FAIL=0（examples-v2.log）
```

新增/修改：

- `impl/lib/xdk/sys.x`：File 直接落盘模型、文件系统操作、`Path`、`ProcessResult`。
- `impl/lib/xdk/sys_res.x`（新）：资源 API 子单元（规避原生 xparser 深嵌套解析退化）。
- `impl/lib/xdk/net.x`：`sendBytes/recvBytes` + hex 辅助。
- `bindings/xdk/{sys_raw,net_raw}.xfb`：二进制/文件/进程输出条目。
- `impl/runtime/{rt_std_sys,rt_std_net}.c`：hex 编解码、文件操作、popen 输出、二进制 socket。
- `tests/b4/xdk-ffi-fix.py`（新）：修复冻结编译器 FFI 参数错位（按投影重建签名的
  原生原型/包装器/调用参数）。
- `tests/s6/xdk-source/`：新增 `io_binary`、`net_socket`。

限制：单次二进制写/发送 1 MiB；`Listener.accept` 未接入；`TaskGroup`/`AtomicRef`
仍待 B5 编译面。

## 6. B4c golden 兼容

完整实现放在 `impl/lib/xdk/{sys,net,text}_full.x`，默认构建继续使用 `sys.x/net.x/
text.x` 的冻结面；raw 绑定移到 `xdk-raw/`（不进入默认 `bindings/` 投影）。
`verify-golden` 复跑：**142/97/9 全绿，FAIL=0**。
