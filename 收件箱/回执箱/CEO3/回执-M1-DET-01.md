<!-- 董事会代归档 2026-11-07 04:20；来源：收件箱/CEO3/回执-M1-DET-01.md；2026-11-07 二次复跑与阶段对齐（7df123d）后更新 -->

# 回执：M1-DET-01（确定性）

**状态：DONE　3/3　（2026-11-07 阶段对齐 main `7df123d` 复跑，无回退）**
> 角色：CEO3-RD2-构建与CI　分支：`pod/c3-rd2`　提交：`66f3a72`（merge `2c00cf5`，merge commit `2813540`）
> 依据：v1.7.0 第 2.1 条 / v1.7.1 第 2 条　台账：`XNull一致性用例台账-v1.0.0.md:32`
> 未改现有测试期望、未删测试、未 push、未合并到 main。

## 一、五行结论

1. `git merge --no-ff main` 两次均无冲突：首次合入 `2c00cf5`（合并提交 `2813540`）；二次为 "Already up to date"（`c737099`/`2c00cf5` 均已在祖先链）。
2. DET-01 三项用例二次复跑全 PASS：`after/rerun-2c00cf5.txt`；全包 9/9 绿：`after/rerun-full-test.txt`。
3. a 诊断确定性：多错误源 200 轮逐字节一致；歧义诊断（`RES-104`）顺序稳定——旧 `sema/xdk.go:173` 的 map 序发射点已随 PKG-01 导入诊断重写消除。
4. b 运行结果确定性：解释 10 轮 + 编译 10 轮同一 sha256 `a6ed6096…`，两路径逐字节一致；示例 9/9 双路径一致：`after/rerun-examples.txt`。
5. c 初始化顺序：同一逻辑树按 20 种文件创建顺序落盘，合并声明序（= 初始化序）与输出逐字节一致；同命令同 `-o` 两次构建 hash 一致（`4e3ec1d7…`）。

## 二、检查表（逐项打勾）

| # | 验收要点（台账原文） | 结果 | 用例 | 证据 |
|---|---|:-:|---|---|
| a | 同一源程序、同一实现版本、同一选项产生**相同诊断** | ✓ | `sema/det01_test.go`（200 轮 + 注入重名注册表 200 轮） | `after/rerun-2c00cf5.txt` |
| b | 同一源程序、同一实现版本、同一选项产生**相同运行结果** | ✓ | `interp/det01_test.go`（10 轮 + 退出码）、`codegen/det01_test.go`（EmitC 5 次） | `after/postmerge-hash-and-runs.txt`、`after/rerun-examples.txt` |
| c | **初始化顺序不依赖文件系统枚举顺序** | ✓ | `codegen/det01_test.go`（20 种文件创建顺序） | `after/rerun-full-test.txt` |

## 三、复跑记录

| 轮次 | 基线 | 动作 | 结果 |
|---|---|---|---|
| 1 | main `2c00cf5` | `git merge --no-ff main`（合并提交 `2813540`）+ 三项 + 全包 + 示例 | 3/3 PASS，9/9 包绿，示例 9/9 一致 |
| 2 | main `2c00cf5`（含 `c737099`） | `git merge main` → Already up to date；三项 + 全包 + 示例重跑 | 3/3 PASS，9/9 包绿，示例 9/9 一致 |

## 四、未测项

| 项 | 原因 |
|---|---|
| 编译路径 10 次运行（Go 测试形式） | 每次 cc 约 3s；由 CLI 证据覆盖：10/10 同一 sha256，且与解释路径逐字节一致 |
| 不同 `-o` 名的两次构建 hash | 仅 16 字节差异（Mach-O `LC_UUID`），内容一致；不属 DET-01 判据，记入 CI 08 项（固定输出路径） |
| 多包/工程清单模式的确定性 | 该形态未实现（PKG-01/ENTRY-01 范围），本锚点只验当前可编译形态 |
| 真实注册表下的歧义触发 | 当前 S6 定案符号无重名（`xdk_test.go:36` 已注明），红用例用临时注册表构造「未来重名」场景 |

## 五、转交（不属 DET-01，未修）

两个 §4.3 初始化缺陷，归属 ENTRY-01：INIT-1「初始化式调用其后声明的函数 → `未定义的函数`」、INIT-2「同目录同包分片未 import 不加载 → `RES-101`」。证据：`before/probe-init-order.txt`。

## 六、证据索引

`evidence/M1-DET-01/`：`checklist.md`、`command.txt`、`stdout.txt`、`stderr.txt`、`exit_code.txt`、`sha.txt`、`artifact.sha256`（`shasum -c` 全 OK）、`acceptance.md`（QA 签名栏留空）、`before/`（红原文 + 初始化探针）、`after/postmerge-*`（首次复跑）、`after/rerun-*`（二次复跑）、过程证据 `after/fix-proof.txt`、`after/on-pkg01-base.txt`、`fix-proposal.diff`（作废）。

**待 QA 独立验收（CEO3-QA2）**：本回执不自签；签名栏留空。

## 七、阶段对齐（main `7df123d`，B0 门已过）

- `git merge --no-ff main` 无冲突 → 合并提交 `3bead3b`；本卡证据提交 `3e41a07`。
- `go test ./... -count=1 -timeout 300s`：首跑 rc=1（codegen 包 359s 超时，cli 263s / ffi 191s，全包同比放慢 3–7 倍，机器争用）；**同命令立即重跑 rc=0，9/9 包 ok**；`internal/codegen` 单包独立复跑 119s ok（-timeout 600s），排除代码回归。
- DET-01 矩阵 5 用例全 PASS（`after/sync-7df123d-det01.txt`）；示例 9/9 双路径一致；同命令两次构建 hash 一致 `f013ccf2…`；10 次运行同一 sha256。
- 结论：DONE 3/3 **不回退**。
