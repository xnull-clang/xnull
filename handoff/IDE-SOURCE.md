# 接力棒：IDE-SOURCE

- **卡片ID**：IDE-SOURCE（E6 收口第二件：`ide/` 源码入库）— **状态：DONE（main 已集成）**
- **输入**（上游产物/条款/接口）：主树未跟踪的 `ide/`（VS Code 扩展 + XDK 索引 + README）；ADR-001 §6（E6 执行 IDE）；排除项要求 `node_modules/`、`out/`、`*.vsix`。
- **输出文件**（精确路径）：
  - `ide/.gitignore`（node_modules/out/*.vsix）
  - `ide/README.md`（第 10 部分实现区说明）
  - `ide/xdk/index.json`（XDK 索引源）
  - `ide/vscode/{package.json,package-lock.json,tsconfig.json,language-configuration.json,LICENSE,README.md,.vscodeignore,.gitignore}`
  - `ide/vscode/src/{extension.ts,cli.ts,project.ts,stdlib.ts,diagnostics.ts,types.ts}`
  - `ide/vscode/{syntaxes/xnull.tmLanguage.json,snippets/xnull.json,scripts/sync-xdk-index.js,.vscode/{launch,tasks}.json}`
  - 入库共 22 个文件，112 KB。
- **commit**：`1a6c2ff`（pod 入库）→ main 集成 `6b6e987`（merge pod/e6-toolchain）→ 文档收口 `9bf370c`（`docs(ide): machine interface + spec index entries`）；main 现 `git ls-files ide | wc -l` = **22**
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
  4. ~~只在 pod 入库~~ **已解**：`ide/` 22 文件已随 `6b6e987` 进入 main；`xnull new/check --json` 接线已在 main（`d28da32`），README 与规范索引于 `9bf370c` 收口。
- **下一步**（谁接、做什么）：IDE 源码已闭环，转发布线 COO：`cd ide/vscode && npm ci && npm run compile && vsce package` 生成 vsix 并作为发布物料；E6 下一卡 `XNFMT-CI`（xnfmt 纳入 CI 与发布产物，见 `handoff/XNFMT-CI.md`）。
- **上一棒**：`handoff/EXP-023.md`（SSOT 看板首版）；BOARD 更新提交在 main `f548b54`。
- **下一棒**：`handoff/XNFMT-CI.md`（E6：xnfmt 纳入 CI/发布产物）。
