# 验收：S8-PROJ-11（资源完整面，端到端复签）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（app 资源面端到端；pom/依赖合并见边界）
> **复验点**：main `9c4f51e`（S8-12 已入 main）；`68d29f4`、`9de80eb` 正例抽检复跑通过
> **时间**：2026-11-08
> **证据**：`evidence/S8-12-E2E/f3/`、`f3-neg/`、`matrix-PROJ-11.tsv`
> **依据**：S8 §5.6、PROJ-11；`收件箱/门/S8-12验收用例-QA.md`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull build`；未做 git 操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 制品内 `resources/<相对路径>` 前缀 | **PASS**：产物含 `templates/a.txt`、`conf/app.conf` |
| includes/excludes | **PASS**：`skip.psd` 未进入产物 |
| 多资源根合并 | **PASS**：主资源根 + `extra/resources` 同时入产物 |
| 缺省资源根自动收录 | **PASS**：无 `resources` 段时 `src/main/resources` 被收录（含 `skip.psd`） |
| 资源根不存在 | **PASS**：`XPD-801` |
| 字符类 glob | **PASS**：`XPD-802` |
| 同路径冲突 | **PASS**：`XPD-803`，点名两个绝对来源 |
| 断链 symlink | **PASS**：`XPD-805` |
| pom 声明资源 / 依赖资源合并 / starter | **BOUNDARY**：见下表 |

**判定：PASS（带边界）。** app 打包链上的资源收割、前缀、过滤、冲突与 symlink 行为全部符合 S8 §5.6。

---

## 二、实测

```text
$ xnull build    # F3-a
…/target/app-1.0.0                          # exit 0
$ strings target/app-1.0.0 | grep -E "templates/a.txt|conf/app.conf|skip.psd"
conf/app.conf
templates/a.txt                             # skip.psd 未命中

$ 默认资源根变体（删除 build.resources）
templates/a.txt
skip.psd                                    # 无 excludes 时收录

$ 负例
XPD-801 / XPD-802 / XPD-803（双来源绝对路径）/ XPD-805   # 均 exit 1
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| `XPD-804` pom 声明资源 | `resolveEntry` 对非 app 先报 `XPD-201`，资源校验不可达；待 S8-14 reactor |
| 依赖资源合并 / starter 不合并 | 依赖未链接 `.xlib`（S8-13）；沿用 `internal/resman` 单元证据 |
| symlink 指向目录 | 单元已覆盖；本卡只构造断链 |
| 资源字节完整 | 本卡断言语义路径与排除；未做二进制逐字节上限/大文件测试 |
| `.x` 数据资源 | 收割按字节；端到端未单独构造 |

---

## 四、证据

- `evidence/S8-12-E2E/matrix-PROJ-11.tsv`
- `f3/F3-build.log`、`f3/F3-resources.txt`
- `f3/F3-default-root.log`、`f3/F3-default-resources.txt`
- `f3-neg/F3-N9.log`（801）、`F3-N10.log`（802）、`F3-N11.log`（803）、`F3-N12.log`（805）
- 夹具：`tests/s8/s812/f3-integration/`
