# S0-27 独立复跑记录（E6 第二次，HEAD `0a42402`）

> 目的：用更强的 mtime 打乱（含「母本比英译新」这一必然触发旧判据假红的方向）和真实双仓库干净 clone，独立复核 S0-27 三条验收。
> 性质：仍是 E6 执行侧复跑，不替代 QA1 验收。

## 环境

| 项 | 值 |
| --- | --- |
| 代码 | `pod/e6-toolchain` @ `0a42402d89cd76a27b2c09dcacf3fbc55c22ce1c` |
| 二进制 | 现场 `go build -o /tmp/xnull-s027 ./cmd/xnull`，sha256 `a14f501f5e62a77eca63bd4dd786f77f1c1a57e84e3196668f2ac3a1745dd92c`（Go 构建不保证逐字节可复现，与 `bin/xnull` 的 `a8382438…` 不同属正常） |
| 干净 clone | `git clone --branch pod/e6-toolchain` → `/tmp/s027clone`（HEAD 同上）；`git clone <主树>/xnull` → `/tmp/s027clone/xnull` |
| 清单 | clone 内 `impl/docs/conformance/en-source.sha256` 存在（8 份） |

## ① mtime 打乱 3 次结果一致

在干净 clone 上按三种方向重设时间戳后各跑一次，**stdout 三次逐字节相同**：

| 次 | 母本 mtime | 英译 mtime | 旧判据会怎样 | 实测 exit | stdout sha256 |
| --- | --- | --- | --- | --- | --- |
| 1 | 2026-01-01 | 2020-01-01 | 母本更新 → 旧代码必报假红 | 0 | `36d92c989af0d9bfcd628e7885b1874c9d76a254f3308812e2289afbbb0ddb4c` |
| 2 | 2020-01-01 | 2026-01-01 | 母本更旧 → 旧代码绿 | 0 | 同上 |
| 3 | 2023-01-01 | 2023-01-01 | 相同 | 0 | 同上 |

同一手法在 `/tmp/s027case`（从工作树拷贝 10 份母本 + `xnull/spec/en` + 清单）复跑，三次 stdout 同为 `ea43ab5f…`。

## ② 真实内容变更仍报滞后（且与 mtime 无关）

在 clone 里向第 3 部分追加一行（**版本号不变**，且把母本 mtime 调到比英译更旧）：

```
exit=1
- S3-Memory-Management-v3.0.0.md: 内容哈希不符——母本 XNull解决方案-第3部分-内存管理-v3.0.0.md 变更后英译未同步重译（清单 a6dbb815…，当前 6a89234c…）
```

母本 mtime 更旧仍报滞后 → 判据确实来自内容哈希，不是时间戳。

## ③ 干净 clone 两布局通过

| 布局 | cwd | exit |
| --- | --- | --- |
| 工作区（母本在根，EN 在 `xnull/spec/en`） | `/tmp/s027clone` | 0 |
| 公开（母本在 `spec/`，EN 在 `spec/en`） | `/tmp/s027clone/xnull` | 0 |
| 真实主树 | `/Users/vjs/Desktop/XNull-Lang` | 0 |
| 真实公开副本 | `/Users/vjs/Desktop/XNull-Lang/xnull` | 0 |

补充：工作树 cwd（`wt/e6-toolchain`）跑 `dev check` 退出码 1，原因是工作树不含被忽略的 `xnull/spec/en`（"en 目录不存在"），与董事会令第 2 条「两布局以主树/公开副本为 cwd」一致，不是 S0-27 缺陷。

## 单测

`go test ./internal/devtool ./internal/cli -count=1 -timeout 180s` → 两包 ok（含 `TestCheckSpecsMtimeShuffleDeterministic`、`TestCheckSpecsDigestStaleDetected`、`TestCheckSpecsDigestMismatchFailsRegardlessOfMtime`）。

## 对实现的两点观察（不阻塞）

1. 清单路径固定在 `Root/impl/docs/conformance/en-source.sha256`：公开布局里 `Root=xnull`，而公开仓库没有该清单，因此公开布局实际只做「覆盖 + 版本」检查，不做内容哈希判定。真实内容变更的检出在内部工作区/工作区 clone 生效。
2. `specs.go` 里读出的 `enText` 仅用于确认可读（`_ = enText`），未参与判定；不影响结果，但可读性略差。
