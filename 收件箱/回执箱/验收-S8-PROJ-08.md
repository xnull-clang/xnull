# 验收：S8-PROJ-08（配置严格性）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `3d46a7b`（含 S8-06 `07819c1`）
> **时间**：2026-11-08
> **证据**：`evidence/S8-QA/PROJ-08/`
> **依据**：S8 §6、PROJ-08；S8-06 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 未知键失败并列出 | **PASS**：3 个未知键逐一点名 |
| 缺失必需键失败 | **PASS**：`app.name` |
| 类型解析失败含键与层级/文件 | **PASS**：2 例，含 `application.properties` |
| 非 app 出现 `application.properties` 失败 | **PASS**：`TestNonAppConfigRejected` |
| 疑似密钥构建失败 | **PASS**：`db.password` / `api.token` |
| `${...}` 占位不误报 | **PASS** |
| 键名非法失败 | **PASS**：6 类 + CLI 非法键 |
| 配置文件必须在资源根顶层 / UTF-8 | **PASS** |

**判定：PASS。** XPD-6xx 严格校验面覆盖未知/缺失/类型/密钥/键名/位置。

---

## 二、实测

```text
$ go test ./internal/config -count=1 -v
PASS TestUnknownKeysListed（3 键）
PASS TestMissingRequiredKey（app.name）
PASS TestTypeMismatch（2 例 + 文件路径）
PASS TestSecretLiteralsRejected（db.password/api.token）
PASS TestSecretPlaceholderAllowed
PASS TestInvalidKeys（Bad/a_b/a..b/.a/a./超长）
PASS TestNonAppConfigRejected
PASS TestConfigFileMustBeAtResourcesRoot
PASS TestInvalidUTF8Rejected
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| 密钥检测 | 段名启发式（password/token 等）；正式密钥值走白名单 env |
| `xnull build` 接入 | 属 S8-04；本卡为配置加载器层 |
| 键名规则 | 与 S8 §6 一致；错误带文件/位置 |

---

## 四、证据

- `evidence/S8-QA/PROJ-08/matrix.tsv`
- `config-tests.log`（15 用例）
- `impl/internal/config/config_test.go`
- `收件箱/回执箱/回执-S8-06.md`
