# 验收：S8-PROJ-08（配置严格校验，端到端复签）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（build 链可达的 6xx 全部命中；604/605 见边界）
> **复验点**：main `9c4f51e`（S8-12 已入 main）；`68d29f4`、`9de80eb` 正例抽检复跑通过
> **时间**：2026-11-08
> **证据**：`evidence/S8-12-E2E/f3-neg/`、`matrix-PROJ-08.tsv`
> **依据**：S8 §6、PROJ-08；`收件箱/门/S8-12验收用例-QA.md`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull build`；未做 git 操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 非法键名 | **PASS**：`XPD-601`（`App.Name`） |
| 同层重复键 | **PASS**：`XPD-602`（`app.name`） |
| 未知键 | **PASS**：`XPD-603`（`unknown.setting`） |
| 疑似密钥字面量 | **PASS**：`XPD-606`（`db.password=plain`；未声明时并存 `XPD-603`） |
| profile 文件名不符 | **PASS**：`XPD-607`（`application-staging.properties`） |
| 配置文件不在资源根顶层 | **PASS**：`XPD-608`（`conf/application.properties`） |
| 非 UTF-8 | **PASS**：`XPD-600` |
| 缺失必需键 / 类型不符 | **BOUNDARY**：build 将 configuration 全按 `KindString`，无 Required/类型规格，E2E 不可达；沿用 `internal/config` 单元证据 |

**判定：PASS。** 所有在 build 链可达的严格校验诊断均按预期码、位置与退出码失败。

---

## 二、实测

```text
$ xnull build   # 逐个变体
XPD-601 App.Name                                   # exit 1
XPD-602 app.name（首次第 1 行）                     # exit 1
XPD-603 unknown.setting                            # exit 1
XPD-606 db.password（+ XPD-603）                    # exit 1
XPD-607 application-staging.properties             # exit 1
XPD-608 conf/application.properties                # exit 1
XPD-600 配置文件不是合法 UTF-8                      # exit 1
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| `XPD-604` 缺失必需键 / `XPD-605` 类型不符 | build 无 Required/KindInt 规格；PROJ-08 原验收的 config 单元用例已覆盖 |
| 非 app 工程配置（`XPD-608` 另一分支） | `resolveEntry` 先对非 app 报 `XPD-201`，该分支 E2E 不可达；待 S8-14 |
| 密钥白名单（env） | build 未注入 env 白名单，“正确走环境变量”的正例不可端到端构造 |

---

## 四、证据

- `evidence/S8-12-E2E/matrix-PROJ-08.tsv`
- `f3-neg/F3-N1.log`（601）、`F3-N2.log`（602）、`F3-N3.log`（603）
- `f3-neg/F3-N4.log`（606 + 603）、`F3-N5.log`（607）
- `f3-neg/F3-N6.log`（608）、`F3-N8.log`（600）
- 夹具与变体构造：`收件箱/门/S8-12验收用例-QA.md` §4.4
