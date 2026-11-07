# 验收：S2-BND-06（枚举）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（§16 的 switch 门全部通过；S2 计划 A02 的「数据枚举项单例/不可变」未闭合）
> **复验点**：main `47fedb8`（`47fedb8ad1659925af04a677a9e82b861c2dffcd`）
> **时间**：2026-11-07
> **证据**：`evidence/S2-QA/BND-06/`、`evidence/S2-QA/matrix.tsv`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 枚举不实现协议 | **PASS**：`SYN-101` + 位置 |
| 无 `default` 时穷尽性（遗漏项） | **PASS**：`TY-213`，列出遗漏项 |
| 重复项 | **PASS**：`TY-213` + 位置 |
| 未知项 / 非项常量 case | **PASS**：`TY-213` + 位置 |
| `default` 位置（必须在最后） | **PASS**：`TY-213` + 位置 |
| `default` 最多一个 | **PASS**：`SYN-101` + 位置 |
| 简单枚举内联 / 格式化 / switch 命中 | **PASS**：双路径 `Green`、`g` |
| 数据枚举项构造、字段读取、单例身份 | **PASS**：`Ready`/`0`；`Ready===Ready=true`、`Ready===Failed=false` |
| 数据枚举项不可变（字段 `final`，方法不能写字段） | **FAIL**：外部写入与方法写入均被接受（check rc=0） |
| 数据枚举项不能 `new` | **FAIL**：`check` rc=0，仅运行/代码生成期报「未定义的类」 |

**判定：FAIL。** BND-06 的 §16 门（枚举不实现协议 + switch 四项检查）全部成立；失败点是 S2 验收计划 A02 的「数据枚举项单例/不可变」：`final` 字段写入未在 sema 强制，数据枚举外部 `new` 未在编译期拒绝。台账 BND-06 不得改 PASS。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `A01a` 简单枚举格式化 | `Green` | `Green`，rc=0 | `Green`，rc=0 | **PASS** |
| `A01b` 无 default 穷尽 switch | `g` | `g`，rc=0 | `g`，rc=0 | **PASS** |
| `A02a` 数据枚举项 + 字段 | `Ready\n0\n` | `Ready\n0\n`，rc=0 | `Ready\n0\n`，rc=0 | **PASS** |
| `A02c` 数据枚举项身份 | `true\nfalse\ntrue\n` | 同左，rc=0 | 同左，rc=0 | **PASS** |
| `A02b` 全 case + default 在最后 | `r` | `r`，rc=0 | `r`，rc=0 | **PASS** |

### 2.2 负例（`xnull check`，期望 rc≠0）

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `R01` 非穷尽 switch | 拒绝 + 码/位置 | `r01_non_exhaustive.x:4:5: error[TY-213]: 枚举 switch 未覆盖全部项（§8.5）：遗漏 Green、Blue` | **PASS** |
| `R02a` 重复 case | 拒绝 + 码/位置 | `r02_dup_case.x:7:19: error[TY-213]: 枚举项 \`Red\` 在 switch 中重复（§8.5）` | **PASS** |
| `R02b` 未知项 / 非项常量 | 拒绝 + 码/位置 | `r02_unknown.x:12:19: error[TY-213]: 枚举 switch 的 case 必须是 \`Color.<项>\` 项常量（§8.5）` | **PASS** |
| `R03a` `default` 不在最后 | 拒绝 + 码/位置 | `r03_default_first.x:5:9: error[TY-213]: default 子句必须位于 switch 最后（§8.5）` | **PASS** |
| `R03b` 两个 `default` | 拒绝 + 码/位置 | `r03_two_default.x:4:5: error[SYN-101]: default 子句最多一个` | **PASS** |
| `R04` 枚举 implements 协议 | 拒绝 + 码/位置 | `r04_impl.x:2:12: error[SYN-101]: 期望枚举体 \`{\`…` | **PASS** |

