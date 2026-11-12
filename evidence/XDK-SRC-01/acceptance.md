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
