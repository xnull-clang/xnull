# B3-07 证据：内存策略（S3 MEM 锚点）

## 结论

- 类策略按 S3 §15.1 判定：含 GC 字段（List/Set/Map/String/Any/协议等）或强引用环 → `gc`（`xn_gc_new` + scan）；其余 → `arc`（`rt_arc_new`）。
- 仅值字段、无 deinit/vtable/泛型实例的类为栈候选；按逃逸预扫描（实参/返回值/赋值右值/初始化式等发布位置）决定栈对象或 ARC 堆对象。
- ARC 堆局部：别名初始化 `rt_retain`，块末按声明逆序 `rt_release`；类标识符返回先 `rt_retain` 再清理、根帧恢复后返回。
- 类引用字段：C 类型 `xn_Cls_X *`（含 `X?`）；ARC 字段在 deinit hook 释放，GC 字段进入 `gc_scan`。
- 类元素容器：`List<X>` → `xn_arr_o_X` 专用 typedef/scan/deinit/push/get/…；ARC 元素带 retain/release，GC 元素不带。
- 类字段容器：`List<Int>`/`List<X>` 初始化发射专用 helper；类分支按需插入容器 typedef 与 helper 定义。
- 类返回/类参数顶层原型、类 forward 排序与节间空行对齐 oracle。

## 验收

```bash
bash tests/b3/xnullc-mem.sh
# PASS mem03/container_cycle.x … mem06/mapset.x
# xnullc-mem 汇总：PASS=11 FAIL=0
```

- 先红：空 stub `PASS=0`（`red.out`）；绿 `PASS=11 FAIL=0`（`green.out`）。
- `hashes.out`：11 个锚点 Go `--emit-c` 与 XNull C SHA-256 相同；同一输入两次生成 SHA-256 相同。
- 双路径：Go 原生构建与 xnullc 生成 C 编译产物 stdout/退出码一致。
- `tests/s3/run.sh` 解释路径 11/11 PASS（`s3-interp.out`）。
- 回归：`bash tests/b3/run.sh` 全绿（`run-all.out`）。

## 边界

- 未改 Go codegen/oracle、未改 `xparser.x` 语义。
- 容器锚点覆盖 `List<Int>`、`List<X>`；`List<String>`/Map 类元素组合留后续。
