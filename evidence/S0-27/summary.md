# S0-27 EN 滞后判据：mtime → 版本 + 母本内容哈希

## 问题

`checkEnSync` 原本用 `stat` mtime 判「母本改动后英译未重译」。mtime 在 `git clone` / `checkout` / rsync 后会刷新，导致同一内容在不同工作树得到不同结论（主树与公开副本曾各自报红/报绿），不可复现。

## 改法

1. 新增清单 `impl/docs/conformance/en-source.sha256`：`<母本文件名>\t<翻译所依据的母本内容 SHA-256>`，当前登记 8 份正式文档。
2. `checkEnSync` 判据改为：
   - 文件名版本号一致（原有）；
   - 母本内容 SHA-256 与清单登记一致（新增）；
   - **完全不再读取 mtime**。
3. 未登记的文件不做滞后判定（避免把历史英译一律判红）；清单缺失时整项跳过。
4. `dev check` 的检查项说明、`impl/README.md` 同步更新。

## 验收（全部机械可复现）

| 项 | 命令 | 结果 |
| --- | --- | --- |
| mtime 打乱 3 次一致 | 干净 clone 上 `touch -t` 三种时间戳后各跑一次 | 三次退出码 0，stdout sha256 均为 `3eb66d8d981d162b4ca268279d62c94509dd5f09bf03193aa31f7495b4e574b8` |
| 真实内容变更仍报滞后 | 向第 3 部分追加一行后重跑 | 退出码 1，`S3-Memory-Management-v3.0.0.md: 内容哈希不符——母本 … 变更后英译未同步重译（清单 a6dbb815…，当前 8f4579e2…）` |
| 干净 clone 工作区布局 | `xnull dev check`（clone 根有 impl/） | 退出码 0 |
| 干净 clone 公开布局 | `xnull dev check`（母本在 `spec/`） | 退出码 0 |
| 主树 | `/Users/vjs/Desktop/XNull-Lang` cwd | 退出码 0 |
| 公开副本 | `/Users/vjs/Desktop/XNull-Lang/xnull` cwd | 退出码 0 |
| 单测 | `go test ./internal/devtool ./internal/cli -timeout 180s` | 通过（含 3 个 S0-27 用例：mtime 无关/哈希滞后/哈希不符） |
| 全量 | `go test ./... -timeout 180s` | 仅 `internal/codegen` 181.876s 超时（P0-1），其余全绿 |

## 附：供 QA 复跑的二进制

`evidence/S0-27/bin/xnull`，sha256 `a8382438f90481962316242d93366782ea17e739d6a24eb9014bcc483cc7a94d`。

## 已知边界

- 只有登记在 `en-source.sha256` 的母本才做哈希比对；新规范文件需在翻译时补登记。
- 公开副本布局没有 `impl/`，清单不可达，因此不做哈希判定，只做版本与覆盖检查（与迁移前一致）。
- 台账本身未纳入清单（其头部随生成器变化，纳入会造成主树与工作树因生成器名不同而互判滞后）。
