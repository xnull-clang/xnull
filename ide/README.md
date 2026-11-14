# XNull IDE（第 10 部分）

本目录是第 10 部分 IDE 的实现区。

```
ide/
├── vscode/         方案 A：VS Code 扩展（TypeScript）
├── web/            单页 Web IDE（浏览器即开即用，零依赖后端）
├── xdk/            XDK 索引（供 IDE 消费）
└── desktop/        方案 C：独立工作台（后续）
```

## Web IDE（ide/web）

单页浏览器 IDE：`python3 ide/web/server.py [端口]`（默认 8765，仅监听 127.0.0.1）。
后端仅用 Python 3 标准库，封装仓库 CLI（`bin/xnull --bootstrap`）；前端内嵌 CodeMirror 5（`vendor/`，离线可用）。

- 工程：模板向导（6 种）、导入本机工程目录、多工程切换；
- 资源管理器：嵌套文件树，新建文件/文件夹、重命名、删除；
- 编辑器：XNull 语法高亮、关键字/类型/片段补全（⌃Space）、括号自动闭合、格式化；
- 生产力：快速打开（⌘P）、命令面板（⌘⇧P）、全局搜索（⌘⇧F）、自动保存、设置持久化；
- 诊断：构建/运行的编译错误解析为问题列表，点击跳转到出错行并在编辑器标记；
- 运行：工程聚合构建缺少 Go oracle 时自动回退入口文件单文件模式（输出中注明）。

工作区为 `ide/web/workspace/`，路径越界与非法工程名均被拒绝。

## 方案顺序

1. **A：VS Code 扩展**——当前实现；工程创建、编辑、标准库文档、检查、构建、运行、单文件二进制。
2. **B：XNull 语言服务**——B2/B3 后用 XNull 实现 LSP，TypeScript 客户端。
3. **C：独立工作台**——确有品牌桌面需求后，Monaco + Tauri/Electron。

## 依赖

- 第 9 部分 `xnull` CLI：`new` / `check --json` / `build --json` / `run`；
- 第 8 部分 XPD：工程文件；
- 第 6 部分 XDK：`ide/xdk/index.json` 的上游。

IDE 不实现编译器、构建系统或第二套语言服务。