### 2.3 失败项（数据枚举不可变 / 单例）

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `R05` 外部写数据枚举项字段 `Status.Ready.code = 9` | `check` 拒绝 | `check` rc=0；interp/compiled 输出 `9` | **FAIL** |
| `R06` 外部 `new Status(1)` | `check` 拒绝（构造器隐式私有） | `check` rc=0；interp `未定义的类：Status`，compiled `codegen：未定义的类 Status` | **FAIL** |
| `R07` 数据枚举方法内写字段 `self.code = 9` | `check` 拒绝 | `check` rc=0；interp/compiled rc=0 | **FAIL** |

根因定位：

- `final` 字段只在构造器赋值计数处检查（`impl/internal/sema/typedecl.go:728` `checkFinalFieldAssignments`），**构造完成后对实例字段的写入未检查**。同一缺口在普通类上也可复现：`final Int x = 1; c.x = 2` → `check` rc=0、运行输出 `2`（`evidence/S2-QA/BND-06/probe-class-final/`）。
- 数据枚举的隐式私有构造器未进入 sema 的 `new` 目标检查；`Status` 被当作可 `new` 的类型，直到 codegen/interp 才报「未定义的类」。
- 两项均属 E2 sema；与 PCTOR-01 R05「`final` 字段重复赋值未拒绝」同源。

---

## 三、官方用例

| 用例 | 覆盖 | 结果 |
|---|---|---|
| `internal/sema/s2_bnd06_test.go:TestS2BND06EnumSwitch` | 穷尽 / 遗漏 / 未知 / 重复 / 有 default / 非枚举 switch / 任意表达式 case | **PASS** |
| `internal/sema/s2_enum_default_test.go:TestS2EnumDefaultLast` | `default` 必须在最后；`default` 后置合法 | **PASS** |
| `internal/sema/typedecl_test.go:TestEnumRules` | 项唯一 / 值唯一 / 混合形式 / 非 final 字段 / 项参数不匹配 / 无构造器 / 简单枚举带方法 | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2EnumSimpleAndSwitch` | 简单枚举格式化 + 穷尽 switch | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2EnumDataSingleton` | 数据枚举项字段/方法/格式化 | **PASS** |
| `internal/interp/s2_enum_isas_test.go:TestS2EnumSimpleRuntime/TestS2EnumDataRuntime/TestS2EnumUnknownItemRejected` | 解释器枚举运行时 | **PASS** |

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2BND06EnumSwitch\|TestS2EnumDefaultLast\|TestEnumRules' -count=1` | **PASS** |
| `go test ./internal/codegen -run 'TestS2EnumSimpleAndSwitch\|TestS2EnumDataSingleton' -count=1` | **PASS** |
| `go test ./internal/interp -run 'TestS2Enum' -count=1` | **PASS** |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 1200s` | **1 红**：`internal/devtool` `TestBuildLedgerRepoGoldenScale`（台账 PASS 13 / golden 18），与本锚点无关但阻断 GATE-01。 |

---

## 五、放行条件

1. E2：数据枚举项字段写入（外部 `Status.Ready.code = ...` 与方法内 `self.code = ...`）在 sema 拒绝，带码 + 位置。
2. E2：数据枚举外部 `new Status(...)` 在 sema 拒绝（隐式私有构造器），不得只在运行期失败。
3. 复跑 `R05`–`R07` check rc≠0；A01/A02 保持当前输出。
4. 若董事会将 BND-06 口径限定为 §16 的 switch 门，则上述两项转入 ENUM-01 / BND-14，不阻断 BND-06；本回执按 S2 验收计划 A02 判 FAIL。

---

## 六、证据

- `evidence/S2-QA/BND-06/A01a/`、`A01b/`、`A02a/`–`A02c/`、`R01/`–`R07/`（含 `cmd.txt`、`check.*`、`interp.*`、`compiled.*`、`sha.txt`）
- `evidence/S2-QA/BND-06/probe-class-final/`（普通类 `final` 写入同源缺口）
- `evidence/S2-QA/qa-c-sema.log`、`qa-c-codegen.log`、`qa-c-interp.log`、`qa-c-fulltest.log`、`qa-c-vet.log`
- `evidence/S2-QA/matrix.tsv`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §8.2–§8.5、§16 BND-06
