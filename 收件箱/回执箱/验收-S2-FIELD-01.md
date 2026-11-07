# 验收：S2-FIELD-01（字段访问）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `05e680c`（`05e680c2367058c617127eb9ce95dc081acf430e`）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-s2-base`，sha256 `5721de8325a4c4804180b9ae5ef26095ad2d7273d18602e9700e076f16dadbf3`
> **证据**：`evidence/S2-QA/FIELD-01-05e680c/`
> **依据**：`XNull解决方案-第2部分-对象编程-v3.3.0.md` §7.3/§7.4、§18 FIELD-01；`internal/sema/typedecl_test.go:TestPrivateFieldRules`
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `private name` 与 `_name` 两种私有形式 | **PASS**：双路径 `1/2` |
| `private _name` 拒绝 | **PASS**：`TY-207` @1:23 |
| `public`/`protected` 与 `_name` 同时出现拒绝 | **PASS**：`TY-207` @1:22 |
| `_` / `__x` / `_1` 非法 | **PASS**：`TY-207` @2:9/3:9/4:9 |
| 类内 `self._name` 拒绝 | **PASS**：`TY-207` @3:28 |
| 类内裸 `name` 拒绝 | **PASS**：`TY-207` @3:24 |
| 外部 `name` / `_name` 都拒绝 | **PASS**：`TY-207` @4:12 |
| 同类局部/参数 `_name` 拒绝 | **PASS**：`TY-207` @4:9 |
| 字段隐藏拒绝 | **PASS**：`TY-203` @2:7 |
| protected 子类访问 | **PASS**：双路径 `6` |
| 跨包 private / protected 拒绝 | **PASS**：`TY-207` / `TY-209` |
| 官方 `TestPrivateFieldRules` | **PASS** |

**判定：PASS。** 私有字段规范名、类内/外部访问、局部冲突、字段隐藏与跨包可见性全部成立；正例双路径一致，负例带诊断码与位置。

---

## 二、逐项实测

### 2.1 正例

| 用例 | 期望 | interp | compiled | 判定 |
|---|---|---|---|---|
| `a01_private_forms` `private name` + `_name` | `1\n2` | 一致，rc=0 | 一致，rc=0 | **PASS** |
| `a02_protected_subclass` 子类访问 protected 字段/方法 | `6` | 一致，rc=0 | 一致，rc=0 | **PASS** |

### 2.2 负例（三路径一致）

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| `r01_private_underscore` | 码+位置 | `1:23 error[TY-207]` | **PASS** |
| `r01_public_underscore` | 码+位置 | `1:22 error[TY-207]` | **PASS** |
| `r01_bad_names` `_`/`__x`/`_1` | 码+位置 | `2:9/3:9/4:9 error[TY-207]` | **PASS** |
| `r02_self_underscore` | 码+位置 | `3:28 error[TY-207]` | **PASS** |
| `r02_bare_name` | 码+位置 | `3:24 error[TY-207]` | **PASS** |
| `r02_external_name` | 码+位置 | `4:12 error[TY-207]` | **PASS** |
| `r02_external_underscore` | 码+位置 | `4:12 error[TY-207]` | **PASS** |
| `r02_local_param` | 码+位置 | `4:9 error[TY-207]` | **PASS** |
| `r02_field_hiding` | 码+位置 | `2:7 error[TY-203]` | **PASS** |
| `X01-private` 跨包 private | 码+位置 | `4:12 error[TY-207]` | **PASS** |
| `X02-protected` 跨包 protected | 码+位置 | `4:12 error[TY-209]` | **PASS** |

---

## 三、回归

| 项 | 结果 |
|---|---|
| `go test ./internal/sema -run 'TestPrivateFieldRules' -count=1` | PASS |
| `go test ./internal/sema ./internal/codegen ./internal/xfront ./internal/cli ./internal/interp -count=1` | 全绿 |
| `go vet ./...` | exit 0 |
| `go test ./... -count=1 -timeout 1200s` | **未完成**：`internal/codegen` 在机器争用下触发 20m 超时；与本锚点无关，GATE-01 需固定低负载/拆分重跑 |

---

## 四、证据

- `evidence/S2-QA/FIELD-01-05e680c/matrix.tsv`
- `evidence/S2-QA/FIELD-01-05e680c/S2-FIELD-a01_private_forms/{check,interp,compiled}/`、`a02_protected_subclass/`
- `evidence/S2-QA/FIELD-01-05e680c/S2-FIELD-r01_*`、`r02_*`、`X01-private/`、`X02-protected/`
- `evidence/S2-QA/FIELD-01-05e680c/gotest-sema/`
- 夹具：`wt/qa-1/difftest/s2/field01/`（含 `xpkg/`）
