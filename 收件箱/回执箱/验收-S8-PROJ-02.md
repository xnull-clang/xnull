# 验收：S8-PROJ-02（继承/变量/profile，端到端复签）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（S8-12 接入后按真实工程复验）
> **复验点**：main `9c4f51e`（S8-12 已入 main）；`68d29f4`、`9de80eb` 正例抽检复跑通过
> **时间**：2026-11-08
> **证据**：`evidence/S8-12-E2E/f1*/`、`evidence/S8-12-E2E/matrix-PROJ-02.tsv`
> **依据**：S8 §3.3/§3.4/§3.8、PROJ-02；`收件箱/门/S8-12验收用例-QA.md`；`回执-S8-12.md`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull build/run`；未做 git 操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 父 `build.sourceRoot=alt/src` 继承 | **PASS**：入口 `alt/src/main.x`，产物 `target/app-1.0.0` |
| 父 properties 继承 | **PASS**：`.xmeta` `xdkVersion = 1.2.3` |
| 子覆盖父属性 | **PASS**：`languageVersion = 3.4.0`（父 3.3.0） |
| `--profile dev` 合并 | **PASS**：`languageVersion = 9.9.9`、`profiles = [dev]` |
| 变量替换 | **PASS**：`${appName}` 解析；未解析变量报 `XPD-307` |
| parent 缺失 | **PASS**：`XPD-305`，exit 2 |
| parent 非 pom | **PASS**：`XPD-306`，exit 2 |
| 未解析变量 | **PASS**：`XPD-307`，exit 2 |
| 未知 `-P` | **PASS**：`XPD-309`，exit 2 |
| 父 profile 不继承 | **PASS**：`XPD-309`，exit 2 |

**判定：PASS。** 继承按字段级覆盖、属性替换、profile 合并与负例码全部与 S8 §3 一致。

---

## 二、实测

```text
$ cd tests/s8/s812/f1-parent/app && xnull build
F1-TEST-OK
…/target/app-1.0.0                         # exit 0

$ xnull run
F1-TEST-OK
F1-MAIN-OK                                 # exit 0

$ xnull build --profile dev && grep languageVersion target/app-1.0.0.xmeta
languageVersion  = 9.9.9
profiles         = [dev]

$ xnull build   # F1-N1..N5 变体
XPD-305 / XPD-306 / XPD-307 / XPD-309(staging) / XPD-309(dev)  # 均 exit 2
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| 坐标不从 parent 继承 | S8 §3.3 明确；用例按子工程坐标断言 |
| 父 profile 不继承 | S8 §3.8 明确；本卡已加负例 |
| parent 定位 | 仅 `relativePath`；本地/远程仓库定位属 S8-13 |
| 父资源根 | 继承后按子工程根解析（未在本卡构造）；风险留给 S8-13/14 |
| 入口运行 | `build` 只编译入口；主程序执行由 `run` 验证 |

---

## 四、证据

- `evidence/S8-12-E2E/matrix-PROJ-02.tsv`
- `f1/F1-build.log`、`F1-run.log`、`F1-meta-base.log`、`F1-profile.log`、`F1-meta-profile.log`
- `f1-neg/F1-N1.log` … `F1-N5.log`
- `LATEST-f1.log`（`68d29f4` 抽检）
- 夹具：`tests/s8/s812/f1-parent/`、`tests/s8/s812/gen.sh`
