# 接力棒：IDE-SOURCE

- **卡片ID**：IDE-SOURCE（E6 收口第二件：`ide/` 源码入库）
- **输入**（上游产物/条款/接口）：主树未跟踪的 `ide/`（VS Code 扩展 + XDK 索引 + README）；ADR-001 §6（E6 执行 IDE）；排除项要求 `node_modules/`、`out/`、`*.vsix`。
- **输出文件**（精确路径）：
  - `ide/.gitignore`（node_modules/out/*.vsix）
  - `ide/README.md`（第 10 部分实现区说明）
  - `ide/xdk/index.json`（XDK 索引源）
  - `ide/vscode/{package.json,package-lock.json,tsconfig.json,language-configuration.json,LICENSE,README.md,.vscodeignore,.gitignore}`
  - `ide/vscode/src/{extension.ts,cli.ts,project.ts,stdlib.ts,diagnostics.ts,types.ts}`
  - `ide/vscode/{syntaxes/xnull.tmLanguage.json,snippets/xnull.json,scripts/sync-xdk-index.js,.vscode/{launch,tasks}.json}`
  - 入库共 22 个文件，112 KB。
- **commit**：`1a6c2ff`（pod/e6-toolchain，`add(ide): VS Code extension sources and XDK index`）
- **验证命令**（可复制）：
  ```bash
  git ls-files ide | wc -l                       # 22
  test ! -e ide/vscode/node_modules && test ! -e ide/vscode/out && echo clean
  git check-ignore -v ide/vscode/node_modules ide/vscode/out ide/vscode/xnull-ide-0.1.0.vsix
  # 扩展编译（需网络装依赖）：
  cd ide/vscode && npm ci && npm run compile
  ```
- **已知缺口/风险**：
  1. `npm ci && npm run compile` **未在本机执行**（入库排除 `node_modules/`，需重新装依赖）；TypeScript 源码齐全、`tsconfig.json`/`package-lock.json` 已入库。
  2. `ide/vscode/xdk/index.json` 为生成物（`.gitignore` 排除），源为 `ide/xdk/index.json` + `scripts/sync-xdk-index.js`。
  3. `out/`（编译产物）与 `xnull-ide-0.1.0.vsix` 未入库，需由构建步骤重建。
  4. 本轮只在 **pod/e6-toolchain** 入库；main 合并仍被 main 工作树未提交的 `impl/internal/cli/cli.go` 阻塞（与 BOARD 同一阻塞点），合并后 `ide/` 才进 main。
- **下一步**（谁接、做什么）：E4（自举线 owner）在 main 工作树清理未提交改动后合并 `pod/e6-toolchain`；随后 COO/发布线用 `npm ci && npm run compile && vsce package` 生成 vsix 并入库发布物料。
- **上一棒**：`handoff/EXP-023.md`（SSOT 看板首版）；BOARD 更新提交在 main `f548b54`。
- **下一棒**：待派（E6 WIP 仅剩 IDE 待验收；下一张由 E4 按 B1 缺口派）。
