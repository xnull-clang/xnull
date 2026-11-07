# 验收：S8-PROJ-04（版本与锁）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（依赖版本与锁通过；插件版本规则为 S8-05 边界）
> **复验点**：main `d779380`（含 S8-03 `4fedb37`）
> **时间**：2026-11-08
> **证据**：`evidence/S8-QA/PROJ-04/`
> **依据**：S8 §4、PROJ-04；S8-03 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 精确版本；范围/SNAPSHOT/LATEST/RELEASE/* 拒绝 | **PASS**：`XPD-402` |
| 预发布精确版本 | **PASS** |
| 锁条目坐标升序 + 稳定字节 | **PASS**：`TestLockSortOrder`、`WriteLock` |
| 锁摘要（SHA-256）正确 | **PASS** |
| 锁缺条目 / 多余坐标 / 摘要不符 / 版本不一致 | **PASS**：`XPD-404/405/406/404` |
| `xnull lock` 校验 + `--update-lock` 唯一重生成入口 | **PASS**：`TestLockCommand` |
| 插件 kind 版本规则 | **BOUNDARY**：`kind=plugin` 未生成（S8-05） |

**判定：PASS。** 依赖版本规则与锁文件生成/校验/重生成入口全部成立；插件版本规则归 S8-05，不阻塞本锚点。

---

## 二、实测

```text
$ go test ./internal/manifest -count=1 -v
PASS TestDependencyManagement（范围/SNAPSHOT/LATEST 拒绝、预发布允许）
PASS TestLockGenerateAndValidate（404/405/406/版本不一致）
PASS TestLockSortOrder

$ go test ./internal/cli -run TestLockCommand -count=1 -v
PASS（缺锁失败、--update-lock 生成、校验通过、清单变更 XPD-404）
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| 插件版本规则 | `kind=plugin` 未生成，随 S8-05 插件接入 |
| 仓库 | 仅本地 `XNULL_REPO`；HTTP/镜像/凭据未接 |
| 无仓库时 | 拒绝生成锁（不造假摘要） |

---

## 四、证据

- `evidence/S8-QA/PROJ-04/matrix.tsv`
- `manifest.log`、`lock-cli.log`
- `impl/internal/manifest/deps.go`、`impl/internal/cli/lock.go`
- `收件箱/回执箱/回执-S8-03.md`
