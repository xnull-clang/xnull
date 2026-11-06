# S0-21d/after-merge 摘要

## 结论

P0 合入 main 后复跑：**七项硬指标 7/7 绿**，9 示例双路径 stdout 9/9 相同、退出码全 0。P0-1/P0-3 的表现均消失：

- `internal/codegen`：187.869s 超时（180s 硬界）→ **20.957s 通过**；
- `parser-seed.xn` 解释路径：合并前挂起（21d 记 `interp=142`）→ **退出 0，与编译路径 stdout 相同**。

## 数据

| 项 | 值 |
| --- | --- |
| 合并提交 | `102310bfcf287f2235058fea812a0690714fa942`（双亲 `fa64db7`、`9301ed4`） |
| main 合并源 | `9301ed4`（含 S1-02 `dff308d`、S1-06 `9301ed4`） |
| check 二进制 | `evidence/S0-21d/bin/xnull`，`5668af91…`（合并前构建，含 mtime 旧判据） |
| 双路径二进制 | `after-merge/bin/xnull`，`f89955da…`（合并后重建） |
| 主树 `dev check` | exit 0 |
| `xnull/` `dev check` | exit 0 |
| 台账 | 120 行 / 101 条 / PASS 10；仅头部生成器名差异 |
| res | Go = Python = `2f88b931…` |
| Python | `.py` 0 个；产品代码引用 1 条（登记例外） |

## 观察项（不阻塞）

`parser-seed` 编译路径的 cc stderr 出现 `-Wparentheses-equality` 警告（S1-02 条件生成的多重括号所致）；`ast-seed` 合并前已有同类警告。stdout/退出码不受影响。未修复（本轮不动 P0 相关代码），建议后续在 codegen 侧消除多余括号或过滤 cc 警告。

## 边界

- 原 `evidence/S0-21d/` 文件未覆盖、未删除；本轮全部写入 `after-merge/`。
- 未 push、未改 main、未改 interp/codegen。
