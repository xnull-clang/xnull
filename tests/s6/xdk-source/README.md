# XDK 源码层 E2E（B5 过渡）

`impl/lib/xdk/*_full.x` 是 XDK 的完整源码层实现（过渡单元）。当前产品编译器把部分
XDK 类型硬编码在发射面，默认构建不加载这些单元；`XNULL_XDK_SOURCE=1` 才把它们编入
AST bundle。默认构建继续使用 `text.x/sys.x/net.x` 的冻结面，B4c golden 不受影响
（142 入口/97 负例/9 示例全绿）。

## 运行

```bash
bootstrap/build.sh                 # 只需 cc
bash tests/s6/xdk-source/run.sh    # 6 组用例
```

## 覆盖

| 用例 | 覆盖 |
| --- | --- |
| `text.x` | `Format`、`parseInt/parseFloat`、`Regex`、UTF-8↔UTF-16 |
| `sys_file.x` | `File` 文本读写、`Dir` 迭代、`Process`/`runProcess` |
| `io_binary.x` | `File` 二进制读写/追加/seek/size、`fileExists/removeFile/renameFile/copyFile`、`makeDir/removeDir`、`Path`、`runProcessResult` |
| `resources.x` | `resourceExists/resourceSize/readResource/readResourceText/listResources` |
| `net_http.x` | `httpGet`、URL 解析、错误面 |
| `net_socket.x` | `Socket.sendBytes/recvBytes` 二进制回显 |

## IO 能力

- **File**：`openFileRead/openFileWrite/openFileAppend`；`read/readAll/readText`、
  `write(Bytes)/writeText/writeLine`、`seek/position/size/close`。
- **文件系统**：`fileExists/removeFile/renameFile/copyFile/makeDir/removeDir`。
- **目录**：`Dir.next()/entries()/close()`。
- **进程**：`spawnProcess`（句柄）、`runProcess`（退出码）、`runProcessResult`
  （stdout + 退出码）。
- **Socket**：`send/recv`（文本）+ `sendBytes/recvBytes`（二进制）。
- **Path**：`isAbsolute/name/parent/ext`、`pathJoin`。

## 实现口径与限制

- 二进制经 **hex 桥**传输；单次 `write`/`sendBytes` 上限 **1 MiB**（逐字节编码），
  超过返回 `Unsupported`。读路径无此限制（受运行时 64 MiB 文件上限约束）。
- `readText` 对二进制文件按 C 字符串语义读到首个 NUL；读二进制请用 `readAll/read`。
- **net**：`Listener` 只有类与 `close()`；运行时尚未接入 listen/accept，
  `accept()` 返回 `Unsupported`，不伪造成功。
- **工厂函数是顶层函数**：`openFileRead/openFileWrite/openFileAppend/openDir/
  spawnProcess/connectSocket/httpGet/httpPost`。产品编译器尚不支持类静态方法调用
  （`File.openRead(...)` 会原样发射），类内保留的 `static` 方法待 B5 修复后启用。
- `readFileText` 保留给编译器 K-07 自举入口；实现走 `readFileTextImpl`
  （编译器对该名字有专用发射，直接写 FFI 调用会丢参）。
- **FFI 只用 raw 桥**：`xdk-raw/sys_raw.xfb` / `net_raw.xfb`（不放在 `bindings/`，
  避免改变默认投影与 golden）。
  冻结编译器在部分 bundle 组合下会清空 FFI 参数；`tests/b4/xdk-ffi-fix.py`
  按投影重建签名/原型/调用参数（只作用于 raw 包装器）。
- **bundle 布局固定**：`tests/b4/xdk-bundle.py` 恒定包含
  runtime/errors/text/sys/sys_res/net/tasks/sync + 入口。
- `sys.x` 与 `sys_res.x` 拆分的唯一原因是原生 xparser 对深嵌套资源函数有解析退化；
  语义与包边界不变。

## 仍未覆盖（B5）

- `xdk.tasks` 的 `TaskGroup`、`xdk.sync` 的 `AtomicRef<T>`：需要编译器发射面支持
  （当前 `Context/Task/Mutex/Channel/AtomicInt/AtomicBool` 由内建面提供）。
- `xdk.sync`/`xdk.tasks` 源码单元保持骨架；源码实现会与内建类型映射冲突。
- `Listener.accept`（运行时 listen/accept）；取消与挂起语义（调度器切片）。
