# ENTRY-01 CLI 侧验收记录

> 角色：CEO3-RD1-工具链（支援卡 A，会签人）　日期：2026-11-07
> 基线：`81ec33d`（`pod/c3-rd1`）　范围：`impl/internal/cli/cli.go`、`impl/internal/cli/cli_test.go`
> 锚点主责：E4（codegen）。本件只证明 CLI 侧，不替代 ENTRY-01 整卡验收。

## 1. 改了什么

### 1.1 入口前置检查（新增）

- `checkEntry(path)`：在编译/解释前加载编译单元并检查 `main`：
  - 缺失 → `ENTRY-001`；
  - 重复 → `ENTRY-002`（带第二个 `main` 的位置）；
  - 签名非法 → `ENTRY-003`（只接受 `main()` 或 `main(String[] args)`，返回 `void` 或 `Int`；拒绝泛型、私有/受保护、参数个数/类型不符）。
- 入口错误退出码 `1`（构建失败语义），不再落到 cc 的 C 语法错误；`build` 路径同样前置检查。

### 1.2 两种 main 签名的启动与参数

- `parseRunArgs` 把工具链 flag 与程序参数分离：
  - 第一个 `.x` 位置参数为入口；
  - `--interp`/`--runtime <dir>` 只作工具选项；
  - `--` 之后全部作为程序参数；
  - 其余位置参数作为程序参数（保持源文件可在参数中任意位置的既有行为）。
- `parseFlags` 在 `--` 处停止 flag 校验，允许程序参数以 `--` 开头。
- `runCompiled` 以 `exec.Command(bin, progArgs...)` 启动可执行文件，把程序参数交给 `main(String[] args)`（编译路径的 C 入口生成由 E4 的 codegen 侧完成）。
- `interpFile` 只把程序参数传给 `interp.Run`，不再把 `--interp` 混入 `args`。
- `--runtime` 现在对 `run` 生效（显式值优先，其次相对探测、`XNULL_RUNTIME`）。

### 1.3 初始化顺序

- CLI 测试断言：顶层字段按声明顺序初始化（`mark("a")` → `mark("b")`），完成后才进入 `main`；输出 `a\nb\nmain\n`。
- 该断言走 `--interp` 路径；编译路径的顶层字段初始化属 codegen 能力（E4），当前 `EmitC` 对 `TopField` 显式报错，未在本卡冒充通过。

## 2. 怎么验

```bash
cd wt/c3-rd1/impl
go vet ./internal/cli
go test ./internal/cli -count=1
go test ./... -count=1 -timeout 900s
```

结果：

| 命令 | 退出码 | 证据 |
|---|---:|---|
| `go vet ./internal/cli` | 0 | `cli-vet.out` / `cli-vet.exit` |
| `go test ./internal/cli -count=1` | 0 | `cli-internal.out` / `cli-internal.exit` |
| `go test ./... -count=1 -timeout 900s` | 0 | `cli-full.out` / `cli-full.exit` |

先红后绿：

- 先红文件：`cli-red.out`（`cli-red.exit`=1）。基线实现 + 新增测试时，`ENTRY-001/002/003` 均缺失，`main(String[])` 的 `args` 混入 `--interp`，`--` 被当作未知 flag。
- 恢复实现后：`cli-targeted.out`（`cli-targeted.exit`=0）与上述全绿。

## 3. 新增测试（未改既有期望、未删测试）

- `TestEntryMissingMainDiagnostic`：缺入口 → `ENTRY-001`，退出 1。
- `TestEntryDuplicateMainDiagnostic`：重复入口 → `ENTRY-002`，退出 1。
- `TestEntrySignatureDiagnostic`：非 `String[]` 参数 / `Bool` 返回 / 参数超限 → `ENTRY-003`，且不出现“C 编译失败”。
- `TestRunMainNoArgsExitCodeInterp`：`main()` 返回 7 → 退出 7。
- `TestRunMainNoArgsExitCodeCompiled`：编译路径 `main()` 返回 7 → 退出 7。
- `TestRunMainWithArgsInterp`：`main(String[] args)` 收到 2 个参数、退出 3。
- `TestRunMainWithArgsAfterSeparator`：`--` 后的 `--verbose` 原样进入程序参数，不被 CLI 拒绝。
- `TestInitOrderViaCLI`：顶层字段 `a`、`b`、`main` 顺序输出。

## 4. 产物与哈希

见 `cli-sha.txt`（基线 commit + `cli.go`/`cli_test.go` 的 SHA-256）。

## 5. 未测项 / 依赖

1. **编译路径的 `main(String[] args)` 尚未端到端通过**：`internal/codegen` 当前生成 `int main(void) { xn_main(); ... }`，对带参 `xn_main` 直接 cc 报“too few arguments”。CLI 已把 `progArgs` 传给进程，但 codegen 必须生成 `int main(int argc, char **argv)` 并构造 `String[]`；该文件属 E4 白名单，本卡未改、也未伪造通过。E4 合入后可直接用现有 `TestRunMainWithArgs*` 扩到编译路径。
2. **编译路径顶层字段初始化**：`EmitC` 目前对 `TopField` 返回未支持错误；CLI 初始化顺序断言暂只走 `--interp`，不宣称编译路径已支持。
3. **多文件入口归属**：`checkEntry` 基于 `LoadUnits` 合并后的单元，跨 import 的 `main` 也视为入口；S1 §11.4“入口文件必须包含 main”的严格文件归属未单独校验，待工程清单入口解析时补。
4. **非匹配 `main` 重载**：S1 §11.2 允许其他 `main` 重载作为普通函数，但 codegen 当前不支持同名顶层函数（C 侧撞名）；本卡对任何第二个 `main` 报 `ENTRY-002`，待重载切片放开。
5. **`--runtime` 缺失值**：当前静默忽略（沿用既有参数形态校验），未新增用法诊断；不属 ENTRY-01 验收面。

## 6. 声明

- 只改白名单内 `cli.go`、`cli_test.go`；未改 codegen/xfront/sema/interp/runtime。
- 只 commit 到 `pod/c3-rd1`，未 push、未合并 main、未派工。
- 本件是 CLI 侧执行证据，不构成 ENTRY-01 整卡验收签署；整卡由 E4 锚点 + QA 会签。
