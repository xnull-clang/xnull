# PLAN（2026-11-15 起）

## 目标

最小的 XNull 端到端跑通：**一个文件、一个类、一次 XDK 调用、一条命令、精确输出**。
之后每级只加一个概念，按开发者第一小时的顺序向上长。

## 边界

| 进 | 不进 |
|---|---|
| 单文件、`package` 声明、`static Int main` | 多文件 / 工程 / 依赖解析 |
| 一个用户 class：`final` 字段 + 构造器 + 方法 + `self` | 泛型新特性、协议、继承、闭包、`defer` |
| `Int` / `String` / `Bool`、拼接、`print` | 并发、net、资源、构建系统、包管理、IDE |
| `import xdk.*` + 一次调用 | 第二个包（等当前级绿了再加） |

只用 S6 §2 的 8 个包：`errors` / `tasks` / `sync` / `runtime` / `collections` / `text` / `sys` / `net`。
`math` / `time` / `codec` / `util` / `compiler` / `build` 不是规范包，不许进 L0—L6。

## 梯子

以下为 2026-11-15 实测快照；状态以命令输出为准，不在文档里维护。

| 级 | 内容 | 证明什么 | 实测 |
|---|---|---|---|
| L0 | `print("hello")` | 编译 → 链接 → 运行 | 绿（3.0s） |
| L1 | 用户 class + 方法 | 对象模型 | 绿（2.1–2.4s） |
| L2 | `import xdk.errors` + `ErrorKind.NotFound` | 包隔离、命名空间（零原语） | 红 |
| L3 | `xdk.text.Format` builder | 库类与用户类走同一条编译路径 | 红 |
| L4 | `sys.fileExists(path)` | 第一个原语：绑定 / 租约 / 错误码 | 红 |
| L5 | `parseInt("x")` | 第一条可读的错误路径 | 红 |
| L6 | `errors.report` | 包间依赖边 | 红 |

## 每级验收

1. `dx/LN-*.x` 与 `dx/LN-*.out` 逐字节一致，exit 0；
2. 冷跑 ≤3 秒；
3. 负例：缺符号 / 类型错 → `file:line:col`，≤2 秒，exit 1；
4. 全程无 `fatal:`，无 Go。

## 当前红在哪（2026-11-15 实测）

探针用的是 `import xdk.math`——它不是 S6 包，只用来测工具链；机制与 L2 相同：任何 `xdk.*` 都会触发全量打包。

- `import xdk.math` + `PI()`：120 秒不返回。
- bundle 把 12 个包单元、14 个文件全部打包，解析 13.7 秒。
- 手动裁到 `Math.x` + 入口：`xn-s4` 4.5 秒编完（72KB C）。
- 全量 bundle：`xn-s4` 约 50 秒后 `fatal: 容器下标越界`，无行列。

## 下一刀

**包级导入隔离**：`import xdk.x` 只解析 `x` 一个包单元。

- 包内死代码也要裁：`Math.x` 的随机数把 `ext_raw` 拖进链接。
- 包从 30 行起步、按需追加；不从 1,500 行的 `Text.x` 往下删。

## 不做

看板、锚点、门、回执、`evidence/`、一致性台账、进度百分比。
