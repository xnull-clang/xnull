# S8-09 自检结论（可复现 / 摘要）

## 交付

`impl/internal/repro`（新包）：
- `WriteLockStable`：锁条目按坐标升序、字段固定对齐，输出与输入顺序无关；同一依赖图重复生成逐字节一致（`manifest.TestLockBytesStableFromGraph` 10 次/5 次两种）。
- `CollectInputs(InputSpec)`：输入穷举——清单链（相对路径+SHA）、源码根（递归文件+SHA）、锁文件（SHA 或 `absent`）、工具链版本、目标平台、profile 集合（排序）；生成 canonical 文本与 SHA-256 摘要；集合一律排序（DET-01）。
- `Summary` / `SameSummary`：两次构建摘要比对（同状态一致；源码/锁/工具链/平台/profile 任一变化即不同）。
- `Snapshot` + `CheckWrites`：记录 target 之外文件摘要，新增/修改/删除 → `REPRO-001`（PROJ-09「target/ 外无写入」）。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前 `go test ./internal/repro` 编译失败（`red.txt`） |
| 绿 | `go test ./internal/repro -count=1` → ok（锁字节稳定 10 次、输入摘要稳定与四类变化、两次构建摘要比对、越界写检测） |
| 锁（依赖图） | `TestLockBytesStableFromGraph` → PASS（5 次逐字节一致） |
| 回归 | `go test ./internal/manifest` → ok |

## 缺口

1. `.xmeta` 的 digest 字段渲染**未做**——按卡片等 E4 的 S8-04 落地后接；本包已提供 `Inputs.Digest/Canonical` 可直接写入 `.xmeta`。
2. 源码根默认值（`src/main/x`）由调用方传入；未做清单字段推导（`build.sourceRoot` 已解析但未在这里消费）。
3. 越界写检测是快照级（内容 SHA），不覆盖权限位/时间戳（规范：产物摘要只含内容）。
4. 未接 `xnull build`（两次构建摘要比对目前是 API，构建侧接入属 E4）。
