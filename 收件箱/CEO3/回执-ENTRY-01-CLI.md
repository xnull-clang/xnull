# 回执：ENTRY-01 CLI 侧（支援卡 A）

> 角色：CEO3-RD1-工具链（会签人）　日期：2026-11-07　分支：`pod/c3-rd1`
> 基线：`81ec33d`　代码提交：`5f8b437fa2f9fefb80eedcf0c95fb57f9de9749f`
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
go test ./... -count=1 -timeout 900s
```

实测：vet=0；`internal/cli`=0；全量 `./...`=0。先红证据 `evidence/M1-ENTRY-01/cli-red.out`（exit=1），修复后 `cli-targeted.out`/`cli-internal.out`/`cli-full.out` 全绿。

## 3. SHA

- 代码提交：`5f8b437fa2f9fefb80eedcf0c95fb57f9de9749f`
- 文件 SHA-256：见 `evidence/M1-ENTRY-01/cli-sha.txt`
  - `cli.go`：`08e487471e5fa7db38015d8ca37a30eed3a50c0af5ef826be2d073d9099bde79`
  - `cli_test.go`：`d0c003dd1495e6a5f0115c2526b566acfff2b6350f1fb3cec12d85f7415c24ae`

## 4. 产物

- `evidence/M1-ENTRY-01/cli-command.txt`
- `evidence/M1-ENTRY-01/cli-red.out` / `cli-red.exit`（先红）
- `evidence/M1-ENTRY-01/cli-targeted.out` / `.exit`
- `evidence/M1-ENTRY-01/cli-internal.out` / `.exit`
- `evidence/M1-ENTRY-01/cli-full.out` / `.exit`
- `evidence/M1-ENTRY-01/cli-vet.out` / `.exit`
- `evidence/M1-ENTRY-01/cli-sha.txt`
- `evidence/M1-ENTRY-01/cli-acceptance.md`

## 5. 未测项

- **编译路径 `main(String[] args)` 尚未端到端绿**：`internal/codegen` 现生成 `int main(void) { xn_main(); ... }`，对带参 `xn_main` 直接 cc 报参数不足。CLI 已把 `progArgs` 传给二进制；需 E4 在 codegen 生成 `int main(int argc, char **argv)` 并构造 `String[]` 后，才能用现有用例扩到编译路径。本卡未改 codegen，也不伪造绿。
- 编译路径顶层字段初始化：`EmitC` 当前对 `TopField` 报未支持；初始化顺序断言暂只走 `--interp`。
- 多文件入口归属：`checkEntry` 基于 `LoadUnits` 合并后的单元，尚未按 S1 §11.4 严格限定“入口文件必须包含 main”。
- 非匹配 `main` 重载：S1 §11.2 允许其作为普通函数，但 codegen 当前同名顶层函数撞名；本卡对第二个 `main` 一律报 `ENTRY-002`，待重载切片放开。
