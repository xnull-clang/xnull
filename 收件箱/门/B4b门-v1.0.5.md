# B4b 门（v1.0.5）：PASS（plugin/xpd 经用户豁免）

- **判定**：`PASS`
- **时间**：2026-11-12 01:00
- **原判定**：`B4b门-v1.0.4.md`（PARTIAL）
- **范围**：`handoff/B4b-c-plan.md`

## 裁决

用户裁决：**豁免 plugin/xpd 完整语义**（记录为 B4c 风险/后续卡），B4b 判 PASS。

## 完成面

- B4b-01 Go-free build/run 管线：9/9；
- B4b-02 native xparser：大文件 12/12，AST 与 xnast 逐字节一致；
- B4b-03a/03b xpd/manifest/reactor/resman/config/artifact：proj02 聚合构建、
  资源表、安装产物对齐；
- B4b-04a/04b tree/why/install/repro/xmeta：逐字节/哈希一致；
- B4b-05a version/clean/doctor/fmt：CLI 对拍 **PASS 11 / DIFF 0 / NA 9**；
- B4b-06 统一 CLI `bin/xnull`：命令可用，对拍不变。

## 豁免项（B4c 风险）

1. plugin：仅设计，未实现受限执行/动态加载；
2. xpd 完整语义：依赖/版本冲突/锁文件增强未做；
3. NA 9 项：单侧缺失命令/工程语义，B4c 前出正式“不适用”清单。

## 判定

B4b **PASS**（含豁免）。B4c 可开始：先冻结 golden，再经用户授权删除 Go。
