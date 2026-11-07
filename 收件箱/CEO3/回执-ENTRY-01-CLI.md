# 回执：ENTRY-01 CLI 侧（支援卡 A）

> 角色：CEO3-RD1-工具链（会签人）　日期：2026-11-07　分支：`pod/c3-rd1`
> 原始基线：`81ec33d`；CLI 侧提交：`5f8b437`；已并入 main `7df123d`（合并提交 `5dbf0d9`）
> 范围：`impl/internal/cli/cli.go`、`impl/internal/cli/cli_test.go`；未改 codegen/xfront/sema/interp/runtime。

## 1. 改了什么

- 新增入口前置检查 `checkEntry`：`ENTRY-001` 缺失入口、`ENTRY-002` 重复入口、`ENTRY-003` 非法签名；`run` 与 `build` 均先检查，退出码 1，不再落到 cc 的 C 语法错误。
- `run` 参数解析拆出 `runOptions`：`--interp`/`--runtime <dir>` 不再混入程序参数；`--` 后原样作为程序参数；`parseFlags` 在 `--` 处停止校验。
- 编译路径 `exec.Command(bin, progArgs...)` 传递程序参数；解释路径只把程序参数传给 `interp.Run`。
- `--runtime` 对 `run` 生效（显式值优先）。
- 新增 8 个测试，覆盖缺失/重复/非法入口、两种 `main` 签名、`--` 分隔、初始化顺序；未改既有测试期望、未删测试。

## 2. 怎么验

```bash
cd wt/c3-rd1/impl
go vet ./internal/cli
go test ./internal/cli -count=1
go test ./... -count=1 -timeout 300s
go test ./internal/cli -run 'TestRunEntry|TestEntry|TestRunMain|TestInitOrder' -count=1
go test ./internal/interp -run 'TestEntry|TestTopFieldInitOrder|TestMissingMain|TestMainWithArgs' -count=1
```

实测（合并 main 后）：`go test ./... -count=1 -timeout 300s` = 0；CLI 入口锚点矩阵 = 0；interp 入口锚点 = 0；codegen `TestB0_04FieldInitOrder`/`TestXdkSeedUnitCompiles` = 0。先红证据 `evidence/M1-ENTRY-01/cli-red.out`（exit=1），修复后 `cli-targeted.out`/`cli-post-merge-anchor.out`/`cli-post-merge-full.out` 全绿。

## 3. SHA

- CLI 侧提交：`5f8b437fa2f9fefb80eedcf0c95fb57f9de9749f`
- 合并 main：`5dbf0d930da5465fa0eccbb1405ea2826abea30a`（main=`7df123d`）
- 文件 SHA-256：见 `evidence/M1-ENTRY-01/cli-sha.txt`
  - `cli.go`：`cea6bc05334993ce554b3ded542ff0b622f713fbc72fbfe182462c36a64a6202`
  - `cli_test.go`：`2e05d939985a7be08e2c7e8723a2cb30dafd52e0f0d49e0266263067de3948e6`

## 4. 产物

- `evidence/M1-ENTRY-01/cli-command.txt`
- `evidence/M1-ENTRY-01/cli-red.out` / `cli-red.exit`（先红）
- `evidence/M1-ENTRY-01/cli-targeted.out` / `.exit`
- `evidence/M1-ENTRY-01/cli-internal.out` / `.exit`
- `evidence/M1-ENTRY-01/cli-full.out` / `.exit`
- `evidence/M1-ENTRY-01/cli-post-merge-anchor.out` / `.exit`（合并 main 后入口锚点）
- `evidence/M1-ENTRY-01/cli-post-merge-full.out` / `.exit`（合并 main 后全量）
- `evidence/M1-ENTRY-01/cli-vet.out` / `.exit`
- `evidence/M1-ENTRY-01/cli-sha.txt`
- `evidence/M1-ENTRY-01/cli-acceptance.md`

## 5. 未测项

- **已解除**：合并 main `7df123d` 后，E4 的 codegen 已支持带参入口与编译路径顶层字段；`TestRunEntryTwoSignatures`/`TestRunEntryArgsArray`/`TestRunEntryInitOrder` 编译路径全绿。
- 多文件入口归属：`checkEntry` 基于 `LoadUnits` 合并后的单元，尚未按 S1 §11.4 严格限定“入口文件必须包含 main”。
- 非匹配 `main` 重载：S1 §11.2 允许其作为普通函数，但 codegen 当前同名顶层函数撞名；本卡对第二个 `main` 一律报 `ENTRY-002`，待重载切片放开。
