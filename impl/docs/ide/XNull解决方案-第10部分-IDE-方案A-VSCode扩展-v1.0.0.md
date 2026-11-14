# XNull 解决方案 第 10 部分：IDE（方案 A：VS Code 扩展）

> **2026-11-15**：本文档是内部实现基线，不属于语言规范序列；实现细节（含 `.xfb` 等格式）可按实现需要修正。

> 本文是第 10 部分方案 A，只落实第 1—9 部分已定义的编辑、工程、标准库、构建与诊断行为；IDE 交互属于实现选择；与第 1—9 部分冲突时以母本为准。

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 10 部分（T10） |
| 方案 | A：VS Code 扩展 |
| 文档版本 | 1.0.0 |
| 规范状态 | 工程实现基线（受第 1—9 部分约束） |
| 文档性质 | 方案详细设计；不新增语言语义 |
| 编制日期 | 2026-11-07 |
| 代码基线 | `f63fcba`（编制时点；工作区可能继续前进） |
| 实现语言 | TypeScript（VS Code 扩展） |
| 依赖 | 第 9 部分 `xnull` CLI、第 8 部分 XPD、第 6 部分 XDK 索引 |
| 明确不含 | 独立桌面 IDE、LSP、编译器/构建实现 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。定义 VS Code 扩展的命令、JSON 接口、模板、标准库索引与验收。 |

---

## 0. 定位

### 0.1 目标

用最低成本让 XNull 可写、可检查、可构建、可运行：

- 在 VS Code 中打开/新建 XNull 工程；
- 编辑 `.x` 有语法高亮和 snippets；
- 查看 XDK 包文档；
- 保存时检查，问题面板可跳转；
- 一键 Build/Run，输出二进制。

### 0.2 不做

- 不实现独立编辑器；
- 不实现 LSP/语义补全；
- 不实现编译器/构建系统；
- 不实现完整工程 packaging（只输出单文件二进制）；
- 不解析 stderr 文本作为诊断来源。

### 0.3 为什么 TypeScript

- VS Code 扩展 API 原生是 TypeScript/JavaScript；
- 语法高亮、命令、诊断、任务、Webview 生态成熟；
- 不需要把 UI 逻辑塞进 XNull 编译器；
- 不与第 9 部分工具链语言冲突；IDE 不是编译器的自举对象。

---

## 1. 架构

```text
VS Code
  ├─ 扩展激活
  ├─ 命令 / 设置 / 诊断集合
  ├─ 语法高亮 / snippets / 语言配置
  │
  └─ child_process.spawn
        └─ xnull CLI（第 9 部分）
             ├─ new --json
             ├─ check --json
             ├─ build --json
             └─ run
```

### 1.1 目录

```text
ide/vscode/
├── package.json
├── tsconfig.json
├── language-configuration.json
├── syntaxes/xnull.tmLanguage.json
├── snippets/xnull.json
├── src/
│   ├── extension.ts
│   ├── cli.ts
│   ├── diagnostics.ts
│   ├── project.ts
│   ├── stdlib.ts
│   └── types.ts
└── README.md
```

### 1.2 依赖

- VS Code API；
- Node `child_process`/`path`/`fs`；
- 不引入框架（不做 Webview 框架）；
- 不引入语言服务器依赖。

---

## 2. 第 9 部分机器接口

### 2.1 `xnull new`

```text
xnull new app <dir> --json
xnull new library <dir> --json
```

行为：

- 创建目录（不存在则创建；非空则失败）；
- 写入 `xnull.project`、`src/main/x/main.x`、`src/main/resources/`、`.gitignore`；
- 输出 JSON；
- 不覆盖已有文件。

JSON：

```json
{
  "ok": true,
  "template": "app",
  "directory": "/abs/path",
  "files": ["xnull.project", "src/main/x/main.x", ".gitignore"]
}
```

失败：

```json
{ "ok": false, "error": "目录非空", "directory": "/abs/path" }
```

退出码：0 成功；1 创建失败；2 参数错误。

### 2.2 `xnull check`

```text
xnull check <file.x> --json
```

行为：

- `LoadUnits` → `sema.Analyze`；不要求 `main`（库文件也可检查）；
- 输出全部诊断；
- 不生成 C、不链接。

JSON：

```json
{
  "ok": false,
  "file": "src/main/x/main.x",
  "diagnostics": [
    {
      "file": "src/main/x/main.x",
      "line": 3,
      "column": 5,
      "code": "TY-101",
      "message": "类型不匹配",
      "hint": "…",
      "snippet": "    Int x = \"s\"",
      "width": 1
    }
  ]
}
```

退出码：0 无诊断；1 有诊断；2 用法/读取错误。

### 2.3 `xnull build`

```text
xnull build <file.x> --json [-o <out>] [--runtime <dir>] [-l <lib>] [-L <dir>]
```

行为：

- 先检查；有诊断 → JSON + 退出 1；
- 成功 → 编译/链接 → 输出二进制；
- 失败 → JSON 带 `log`/`exitCode`；
- stdout 只放 JSON；构建日志放 stderr（或 JSON 字段）。

