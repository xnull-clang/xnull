# XFRONT-FIX（NEG-01 / GEN-01 跨域项）before / after

> **域：** 仅 `impl/internal/xfront/**`　**分支：** `pod/c1-rd1`　**基线：** `81ec33d`
> **纪律：** 未改 sema/interp/codegen；未改现有测试期望、未删测试。
> **测量方法：** 从 `pod/c3-rd3@df36621`、`pod/c1-rd3@35f9e06` 用 `git archive` 导出到 `/tmp`，分别先跑 before，再仅覆盖 `internal/xfront/*.go`（7 个生产文件）跑 after；不改动对方 worktree。

## 一、结论

| 项 | before | after | 变化 |
|---|---:|---:|---|
| NEG-01 `TestDiagMatrixS1` | 47/60 | **48/60** | +1（包别名 `neg-3.2-02` 由 SYN-112 拒绝） |
| GEN-01 `TestGEN01` | 2/25 子测试 | 2/25 子测试 | 计数不变；**G4/G10 从解析失败（SYN-101×N）推进到语义层（TY-101）**，xfront 缺陷已清除 |
| GEN-01 台账 26 项（含 `TestGEN01CrossFile`） | 2/26 | 2/26 | 剩余 24 项阻塞在 sema（B2）/interp（B3），非 xfront |
| 全仓回归 `go test ./...` | — | 10/10 包 ok | exit 0 |

**xfront 两项 GEN 缺陷（B1/B1b）已修复并以解析探针证明：**
`static T f<T, U>(...)` + `g<List<Int>>(...)` 同一文件：before 报 8 条 SYN-101 解析级联；after 解析零 SYN，仅剩语义 `RES-101 未定义名称 g`（预期）。
原始对照：`before/after-parse-probe.out`。

## 二、NEG-01 13 项红 → 归属

| # | 用例 | 修复 | after 状态 |
|---|---|---|---|
| 54 | `neg-3.2-02` 包别名 `import P as Q` | **xfront**：`parseImportDecl` 对单段路径 + `as` 报 `SYN-112` | ✅ PASS |
| 41 | `neg-0.6-41` 类型别名 `type Foo = Int` | sema（未知类型名） | ❌ 仍红（RD2） |
| 44–49 | `neg-1.3-01…06` 保留名 6 项 | sema（声明名合法性） | ❌ 仍红（RD2） |
| 51 | `neg-1.3-08` `Array` 作类型名 | sema（`builtinTypeNames`） | ❌ 仍红（RD2） |
| 52 | `neg-1.3-09` `true` 作声明名 | sema（声明名合法性） | ❌ 仍红（RD2） |
| 55–57 | `neg-10.4-01…03` defer 限制 | sema（defer 体检查） | ❌ 仍红（RD2） |

**NEG 残留 12 项全部为 sema 域**，需 CEO2 派 CEO1-RD2；本次未越界。

## 三、GEN-01 两项 xfront 缺陷

| 编号 | 缺陷 | 修复位置 | 验证 |
|---|---|---|---|
| B1 | 多类型参数 `<T, U>` 不解析：`genericParamsFollows` 把逗号当 `Op`；`parseTopFuncRest` 用 `atOp(",")` | `unit.go` `genericParamsFollows`（`tk.Kind == Comma`）、`parseTopFuncRest`（`p.at(Comma)`） | `TestGenericMultiTypeParams`；G4/G10 after 日志 |
| B1b | 嵌套实参 `>>` 被词法当移位：`expectOp(">")` 只认单 `>` | `parser.go` 新增 `splitAngleClose`，在 `parseNamedType`/`tryTypeArgs`/`parseNamedTypeRef`/`parseGenericPars`/顶层泛型参数闭合前拆分 | `TestNestedTypeArgs`；`before/after-parse-probe.out` |

**GEN 剩余（全部跨域）：**
- B2 sema：类型参数进作用域、推断/合一、`Call.TypeArgs` 回写、重载候选、单态化（约 6h）。
- B3 interp：泛型执行（约 3h）。
- `TestGEN01CrossFile`：同属 B2。

## 四、命令（可复制）

```bash
# NEG（被测分支 df36621，/tmp 导出 + 仅覆盖 xfront）
git -C wt/c3-rd3 archive df36621 | tar -x -C /tmp/xf-neg
cd /tmp/xf-neg/impl && go test ./Tests/ -run '^TestDiagMatrixS1$' -count=1 -v   # before 47/60
cp <wt/c1-rd1>/impl/internal/xfront/{ast,lexer,parser,printer,token,types,unit}.go /tmp/xf-neg/impl/internal/xfront/
cd /tmp/xf-neg/impl && go test ./Tests/ -run '^TestDiagMatrixS1$' -count=1 -v   # after 48/60

# GEN（被测分支 35f9e06）
git -C wt/c1-rd3 archive 35f9e06 | tar -x -C /tmp/xf-gen
cd /tmp/xf-gen/impl && go test ./internal/codegen -run '^TestGEN01$' -count=1 -v  # before 2/25
cp <wt/c1-rd1>/impl/internal/xfront/{ast,lexer,parser,printer,token,types,unit}.go /tmp/xf-gen/impl/internal/xfront/
cd /tmp/xf-gen/impl && go test ./internal/codegen -run '^TestGEN01$' -count=1 -v  # after 2/25（G4/G10 进入语义层）

# 本分支回归
cd <wt/c1-rd1>/impl
go test ./internal/xfront -run 'TestImportPackageAliasRejected|TestGenericMultiTypeParams|TestNestedTypeArgs' -count=1 -v
go test ./... -count=1 -timeout 300s
```

## 五、证据文件

| 路径 | 内容 |
|---|---|
| `before/neg-TestDiagMatrixS1.out` | 47 PASS / 13 FAIL（原始） |
| `after/neg-TestDiagMatrixS1.out` | 48 PASS / 12 FAIL（原始） |
| `before/gen-TestGEN01.out` | 2 PASS / 22 FAIL / 1 SKIP；G4/G10 为 SYN-101 级联 |
| `after/gen-TestGEN01.out` | 同上计数；G4/G10 变为 TY-101（语义层） |
| `before/after-parse-probe.out` | B1/B1b 解析前后对照 |
| `after/full-suite.out` | `go test ./...` 10 包全 ok |

## 六、未测项

1. GEN 双路径（编译 vs 解释）仍无法验收：interp 无泛型（B3）。
2. 未在对方分支提交任何改动；after 为 `/tmp` 覆盖测量，正式合入需 CEO2 合分支。
3. NEG 的 12 项 sema 红项未修（越界），交 RD2。
