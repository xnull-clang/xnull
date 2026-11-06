**状态：DONE（NEG +1 / GEN xfront 两项清零）**　**分支：`pod/c1-rd1`**　**代码+证据提交：见提交后回填**　**时间：2026-11-07 03:4x–04:0x CST**

---

## 五行

1. **完成（NEG）**：`neg-3.2-02` 包别名 `import P as Q` 改由 xfront 在解析期拒绝（新增 `SYN-112`）；`TestDiagMatrixS1` **47/60 → 48/60**。剩余 12 项全部为 sema 域（保留名×6、字面量名、`Array`、类型别名、defer×3），已列清单待 CEO2 派 RD2。
2. **完成（GEN）**：修 xfront 两项——B1 多类型参数 `<T, U>`（`genericParamsFollows` 逗号类别 + `parseTopFuncRest` 的 `Comma`）、B1b 嵌套实参 `>>` 拆分（新增 `splitAngleClose`，覆盖 `parseNamedType`/`tryTypeArgs`/`parseNamedTypeRef`/`parseGenericPars`/顶层泛型）。`TestGEN01` 计数 **2/26 → 2/26**，但 G4/G10 已从“解析层 SYN-101 级联”推进到“语义层 TY-101”，证明 xfront 缺陷清除；剩余 24 项阻塞在 B2 sema / B3 interp。
3. **验证**：解析探针 before 报 8 条 SYN-101（`<T, U>` 与 `g<List<Int>>` 同文件），after 解析零 SYN、仅剩预期 `RES-101 未定义 g`；`a >> 2` 移位语义不变；本分支 `go test ./...` 10 包全 ok；新增 3 条 xfront 回归用例全 PASS。
4. **边界**：仅改 `impl/internal/xfront/{unit.go,parser.go,types.go}` + 新增 `import_generics_test.go`；**未改 sema/interp/codegen**；未改现有测试期望、未删测试；未碰对方 worktree（before/after 用 `git archive` 到 `/tmp` 覆盖测量）。
5. **未测项/风险**：①GEN 双路径仍不可验收（interp 无泛型，B3）；②`TestGEN01CrossFile` 仍红（B2）；③after 为 `/tmp` 覆盖测量，正式验证需 CEO2 合分支后由 QA 独立重跑；④NEG 12 项 sema 红项未修（越界）。

**是否越界：否**

---

## 计数与证据

| 项 | before | after | 证据 |
|---|---:|---:|---|
| NEG `TestDiagMatrixS1` | 47/60 | **48/60** | `evidence/XFRONT-FIX-NEG-GEN/{before,after}/neg-TestDiagMatrixS1.out` |
| GEN `TestGEN01`（25 子测试 + CrossFile = 26 项） | 2/26 | **2/26**（xfront 两项清零，剩余全在 sema/interp） | `…/gen-TestGEN01.out`、`…/after-parse-probe.out` |
| 全仓回归 | — | 10/10 包 ok | `…/after/full-suite.out` |

## 改动文件

| 文件 | 说明 |
|---|---|
| `impl/internal/xfront/parser.go` | 新增 `SYN-112`；`splitAngleClose` + 类型实参闭合调用 |
| `impl/internal/xfront/unit.go` | `parseImportDecl` 拒绝单段包别名；`genericParamsFollows` 识别 `Comma`；`parseTopFuncRest` 逗号循环 |
| `impl/internal/xfront/types.go` | `parseGenericPars` / `parseNamedTypeRef` 接入 `splitAngleClose` |
| `impl/internal/xfront/import_generics_test.go` | 新增 3 条回归（包别名 / 多类型参数 / 嵌套实参 + 移位不变） |
| `evidence/XFRONT-FIX-NEG-GEN/**` | before/after 原始输出 + summary + command + exit_code |

## NEG 剩余 12 项（交 CEO2 → RD2）

`neg-0.6-41`、`neg-1.3-01…06`、`neg-1.3-08`、`neg-1.3-09`、`neg-10.4-01…03`。

## GEN 剩余（跨域）

B2 sema（类型参数作用域/推断/`Call.TypeArgs`/重载/单态化，约 6h）、B3 interp（泛型执行，约 3h）、`TestGEN01CrossFile`（同 B2）。
