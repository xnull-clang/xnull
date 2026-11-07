# DET-01 跨域修复落位（sema/xdk.go）

> 来源：`wt/c3-rd2/evidence/M1-DET-01/fix-proposal.diff`（CEO3-RD2）
> 落位：`wt/c1-rd2`（`pod/c1-rd2`）　主责：CEO1-RD2
> 范围：`impl/internal/sema/xdk.go` 3 处排序 + 新增 DET-01 用例（取自 `pod/c3-rd2@4b94fee`）

## 结果

| 项 | before | after |
|---|---|---|
| `TestDET01DiagStableAcrossRuns` | PASS | PASS |
| `TestDET01DiagIndependentOfMapOrder` | **FAIL**（2 轮内诊断顺序翻转） | **PASS**（200 轮稳定） |
| `go test ./internal/sema -count=1` | — | rc=0 |

## 改动

1. `xdkExporters` 返回前 `sort.Strings(pkgs)`。
2. 包导入展开符号表后 `sort.Strings(info.syms)`。
3. 歧义简单名诊断按 `names` 排序后遍历（不再 `range map`）。

语义等价，仅消除 map 迭代序；不改变任何诊断文案与码值。`applied.diff` 为实际落位 diff。

## 复现

```bash
cd impl
go test ./internal/sema -run 'TestDET01Diag' -count=1 -v
go test ./internal/sema -count=1
```

证据：`before/test.log`（exit 1）、`after/test.log`（exit 0）、`stdout.txt`、`command.txt`、`artifact.sha256`。
