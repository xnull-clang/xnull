# S1-22 自检结论（.xn → .x 全量改名）

> 依据：`收件箱/董事会令-S1-22立即改名-v1.0.0-2026-11-07.md`。基线 `f826d1f`。本文件为 E6 执行侧自检，独立验收归 QA1。

## 步骤

1. **改名 13 个文件**：全部 `git mv`，无 `rm`+新建（清单见 `renames.txt`）。
2. **活引用替换**：统一用正则 `\.xn\b` → `.x`，未做裸替换。共 27 个跟踪文件：
   - Go 13 个文件、57 处（`impl/**/*.go`）；
   - `impl/README.md`、`impl/docs/{xdk-design,m4-codegen-design,ffi-design}.md`；
   - `推广/**` 4 份、`XNull开发任务规划.md`、`内部-{COO,CTO}启动提示词-2026-11-06.md` 2 份（后者为满足第 3 条硬判据 0 命中而纳入，属活引用而非历史记录）。
   - 未改：`日志/**`、`收件箱/**`、`evidence/**`、8 份规范母本（本就零 `.xn`）。
3. 模块路径 `xnull.dev/xnull` 未被触碰（`\.xn\b` 不匹配 `.xnull`）；39 个 Go 文件仍正常引用，`go build`/`go test` 全绿。

## 董事会令第 3 条验收

| # | 判据 | 实测 |
|---|---|---|
| 1 | 主仓 `.xn` 文件为 0 | `find . -path ./wt -prune -o -path ./xnull -prune -o -name '*.xn' -print` → **0** |
| 2 | 公开仓 `.xn` 文件为 0 | 公开仓当前仍有 12 个（本卡不动公开仓；按令第 4 条属 COO 同步步骤） |
| 3 | 活引用为 0 | `git grep -n '\.xn\b' -- ':!日志/**' ':!收件箱/**' ':!evidence/**'` → **0 命中** |
| 4 | Go 全绿 | `go vet ./...`=0；`go test ./... -count=1 -timeout 300s`=**0**（9 包全绿，codegen 49.130s） |
| 5 | C 运行时 | `sh impl/runtime/build_rt.sh`=**0**（资源表测试通过） |
| 6 | 9 示例双路径 | **9/9** stdout 逐字节一致、退出码一致；`parser-seed` 解释器 **real 0.02s**（要求 <10s） |
| 7 | 公开布局 | 同步前先记录：新二进制在主树与公开仓 cwd 均 exit 0（公开仓内容未同步，属 COO） |

## 双路径明细

| 示例 | interp | compiled | stdout |
|---|---|---|---|
| ast-seed / classes / containers / defer-cleanup / hello / lexer-seed / objlist / parser-seed / result-try | 0 | 0 | 全部相同 |

## 说明

- `examples/*.x` 自身注释中的文件名同步改为 `.x`（3 处）。
- `impl/cmd/xnpt/main.go` 的 `ParseUnit("xnpt.xn", ...)` 同步改为 `"xnpt.x"`（仅诊断用文件名，不影响解析）。
- 编译路径 stderr 仍有 cc `-Wparentheses-equality` 警告（ast-seed/parser-seed），与 S1-22 无关；本轮只比对 stdout 与退出码，符合令第 3 条第 6 项。
- 公开仓未改、未 push、未合并 main。

## 声明

执行侧自检，不构成验收签署。
