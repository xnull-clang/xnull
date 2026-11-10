# B4a-01 性能重构报告（2026-11-10）

> 分支：`pod/e2-sema@ce80444`（未合入 main；B3-09 v1.0.3 基线在该分支为 140/97，
> 需以 main 的 142 入口重跑后再合）。

## 已做

1. `--stage-log` 计数：expr/stmt/block/mark/inNames 次数。
2. `SC.escaped`：`List<String>` → `Map<String,Int>`（O(1) has/put）。
3. `UNQ_CACHE`：短 raw 字符串 unq 缓存。
4. `emitUnit` 阶段拆分：collect / scan-cls / emit-funcs / emit-main / instances。
5. `dynContainerHelpers`：map 使用 String 时不再重复发 arr_s helper。
6. AP 每字符 substring 改 Bytes.get（前序卡）。

## 结果

| 指标 | 优化前 | B4a-01 |
|---|---:|---:|
| 解释器自编译总时间 | 2014s | **103s** |
| parse-bundle | 1974s | **57s** |
| emit-funcs | 35.8s | **26.3s** |
| 峰值内存 | 1.6–3GB | **1.75GB** |
| escape 计数 | — | expr=40553 stmt=7158 block=2305 mark=10945 inn=232125 |

## 仍阻塞

- **native xn-s1 自编译**：`/tmp/xn-s1c` 在 parse 119s + collect 201s + scan-cls 2s
  后，进入 emitFuncs/escape 超过 **47 分钟**未完成（1.17GB），被 kill；
  上一版 native 在 `escMark` **段错误**。
- 解释器 103s 可接受，但 native 路径更慢且不稳定，说明：
  1. native `Map<String,Int>` 可能是线性数组 Map，O(1) 假设不成立；
  2. escape 分析仍对深 AST/长表达式重复扫描；
  3. native GC/SC 生命周期在 `escMark` 有未定义行为。
- 没有 xn-s2，固定点链未启动。

## 下一步（B4a-02 建议）

1. 为 `escaped` 实现**原生哈希 Map**（`xn_map_s_i` 的线性 find 改为 hash 桶），
   或改用 `Set` 的 hash 版本；
2. escape 预计算：每个函数体一次自底向上，结果存 `Map<N, Bool>`；
3. `escMark` 的 SC/Map 生命周期加 ASAN 检查，修 native 段错误；
4. 目标 native 自编译 <5min/<500MB，再跑 xn-s2。

## 结论

B4a-01 只完成了解释器路径的提速；**B3-10/B4a 仍 BLOCKED**。
