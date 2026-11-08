# B3-08c-24 per-scope defers 重写记录（未完成，已回退）

## 已做
- SC 增加 `scopeDefers` 栈；函数入口注册 `root_restore(fnMark)`；
- String/Bytes 局部 release 改为挂当前 scope；
- 函数尾改为 `emitAllDefers`。

## 阻塞
- 现有 If/While/For/Switch 在块尾仍独立生成 `root_restore`，需全部替换为
  `emitScopeDefers` 并处理 returned 时“只 pop 不输出”，否则 restore 重复/缺失；
- Result early return 的 scope 栈与 blockRoots 需同步消费；
- 未完成前实测 raw 349→388、regexMatchAt 0→64，故回退。

## 结论
- 回退到 `9313c48` 行为：raw 349，regexMatchAt 0。
- 全量重写需要一次替换所有块尾 restore 生成点与 return/break 消费点，
  建议下一会话按整文件重构而非增量替换。
