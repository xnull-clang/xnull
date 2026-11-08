# 验收：S8-PROJ-10（文法与诊断）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `e1cdf78`（含 S8-10c；按任务声明，本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-10/`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| XPD 码位段 2xx–8xx 类别/模板 | **PASS**：`TestS810CodeRegistry` |
| 段位代表码（201/301/401/501/601/701/801） | **PASS**：`TestS810NoUnknownSegment` |
| `XPD-408`（依赖元数据）/`XPD-409`（依赖环）登记 | **PASS**：`TestS810bCodeCoverage`、`TestS810cGraphCodes` |
| 全部 XPD-2xx–8xx 校验器落点 | **PASS**：`TestS810bCodeCoverage` 零未登记 |
| 段落路径渲染 | **PASS**：`project/dependencies/dependency[2]/optional` |
| `xnull fmt` 清单/锁/元数据幂等与语法错误 | **PASS**：`TestS810Format*` |
| 同一错误多位置 | **PASS**：`TestS810CodeRegistry`/diagnostic 渲染 |

**判定：PASS。** XPD-408/409 已登记并与 `internal/manifest/graph.go` 对齐；码位段、段落路径与 fmt 检查全部通过。

---

## 二、实测

```bash
cd impl
go test ./internal/xpd ./internal/manifest -count=1 -v
```

`xpd-manifest-tests.log`：

```text
--- PASS: TestS810bCodeCoverage
--- PASS: TestS810CodeRegistry
--- PASS: TestS810NoUnknownSegment
--- PASS: TestS810cGraphCodes
--- PASS: TestS810FormatSource
--- PASS: TestS810FormatLockAndMeta
--- PASS: TestS810FormatRejectsSyntax
PASS
```

`XPD-408`/`XPD-409` 使用与登记：

```text
internal/manifest/graph.go: codeGraphMeta  = "XPD-408"
internal/manifest/graph.go: codeGraphCycle = "XPD-409"
internal/xpd/diagcodes.go: 已登记（4xx 依赖与锁）
```

段落路径：`XPD-202` + `project/dependencies/dependency[2]/optional` 渲染包含路径。

---

## 三、证据

- `/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-10/xpd-manifest-tests.log`
- `/Users/vjs/Desktop/XNull-Lang/evidence/S8-QA/PROJ-10/gap.txt`（上一轮缺口，已关闭）
- 断言依据：S8 §9/§10 PROJ-10；`收件箱/门/S8验收计划-QA.md`
