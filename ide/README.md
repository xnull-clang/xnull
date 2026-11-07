# XNull IDE（第 10 部分）

本目录是第 10 部分 IDE 的实现区。

```
ide/
├── vscode/         方案 A：VS Code 扩展（TypeScript）
├── xdk/            XDK 索引（供 IDE 消费）
└── desktop/        方案 C：独立工作台（后续）
```

## 方案顺序

1. **A：VS Code 扩展**——当前实现；工程创建、编辑、标准库文档、检查、构建、运行、单文件二进制。
2. **B：XNull 语言服务**——B2/B3 后用 XNull 实现 LSP，TypeScript 客户端。
3. **C：独立工作台**——确有品牌桌面需求后，Monaco + Tauri/Electron。

## 依赖

- 第 9 部分 `xnull` CLI：`new` / `check --json` / `build --json` / `run`；
- 第 8 部分 XPD：工程文件；
- 第 6 部分 XDK：`ide/xdk/index.json` 的上游。

IDE 不实现编译器、构建系统或第二套语言服务。
