# 验收：S8-CLI-INSTALL（`xnull install`）

> **验收人**：QA1（独立质量线）
> **结论：FAIL**（library/app 安装正确；pom 聚合根把聚合摘要当产物安装，P1）
> **复验点**：main `d963b02`（含 S8-17 `1cf40e7`）
> **时间**：2026-11-08
> **证据**：`evidence/S8-17-E2E/`、`tests/s8/s817/`、`matrix-INSTALL.tsv`
> **依据**：S8 §4/§5、S8-17 回执；`收件箱/门/S8-12-15补卡计划-v1.0.0.md`
> **确认方式**：读取 `.git/refs/heads/main`；执行 `xnull install`；未做 git 操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| library 安装 `.xlib` + 清单到本地仓库 | **PASS**：`repo/g/lib/1.0.0/{lib-1.0.0.xlib,xnull.project}` |
| app 安装可执行体 + `.xmeta` + 清单 | **PASS**：`repo/g/app/1.0.0/{app-1.0.0,app-1.0.0.xmeta,xnull.project}` |
| stdout sha256 与产物一致 | **PASS**：lib `c285e6f7…`、app `2e15e09d…`，与 `shasum -a 256` 一致 |
| 构建失败不安装 | **PASS**：源码错误 exit 1，仓库为空 |
| **pom 聚合根 install** | **FAIL**：把 `target/reactor-summary.txt` 当产物安装到根 GAV；app 模块产物未安装 |

**判定：FAIL。** 单工程 library/app 安装路径正确；聚合根（`packaging=pom`）没有 install 分支，误装聚合摘要。

---

## 二、失败项（P1）

| # | 现象 | 证据 | 归属 |
|---:|---|---|---|
| P-01 | 在 `packaging=pom` 根执行 `xnull install`：`buildManifestManaged` 返回 `target/reactor-summary.txt`；`runInstall` 按“非 .xlib ⇒ app 产物”复制该文本到 `repo/io/xnull/sdk-suite/1.0.0/reactor-summary.txt`，并输出 `已安装 …（sha256 …）` | `install-reactor.log`、`reactor-repo.txt` | E6（`deps_commands.go` 未处理 reactor） |
| P-02 | 同一 reactor 内 app 模块产物未安装（build 已产出 `app-1.0.0`） | `reactor-repo.txt` | E6 |

放行条件：`packaging=pom` 时 `install` 交给 reactor 处理（逐模块安装 library/app），或明确拒绝并给 XPD 诊断；不得把摘要文件写入仓库。

---

## 三、实测

```text
$ XNULL_REPO=/tmp/s817-repo-lib xnull install     # library
xnull: 已安装 …/g/lib/1.0.0/lib-1.0.0.xlib（sha256 c285e6f7…）
已安装 …/target/lib-1.0.0.xlib（sha256 c285e6f7…）      # exit 0

$ XNULL_REPO=/tmp/s817-repo-app xnull install     # app
已安装 …/target/app-1.0.0（sha256 2e15e09d…）           # exit 0
# repo: app-1.0.0 / app-1.0.0.xmeta / xnull.project

$ 源码错误 → exit 1，仓库为空

$ cd tests/s8/s814/topo && XNULL_REPO=… xnull install   # pom 根（FAIL）
module core … / module codec … / module app …
已安装 …/target/reactor-summary.txt（sha256 b52fa3d6…）   # 不应安装
```

---

## 四、边界

| 项 | 说明 |
|---|---|
| app 依赖闭包 | app 安装仅复制可执行体与 `.xmeta`，不打包依赖（回执已披露） |
| sha 清单 | install 不落 sha 清单文件，仅 stdout 输出 |
| 单模块 install | 模块清单省略版本时只能在聚合根构建；模块目录单独 install 报 `XPD-401` |
| 覆盖策略 | 同版本覆盖写，无不可变校验 |

---

## 五、证据

- `evidence/S8-17-E2E/install-lib.log`、`install-app.log`、`install-fail.log`
- `evidence/S8-17-E2E/sha.txt`、`repo-app.txt`
- `evidence/S8-17-E2E/install-reactor.log`、`reactor-repo.txt`（FAIL）
- `evidence/S8-17-E2E/matrix-INSTALL.tsv`
- 夹具：`tests/s8/s817/{install-lib,install-app}/`、`tests/s8/s814/topo/`
