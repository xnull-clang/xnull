# B4b 门（v1.0.3）：PARTIAL（仅 plugin/xpd 增强剩余）

- **判定**：`PARTIAL`（B4c 不得启动）
- **时间**：2026-11-11 17:00
- **原判定**：`B4b门-v1.0.2.md`
- **范围**：`handoff/B4b-c-plan.md`

## 更新（B4b-04b / 05a）

- `version` / `clean` / `doctor` / `fmt` / `install` 已补齐；install 库制品改为
  `.xlib`，app 安装集合对齐 Go；
- CLI 对拍矩阵：**PASS 11 / DIFF 0 / NA 9**（NA 为单侧缺失的命令/工程语义，
  如 Go 无 project run/validate/repro，单文件无 GAV）；
- B4b-01/02/03a/03b-1/03b-2/04a/04b-1/04b-2/05a 全部完成；
- 证据：`handoff/B4b-05a.md`、`tests/b4/cli-parity.sh`。

## 仍剩余

1. **plugin 实现**：当前仅设计 `handoff/B4b-04b-3-plugin.md`；需要 E5 的受限
   执行/动态加载能力，拆 a/b/c 子卡；
2. **xpd 增强**：完整依赖/版本冲突/锁文件语义（当前最小集）；
3. B4b-05 的 NA 项需要在 B4c 前给出“无对等物/不适用”的正式清单；
4. 统一 CLI：当前为 `tests/b4/xnull-build.sh` + native 小工具，未合并为单一
   `xnull` 二进制；
5. B4c（冻结 golden、删除 Go、无 Go 验证）未开始。

## 判定

B4b **PARTIAL**；核心构建/工程/工具链已可用，plugin/xpd 与统一 CLI 未完成。
B4c 不启动，Go 保留。
