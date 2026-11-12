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

---

# 聚合面补记：S8-14 reactor（2026-11-08）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（聚合拓扑/依赖/安装通过；starter 模块无法参与构建，P0 阻塞）
> **复验点**：main `25f8be6`（含 S8-14 `ae1a573`；S8-13 `.xlib` 已入）
> **证据**：`evidence/S8-14-E2E/`、`tests/s8/s814/`、`matrix-S8-14.tsv`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull build`；未做 git 操作。

## 一、结论

| 聚合面检查 | 结果 |
|---|---|
| pom 聚合根 + 2 library + 1 app，逆序声明仍按拓扑构建 | **PASS**：摘要顺序 `core→codec→app`（声明为 `app,codec,core`） |
| library 产 `.xlib` 并安装本地仓库 | **PASS**：`repo/io/xnull/{core,codec}/1.0.0/*.xlib` |
| 聚合根 `dependencyManagement` 注入模块 | **PASS**：模块省略版本可构建，无 XPD-401 |
| starter 依赖版本一致性（并入使用者） | **PASS**：bundle 与 app 均报 `XPD-403`（9.9.9 ≠ 1.0.0） |
| starter 含 `src/` 拒绝 | **PASS**：`XPD-201` |
| **starter 模块参与聚合构建** | **FAIL**：`bundle` 以空入口进入 compile → `RES-106 找不到包文件 .`，reactor 报 `XPD-201`，后续 app 不构建、无聚合摘要 |
| 失败即停（非 starter） | **PASS**：core 已建/已装，codec 失败后 app 与根 `target/` 不存在 |

**判定：FAIL。** 聚合拓扑、模块仲裁、`.xlib` 安装与失败即停成立；`packaging=starter` 模块没有生命周期分支，导致含 starter 的聚合工程无法构建。计划级 starter 展开（单元测试与 XPD-403 传播）成立，但端到端不成立。

## 二、失败项（P0）

| # | 失败 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | reactor 对每个模块统一调用 `buildManifestManaged`；`run()` 只对 `library` 分支，`starter` 落入 app 编译路径并以空入口编译 | `with-starter.log` | E6（`internal/cli/manifest.go` / `reactor_build.go`） |
| P-02 | 失败信息双重包装：`模块 bundle 构建失败：模块 bundle 构建失败（exit=1）` | `with-starter.log` | E6（诊断可读性，P2） |

## 三、放行条件

1. `starter` 模块跳过 compile/test，按“清单/元数据 + 依赖”产出（或显式 no-op），不得进入 app 入口解析。
2. 复跑 `tests/s8/s814/with-starter`：exit 0，摘要顺序 `core→codec→bundle→app`，app 产物存在。
3. 复跑 `starter-src`/`starter-mismatch` 负例保持 XPD-201/XPD-403。

## 四、证据

- `evidence/S8-14-E2E/topo.log`、`topo-reactor-summary.txt`、`topo-repo-install.txt`、`topo-app-run.log`
- `evidence/S8-14-E2E/failfast.log`、`failfast-artifacts.txt`
- `evidence/S8-14-E2E/starter-src.log`、`starter-mismatch.log`
- `evidence/S8-14-E2E/with-starter.log`（FAIL）
- `evidence/S8-14-E2E/matrix-S8-14.tsv`
- 夹具：`tests/s8/s814/{topo,with-starter,failfast,starter-src,starter-mismatch}/`

## 五、结构边界

| 项 | 说明 |
|---|---|
| 模块 `xnull.lock` | 全 reactor 一份锁；模块目录单独 `xnull lock` 未纳入本卡 |
| 单模块构建 | 模块清单省略版本时只能在聚合根构建（`ManagedFallback` 由 reactor 注入）；模块目录单独 build 报 `XPD-401` |
| 外部依赖 | 走 `XNULL_REPO` 本地仓库；远程仓库未接 |
| 聚合摘要 | 自定义文本 `target/reactor-summary.txt`，未纳入 `.xmeta` |