成功：

```json
{
  "ok": true,
  "file": "src/main/x/main.x",
  "output": "target/hello",
  "exitCode": 0,
  "diagnostics": []
}
```

失败：

```json
{
  "ok": false,
  "file": "src/main/x/main.x",
  "output": "target/hello",
  "exitCode": 1,
  "diagnostics": [],
  "log": "cc: ..."
}
```

### 2.4 `xnull run`

```text
xnull run <file.x> [--interp] [-- <程序参数>...]
```

- 扩展用终端运行；
- 不要求 JSON；
- 退出码由终端显示。

### 2.5 边界

- 第 9 部分未提供 `package --json` 前，方案 A 的 “Package Binary” 使用 `build -o target/<name>`；
- 不伪造完整工程 packaging；
- JSON 字段变更需先改第 9 部分文档/测试。

---

## 3. 扩展命令

| 命令 ID | 标题 | 行为 |
| --- | --- | --- |
| `xnull.ide.newProject` | XNull: New Project | 选择模板/目录 → `xnull new ... --json` → 打开目录 |
| `xnull.ide.check` | XNull: Check | 当前 `.x` → `xnull check --json` → 问题面板 |
| `xnull.ide.build` | XNull: Build | 当前 `.x` → `xnull build --json -o target/<name>` |
| `xnull.ide.run` | XNull: Run | 当前 `.x` → 终端 `xnull run` |
| `xnull.ide.packageBinary` | XNull: Package Binary | 同 Build，输出到 `target/`；明确是单文件二进制 |
| `xnull.ide.showStdlib` | XNull: Show Standard Library | 读取 `ide/xdk/index.json` → Quick Pick → 文档 |
| `xnull.ide.doctor` | XNull: Doctor | 显示 toolchainPath、版本、运行时目录、工作区 |

### 3.1 激活事件

- `onLanguage:xnull`
- `onCommand:...`
- `workspaceContains:xnull.project`（可选）

### 3.2 设置

| 设置 | 类型 | 缺省 | 说明 |
| --- | --- | --- | --- |
| `xnull.toolchainPath` | string | `xnull` | CLI 路径 |
| `xnull.runtimePath` | string | `""` | 运行时源码目录 |
| `xnull.checkOnSave` | boolean | `true` | 保存 `.x` 时检查 |
| `xnull.defaultOutput` | string | `target` | 二进制输出目录 |
| `xnull.profile` | string | `""` | 默认 profile（预留） |
| `xnull.autoOpenProblems` | boolean | `true` | 有诊断时聚焦问题面板 |

### 3.3 状态栏

- 显示 `XNull` 当前工具链状态；
- Build 中显示 `$(sync~spin) XNull: Building`；
- 失败显示 `$(error) XNull`。

---

## 4. 工程创建与配置

### 4.1 模板

`app`：

```x
static Int main() {
    print("hello, XNull")
    return 0
}
```

`library`：

```x
static Int add(Int a, Int b) {
    return a + b
}
```

### 4.2 `xnull.project`

模板：

```xpd
project {
  groupId    = com.example
  artifactId = <name>
  version    = 0.1.0
  packaging  = app

  properties {
    xdk-version      = 1.1.0
    language-version = [3.3, 4.0)
  }

  build {
    mode         = debug
    entryFile    = src/main/x/main.x
    entryPackage = com.example.<name>
  }

  link {
    unsafe = false
  }
}
```

- `groupId` 缺省 `com.example`；
- `artifactId` 由目录名清洗为小写/连字符；
- 配置编辑由 VS Code 文本编辑完成；
- 校验调用 `xnull check/build`，IDE 不实现 XPD 语义。

### 4.3 工程打开

- 选择目录；
- 若存在 `xnull.project`，设为工作区；
- 否则提示新建。

---

## 5. 标准库使用

### 5.1 索引

`ide/xdk/index.json`：

```json
{
  "version": "1.1.0",
  "source": "第6部分 XDK",
  "packages": [
    {
      "name": "xdk.runtime",
      "summary": "诊断、退出、时间、环境",
      "stability": "preview",
      "items": [
        {"name": "diagnose", "signature": "diagnose(String)", "summary": "单行诊断输出"},
        {"name": "nowMono", "signature": "nowMono() -> Int", "summary": "单调毫秒"}
      ]
    }
  ]
}
```

约束：

- 包名、API 名来自第 6 部分；
- 未定案 API 不写入，或标 `preview`；
- 索引可后续由工具生成，IDE 只消费；
- 不把索引当作语言规范。

### 5.2 UI

- Quick Pick 列出 8 包；
- 选择包 → 显示包摘要与条目；
- 选择条目 → 显示签名/摘要；
- 提供“插入 snippet”命令（后续）；
- 不做语义补全（方案 B）。

---

## 6. 诊断

### 6.1 数据流

