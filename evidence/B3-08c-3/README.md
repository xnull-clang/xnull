# B3-08c-3 证据：text 继续收敛

## 2845 行 diff 归类（修复前）

- 约 90% 为 temp 编号/缩进抖动：783 added + 1041 removed 行中，仅 92/121 行归一化（`xn_tN`→`xn_tN`）后仍不同。
- 区域 hunks：parseFloat 9、parseInt 8、regexMatchAt 4、utf8ToUtf16 2、utf16ToUtf8 2、Format/Regex 类与前置 typedef 约 9。
- 语义机制：
  - String 调用参数未生成 temps（函数实参未走 `argExpr`）；
  - 空字符串字面量未生成 `rt_string_from_c("")`；
  - `Bytes.fromString` / `Bytes.length/get/push` 未映射；
  - `as Int` 被误走 Any 拆箱；
  - SC 局部类型表跨函数未重置，导致同名局部（如 `c`）类型串味；
  - String 局部 Call 初始化未分配 Go 的预留 temp（造成后续全局 temp 偏移）。

## 本轮修复（占比最大的 1–2 类：temp 分配 + String/Bytes 基础）

- 函数实参 String 统一走 `argExpr`，调用参数生成 temps/roots。
- 空字符串字面量生成临时串。
- `String x = <Call>` 预留 temp，修正 parseFloat 后续全部编号。
- `sc.names/types` 每函数重置，修复同名局部类型串味。
- Bytes：`fromString`、`length/get/push/slice`；`as Int` 改标量转换。

## 结果

- `bundle_text` diff：**2845 → 1570 行（-44.8%，超过本轮 ≥30% 目标）**。
- `xnullc-bundle`：sync/tasks/collections PASS，text 仍 KNOWN-DIFF。
- `xnullc check` 通过。

## 剩余

parseFloat/utf8/utf16/regexMatchAt 的 root 缩进与少量 temp 空号、Format.build、Regex.compile/isMatch 细节。
