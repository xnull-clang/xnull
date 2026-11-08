# 测试执行策略（切片并发）

> 生效：2026-11-08；依据：用户裁决「所有测试统一使用切片并发」

## 标准命令

| 场景 | 命令 |
|---|---|
| 本地目标包 | `xnull dev test --fast <pkg>` |
| 本地包级并发 | `go test -p 4 ./internal/...` |
| 全量分片 | `xnull dev test --shard 1/4 --parallel 4` … `4/4` |
| 合并门禁 | 依次跑 `--shard 1/4..4/4`，全部通过才算绿 |
| B2 差分 | `bash tests/b2/batch.sh --parallel 4`（批处理） |

## 规则

1. 切片按包名/测试名稳定哈希，确定性；
2. 所有切片必须执行并汇总，禁止只跑一个；
3. 必须串行的用例在测试内显式标记（如 `t.Setenv`/全局端口/GC 压力），不得静默串行；
4. 每个切片独立报告 PASS/FAIL/耗时，聚合到同一个结果；
5. 缓存（libxnrt、编译产物）按内容哈希，禁止用缓存掩盖失败；
6. 合并门禁仍是全量语义，切片只是执行方式。

## 当前实现

- `xnull dev test --shard/--parallel` 已在 S8-21 WIP 中实现；
- codegen 测试的 `libxnrt.a` 链路待隔离测量后决定保留或回退；
- B2 差分 `tests/b2/batch.sh` 已具备批处理基础。
