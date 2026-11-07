# 验收：S4-OBS-03（观测：defer 清理 Result）

> **验收人**：QA1（独立质量线）
> **结论：PASS**
> **复验点**：main `28e4f19`（含 E4 `82f6a7d` S4-02）
> **时间**：2026-11-08
> **二进制**：`/tmp/xnull-obs`，sha256 `074c5cb0a8bb6f34ca682fcd8715851d3060019485be3d83207d23a0be102dce`
> **证据**：`evidence/S4-QA/OBS-03/`
> **依据**：S4 §4.4、OBS-03；S1 §10.3
> **确认方式**：按“禁止 git”指令未执行任何 git 命令；main 版本读取 `.git/refs/heads/main`。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `defer g()` 未处理清理 Result | **PASS**：`ERR-201` @3:11 |
| §4.4 显式观测模式 `if (r.isErr()) { report(r) }` | **PASS**：`check` rc=0 |
| 显式观测可执行 | **PASS**：interp/compiled 均 rc=0，单行诊断 |
| 诊断缺失 | **PASS**：未处理即 ERR-201，不只运行期失败 |

**判定：PASS。** defer 内裸 Result 在编译期被 `ERR-201` 拒绝；显式观测模式零诊断并可执行。

---

## 二、实测

```text
$ xnull check defer_unhandled.x
defer_unhandled.x:3:11: error[ERR-201]: Result 是 @mustUse：不得作为裸表达式语句丢弃（§10.1）

$ xnull check defer_observed.x
exit 0

$ xnull run --interp defer_observed.x
stderr: Internal: disk
$ xnull run defer_observed.x
stderr: [Internal] disk
```

两条路径均为单行 kind+describe；格式差异归 OBS-01 P-03。

---

## 三、证据

- `evidence/S4-QA/OBS-03/matrix.tsv`
- `defer_unhandled.x` / `.err`
- `defer_observed.x` / `.err`
- `observed.interp.err`、`observed.compiled.err`
