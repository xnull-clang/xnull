# 验收（PASS）：INTEG-c3-rd2 集成复核 P1

> **卡片**：集成复核 P1（`pod/c3-rd2`，main `9f5f66c`）
> **角色**：CEO3-QA2（独立复核，只读；未改代码/测试）
> **时间**：2026-11-07
> **环境**：macOS 26.5.2 x86_64 / go1.27.3 / Apple clang 17.0.0
> **被测**：`9f5f66c0e132953646ae4213218629dbaa3be0e8`（merge commit，parents `f20081b` + `3e41a07`）；分支尖 `3e41a07`
> **证据**：`evidence/INTEG-c3-rd2/`（11 个文件）

## 结论

# **PASS**

四项复核全过；DET-01 3/3；同命令同 `-o` 两次构建 sha256 相同；编译/解释各 10 次运行 sha256 均为 `6319d98b…` 且逐字节一致。无回退建议。

| # | 复核项 | 结果 | 证据 |
|---|---|:-:|---|
| 1 | `git merge-base --is-ancestor 3e41a07 9f5f66c` | **真**（rc=0） | `00-ancestor.txt` |
| 2a | `go vet ./...` | rc=0 | `01-vet.txt` |
| 2b | `go test ./... -count=1 -timeout 300s` | rc=0，9/9 包绿 | `02-fulltest.txt` |
| 2c | `bash impl/runtime/build_rt.sh` | rc=0（gc/hard/abi/std/资源表全过） | `03-rt-build.txt` |
| 3a | DET-01 3/3 | 5 个用例全 PASS（sema 2 / interp 1 / codegen 2） | `04-det01.txt` |
| 3b | 两次构建 hash 一致 | 同命令同 `-o`：`76d871a7…` = `76d871a7…` | `05a-build-hash.txt` |
| 3c | 多次运行结果一致 | 编译 10/10、解释 10/10 同 sha `6319d98b…`，双路径逐字节一致 | `06-runs.txt` |
| 附 | 示例双路径 | 9 示例 + multi 10/10 stdout 一致、退出码均 0 | `07-examples-dualpath.txt` |

## 一、命令与原始结果

```text
$ git merge-base --is-ancestor 3e41a07 9f5f66c ; echo $?
0

$ cd impl && go vet ./... ; echo $?
0

$ go test ./... -count=1 -timeout 300s
ok  internal/cli 70.520s   ok  internal/codegen 100.948s   ok  internal/codegen/ffi 41.131s
ok  internal/devtool 13.397s  ok  internal/diag 11.444s   ok  internal/interp 14.063s
ok  internal/sema 12.686s     ok  internal/xfront 14.734s  ok  internal/xpd 15.416s
测试总耗时 real 103.98s

$ bash runtime/build_rt.sh
gc tests passed (invariants 2/3/5/6)
ok  resurrection detection terminates (fatal handler)
ok  weak slots (invariant 4, cleared before deinit, reusable)
hard-semantics tests passed / abi 测试通过 / std 测试通过 / 资源表测试通过

$ go test ./internal/sema ./internal/interp ./internal/codegen -run 'TestDET01' -v -count=1
--- PASS: TestDET01DiagStableAcrossRuns
--- PASS: TestDET01DiagIndependentOfMapOrder
--- PASS: TestDET01RuntimeStable
--- PASS: TestDET01InitOrderIndependentOfCreationOrder
--- PASS: TestDET01EmitCDeterministic
PASS
```

## 二、确定性实测

| 检查 | 实测 |
|---|---|
| 同命令同 `-o` 构建两次（`examples/containers.x`） | `76d871a7f443fe4a5bf20ddb6787f20fce588489835c8b4135f54f603c3168d4` 两次完全相同 |
| 不同 `-o`（b1 vs b2） | sha 不同，`cmp -l` 差异 **16 字节**（Mach-O `LC_UUID`），与既往结论一致 |
| 编译路径 10 次运行 | 10/10 同一 sha `6319d98b17033f951fe72bb637d7cc2d40ac849b40d8b088ca467db08948c2b3`，退出码全 0 |
| 解释路径 10 次运行 | 10/10 同一 sha `6319d98b…` |
| 双路径比对 | `cmp` 一致（52 B vs 52 B） |
| 示例双路径 | 10/10 OK（9 个 `examples/*.x` + `examples/multi/main.x`） |

**口径说明**：构建产物 hash 只在「同一输出路径」下可复现；换 `-o` 名会改 Mach-O `LC_UUID`（16 B）。这不是 DET-01 违约，但 CI 08 项若要落二进制 sha 锚点，必须固定输出路径。

