# 验收：S8-PROJ-07（配置覆盖）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `3d46a7b`（含 S8-06 `07819c1`、S8-02 `01c5b2e`）
> **时间**：2026-11-08
> **证据**：`evidence/S8-QA/PROJ-07/`
> **依据**：S8 §6、PROJ-07；S8-06/S8-02 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 五层覆盖 configuration(0)→builtin(1)→application(2)→profile(3)→env(4)→CLI(5) | **PASS**：`TestLoadFiveLayers` |
| 来源层与 CLI 覆盖审计 | **PASS**：`Origins` + `key=db.url layer=5` |
| env 白名单：白名单外忽略 | **PASS**：`TestEnvWhitelistIgnoresNonWhitelisted` |
| profile 文件名与清单 id 不符失败 | **PASS**：`TestProfileMismatch`（XPD-6xx） |
| `-P` / `activation.platform` 激活与合并 | **PASS**：`TestProfiles` |
| 同键冲突 / 未知 profile / 不可覆盖段 | **PASS**：XPD-309 |
| 配置键名/位置/UTF-8 | **PASS**（见 PROJ-08） |

**判定：PASS。** 五层覆盖、白名单、profile 文件与合并语义均成立；CLI 审计不记录值。

---

## 二、实测

```text
$ go test ./internal/config -count=1 -v
PASS TestLoadFiveLayers / TestEnvWhitelistIgnoresNonWhitelisted /
     TestProfileMismatch / ... 15 用例

$ go test ./internal/manifest -run 'TestProfiles|TestParentChainRules' -count=1 -v
PASS TestProfiles/-P 激活与合并 / platform 激活 / 同键冲突 / 未知 profile / 不可覆盖段
```

`TestLoadFiveLayers` 断言：
- `app.name=svc`（builtin）、`net.http.listen-port=9090`（CLI）、`db.url=cli`（CLI）；
- `db.password=s3cret`（env 白名单）、`feature.flag=true`（application）、`app.ratio=1.5`（profile；env 非白名单被忽略）。

---

## 三、边界

| 项 | 说明 |
|---|---|
| `xnull build` 清单模式接入 | 属 S8-04；本卡交付纯加载器 + manifest profile 合并 |
| 热重载/配置中心 | S8 §10 否决，不做 |
| 密钥正式值 | 走白名单环境变量；`${...}` 占位允许 |

---

## 四、证据

- `evidence/S8-QA/PROJ-07/matrix.tsv`
- `config-tests.log`（15 用例）
- `manifest-profiles.log`（激活/合并/冲突）
- `impl/internal/config/config_test.go`、`impl/internal/manifest/manifest_test.go`
- `收件箱/回执箱/回执-S8-06.md`、`回执-S8-02.md`
