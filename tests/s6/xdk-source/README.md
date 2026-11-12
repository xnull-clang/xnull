# XDK 源码层 E2E（B5 过渡）

`impl/lib/xdk/*.x` 是 XDK 的公开 API 源码层。当前产品编译器把部分 XDK 类型硬编码在
发射面，源码单元默认不参与用户程序编译；`XNULL_XDK_SOURCE=1` 打开"按需编译源码层"
过渡模式（B5 之前的桥），让单元真正进入 AST bundle。

## 运行

```bash
bootstrap/build.sh                 # 只需 cc
bash tests/s6/xdk-source/run.sh    # 4 组用例
```

## 覆盖

| 用例 | 覆盖 |
| --- | --- |
| `text.x` | `Format`、`parseInt/parseFloat`、`Regex`、UTF-8↔UTF-16 |
| `sys_file.x` | `File` 整文件读写、`Dir` 迭代、`Process`/`runProcess` |
| `resources.x` | `resourceExists/resourceSize/readResource/readResourceText/listResources` |
| `net_http.x` | `httpGet`、URL 解析、错误面 |

## 实现口径与限制

- **文件是整文件文本模型**：`openFileRead` 一次读入（64 MiB 上限），
  `openFileWrite` 缓冲到 `close()` 落盘；不提供二进制流句柄。
- **net 首版是文本形态**：`Socket.send/recv` 与 HTTP body 以 String 传输；
  二进制传输待 B5 的 Bytes 借出面接通。
- **Listener** 只有类与 `close()`；运行时尚未接入 listen/accept，`accept()` 返回
  `Unsupported`，不伪造成功。
- **工厂函数是顶层函数**：`openFileRead/openFileWrite/openDir/spawnProcess/
  connectSocket/httpGet`。产品编译器尚不支持类静态方法调用（`File.openRead(...)`
  会原样发射），类内保留的 `static` 方法待 B5 修复后启用。
- `readFileText` 保留给编译器 K-07 自举入口；实现走 `readFileTextImpl`
  （编译器对该名字有专用发射，直接写 FFI 调用会丢参）。
- **FFI 只用 raw 桥**：`bindings/xdk/sys_raw.xfb` / `net_raw.xfb`。
  冻结编译器在混合绑定集下会错位 FFI 原型参数，raw-only 集通过全部四组 E2E。
- **bundle 布局固定**：`tests/b4/xdk-bundle.py` 恒定包含
  runtime/errors/text/sys/net/tasks/sync + 入口；文件数变化同样会触发上述错位。

## 仍未覆盖（B5）

- `xdk.tasks` 的 `TaskGroup`、`xdk.sync` 的 `AtomicRef<T>`：需要编译器发射面支持
  （当前 `Context/Task/Mutex/Channel/AtomicInt/AtomicBool` 由内建面提供）。
- `xdk.sync`/`xdk.tasks` 源码单元保持骨架；源码实现会与内建类型映射冲突。
- 二进制文件/网络流、取消与挂起语义（调度器切片）。
