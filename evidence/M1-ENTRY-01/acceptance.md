# M1-ENTRY-01 验收结论（执行侧自检，非 QA 签署）

台账验收要点逐项（原文：入口与启动；两种 `main` 签名均可运行；退出码正确；初始化顺序正确；缺失/重复入口被拒绝）：

| # | 验收要点 | 用例 | 实测 |
| --- | --- | --- | --- |
| 1 | 入口与启动 | `TestRunEntryTwoSignatures`、`TestRunEntryArgsArray`、`TestEntryTwoSignatures` | 通过：编译/解释双路径均可启动；`args` 为运行时新数组（不含程序名、不含标志） |
| 2 | 两种 `main` 签名均可运行 | `TestRunEntryTwoSignatures`（void/Int × 无参/String[] 四形态）、`TestEntryTwoSignatures`、`TestMainWithArgs` | 通过：四种形态全部运行 |
| 3 | 退出码正确 | `TestRunEntryTwoSignatures`（Int→4/5）、`TestExitCodeMapping`（7/0/134）、`entry.x`（→7） | 通过：Int 返回值直通；void→0；fatal→134；双路径一致 |
| 4 | 初始化顺序正确 | `TestRunEntryInitOrder`（编译+解释）、`TestTopFieldInitOrder` | 通过：顶层字段按声明顺序先于入口初始化（`init 1`→`init 2`→`main`）；生成 C 为 `int main(){ xn_init_globals(); ... xn_main(); }` |
| 5 | 缺失入口被拒绝 | `TestEntryMissingRejected`、`TestRunEntryMissingRejected` | 通过：报“找不到入口 main（缺失入口，§11.4）”，不再落到 cc |
| 6 | 重复入口被拒绝 | `TestEntryDuplicateRejected`、`TestRunEntryDuplicateRejected` | 通过：报“重复入口 main（§11.4）” |

合计：**6/6 全绿**。

## 变更范围

- `impl/internal/interp/interp.go`：入口缺失/重复/签名校验（§11.2/§11.4）。
- `impl/internal/codegen/codegen.go`、`build.go`：入口校验（`RequireEntry`）、C 入口垫片支持 `String[]` 参数与顶层字段初始化、顶层字段（Int/Bool/String）代码生成。
- `impl/internal/cli/cli.go`：程序参数透传（编译/解释一致）。
- 测试：`impl/internal/interp/interp_test.go`、`impl/internal/cli/cli_test.go` 追加用例；未改任何既有期望、未删测试。

## 未测项（明确列出）

1. 入口 `public` 可见性：`private`/`protected main` 的拒绝尚未覆盖（可见性未接入入口校验）。
2. 工程清单指定入口文件/入口包（§11.4 清单模式）：工程配置规范未落地。
3. 泛型 `main`、默认参数、可变参数：语法层尚未支持，无法构造负例。
4. 非默认包 `main` 不作为入口：多包编译未支持（PKG-01 范围）。
5. 顶层字段类型：仅 Int/Bool/String；类引用/容器顶层字段显式报错（超出本锚点）。

## 口径说明

- “两种 `main` 签名”按 §11.2 的返回形态判定：`void main` 与 `Int main`；参数形态同时接受空参与 `String[] args`（无参形态为既有实现与全部示例的兼容面，若董事会要求严格只允许 `String[]`，需另开变更并同步改示例/既有测试）。

## 声明

执行侧自检，不构成验收签署；按 v1.7.0 第 1 条需 QA 独立签 L1、CEO1 签 L2。
