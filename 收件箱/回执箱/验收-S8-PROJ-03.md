# 验收：S8-PROJ-03（依赖/仲裁/锁，端到端复签）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（S8-12 接入后按真实工程复验）
> **复验点**：main `9c4f51e`（S8-12 已入 main）；`68d29f4`、`9de80eb` 正例抽检复跑通过
> **时间**：2026-11-08
> **证据**：`evidence/S8-12-E2E/f2*/`、`evidence/S8-12-E2E/matrix-PROJ-03.tsv`
> **依据**：S8 §3.5–§3.8/§4、PROJ-03；`收件箱/门/S8-12验收用例-QA.md`；`回执-S8-12.md`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull lock/build`；未做 git 操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 传递依赖图 | **PASS**：锁 2 条 `g:lib 2.0.0`、`g:top 1.0.0` |
| 锁校验 | **PASS**：`锁有效（2 条）` |
| `.xmeta.lockSha256` | **PASS**：`33fb9b4c…` 与 `shasum -a 256 xnull.lock` 一致 |
| 锁可复现 | **PASS**：两次 `--update-lock` 字节一致 |
| 管理版本优先 | **PASS**：`app-managed` 选中 `g:lib 1.0.0`（传递版本 2.0.0 被钉住） |
| 显式覆盖管理版本 | **PASS**：告警输出，锁仍为管理版本 1.0.0 |
| 锁缺条目 | **PASS**：`XPD-404` |
| 锁多余坐标 | **PASS**：`XPD-405` |
| 摘要不符 | **PASS**：`XPD-406` |
| 锁与清单版本不一致 | **PASS**：`XPD-404` |
| 同深度冲突 | **PASS**：`XPD-403`，列出 `g:a@1.0.0`/`g:b@1.0.0`/`g:x@2.0.0`/`g:x@3.0.0` |
| 依赖环 | **PASS**：`XPD-409`（含路径） |
| 依赖缺版本 / 范围版本 | **PASS**：`XPD-401` / `XPD-402` |

**判定：PASS。** 图仲裁、锁生成/校验、摘要与版本一致性、管理版本优先级均与 S8 §4 一致。

---

## 二、实测

```text
$ export XNULL_REPO=tests/s8/s812/f2-dep-lock/repo
$ cd tests/s8/s812/f2-dep-lock/app
$ xnull lock --update-lock
已生成 …/xnull.lock：2 条
$ xnull lock
锁有效：…/xnull.lock（2 条）
$ xnull build
…/target/app-1.0.0                        # exit 0
$ shasum -a 256 xnull.lock
33fb9b4c253417230c28ce22485c670681ccd1bc1014c6787d1b795ddb58933e
# .xmeta.lockSha256 同值；再次 --update-lock 后 cmp 字节一致

$ cd ../app-managed && xnull lock --update-lock
entry g:lib 1.0.0 / entry g:top 1.0.0      # 管理版本优先

$ 负例：XPD-404 / 405 / 406 / 404 / 403 / 409 / 401 / 402
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| 依赖制品链接 | 依赖只参与图/锁校验，不链接 `.xlib`（S8-13） |
| 图冲突触发路径 | 无锁 build 不校验图；本卡用 `xnull lock` 触发 XPD-403/409 |
| `xnull lock --profile` | 命令未接 profile；profile 依赖不可锁（按计划顺延） |
| 远程仓库 | 仅 `XNULL_REPO` 本地仓库布局 |
| 传递依赖范围 | compile/runtime 传递；test/provided 不传递（既有单元证据） |

---

## 四、证据

- `evidence/S8-12-E2E/matrix-PROJ-03.tsv`
- `f2/F2-lock-generate.log`、`F2-lock-validate.log`、`F2-build.log`、`F2-meta.log`、`F2-lock-sha.log`、`F2-repro.txt`、`F2-managed.log`
- `f2-neg/F2-N1.log` … `F2-N9.log`
- `LATEST-f2.log`（`68d29f4` 抽检）
- 夹具：`tests/s8/s812/f2-dep-lock/`（含本地仓库）
