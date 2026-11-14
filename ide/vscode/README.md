# XNull IDE（方案 A：VS Code 扩展）

这是第 8 部分方案 A 的实现：一个 VS Code 扩展，负责编辑体验、工程创建、标准库浏览、Build/Run/Package Binary 与诊断展示。

它不实现编译器、构建系统或语言服务；所有实际编译/检查/运行都调用第 7 部分 `xnull` CLI。

## 构建

```bash
cd ide/vscode
npm install
npm run compile
```

产物在 `out/`。用 VS Code 打开 `ide/vscode` 后按 `F5` 启动 Extension Development Host，或打包：

```bash
npx @vscode/vsce package
```

## 配置

| 设置 | 缺省 | 说明 |
| --- | --- | --- |
| `xnull.toolchainPath` | `xnull` | 工具链路径；未安装时指向 `impl/xnull` 的绝对路径 |
| `xnull.runtimePath` | 空 | 运行时源码目录，传给 `--runtime` |
| `xnull.checkOnSave` | `true` | 保存 `.x` 时检查 |
| `xnull.defaultOutput` | `target` | 二进制输出目录 |

工具链需要支持：

```text
xnull new app <dir> --json
xnull check <file.x> --json
xnull build <file.x> --json -o <out>
xnull run <file.x>
```

## 命令

- `XNull: New Project`
- `XNull: Check`
- `XNull: Build`
- `XNull: Run`
- `XNull: Package Binary`
- `XNull: Show Standard Library`
- `XNull: Doctor`

## 边界

- 只输出单文件二进制；完整工程 packaging 由第 7 部分模块 06 后续提供。
- 不做 LSP/语义补全；方案 B 后续接入。
- 不解析 stderr 作为诊断；诊断来自 `--json`。
- 不把 VS Code 扩展 API 当作 XNull 语言 API。

## 目录

```text
ide/vscode/
├── src/                 TypeScript 源码
├── syntaxes/            TextMate 语法
├── snippets/            XNull snippets
├── language-configuration.json
├── package.json
└── tsconfig.json
```