## 三、集成完整性抽查

| 项 | 结果 |
|---|---|
| merge commit 父提交 | `f20081b`（main 侧）+ `3e41a07`（分支尖） |
| 分支独有差异 `merge-base..3e41a07` | 空（`merge-base` 即 `3e41a07`，已被 main 完整吸收） |
| 分支内删除文件 | 0 |
| 测试文件数 | 分支 40 → 合并后 43（只增不减） |
| 工作树/仓库改动 | 本轮只读；临时副本在 `$TMPDIR`，未改生产代码与测试 |

## 四、未测项

| 项 | 原因 |
|---|---|
| 不同 `-o` 的二进制逐字节一致 | 平台 `LC_UUID` 随机；只有同路径可复现（见上） |
| 多包/工程清单模式确定性 | 该形态未实现，属 B2 之后 |
| Windows/Linux 平台 | 本机仅 macOS x86_64 |
| 自举版确定性（xn-s1/s2/s3） | B2 未开工，不在本卡 |

## 五、结论与建议

- **PASS**。祖先关系为真，全量测试与运行时不退化，DET-01 三项均成立，确定性可复现。
- **不建议回退**。
- 唯一需登记的约束：二进制 sha 锚点必须固定 `-o` 路径；建议并入 CI 08 项（与既有 DET-01 回执的「未测项」一致）。

---

# 追加：最终集成复核（main `f63fcba`）

> **时间**：2026-11-07　**基线**：`f63fcba52a763eb6176c2fabe7aedd80352f72a2`（`merge(pod/e3-interp): SYNCED 37cbe18`，parents `49cbb27` + `37cbe18`）
> **方式**：只读；`git archive f63fcba` 干净树，未改代码/测试
> **证据**：`evidence/INTEG-final-c3rd2/`

## 结论

# **PASS**

| 复核项 | 结果 | 证据 |
|---|---|:-:|
| DET-01 3/3 | 5 个用例全过（sema 2 / interp 1 / codegen 2） | `01-det01.txt` |
| 两次构建 hash 一致（同命令同 `-o`） | `c5aae4b0…` = `c5aae4b0…` | `02-build-hash.txt` |
| 10 次运行一致 | 编译 10/10、解释 10/10 同 sha `6319d98b…`；双路径 `cmp` 一致 | `04-runs10.txt` |
| `go test ./internal/sema/ ./internal/interp/ -count=1` | rc=0（sema 10.886s / interp 11.499s） | `03-sema-interp.txt` |

## 命令与原始结果

```text
$ go test ./internal/sema ./internal/interp ./internal/codegen -run 'TestDET01' -v -count=1
--- PASS: TestDET01DiagStableAcrossRuns
--- PASS: TestDET01DiagIndependentOfMapOrder
--- PASS: TestDET01RuntimeStable
--- PASS: TestDET01InitOrderIndependentOfCreationOrder
--- PASS: TestDET01EmitCDeterministic
（sema 10.118s / interp 9.236s / codegen 12.293s）

$ go test ./internal/sema/ ./internal/interp/ -count=1
ok  xnull.dev/xnull/internal/sema     10.886s
ok  xnull.dev/xnull/internal/interp   11.499s

$ xnull build examples/containers.x -o …/prog   # 连续两次
sha1=c5aae4b0a79ada4b1ab81f2a6e9c856813420a250ff9fcef1e6df60d21c8fc4e
sha2=c5aae4b0a79ada4b1ab81f2a6e9c856813420a250ff9fcef1e6df60d21c8fc4e

$ 10 × xnull run examples/containers.x
  10 6319d98b17033f951fe72bb637d7cc2d40ac849b40d8b088ca467db08948c2b3
$ 10 × xnull run examples/containers.x --interp
  10 6319d98b17033f951fe72bb637d7cc2d40ac849b40d8b088ca467db08948c2b3
双路径 cmp：same（52 B = 52 B）
```

## 说明

- 构建产物 sha 只在「同一输出路径」下可复现；换 `-o` 名会有 Mach-O `LC_UUID` 差异（上一轮已实测 16 B）。本轮的两次构建使用同一路径，故 sha 相同。
- 与上一轮（`9f5f66c`）相比，二进制 sha 由 `76d871a7…` 变为 `c5aae4b0…`（main 前进所致），口径不变。
- 不建议回退。未测项同前（多包/工程清单、非 macOS 平台、自举版确定性）。
