# B3-08c-22 parseFloat 只读对照（暂停改码）

## 输入
- fixture：`tests/b3/fixtures/bundle_text/app.x`
- Go C：`parseFloat.go.c`
- xnullc C：`parseFloat.xnullc.c`
- 归一化 diff：`parseFloat.diff`（当前 181 行 raw 函数 diff）

## 关键差异

1. early Err return 的 `rt_release(ch)` 独立块缺失（3 处）。
2. 循环内 String 相等操作数 root 次数：xnullc 少 1（ch 临时）/多 1（substring 临时）。
3. `break` 路径 block restore 多恢复一层（xnullc 多 `xn_root_restore`）。
4. 部分 `xn_root_add` 缩进与位置不同（8/12 空格层序）。

## 已试插入点（已回退，勿重复）

- 在 Result early 分支：先恢复最内层 block root → 插入 `rt_release(ch)` 独立块 →
  再恢复外层 loop/函数 root。
- 结果：text raw 349 → 403（更差），判断 release 应位于 defer 注册逆序中、
  而不是紧跟内层 block restore；需按 `emitBlock` 的 deferred release 队列整体实现。

## 当前状态（2026-11-09）
- text raw：349
- regexMatchAt norm：0
- 未改 xnullc；等待 `handoff/B3-text-rest-diff.md`
