# B3-08c-23 block-scoped release 尝试记录

- 按 `B3-text-rest-diff.md` §0.1 实现 blockRels 队列：
  - 声明挂到当前块；emitBlock/return 消费；break 只 restore。
- 实测：
  - 结构接通后 raw 349 → 388，regexMatchAt norm 0 → 64（块尾 release/顺序错位）。
  - 尝试对 regexMatchAt 关闭 blockRels 仍为 64，说明 block 退出消费点与现有
    If/While 的 restore 插入顺序不一致，需整体重排 emitBlock 结构，不能局部拼接。
- 已回退到 `9313c48`（raw 349，regexMatchAt 0），未提交不完整结构改动。