```
save/check command
  → xnull check --json
  → JSON diagnostics
  → DiagnosticCollection
  → Problems / 跳转
```

### 6.2 映射

| JSON | VS Code |
| --- | --- |
| `file` | URI |
| `line`/`column` | 1 基 → 0 基 |
| `message` | Diagnostic.message |
| `code` | Diagnostic.code |
| `hint` | 追加到 message 或 relatedInformation |
| `snippet`/`width` | 用于范围；缺省 1 字符 |

- Severity 固定 Error（第 9 部分当前只有 error）；
- `source = "xnull"`；
- 每次检查先清空旧诊断；
- 构建返回的诊断也发布。

### 6.3 保存检查

- `xnull.checkOnSave` 为 true；
- 仅 `.x` 文件；
- 防抖（500ms）；
- 失败不弹窗刷屏，状态栏/问题面板显示。

---

## 7. 构建、运行与二进制

### 7.1 Build

- 当前文件或选择文件；
- 输出 `target/<basename>`；
- 调用 `xnull build --json`；
- 成功：状态栏 + 输出路径 + 可选“在终端显示”；
- 失败：发布诊断、显示 log。

### 7.2 Run

- 打开终端；
- 执行 `xnull run <file>`；
- `--interp` 可选；
- 程序参数通过 `--` 传递。

### 7.3 Package Binary

- 方案 A 的边界：单文件二进制；
- 输出 `target/<name>`；
- 文案必须写“单文件二进制”，不得宣称完整工程 packaging；
- 完整 packaging 由第 9 部分模块 06 后续接入。

---

## 8. 安全与错误

| 风险 | 处理 |
| --- | --- |
| 路径含空格/特殊字符 | `spawn` 参数数组，不拼 shell |
| 工具链不存在 | 捕获 `ENOENT`，提示设置 `xnull.toolchainPath` |
| 非零退出 | 读取 stdout JSON，必要时显示 stderr |
| 大日志 | 截断显示，完整日志写入 OutputChannel |
| 凭据 | 不写入设置/日志；不读取凭据文件 |
| 网络 | 不需要 |
| 覆盖工程 | `new` 拒绝非空目录 |

---

## 9. 测试与验收

### 9.1 测试

| 层 | 内容 |
| --- | --- |
| TypeScript 编译 | `tsc --noEmit` 零错误 |
| 单元 | JSON 解析、诊断映射、路径/模板 |
| 集成 | mock `xnull` 可执行：new/check/build/run |
| 手动 | 真实 `xnull`：新建 → 编辑 → 检查 → 构建 → 运行 |

### 9.2 验收

- 安装 `.vsix` 后能激活；
- 新建 app 工程成功；
- 打开 `.x` 有高亮/snippets；
- 保存错误代码能显示诊断并跳转；
- Build 成功生成二进制；
- Run 能启动程序；
- Show Standard Library 能列出 8 包；
- 工具链路径错误时有明确提示；
- 不解析 stderr 作为诊断；
- 不新增编译器/构建实现。

---

## 10. 边界与建议

### 10.1 边界

- VS Code 依赖；
- 无 LSP/语义补全；
- 无完整工程 packaging；
- 无独立桌面应用；
- 无调试器；
- 标准库索引非完整 API；
- 不是语言用户稳定 CLI 的一部分。

### 10.2 建议

1. 先固化 `check --json` / `build --json` 字段，再扩展 UI。
2. 诊断输出增加 `severity` 字段时，IDE 映射表同步。
3. 标准库索引后续由第 6 部分生成，避免手工维护。
4. 工程模板只保留最小可用，不复制第 8 部分全部示例。
5. 方案 A 稳定后再启动方案 B，避免同时维护两套语言服务。

---

## 规范依据与实现选择

### 规范依据

| 第 1—9 部分条款 | 本方案落实 |
| --- | --- |
| 第 1 部分 §1—§11 | 语法高亮、snippets、入口/错误提示 |
| 第 6 部分 §2、§4 | XDK 包/能力索引 |
| 第 8 部分 §2—§6 | 工程模板、配置展示、profile/资源 |
| 第 9 部分 §2—§6 | new/check/build/run 机器接口、诊断、构建 |

### 实现选择

- VS Code 扩展而非独立编辑器；
- TypeScript；
- `spawn` 调用 CLI；
- JSON 诊断/构建结果；
- `target/` 作为二进制输出；
- 静态 XDK 索引；
- 不做 LSP/语义补全。

以上为实现选择，不新增语言语义；与第 1—9 部分冲突时以母本为准。

## 参考

- `XNull解决方案-第9部分-工具链-v1.0.0.md`
- `XNull解决方案-第9部分-工具链-模块02-命令行工具-v1.0.0.md`
- `XNull解决方案-第9部分-工具链-模块07-诊断与错误呈现-v1.0.0.md`
- `XNull解决方案-第8部分-工程配置-v5.2.0.md`
- `XNull解决方案-第6部分-标准库XDK-v1.1.0.md`
- `impl/internal/cli/cli.go`
