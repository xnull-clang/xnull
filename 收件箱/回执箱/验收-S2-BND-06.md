# 验收：S2-BND-06（枚举）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `e2f943c`（含 `c90880d` 数据枚举项不可变；按用户声明，本次未运行 git 命令）
> **时间**：2026-11-07
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-A2-BND-06/`、`/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/qa-a2-*.log`

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
| 数据枚举项字段外部不可写 | **PASS**：`TY-218` + 位置 |
| 数据枚举方法内不可写字段 | **PASS**：`TY-218` + 位置 |
| 数据枚举不可 `new`（类型或项） | **PASS**：`TY-218` + 位置 |

**判定：PASS。** `c90880d` 的 `TY-218` 检查覆盖了外部写、方法内写、`new Status(...)` 与 `new Status.Ready()` 四种形态；switch 门与数据枚举只读面均成立。台账 BND-06 可登记为 PASS。

---

## 二、逐项实测

### 2.1 正例（双路径）

| 用例 | 期望 | 解释路径 | 编译路径 | 判定 |
|---|---|---|---|---|
| `A01a` 简单枚举格式化 | `Green` | `Green`，rc=0 | `Green`，rc=0 | **PASS** |
| `A01b` 无 default 穷尽 switch | `g` | `g`，rc=0 | `g`，rc=0 | **PASS** |
| `A02a` 数据枚举项 + 字段读取 | `Ready\n0\n` | `Ready\n0\n`，rc=0 | `Ready\n0\n`，rc=0 | **PASS** |
| `A02b` 全 case + default 在最后 | `r` | `r`，rc=0 | `r`，rc=0 | **PASS** |
| `A02c` 数据枚举项身份 | `true\nfalse\ntrue\n` | 同左，rc=0 | 同左，rc=0 | **PASS** |
| `A03read` 数据枚举字段读取（只读） | `0` | `0`，rc=0 | `0`，rc=0 | **PASS** |

### 2.2 负例（`xnull check`，期望 rc≠0）

| 用例 | 实测诊断 | 判定 |
|---|---|---|
| `R01` 非穷尽 switch | `source.x:4:5: error[TY-213]: 枚举 switch 未覆盖全部项（§8.5）：遗漏 Green、Blue` | **PASS** |
| `R02a` 重复 case | `source.x:7:19: error[TY-213]: 枚举项 \`Red\` 在 switch 中重复（§8.5）` | **PASS** |
| `R02b` 未知项 / 非项常量 | `source.x:12:19: error[TY-213]: 枚举 switch 的 case 必须是 \`Color.<项>\` 项常量（§8.5）` | **PASS** |
| `R03a` `default` 不在最后 | `source.x:5:9: error[TY-213]: default 子句必须位于 switch 最后（§8.5）` | **PASS** |
| `R03b` 两个 `default` | `source.x:4:5: error[SYN-101]: default 子句最多一个` | **PASS** |
| `R04` 枚举 implements 协议 | `source.x:2:12: error[SYN-101]: 期望枚举体 \`{\`…` | **PASS** |
| `R05` 外部写 `Status.Ready.code = 9` | `source.x:7:17: error[TY-218]: 数据枚举项字段不可变（§8.3）` | **PASS** |
| `R06` 外部 `new Status(1)` | `source.x:7:16: error[TY-218]: 数据枚举类型不能 new（§8.3）` | **PASS** |
| `R07` 方法内 `self.code = 9` | `source.x:5:10: error[TY-218]: 数据枚举方法不能写字段（§8.3：实例不可变）` | **PASS** |
| `R08` 外部 `new Status.Ready()` | `source.x:7:16: error[TY-218]: 数据枚举项不能 new（§8.3）` | **PASS** |

全部负例 `check/interp/compiled` 三路径 rc=1；诊断带 `file:line:col` 与 `TY-213` / `TY-218` / `SYN-101`。

---

## 三、官方用例

| 用例 | 覆盖 | 结果 |
|---|---|---|
| `internal/sema/s2_enum_immutable_test.go:TestS2EnumImmutable` | 外部写 / 方法写 / `new` 项拒绝；字段读取允许 | **PASS** |
| `internal/sema/s2_bnd06_test.go:TestS2BND06EnumSwitch` | 穷尽 / 遗漏 / 未知 / 重复 / 有 default / 非枚举 switch / 任意表达式 case | **PASS** |
| `internal/sema/s2_enum_default_test.go:TestS2EnumDefaultLast` | `default` 最后；后置合法 | **PASS** |
| `internal/sema/typedecl_test.go:TestEnumRules` | 项唯一 / 值唯一 / 混合形式 / 非 final 字段 / 项参数不匹配 / 无构造器 / 简单枚举带方法 | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2EnumSimpleAndSwitch` | 简单枚举格式化 + 穷尽 switch | **PASS** |
| `internal/codegen/s2_object_test.go:TestS2EnumDataSingleton` | 数据枚举项字段/方法/格式化 | **PASS** |
| `internal/interp/s2_enum_isas_test.go:TestS2EnumSimpleRuntime/TestS2EnumDataRuntime/TestS2EnumUnknownItemRejected` | 解释器枚举运行时 | **PASS** |

规则位置：`impl/internal/sema/ty.go:1235`（`new` 拒绝）、`impl/internal/sema/ty.go:841`（外部写拒绝）、`impl/internal/sema/typedecl.go:649`（方法内写拒绝）、`TY-218` 定义在 `typedecl.go:43`。

---

## 四、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestS2EnumImmutable\|TestS2BND06EnumSwitch\|TestS2EnumDefaultLast\|TestEnumRules\|TestS2BND0708' -count=1` | **PASS** |
| `go test ./internal/codegen -run 'TestS2EnumSimpleAndSwitch\|TestS2EnumDataSingleton\|TestS2INT01TryMemberCall' -count=1` | **PASS** |
| `go test ./internal/interp -run 'TestS2INT01\|TestS2Enum' -count=1` | **PASS** |
| `go test ./internal/sema ./internal/interp ./internal/codegen -count=1` | **PASS**（三包全量） |
| `go vet ./internal/sema ./internal/interp ./internal/codegen` | exit 0 |

本次按“只验两项”未跑全仓 `go test ./...`；三包全量与针对性用例已覆盖 BND-06。

---

## 五、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-A2-BND-06/A01a/`、`A01b/`、`A02a/`–`A02c/`、`A03read/`、`R01/`–`R08/`（每条含 `source.x`、`cmd.txt`、`check.*`、`interp.*`、`compiled.*`、`sha.txt`）
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/QA-A2-BND-06/matrix.tsv`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S2-QA/qa-a2-sema.log`、`qa-a2-codegen.log`、`qa-a2-interp.log`、`qa-a2-targeted.log`、`qa-a2-vet.log`
- 断言依据：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §8.2–§8.5、§16 BND-06
