# 验收：S8-PROJ-07（配置五层/profile，端到端复签）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（层 0/2/3 端到端；层 1/4/5 沿用 config 单元证据，见边界）
> **复验点**：main `9c4f51e`（S8-12 已入 main）；`68d29f4`、`9de80eb` 正例抽检复跑通过
> **时间**：2026-11-08
> **证据**：`evidence/S8-12-E2E/f3/`、`matrix-PROJ-07.tsv`
> **依据**：S8 §6.4、PROJ-07；`收件箱/门/S8-12验收用例-QA.md`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull build --profile`；未做 git 操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 层 2（application）覆盖层 0（configuration） | **PASS**：`configSha256=e960…` 与期望值逐字节一致（`app.env=file`、`app.name=from-file`） |
| 层 3（profile 文件）覆盖层 2 | **PASS**：`--profile dev` 后 `configSha256=b5a3…` 与期望值一致（`app.env=dev-file`） |
| profile 激活入 `.xmeta` | **PASS**：`profiles = [dev]` |
| profile properties 参与层 0 替换 | **PASS**：`appName=demo-dev` 生效，但层 2 仍将 `app.name` 覆盖为 `from-file` |
| 摘要可复现 | **PASS**：同输入两次构建 `.xmeta` 一致 |

**判定：PASS（带边界）。** 构建链可观测的三层顺序与 profile 合并符合 S8 §6.4；层 1/4/5 未在 `xnull build` 注入口暴露。

---

## 二、实测（摘要反推，证明值而非仅“有变化”）

期望值按 `hashKeyValues`（排序 `k=v\n` 后 SHA-256）独立计算：

```text
base:
  期望 e9604569…  == 实际 e9604569…
  值: app.env=file(layer2) / app.name=from-file(layer2) / feature.flag=true / net.port=8080
profile dev:
  期望 b5a374d3…  == 实际 b5a374d3…
  值: app.env=dev-file(layer3) / app.name=from-file(layer2) / feature.flag=true / net.port=8080

$ xnull build --profile dev && grep -E "profiles|configSha256" target/app-1.0.0.xmeta
profiles         = [dev]
configSha256     = b5a374d3…
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| 层 1 builtin / 层 4 env / 层 5 CLI | `xnull build` 未注入；`config.Load` 单元测试已覆盖（PROJ-07 原验收） |
| env 白名单 | 清单未暴露 `envOverrides` 到 build；无法端到端构造 |
| profile 文件“已声明未激活” | 触发 `XPD-607`（见用例 §4.7 R1）；本卡按“激活集”语义验收，语义待董事会确认 |
| 配置值可见性 | `.xmeta` 只存摘要；本卡用独立计算的期望摘要反推最终值 |

---

## 四、证据

- `evidence/S8-12-E2E/matrix-PROJ-07.tsv`
- `f3/F3-build.log`、`f3/F3-meta.log`
- `f3/F3-profile.log`、`f3/F3-meta-profile.log`
- `f3/F3-config-digest-proof.txt`（期望 vs 实际摘要）
- `f3/F3-deterministic.txt`
