# B2-04d 最小复现结果

| 程序 | 覆盖点 | interp | 原生（修前） | 原生（修后） |
|---|---|---|---|---|
| r1_class_reassign.x | 类引用重赋值 + GC 压力 | 2 | 2 | 2 |
| r2_container_reassign.x | 容器重赋值 | second | 编译失败（语法） | 未复现 |
| r3_handle_reassign.x | 类句柄循环重赋值 | 49999 | 49999 | 49999 |
| r4_giant_list.x | GC 类对象列表 + 方法游标 | 148890 | 段错误（约 1/10） | 148890（10/10） |
| r5_list_iterate.x | 列表元素 new 入容器 + 长度 | 148890 | 段错误（约 1/10） | 148890（30/30） |

## 结论

根因之一：`xs.push(new Tok(...))` 中 `new` 产生的 GC 类对象没有在
push 分配（可能触发 GC）前登记为根；r5 修复后稳定通过。

仍存：`text.x`/`xnfmt.x` 大语料在 GC 开启时段错误（约 1/10~1/5）；
关闭 safepoint 后 AST 与 Go 逐字节一致，说明还有另一处表达式临时/Result
载荷 GC 根缺口，尚未定位到最小点。
