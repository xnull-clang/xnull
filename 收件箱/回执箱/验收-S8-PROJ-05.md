# 验收：S8-PROJ-05（生命周期/构建/.xmeta，端到端复签）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（S8-12 接入后按真实工程复验）
> **复验点**：main `9c4f51e`（S8-12 已入 main）；`68d29f4`、`9de80eb` 正例抽检复跑通过
> **时间**：2026-11-08
> **证据**：`evidence/S8-12-E2E/p05/`、`f1/`、`f2/`、`f3/`、`matrix-PROJ-05.tsv`
> **依据**：S8 §5、PROJ-05；`收件箱/门/S8-12验收用例-QA.md`；`回执-S8-12.md`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull build/run`；未做 git 操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 生命周期 validate→compile→test→package | **PASS**：build exit 0，测试阶段输出 `F1-TEST-OK`，产物生成 |
| 入口可执行 | **PASS**：`run` 输出 `F1-TEST-OK` + `F1-MAIN-OK` |
| `--skip test` | **PASS**：不输出测试标记，exit 0 |
| `--skip package` | **PASS**：`target/` 为空，exit 0 |
| `.xmeta` 字段 | **PASS**：坐标/平台/xdk/language/toolchain/profiles/plugins/三摘要/lockSha256/inputs 齐全 |
| `.xmeta.lockSha256` | **PASS**：与 `xnull.lock` 字节 SHA-256 一致 |
| 可复现 | **PASS**：连续两次 build `.xmeta` 字节一致（f1/p05/f3 三处） |
| 入口缺失 | **PASS**：`XPD-202`，exit 2 |
| `entryPackage` 不符 | **PASS**：`XPD-202`（com.acme vs com.other） |
| `sourceRoot` 含 `target/` | **PASS**：`XPD-201` |
| `build.mode` 非法 | **PASS**：`XPD-201` |

**判定：PASS。** 五阶段、跳过语义、入口解析、`.xmeta` 字段与复现性均成立。

---

## 二、实测

```text
$ xnull build            # F1
F1-TEST-OK
…/target/app-1.0.0       # exit 0
$ xnull run
F1-TEST-OK
F1-MAIN-OK

$ xnull build --skip test
…/target/app-1.0.0       # exit 0，无 F1-TEST-OK
$ xnull build --skip package
F1-TEST-OK               # exit 0，target/ 为空

$ 两次 build 后 cmp target/app-1.0.0.xmeta → identical

$ 负例：XPD-202(入口缺失) / XPD-202(entryPackage) / XPD-201(sourceRoot) / XPD-201(mode)
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| install 阶段 | 当前为本地空操作（1.x 可跳过） |
| library/pom/starter 构建 | 未接；`resolveEntry` 仅支持 `packaging=app`（S8-13/14） |
| 测试阶段 | 仅当 `build.testRoot/main.x` 存在时执行；并发/报告格式未在本卡断言 |
| `.xmeta` 平台字段 | 取构建机 GOOS（macos），跨平台一致性未验 |

---

## 四、证据

- `evidence/S8-12-E2E/matrix-PROJ-05.tsv`
- `f1/F1-build.log`、`f1/F1-run.log`
- `p05/P05-skip-test.log`、`P05-skip-package.log`、`P05-skip-package-target.txt`
- `p05/P05-deterministic.txt`、`f3/F3-deterministic.txt`
- `p05/P05-entry-missing.log`、`P05-entrypackage-mismatch.log`、`P05-badsource.log`、`P05-badmode.log`
- `f2/F2-meta.log`、`f3/F3-meta.log`

---

# 聚合面补记：S8-14 reactor 生命周期（2026-11-08）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（聚合生命周期/失败即停通过；starter 无生命周期分支，P0 阻塞）
> **复验点**：main `25f8be6`（含 S8-14 `ae1a573`）
> **证据**：`evidence/S8-14-E2E/`、`tests/s8/s814/`、`matrix-S8-14.tsv`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull build`；未做 git 操作。

## 一、结论

| 聚合面检查 | 结果 |
|---|---|
| 模块按拓扑序逐模块构建 | **PASS**：逆序声明下顺序为 `core→codec→app` |
| 每模块独立 `.xlib`/可执行体 + `.xmeta` | **PASS**：core/codec `.xlib`、app 可执行体与 `.xmeta` |
| app 产物可执行 | **PASS**：`./target/app-1.0.0` → `S814-TOPO-APP-OK` |
| 聚合摘要 `target/reactor-summary.txt` | **PASS**：模块顺序 + 产物 + sha256；成功路径生成 |
| 失败即停 | **PASS**：core 已建/已装，codec 失败后 app 与根 `target/` 不存在、摘要不生成 |
| starter 含 `src/` 拒绝 | **PASS**：`XPD-201` |
| **starter 模块生命周期** | **FAIL**：进入 compile 分支并以空入口解析 → `RES-106`；无跳过/元数据产物路径 |

**判定：FAIL。** 非 starter 模块的聚合生命周期与失败即停符合 S8 §5.1；`packaging=starter` 缺少生命周期分支，含 starter 的聚合无法完成构建。

## 二、失败项（P0）

| # | 失败 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | `run()` 未对 `starter` 做跳过/元数据分支；空入口进入 codegen 报 `RES-106` | `with-starter.log` | E6 |
| P-02 | 失败包装重复（`模块 X 构建失败：模块 X 构建失败`），定位噪音 | `with-starter.log` | E6（P2） |

## 三、放行条件

1. starter 模块跳过 compile/test/package 的可执行体路径，仅产出清单/元数据（或显式 no-op），并计入聚合摘要。
2. `tests/s8/s814/with-starter` 复跑 exit 0，摘要顺序 `core→codec→bundle→app`。
3. 复跑 fail-fast 用例，保持“已完成模块保留、后续不构建、无摘要”。

## 四、证据

- `evidence/S8-14-E2E/topo.log`、`topo-reactor-summary.txt`、`topo-app-run.log`
- `evidence/S8-14-E2E/failfast.log`、`failfast-artifacts.txt`
- `evidence/S8-14-E2E/starter-src.log`
- `evidence/S8-14-E2E/with-starter.log`（FAIL）
- `evidence/S8-14-E2E/matrix-S8-14.tsv`
- 夹具：`tests/s8/s814/`

## 五、结构边界

| 项 | 说明 |
|---|---|
| 模块 test 阶段 | reactor 未编排模块 `test`，`--skip` 对每模块透传 |
| 单模块 run | 省略版本的模块在子目录 `run` 报 `XPD-401`；本轮用产物二进制验证 app |
| install | library 安装本地仓库；app/starter 无 install 语义 |
| 聚合摘要 | 自定义文本，未入 `.xmeta`；失败路径不生成 |
