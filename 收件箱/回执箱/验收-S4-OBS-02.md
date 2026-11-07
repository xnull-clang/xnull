# 验收：S4-OBS-02（观测：禁止形态）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `28e4f19`（含 E4 `82f6a7d` S4-02）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-obs`，sha256 `074c5cb0a8bb6f34ca682fcd8715851d3060019485be3d83207d23a0be102dce`
> **证据**：`evidence/S4-QA/OBS-02/`
> **依据**：S4 §4.2、OBS-02
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| 全局错误通知中心 `setGlobalErrorHandler` | **PASS**：`RES-101 未定义` |
| 隐式“当前错误” `lastError()` | **PASS**：`RES-101 未定义` |
| 无此 API（编译错误） | **PASS**：无隐式观测入口 |
| 隐式恢复/全局钩子 | **PASS**：语言面未提供此类 API |

**判定：PASS。** §4.2 禁止的全局通知中心与隐式当前错误均不可用，访问即编译错误。

---

## 二、实测

```text
$ xnull check global_handler.x
global_handler.x:2:5: error[RES-101]: 未定义的名称 `setGlobalErrorHandler`

$ xnull check last_error.x
last_error.x:2:11: error[RES-101]: 未定义的名称 `lastError`
```

---

## 三、证据

- `evidence/S4-QA/OBS-02/matrix.tsv`
- `global_handler.x` / `global_handler.err`
- `last_error.x` / `last_error.err`
