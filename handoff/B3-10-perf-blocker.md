# B3-10 自编译性能阻塞（2026-11-10）

## 结论

- **B3-10-01 已完成**：用 Go oracle（含容器 Member/赋值/Ternary/ArrayLit 推断）
  编译 `xnullc.x` 得到原生 `xn-s1`（`/tmp/xnullc-go2`，1.67MB），可编译
  `examples/hello.x`，cc 运行输出正确。
- **B3-10-02 阻塞**：`xn-s1` 自编译 `xnullc.x` 在 50 分钟内无法完成
  `emitUnit` 的 escape 分析，内存 ~1GB；不进入 xn-s2。

## 数据

| 阶段 | 时间/内存 | 说明 |
|---|---|---|
| `read-ast` | 6–12ms | 3.9MB AST 读取 |
| `parse-bundle` | 34s（优化后） | AP 每字符 substring 改为 Bytes.get 后从 1h 降到 34s |
| `emitUnit collect` | 未完成（>50min，~1GB） | 卡在 `escBlock/escStmt/escExpr` |

`sample` 调用栈（`/tmp/xn-sample.txt`）：

```text
xn_emitFunc
  xn_escBlock
    xn_escStmt
      xn_escBlock
        xn_escStmt
          xn_escExpr  (递归 5728/6269 偏移)
            xn_inNames (线性 List<String> 扫描)
            xn_unq
```

## 根因假设

1. `escBlock/escStmt/escExpr` 对每个函数体做递归 escape 分析，嵌套块/表达式可能
   被重复扫描；对 xnullc.x 的深 AST 退化为 O(n²) 或更高。
2. `inNames`/`sc.names`/`escaped` 用 `List<String>` 线性查找，名字多时 O(n²)。
3. `unq/txt/fld` 在热路径反复调用，字符串比较/分配放大。

## 建议修复顺序（B4a）

1. **escape 记忆化**：按 AST 节点（N 引用）缓存 `escBlock/escStmt` 结果；上下文
   相关时按函数/作用域缓存；禁止对同一子树重复分析。
2. **名字索引**：`IN_NAMES`/`ESC_NAMES`/`sc.names` 改 `Map<String,Bool>` 或
   `Set<String>`，`inNames` O(1)。
3. **热路径去字符串化**：`txt/fld/unq` 结果缓存；成员名比较用一次 hash。
4. **分阶段计时**：保留 `--stage-log`，目标：parse <5s、emit <60s、总 <5min、
   峰值 <500MB。
5. 达标后再跑 xn-s2→xn-s3→xn-s4 固定点；否则 B4a 不启动。

## 临时状态

- `/tmp/xnullc-go2` 是 xn-s1 证据；`/tmp/xn-s2.c` 未生成。
- `pod/e2-sema@e3a96ac` 含 AP/bytes/global/FFI 修复，但 Ternary 未实现，
  门禁 140/97/1 FAIL（`tests/b3/neg/ternary.x` 变正例）；**未合入 main**。
- B3-09 门禁判定仍以 `6a729c5`（141/0）为准；main 在合入 Go Ternary 后需
  补 xnullc Ternary 并复跑 142 入口。
