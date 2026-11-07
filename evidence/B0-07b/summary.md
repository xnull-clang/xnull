# M6-B0-07b 摘要

## 一句话

补齐文本变体文件 API：`readFileText(path) -> String` 与 `writeFileText(path, text) -> Int`（绑定 + C 实现），P-09 注入已识别；用 QA1 的真实 B0-06 文本变体程序端到端 **2/2**。

## 数据

| 项 | 值 |
| --- | --- |
| 基线 | `main` = `7d5651a`（本卡前快进） |
| 红 | `red.txt`：绑定缺少 readFileText |
| 绿 | `green.txt`：写 0、读 11 字节、缺失文件返回 null |
| 端到端 | `e2e-text-variant.txt`：build 0，PASS 2 / FAIL 0 |
| 告警 | 3 条（2 条既有括号噪声 + 1 条 P-09 调用点类型，功能无影响） |
| 回归 | vet 0 / 全量测试 0 / build_rt 0 |
| 附带修复 | `emit.go` String 返回原生变量类型 `xrt_string *` → `const char *`（告警 7 → 3） |

## 设计

- `readFileText` 用静态复用缓冲，包装层 `xrt_string_from_c` 在返回后立即复制；失败返回 NULL（映射为 null String）。
- `writeFileText` 返回 `Int`：0 成功、1 路径非法、2 IO/关闭失败。
- 不使用句柄/Bytes/错误码通道，签名与 B0-06 程序完全一致，避免 P-09 未覆盖形态。

## 未覆盖

- numeric 变体（`readFile`/`writeFile` + Bytes/Int32/Int64）待 E2 完成后复跑，不在本卡。
- P-09 调用点 `rt_string **`/`xrt_string **` 类型告警属 E4 域，未在本卡修改。
