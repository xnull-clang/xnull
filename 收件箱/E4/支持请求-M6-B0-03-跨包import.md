# 支持请求：M6-B0-03 跨包 import 红用例（来自 QA1）

> 发起：QA1　时间：2026-11-07 05:45　关联：M6-B0-06 门禁阻塞
> 性质：红用例 + 期望，不是实现代码；E4 完成后 QA1 复跑。

## 现状

在 B0 候选树（main `2c00cf5` + B0-01 `23f1539` codegen + B0-02 `55fece4`）上：

```bash
xnull build evidence/M6-B0-06/b0-03-request/main.x -o /tmp/b0-03.bin
# exit=1
# lib/a.x:1:1: error[RES-109] 跨包导入暂不支持：子文件包名必须与入口一致
# lib/b.x:1:1: error[RES-109] 同上
```

原始日志：`wt/qa-1/evidence/M6-B0-06/b0-03-request/current.log`

## 红用例

```text
b0-03-request/
├── main.x         package app;  import lib.a; import lib.b
├── lib/a.x        package liba; Int fa() { return 1 }
├── lib/b.x        package libb; Int fb() { return 2 }
└── expected.txt   3
```

- 入口：`main.x`；依赖：`lib/a.x`、`lib/b.x`（两个不同包）
- 期望：`xnull build` exit 0；运行 stdout `3`，退出码 0
- 验收命令：
  ```bash
  xnull build <...>/b0-03-request/main.x -o /tmp/b0-03
  /tmp/b0-03; echo $?   # 期望 3\n0
  ```

## 需要 E4 做的

1. `LoadUnits` 允许子文件包名 ≠ 入口包名（当前 `impl/internal/codegen/multifile.go` 的 `codeMultiPackage` 拒绝）；
2. 跨包符号可见性/重名检查（同包唯一、跨包不冲突）；
3. 合并顺序保持确定性（依赖在前、入口最后），错误码/诊断稳定；
4. 保留同包多文件与默认包行为不回归。

## 完成后 QA1 会做

- 复跑上述红用例 + 现有 9 示例双路径 + `go test ./...`；
- 若通过，把 B0-06 回执从 BLOCKED 改为正式 PASS（B0 门其余项仍由董事会判）。
