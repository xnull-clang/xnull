# B4b 门（v1.0.4）：PARTIAL（仅 plugin/xpd 豁免待裁决）

- **判定**：`PARTIAL`
- **时间**：2026-11-12 00:55
- **原判定**：`B4b门-v1.0.3.md`
- **范围**：`handoff/B4b-c-plan.md`

## 更新（B4b-06）

- 统一 CLI `bin/xnull` 已实现，转发 `tests/b4/xnull-build.sh`；
- CLI 对拍矩阵保持 **PASS 11 / DIFF 0 / NA 9**；
- `version`/`tree`/`build` 等从仓库根可直接运行；
- 9 示例 9/9 不变。

## 剩余

1. **plugin**：仅设计，未实现；依赖 E5 受限执行/动态加载。
2. **xpd 增强**：完整依赖/版本冲突/锁文件；当前最小集。
3. 若 plugin/xpd 可豁免，B4b 可判 PASS 并进入 B4c；否则继续 B4b-04b-3。

## 判定

B4b **PARTIAL**。核心构建/工程/工具链/统一 CLI 已完成；plugin 与 xpd 完整语义
待裁决。B4c 不启动。
