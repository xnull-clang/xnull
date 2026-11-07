# 验收：S6-XDK-03（errors）

> **验收人**：QA1（独立质量线）
> **结论：BLOCKED / 规范冲突（`report` 返回类型未裁决）**
> **复验点**：main 含 S6-03/04/05 合并（按任务声明；本次**未运行任何 git 命令**）
> **时间**：2026-11-08
> **证据**：`/Users/vjs/Desktop/XNull-Lang/impl/lib/xdk/errors.x`、`收件箱/门/S6验收计划-E2.md`、`evidence/S4-*`

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `ErrorKind` 14 项、`Error` 协议 2 成员 | **PASS**：`errors.x` 与 S4 一致 |
| `CauseError.cause: Error?` | **PASS**：`errors.x` 声明 |
| `wrap` 丢弃原错误 / `mapErr` 转换 | **PASS（源码单元静态面）** |
| `report` 行为 | **BLOCKED**：S6 §4.1 要求“返回原 `Result`”，S4 已签为 `void`，`errors.x` 当前 `void` |
| 端到端 errors 单元 | **BLOCKED**：依赖 S6-02 runtime / codegen 链接 |

**判定：BLOCKED / 规范冲突。** 计划明确：`report` 返回类型在裁决前 **XDK-03 不得签 PASS**。当前 `errors.x` 按 S4 门口径返回 `void`，与 S6 §4.1 定案 3-a-1 冲突。

---

## 二、实测/静态证据

`impl/lib/xdk/errors.x`：

- `enum ErrorKind` 14 项（`InvalidArgument..Internal`）。
- `protocol Error { ErrorKind kind(); String describe(); }`。
- `class CauseError implements Error { final Error? cause; ... }`。
- `wrap`/`mapErr` 实现；`report` 注释明确“返回 void”。

计划 §0.4：

```text
S6 §4.1 定案 3-a-1 = 返回原 Result；S4 门按 S4 §2.1 = void；errors.x 当前 void。
XDK-03 在裁决前不得签 PASS。
```

`codegen-s6.log` 中 S6-02/S6-03 的链接失败会阻断 errors 端到端；本锚点也不能以单侧源码静态面签 PASS。

---

## 三、阻塞项

| # | 阻塞 | 归属 |
|---:|---|---|
| 03-1 | `report` 返回类型 S6/S4 冲突，未裁决 | 董事会/规范 |
| 03-2 | errors 单元端到端（codegen/interp 链接）未通 | E4/E5 |

---

## 四、证据

- `/Users/vjs/Desktop/XNull-Lang/impl/lib/xdk/errors.x`
- `/Users/vjs/Desktop/XNull-Lang/收件箱/门/S6验收计划-E2.md` §0.4
- `/Users/vjs/Desktop/XNull-Lang/evidence/QA-S6A/codegen-s6.log`
- 断言依据：S6 §4.1/§10 XDK-03；S4 §2.1
